//! In-memory inventory adapter with atomic reserve-all.

use std::collections::BTreeMap;
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};

use warehouse_application::ports::{InventoryGateway, ReservationToken};
use warehouse_domain::error::{CompensationFailure, InsufficientStock};
use warehouse_domain::order::{OrderId, OrderLine};
use warehouse_domain::sku::Sku;

#[derive(Debug)]
struct Inner {
    stock: BTreeMap<Sku, u32>,
    reservations: BTreeMap<String, Vec<(Sku, u32)>>,
    fail_release: bool,
}

/// [`InventoryGateway`] double enforcing finite stock, for tests and demos.
///
/// Clones share the same stock map so concurrent use cases cannot oversell.
#[derive(Debug, Clone)]
pub struct InMemoryInventoryGateway {
    inner: Arc<Mutex<Inner>>,
}

impl Default for InMemoryInventoryGateway {
    fn default() -> Self {
        Self::new(BTreeMap::new())
    }
}

impl InMemoryInventoryGateway {
    /// Starts from an initial finite stock map, copied defensively.
    #[must_use]
    pub fn new(stock: BTreeMap<Sku, u32>) -> Self {
        Self {
            inner: Arc::new(Mutex::new(Inner {
                stock,
                reservations: BTreeMap::new(),
                fail_release: false,
            })),
        }
    }

    /// Returns the remaining stock for a SKU (0 when unknown).
    #[must_use]
    pub fn available(&self, sku: &Sku) -> u32 {
        lock(&self.inner).stock.get(sku).copied().unwrap_or(0)
    }

    /// Returns a copy of remaining units per SKU.
    #[must_use]
    pub fn snapshot_stock(&self) -> BTreeMap<Sku, u32> {
        lock(&self.inner).stock.clone()
    }

    /// Configures the next [`InventoryGateway::release`] to fail.
    pub fn set_fail_release(&self, fail: bool) {
        lock(&self.inner).fail_release = fail;
    }
}

impl InventoryGateway for InMemoryInventoryGateway {
    fn reserve_all(
        &self,
        order_id: &OrderId,
        lines: &[OrderLine],
        idempotency_key: &str,
    ) -> Result<ReservationToken, InsufficientStock> {
        let mut inner = lock(&self.inner);
        if inner.reservations.contains_key(idempotency_key) {
            return Ok(ReservationToken::new(order_id.clone(), idempotency_key));
        }
        let needed = collect_needed(&inner.stock, lines)?;
        apply_needed(&mut inner.stock, &needed);
        inner
            .reservations
            .insert(idempotency_key.to_owned(), needed);
        Ok(ReservationToken::new(order_id.clone(), idempotency_key))
    }

    fn release(&self, token: &ReservationToken) -> Result<(), CompensationFailure> {
        let mut inner = lock(&self.inner);
        if inner.fail_release {
            return Err(CompensationFailure::new("release", "forced failure"));
        }
        restore(&mut inner, token.idempotency_key());
        Ok(())
    }
}

fn lock(mutex: &Mutex<Inner>) -> MutexGuard<'_, Inner> {
    mutex.lock().unwrap_or_else(PoisonError::into_inner)
}

fn collect_needed(
    stock: &BTreeMap<Sku, u32>,
    lines: &[OrderLine],
) -> Result<Vec<(Sku, u32)>, InsufficientStock> {
    let mut needed = Vec::with_capacity(lines.len());
    for line in lines {
        let available = stock.get(line.sku()).copied().unwrap_or(0);
        let requested = line.quantity().value();
        if available < requested {
            return Err(InsufficientStock::new(
                line.sku().clone(),
                line.quantity(),
                available,
            ));
        }
        needed.push((line.sku().clone(), requested));
    }
    Ok(needed)
}

fn apply_needed(stock: &mut BTreeMap<Sku, u32>, needed: &[(Sku, u32)]) {
    for (sku, amount) in needed {
        if let Some(available) = stock.get_mut(sku) {
            *available = available.saturating_sub(*amount);
        }
    }
}

