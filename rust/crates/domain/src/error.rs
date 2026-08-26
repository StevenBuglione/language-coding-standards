//! Typed domain errors raised by the pure domain layer.
//!
//! Exactly three rule verdicts exist ([CONTRACTS.md §2](../../docs/CONTRACTS.md)):
//! [`InvalidOrder`], [`InsufficientStock`], and [`OrderAlreadyShipped`].
//! [`DomainError`] bundles them where a call site can produce more than one.

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

/// A shipped order can no longer be mutated.
#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
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
    pub fn id(&self) -> OrderId {
        self.id
    }
}

/// Exactly one of the three canonical domain-rule verdicts.
///
/// Call sites that can produce several verdicts (the `Order` transitions)
/// return this enum; ports narrow it down to the single verdict they can
/// raise.
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
    fn already_shipped_names_the_order() {
        let id = OrderId::next();
        let error = OrderAlreadyShipped::new(id);
        assert_eq!(error.id(), id);
        assert_eq!(error.to_string(), format!("order {id} has already shipped"));
    }

    #[test]
    fn domain_error_is_transparent_over_its_variants() {
        let verdict = DomainError::from(InvalidOrder::new("boom"));
        assert_eq!(verdict.to_string(), "invalid order: boom");
        match DomainError::from(OrderAlreadyShipped::new(OrderId::next())) {
            DomainError::AlreadyShipped(_) => {}
            other => panic!("expected already-shipped variant, got {other:?}"),
        }
    }
}
