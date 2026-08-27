//! Deterministic order-id generators for tests and in-memory wiring.

use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};

use warehouse_application::ports::OrderIdGenerator;
use warehouse_domain::order::OrderId;

/// Issues `ord-1`, `ord-2`, ... from a process-local counter.
///
/// The domain never reads this counter; the application injects it.
#[derive(Debug, Clone)]
pub struct SequenceOrderIdGenerator {
    next: Arc<AtomicU64>,
}

impl SequenceOrderIdGenerator {
    /// Starts so the first id is `ord-1`.
    #[must_use]
    pub fn new() -> Self {
        Self {
            next: Arc::new(AtomicU64::new(1)),
        }
    }
}

impl Default for SequenceOrderIdGenerator {
    fn default() -> Self {
        Self::new()
    }
}

impl OrderIdGenerator for SequenceOrderIdGenerator {
    fn next(&self) -> OrderId {
        OrderId::from_sequence(self.next.fetch_add(1, Ordering::Relaxed))
    }
}

/// Always returns the same injected identifier.
#[derive(Debug, Clone)]
pub struct FixedOrderIdGenerator {
    id: OrderId,
}

impl FixedOrderIdGenerator {
    /// Holds a single identifier.
    #[must_use]
    pub fn new(id: OrderId) -> Self {
        Self { id }
    }
}

impl OrderIdGenerator for FixedOrderIdGenerator {
    fn next(&self) -> OrderId {
        self.id.clone()
    }
}

#[cfg(test)]
mod tests {
    #![allow(
        clippy::unwrap_used,
        reason = "tests build known-valid values and read errors"
    )]

    use super::*;

    #[test]
    fn sequence_issues_ord_one_then_two() {
        let generator = SequenceOrderIdGenerator::default();
        assert_eq!(generator.next().value(), "ord-1");
        assert_eq!(generator.next().value(), "ord-2");
    }

    #[test]
    fn clones_share_the_counter() {
        let generator = SequenceOrderIdGenerator::new();
        let clone = generator.clone();
        assert_eq!(generator.next().value(), "ord-1");
        assert_eq!(clone.next().value(), "ord-2");
    }

    #[test]
    fn fixed_repeats_the_injected_id() {
        let id = OrderId::new("ord-fixed-9").unwrap();
        let generator = FixedOrderIdGenerator::new(id.clone());
        assert_eq!(generator.next(), id);
        assert_eq!(generator.next(), id);
    }
}
