//! Fake payment adapter with a configurable decline switch.

use warehouse_application::ports::{Charged, PaymentProcessor};
use warehouse_domain::error::InvalidOrder;
use warehouse_domain::order::Order;

/// [`PaymentProcessor`] test double that records every charge attempt.
///
/// Configure `decline` to make each collection fail with a typed
/// [`InvalidOrder`] refusal.
#[derive(Debug, Default)]
pub struct FakePaymentProcessor {
    decline: bool,
    charged_orders: Vec<Order>,
}

impl FakePaymentProcessor {
    /// Starts in the configured outcome mode with an empty attempt log.
    #[must_use]
    pub fn new(decline: bool) -> Self {
        Self {
            decline,
            charged_orders: Vec::new(),
        }
    }

    /// Returns the orders this processor was asked to charge, in order.
    #[must_use]
    pub fn charged_orders(&self) -> &[Order] {
        &self.charged_orders
    }
}

impl PaymentProcessor for FakePaymentProcessor {
    fn charge(&mut self, order: &Order) -> Result<Charged, InvalidOrder> {
        self.charged_orders.push(order.clone());
        if self.decline {
            return Err(InvalidOrder::new(format!(
                "payment declined for order {}",
                order.id()
            )));
        }
        Ok(Charged)
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
    fn accepting_charge_records_the_attempt() {
        let mut processor = FakePaymentProcessor::new(false);
        let order = sample_order();
        assert!(processor.charge(&order).is_ok());
        assert_eq!(processor.charged_orders().len(), 1);
    }

    #[test]
    fn declined_charge_is_an_invalid_order() {
        let mut processor = FakePaymentProcessor::new(true);
        let order = sample_order();
        match processor.charge(&order) {
            Err(error) => assert!(error.reason().contains("declined")),
            Ok(charged) => panic!("expected decline, got {charged:?}"),
        }
        // The attempt is recorded even when refused.
        assert_eq!(processor.charged_orders().len(), 1);
    }
}
