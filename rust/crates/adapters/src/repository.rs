//! In-memory order repository keyed by immutable order id.

use std::collections::BTreeMap;
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};

use warehouse_application::ports::OrderRepository;
use warehouse_domain::error::PersistenceConflict;
use warehouse_domain::order::{Order, OrderId};

#[derive(Debug, Default)]
struct Inner {
    orders: BTreeMap<OrderId, Order>,
    by_key: BTreeMap<String, (String, Order)>,
    saved: Vec<Order>,
    fail_save: bool,
}

/// [`OrderRepository`] double keeping snapshots, never aliases.
#[derive(Debug, Clone, Default)]
pub struct InMemoryOrderRepository {
    inner: Arc<Mutex<Inner>>,
}

impl InMemoryOrderRepository {
    /// Starts with an empty store.
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// Returns snapshots written by successful saves, in order.
    #[must_use]
    pub fn saved(&self) -> Vec<Order> {
        lock(&self.inner).saved.clone()
    }

    /// Configures the next [`OrderRepository::save`] to fail.
    pub fn set_fail_save(&self, fail: bool) {
        lock(&self.inner).fail_save = fail;
    }
}

impl OrderRepository for InMemoryOrderRepository {
    fn save(&self, order: &Order, expected_version: u32) -> Result<Order, PersistenceConflict> {
        let mut inner = lock(&self.inner);
        if inner.fail_save {
            return Err(PersistenceConflict::new(format!(
                "forced save failure for {}",
                order.id()
            )));
        }
        let current_version = inner.orders.get(order.id()).map_or(0, Order::version);
        if current_version != expected_version {
            return Err(conflict(order, expected_version, current_version));
        }
        Ok(store(&mut inner, order))
    }

    fn get(&self, order_id: &OrderId) -> Option<Order> {
        lock(&self.inner).orders.get(order_id).map(Order::snapshot)
    }

    fn get_by_idempotency_key(&self, key: &str) -> Option<(String, Order)> {
        lock(&self.inner)
            .by_key
            .get(key)
            .map(|(fingerprint, order)| (fingerprint.clone(), order.snapshot()))
    }

    fn remember_idempotency(&self, key: &str, fingerprint: &str, order: &Order) {
        lock(&self.inner)
            .by_key
            .insert(key.to_owned(), (fingerprint.to_owned(), order.snapshot()));
    }
}

fn lock(mutex: &Mutex<Inner>) -> MutexGuard<'_, Inner> {
    mutex.lock().unwrap_or_else(PoisonError::into_inner)
}

fn conflict(order: &Order, expected: u32, stored: u32) -> PersistenceConflict {
    PersistenceConflict::new(format!(
        "version conflict for {}: expected {expected}, stored {stored}",
        order.id()
    ))
}

fn store(inner: &mut Inner, order: &Order) -> Order {
    let mut stored = order.snapshot();
    stored.bump_version();
    inner.orders.insert(order.id().clone(), stored.snapshot());
    inner.saved.push(stored.snapshot());
    stored
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
    use warehouse_domain::order::{OrderLine, OrderStatus};
    use warehouse_domain::quantity::Quantity;
    use warehouse_domain::sku::Sku;

    fn sample_order() -> Order {
        Order::new(
            OrderId::new("ord-1").unwrap(),
            vec![OrderLine::new(
                Sku::new("SKU-A").unwrap(),
                Quantity::new(1).unwrap(),
                Money::from_minor(100, Currency::new("EUR").unwrap()).unwrap(),
            )],
        )
        .unwrap()
    }

    fn paid_order() -> Order {
        let mut order = sample_order();
        order.pay().unwrap();
        order
    }

    #[test]
    fn save_then_get_round_trips_a_snapshot() {
        let repository = InMemoryOrderRepository::new();
        let order = paid_order();
        let saved = repository.save(&order, 0).unwrap();
        assert_eq!(saved.status(), OrderStatus::Paid);
        assert_eq!(saved.version(), 1);
        let loaded = repository.get(order.id()).unwrap();
        assert_eq!(loaded.version(), 1);
        assert_eq!(loaded.status(), OrderStatus::Paid);
    }

    #[test]
    fn unknown_id_returns_none_without_raising() {
        let repository = InMemoryOrderRepository::new();
        let missing = OrderId::new("missing-order").unwrap();
        assert_eq!(repository.get(&missing), None);
    }

    #[test]
    fn stale_expected_version_is_a_persistence_conflict() {
        let repository = InMemoryOrderRepository::new();
        let order = paid_order();
        repository.save(&order, 0).unwrap();
        match repository.save(&order, 0) {
            Err(error) => assert!(error.reason().contains("version conflict")),
            Ok(saved) => panic!("expected conflict, got {saved:?}"),
        }
    }

    #[test]
    fn mutating_a_returned_order_does_not_alias_storage() {
        let repository = InMemoryOrderRepository::new();
        repository.save(&paid_order(), 0).unwrap();
        let id = OrderId::new("ord-1").unwrap();
        let mut loaded = repository.get(&id).unwrap();
        loaded.ship().unwrap();
        let stored = repository.get(&id).unwrap();
        assert_eq!(stored.status(), OrderStatus::Paid);
        assert_eq!(stored.version(), 1);
    }

    #[test]
    fn forced_save_failure_is_a_persistence_conflict() {
        let repository = InMemoryOrderRepository::new();
        repository.set_fail_save(true);
        match repository.save(&paid_order(), 0) {
            Err(error) => assert!(error.reason().contains("forced save failure")),
            Ok(saved) => panic!("expected conflict, got {saved:?}"),
        }
        assert!(repository.saved().is_empty());
    }

    #[test]
    fn idempotency_memory_returns_a_snapshot() {
        let repository = InMemoryOrderRepository::new();
        let saved = repository.save(&paid_order(), 0).unwrap();
        repository.remember_idempotency("idem-1", "fp", &saved);
        let (fingerprint, replayed) = repository.get_by_idempotency_key("idem-1").unwrap();
        assert_eq!(fingerprint, "fp");
        assert_eq!(replayed.status(), OrderStatus::Paid);
    }
}
