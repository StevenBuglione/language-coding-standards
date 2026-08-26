//! In-memory order repository keyed by immutable order id.

use std::collections::BTreeMap;

use warehouse_application::ports::OrderRepository;
use warehouse_domain::order::{Order, OrderId};

/// [`OrderRepository`] double keeping orders in a map, for tests and demos.
#[derive(Debug, Default, Clone)]
pub struct InMemoryOrderRepository {
    orders: BTreeMap<OrderId, Order>,
}

impl InMemoryOrderRepository {
    /// Starts with an empty store.
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }
}

impl OrderRepository for InMemoryOrderRepository {
    fn save(&mut self, order: Order) -> Order {
        self.orders.insert(order.id(), order.clone());
        order
    }

    fn get(&self, order_id: OrderId) -> Option<Order> {
        self.orders.get(&order_id).cloned()
    }
}

#[cfg(test)]
mod tests {
    #![allow(
        clippy::unwrap_used,
        reason = "tests build known-valid values and read errors"
    )]

    use super::*;
    use warehouse_domain::money::{Currency, Money};
    use warehouse_domain::order::OrderLine;
    use warehouse_domain::quantity::Quantity;
    use warehouse_domain::sku::Sku;

    fn sample_order() -> Order {
        Order::new(vec![OrderLine::new(
            Sku::new("SKU-A").unwrap(),
            Quantity::new(1).unwrap(),
            Money::from_minor(100, Currency::new("EUR").unwrap()),
        )])
        .unwrap()
    }

    #[test]
    fn save_then_get_round_trips() {
        let mut repository = InMemoryOrderRepository::new();
        let order = sample_order();
        repository.save(order.clone());
        assert_eq!(repository.get(order.id()), Some(order));
    }

    #[test]
    fn unknown_id_returns_none_without_raising() {
        let repository = InMemoryOrderRepository::new();
        assert_eq!(repository.get(OrderId::next()), None);
    }
}
