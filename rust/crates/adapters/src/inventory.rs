//! In-memory inventory adapter backed by a finite per-SKU stock map.

use std::collections::BTreeMap;

use warehouse_application::ports::{InventoryGateway, Reserved};
use warehouse_domain::error::InsufficientStock;
use warehouse_domain::quantity::Quantity;
use warehouse_domain::sku::Sku;

/// [`InventoryGateway`] double enforcing finite stock, for tests and demos.
#[derive(Debug, Default, Clone)]
pub struct InMemoryInventoryGateway {
    stock: BTreeMap<Sku, u32>,
}

impl InMemoryInventoryGateway {
    /// Starts from an initial finite stock map.
    #[must_use]
    pub fn new(stock: BTreeMap<Sku, u32>) -> Self {
        Self { stock }
    }

    /// Returns the remaining stock for a SKU (0 when unknown).
    #[must_use]
    pub fn available(&self, sku: &Sku) -> u32 {
        self.stock.get(sku).copied().unwrap_or(0)
    }
}

impl InventoryGateway for InMemoryInventoryGateway {
    fn reserve(&mut self, sku: Sku, quantity: Quantity) -> Result<Reserved, InsufficientStock> {
        let available = self.available(&sku);
        let requested = quantity.value();
        if available < requested {
            return Err(InsufficientStock::new(sku, quantity, available));
        }
        let remaining = available - requested;
        if remaining == 0 {
            self.stock.remove(&sku);
        } else {
            self.stock.insert(sku, remaining);
        }
        Ok(Reserved)
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

    #[test]
    fn reservation_decrements_stock() {
        let sku = Sku::new("SKU-A").unwrap();
        let mut gateway = InMemoryInventoryGateway::new(BTreeMap::from([(sku.clone(), 3)]));
        assert_eq!(
            gateway.reserve(sku.clone(), Quantity::new(2).unwrap()),
            Ok(Reserved)
        );
        assert_eq!(gateway.available(&sku), 1);
    }

    #[test]
    fn shortage_reports_available() {
        let sku = Sku::new("SKU-A").unwrap();
        let mut gateway = InMemoryInventoryGateway::default();
        match gateway.reserve(sku.clone(), Quantity::new(1).unwrap()) {
            Err(error) => assert_eq!(error.available(), 0),
            Ok(reserved) => panic!("expected shortage, got {reserved:?}"),
        }
    }

    #[test]
    fn exhausting_stock_removes_the_entry() {
        let sku = Sku::new("SKU-B").unwrap();
        let mut gateway = InMemoryInventoryGateway::new(BTreeMap::from([(sku.clone(), 2)]));
        assert_eq!(
            gateway.reserve(sku.clone(), Quantity::new(2).unwrap()),
            Ok(Reserved)
        );
        assert_eq!(gateway.available(&sku), 0);
    }
}