fn restore(inner: &mut Inner, key: &str) {
    let Some(held) = inner.reservations.remove(key) else {
        return;
    };
    for (sku, amount) in held {
        let entry = inner.stock.entry(sku).or_insert(0);
        *entry = entry.saturating_add(amount);
    }
}

#[cfg(test)]
mod tests {
    #![allow(
        clippy::unwrap_used,
        reason = "tests build known-valid values and read errors"
    )]
    #![allow(clippy::panic, reason = "a failed assertion IS the test failing")]

    use super::*;
    use warehouse_domain::money::{Currency, Money};
    use warehouse_domain::order::OrderLine;
    use warehouse_domain::quantity::Quantity;

    fn sku(code: &str) -> Sku {
        Sku::new(code).unwrap()
    }

    fn line(code: &str, amount: u32) -> OrderLine {
        OrderLine::new(
            sku(code),
            Quantity::new(amount).unwrap(),
            Money::from_minor(100, Currency::new("EUR").unwrap()).unwrap(),
        )
    }

    fn gateway(code: &str, units: u32) -> InMemoryInventoryGateway {
        InMemoryInventoryGateway::new(BTreeMap::from([(sku(code), units)]))
    }

    #[test]
    fn reservation_decrements_stock() {
        let gateway = gateway("SKU-A", 3);
        let id = OrderId::new("ord-1").unwrap();
        assert!(
            gateway
                .reserve_all(&id, &[line("SKU-A", 2)], "idem-1")
                .is_ok()
        );
        assert_eq!(gateway.available(&sku("SKU-A")), 1);
    }

    #[test]
    fn shortage_reports_available() {
        let gateway = InMemoryInventoryGateway::default();
        let id = OrderId::new("ord-1").unwrap();
        match gateway.reserve_all(&id, &[line("SKU-A", 1)], "idem-1") {
            Err(error) => assert_eq!(error.available(), 0),
            Ok(token) => panic!("expected shortage, got {token:?}"),
        }
    }

    #[test]
    fn exhausting_stock_leaves_zero() {
        let gateway = gateway("SKU-B", 2);
        let id = OrderId::new("ord-1").unwrap();
        assert!(
            gateway
                .reserve_all(&id, &[line("SKU-B", 2)], "idem-1")
                .is_ok()
        );
        assert_eq!(gateway.available(&sku("SKU-B")), 0);
    }

    #[test]
    fn identical_key_does_not_double_reserve() {
        let gateway = gateway("SKU-A", 3);
        let id = OrderId::new("ord-1").unwrap();
        let lines = [line("SKU-A", 2)];
        assert!(gateway.reserve_all(&id, &lines, "idem-1").is_ok());
        assert!(gateway.reserve_all(&id, &lines, "idem-1").is_ok());
        assert_eq!(gateway.available(&sku("SKU-A")), 1);
    }

    #[test]
    fn release_restores_stock() {
        let gateway = gateway("SKU-A", 3);
        let id = OrderId::new("ord-1").unwrap();
        let token = gateway
            .reserve_all(&id, &[line("SKU-A", 2)], "idem-1")
            .unwrap();
        assert!(gateway.release(&token).is_ok());
        assert_eq!(gateway.available(&sku("SKU-A")), 3);
    }

    #[test]
    fn forced_release_failure_is_compensation_failure() {
        let gateway = gateway("SKU-A", 3);
        let id = OrderId::new("ord-1").unwrap();
        let token = gateway
            .reserve_all(&id, &[line("SKU-A", 1)], "idem-1")
            .unwrap();
        gateway.set_fail_release(true);
        match gateway.release(&token) {
            Err(error) => assert_eq!(error.stage(), "release"),
            Ok(()) => panic!("expected compensation failure"),
        }
    }
}
