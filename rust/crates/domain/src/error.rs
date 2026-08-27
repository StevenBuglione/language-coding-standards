//! Typed domain errors raised by the pure domain layer.
//!
//! The v2 vocabulary is [`InvalidOrder`], [`InsufficientStock`],
//! [`PaymentDeclined`], [`PersistenceConflict`], [`CompensationFailure`],
//! and [`OrderAlreadyShipped`]. [`DomainError`] bundles the verdicts that
//! order transitions can produce.

use crate::order::OrderId;
use crate::quantity::Quantity;
use crate::sku::Sku;

/// An order or value violates a structural domain invariant.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[error("invalid order: {reason}")]
pub struct InvalidOrder {
    reason: String,
}

impl InvalidOrder {
    /// Records why an order or value was rejected.
    #[must_use]
    pub fn new(reason: impl Into<String>) -> Self {
        Self {
            reason: reason.into(),
        }
    }

    /// Returns the human-readable rejection reason.
    #[must_use]
    pub fn reason(&self) -> &str {
        &self.reason
    }
}

/// The inventory cannot cover the requested quantity for a SKU.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[error("insufficient stock for `{sku}`: requested {requested}, available {available}")]
pub struct InsufficientStock {
    sku: Sku,
    requested: Quantity,
    available: u32,
}

impl InsufficientStock {
    /// Records which SKU fell short, by how much, and what remained.
    #[must_use]
    pub fn new(sku: Sku, requested: Quantity, available: u32) -> Self {
        Self {
            sku,
            requested,
            available,
        }
    }

    /// Returns the SKU whose reservation fell short.
    #[must_use]
    pub fn sku(&self) -> &Sku {
        &self.sku
    }

    /// Returns the quantity that was requested.
    #[must_use]
    pub fn requested(&self) -> Quantity {
        self.requested
    }

    /// Returns the stock that remained at the time of the request.
    #[must_use]
    pub fn available(&self) -> u32 {
        self.available
    }
}

/// The payment processor refused to charge the order.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[error("payment declined: {reason}")]
pub struct PaymentDeclined {
    reason: String,
}

impl PaymentDeclined {
    /// Records why the charge was refused.
    #[must_use]
    pub fn new(reason: impl Into<String>) -> Self {
        Self {
            reason: reason.into(),
        }
    }

    /// Returns the human-readable refusal reason.
    #[must_use]
    pub fn reason(&self) -> &str {
        &self.reason
    }
}

/// An optimistic save lost a compare-and-set race.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[error("persistence conflict: {reason}")]
pub struct PersistenceConflict {
    reason: String,
}

impl PersistenceConflict {
    /// Records why the compare-and-set failed.
    #[must_use]
    pub fn new(reason: impl Into<String>) -> Self {
        Self {
            reason: reason.into(),
        }
    }

    /// Returns the human-readable conflict reason.
    #[must_use]
    pub fn reason(&self) -> &str {
        &self.reason
    }
}

/// Refund or reservation release failed after a partial success.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[error("compensation failed at {stage}: {detail}")]
pub struct CompensationFailure {
    stage: String,
    detail: String,
}

impl CompensationFailure {
    /// Records which compensation step failed and why.
    #[must_use]
    pub fn new(stage: impl Into<String>, detail: impl Into<String>) -> Self {
        Self {
            stage: stage.into(),
            detail: detail.into(),
        }
    }

    /// Returns the compensation stage that failed (`refund` or `release`).
    #[must_use]
    pub fn stage(&self) -> &str {
        &self.stage
    }

    /// Returns the human-readable failure detail.
    #[must_use]
    pub fn detail(&self) -> &str {
        &self.detail
    }
}

/// A shipped order can no longer be mutated.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[error("order {id} has already shipped")]
pub struct OrderAlreadyShipped {
    id: OrderId,
}

impl OrderAlreadyShipped {
    /// Records which shipped order refused a mutation.
    #[must_use]
    pub fn new(id: OrderId) -> Self {
        Self { id }
    }

    /// Returns the identifier of the shipped order.
    #[must_use]
    pub fn id(&self) -> &OrderId {
        &self.id
    }
}

/// Verdicts that order transitions can produce.
///
/// Ports narrow this down to the single verdict they can raise. Decline,
/// conflict, and compensation stay as their own types so they are never
/// mislabeled as [`InvalidOrder`].
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum DomainError {
    /// The inventory cannot cover the request.
    #[error(transparent)]
    InsufficientStock(#[from] InsufficientStock),
    /// A structural invariant was violated.
    #[error(transparent)]
    InvalidOrder(#[from] InvalidOrder),
    /// A shipped order refused a mutation.
    #[error(transparent)]
    AlreadyShipped(#[from] OrderAlreadyShipped),
}

#[cfg(test)]
mod tests {
    // Documented test-side suppressions (see src/order.rs).
    #![allow(
        clippy::unwrap_used,
        reason = "tests build known-valid values and read errors"
    )]
    #![allow(clippy::panic, reason = "a failed assertion IS the test failing")]

    use super::*;
    use crate::order::OrderId;

    #[test]
    fn invalid_order_carries_its_reason() {
        let error = InvalidOrder::new("lines were empty");
        assert_eq!(error.reason(), "lines were empty");
        assert_eq!(error.to_string(), "invalid order: lines were empty");
    }

    #[test]
    fn insufficient_stock_reports_sku_request_and_availability() {
        let sku = Sku::new("SKU-9").unwrap();
        let requested = Quantity::new(4).unwrap();
        let error = InsufficientStock::new(sku.clone(), requested, 2);
        assert_eq!(error.sku(), &sku);
        assert_eq!(error.requested().value(), 4);
        assert_eq!(error.available(), 2);
        let text = error.to_string();
        assert!(
            text.contains("SKU-9") && text.contains("requested 4") && text.contains("available 2")
        );
    }

    #[test]
    fn payment_declined_is_not_an_invalid_order() {
        let error = PaymentDeclined::new("card refused");
        assert_eq!(error.reason(), "card refused");
        assert_eq!(error.to_string(), "payment declined: card refused");
    }

    #[test]
    fn persistence_conflict_carries_its_reason() {
        let error = PersistenceConflict::new("version 0 vs 1");
        assert_eq!(error.reason(), "version 0 vs 1");
        assert!(error.to_string().contains("persistence conflict"));
    }

    #[test]
    fn compensation_failure_names_the_stage() {
        let error = CompensationFailure::new("refund", "forced failure");
        assert_eq!(error.stage(), "refund");
        assert_eq!(error.detail(), "forced failure");
        assert_eq!(
            error.to_string(),
            "compensation failed at refund: forced failure"
        );
    }

    #[test]
    fn already_shipped_names_the_order() {
        let id = OrderId::new("ord-1").unwrap();
        let error = OrderAlreadyShipped::new(id.clone());
        assert_eq!(error.id(), &id);
        assert_eq!(error.to_string(), format!("order {id} has already shipped"));
    }

    #[test]
    fn domain_error_is_transparent_over_its_variants() {
        let verdict = DomainError::from(InvalidOrder::new("boom"));
        assert_eq!(verdict.to_string(), "invalid order: boom");
        match DomainError::from(OrderAlreadyShipped::new(OrderId::from_sequence(1))) {
            DomainError::AlreadyShipped(_) => {}
            other => panic!("expected already-shipped variant, got {other:?}"),
        }
    }
}
