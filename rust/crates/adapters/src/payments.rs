//! Fake payment adapter with idempotent charge and refund.

use std::collections::BTreeMap;
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};

use warehouse_application::ports::{ChargeReceipt, PaymentProcessor};
use warehouse_domain::error::{CompensationFailure, PaymentDeclined};
use warehouse_domain::order::Order;

#[derive(Debug)]
struct Inner {
    decline: bool,
    fail_refund: bool,
    charged_orders: Vec<Order>,
    refunded: Vec<ChargeReceipt>,
    receipts: BTreeMap<String, Result<ChargeReceipt, PaymentDeclined>>,
}

/// [`PaymentProcessor`] test double that records every charge attempt.
///
/// Configure `decline` to refuse collection. Identical idempotency keys
/// replay the original outcome without a second charge.
#[derive(Debug, Clone)]
pub struct FakePaymentProcessor {
    inner: Arc<Mutex<Inner>>,
}

impl Default for FakePaymentProcessor {
    fn default() -> Self {
        Self::new(false)
    }
}

impl FakePaymentProcessor {
    /// Starts in the configured outcome mode with an empty attempt log.
    #[must_use]
    pub fn new(decline: bool) -> Self {
        Self {
            inner: Arc::new(Mutex::new(Inner {
                decline,
                fail_refund: false,
                charged_orders: Vec::new(),
                refunded: Vec::new(),
                receipts: BTreeMap::new(),
            })),
        }
    }

    /// Returns snapshots of the orders this processor was asked to charge.
    #[must_use]
    pub fn charged_orders(&self) -> Vec<Order> {
        lock(&self.inner).charged_orders.clone()
    }

    /// Returns receipts that were refunded, in order.
    #[must_use]
    pub fn refunded(&self) -> Vec<ChargeReceipt> {
        lock(&self.inner).refunded.clone()
    }

    /// Configures the next [`PaymentProcessor::refund`] to fail.
    pub fn set_fail_refund(&self, fail: bool) {
        lock(&self.inner).fail_refund = fail;
    }
}

impl PaymentProcessor for FakePaymentProcessor {
    fn charge(
        &self,
        order: &Order,
        idempotency_key: &str,
    ) -> Result<ChargeReceipt, PaymentDeclined> {
        let mut inner = lock(&self.inner);
        if let Some(prior) = inner.receipts.get(idempotency_key) {
            return prior.clone();
        }
        inner.charged_orders.push(order.snapshot());
        record_attempt(&mut inner, order, idempotency_key)
    }

    fn refund(&self, receipt: &ChargeReceipt) -> Result<(), CompensationFailure> {
        let mut inner = lock(&self.inner);
        if inner.fail_refund {
            return Err(CompensationFailure::new("refund", "forced failure"));
        }
        inner.refunded.push(receipt.clone());
        Ok(())
    }
}

fn lock(mutex: &Mutex<Inner>) -> MutexGuard<'_, Inner> {
    mutex.lock().unwrap_or_else(PoisonError::into_inner)
}

fn record_attempt(
    inner: &mut Inner,
    order: &Order,
    idempotency_key: &str,
) -> Result<ChargeReceipt, PaymentDeclined> {
    if inner.decline {
        let declined = PaymentDeclined::new(format!("payment declined for order {}", order.id()));
        inner
            .receipts
            .insert(idempotency_key.to_owned(), Err(declined.clone()));
        return Err(declined);
    }
    let receipt = ChargeReceipt::new(order.id().clone(), idempotency_key);
    inner
        .receipts
        .insert(idempotency_key.to_owned(), Ok(receipt.clone()));
    Ok(receipt)
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
    use warehouse_domain::order::{OrderId, OrderLine};
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

    #[test]
    fn accepting_charge_records_the_attempt() {
        let processor = FakePaymentProcessor::new(false);
        let order = sample_order();
        assert!(processor.charge(&order, "idem-1").is_ok());
        assert_eq!(processor.charged_orders().len(), 1);
    }

    #[test]
    fn declined_charge_is_payment_declined() {
        let processor = FakePaymentProcessor::new(true);
        let order = sample_order();
        match processor.charge(&order, "idem-1") {
            Err(error) => assert!(error.reason().contains("declined")),
            Ok(receipt) => panic!("expected decline, got {receipt:?}"),
        }
        assert_eq!(processor.charged_orders().len(), 1);
    }

    #[test]
    fn identical_key_does_not_double_charge() {
        let processor = FakePaymentProcessor::default();
        let order = sample_order();
        assert!(processor.charge(&order, "idem-1").is_ok());
        assert!(processor.charge(&order, "idem-1").is_ok());
        assert_eq!(processor.charged_orders().len(), 1);
    }

    #[test]
    fn refund_records_the_receipt() {
        let processor = FakePaymentProcessor::new(false);
        let order = sample_order();
        let receipt = processor.charge(&order, "idem-1").unwrap();
        assert!(processor.refund(&receipt).is_ok());
        assert_eq!(processor.refunded().len(), 1);
    }

    #[test]
    fn forced_refund_failure_is_compensation_failure() {
        let processor = FakePaymentProcessor::new(false);
        let order = sample_order();
        let receipt = processor.charge(&order, "idem-1").unwrap();
        processor.set_fail_refund(true);
        match processor.refund(&receipt) {
            Err(error) => assert_eq!(error.stage(), "refund"),
            Ok(()) => panic!("expected compensation failure"),
        }
    }
}
