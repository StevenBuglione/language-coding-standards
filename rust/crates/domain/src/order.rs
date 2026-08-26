//! Order entity: the `NEW -> PAID -> SHIPPED` state machine and its invariants.

use std::collections::HashSet;
use std::fmt;
use std::sync::atomic::{AtomicU64, Ordering};

use crate::error::{DomainError, InvalidOrder, OrderAlreadyShipped};
use crate::money::Money;
use crate::quantity::Quantity;
use crate::sku::Sku;

/// Process-local allocator for order identifiers.
static NEXT_ID: AtomicU64 = AtomicU64::new(1);

/// Immutable unique identifier of an order.
///
/// Identifiers are allocated from a process-local counter: uniqueness holds
/// within a process lifetime. The template deliberately avoids a UUID
/// dependency for one value object (see `LANG_SPEC.md`); processes that
/// need cross-restart uniqueness should back this newtype with their own
/// source.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct OrderId(u64);

impl OrderId {
    /// Allocates the next process-unique identifier.
    #[must_use]
    pub fn next() -> Self {
        Self(NEXT_ID.fetch_add(1, Ordering::Relaxed))
    }

    /// Returns the numeric identifier.
    #[must_use]
    pub fn value(self) -> u64 {
        self.0
    }
}

impl fmt::Display for OrderId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "order-{}", self.0)
    }
}

/// States of the canonical order life cycle.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OrderStatus {
    /// Placed, not yet paid.
    New,
    /// Paid, not yet shipped.
    Paid,
    /// Shipped; no mutation is possible anymore.
    Shipped,
}

/// One SKU/quantity/unit-price row of an order.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OrderLine {
    sku: Sku,
    quantity: Quantity,
    unit_price: Money,
}

impl OrderLine {
    /// Builds a line from already-validated value objects.
    ///
    /// The component types carry every invariant, so construction is
    /// infallible.
    #[must_use]
    pub fn new(sku: Sku, quantity: Quantity, unit_price: Money) -> Self {
        Self {
            sku,
            quantity,
            unit_price,
        }
    }

    /// Returns the ordered SKU.
    #[must_use]
    pub fn sku(&self) -> &Sku {
        &self.sku
    }

    /// Returns the ordered quantity.
    #[must_use]
    pub fn quantity(&self) -> Quantity {
        self.quantity
    }

    /// Returns the per-unit price.
    #[must_use]
    pub fn unit_price(&self) -> &Money {
        &self.unit_price
    }

    /// Returns the unit price scaled by the ordered quantity.
    ///
    /// # Errors
    ///
    /// Returns [`InvalidOrder`] when scaling overflows.
    pub fn line_total(&self) -> Result<Money, InvalidOrder> {
        self.unit_price.times(i64::from(self.quantity.value()))
    }
}

/// Order entity enforcing the four canonical invariants:
///
/// 1. at least one line (`Order::new` rejects empty input);
/// 2. no duplicate SKUs across lines (`Order::new` rejects duplicates);
/// 3. the total always equals the sum of line totals (computed on demand,
///    never stored stale);
/// 4. no mutation after `SHIPPED` (`pay`/`ship` refuse with
///    [`OrderAlreadyShipped`]; there is no other mutator).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Order {
    id: OrderId,
    lines: Vec<OrderLine>,
    status: OrderStatus,
}

impl Order {
    /// Places a new order from validated lines, assigning a fresh id.
    ///
    /// # Errors
    ///
    /// Returns [`InvalidOrder`] when `lines` is empty or contains two lines
    /// with the same SKU.
    pub fn new(lines: Vec<OrderLine>) -> Result<Self, InvalidOrder> {
        if lines.is_empty() {
            return Err(InvalidOrder::new("an order requires at least one line"));
        }
        let mut seen = HashSet::with_capacity(lines.len());
        for line in &lines {
            if !seen.insert(line.sku().clone()) {
                return Err(InvalidOrder::new(format!(
                    "duplicate SKU `{}` across order lines are not allowed",
                    line.sku()
                )));
            }
        }
        Ok(Self {
            id: OrderId::next(),
            lines,
            status: OrderStatus::New,
        })
    }

    /// Returns the immutable order identifier.
    #[must_use]
    pub fn id(&self) -> OrderId {
        self.id
    }

    /// Returns the current state-machine state.
    #[must_use]
    pub fn status(&self) -> OrderStatus {
        self.status
    }

    /// Returns the immutable set of order lines.
    #[must_use]
    pub fn lines(&self) -> &[OrderLine] {
        &self.lines
    }

    /// Returns the sum of all line totals in a single currency.
    ///
    /// The total is computed, never cached, so invariant 3 cannot go stale.
    ///
    /// # Errors
    ///
    /// Returns [`InvalidOrder`] when any line total overflows or the running
    /// sum does.
    pub fn total(&self) -> Result<Money, InvalidOrder> {
        let mut line_totals = self.lines.iter().map(OrderLine::line_total);
        let Some(first) = line_totals.next() else {
            return Err(InvalidOrder::new("an order requires at least one line"));
        };
        let mut total = first?;
        for line_total in line_totals {
            total = total.add(&line_total?)?;
        }
        Ok(total)
    }

    /// Transitions `NEW` to `PAID`; refuses paid or already-shipped orders.
    ///
    /// # Errors
    ///
    /// Returns [`DomainError::AlreadyShipped`] for shipped orders and
    /// [`DomainError::InvalidOrder`] for an order that was already paid.
    pub fn pay(&mut self) -> Result<(), DomainError> {
        match self.status {
            OrderStatus::Shipped => Err(DomainError::AlreadyShipped(OrderAlreadyShipped::new(
                self.id,
            ))),
            OrderStatus::Paid => Err(DomainError::InvalidOrder(InvalidOrder::new(
                "order has already been paid",
            ))),
            OrderStatus::New => {
                self.status = OrderStatus::Paid;
                Ok(())
            }
        }
    }

    /// Transitions `PAID` to `SHIPPED`; only paid orders may ship.
    ///
    /// # Errors
    ///
    /// Returns [`DomainError::AlreadyShipped`] for shipped orders and
    /// [`DomainError::InvalidOrder`] for an order that was never paid.
    pub fn ship(&mut self) -> Result<(), DomainError> {
        match self.status {
            OrderStatus::Shipped => Err(DomainError::AlreadyShipped(OrderAlreadyShipped::new(
                self.id,
            ))),
            OrderStatus::New => Err(DomainError::InvalidOrder(InvalidOrder::new(
                "only paid orders can be shipped",
            ))),
            OrderStatus::Paid => {
                self.status = OrderStatus::Shipped;
                Ok(())
            }
        }
    }
}

#[cfg(test)]
mod tests {
    // Documented test-side suppressions (PHILOSOPHY.md §2): production code
    // may never unwrap or panic, but unit tests construct known-valid values
    // and report mismatches by failing loudly. The reasons are the policy.
    #![allow(
        clippy::unwrap_used,
        reason = "tests build known-valid values and read errors"
    )]
    #![allow(clippy::panic, reason = "a failed assertion IS the test failing")]

    use super::*;
    use crate::money::Currency;

    /// Test-only constructor over known-valid literals.
    fn money(units: u64) -> Money {
        Money::from_minor(units, currency())
    }

    /// Test-only constructor over a known-valid literal.
    fn currency() -> Currency {
        Currency::new("EUR").unwrap()
    }

    /// Test-only constructor over known-valid literals.
    fn sku(code: &str) -> Sku {
        Sku::new(code).unwrap()
    }

    /// Test-only constructor over a known-valid literal.
    fn quantity(value: u32) -> Quantity {
        Quantity::new(value).unwrap()
    }

    fn line(code: &str, amount: u32, units: u64) -> OrderLine {
        OrderLine::new(sku(code), quantity(amount), money(units))
    }

    #[test]
    fn empty_lines_are_rejected() {
        let error = Order::new(Vec::new()).unwrap_err();
        assert!(error.reason().contains("at least one line"));
    }

    #[test]
    fn duplicate_skus_are_rejected() {
        let error = Order::new(vec![line("SKU-A", 1, 100), line("SKU-A", 2, 200)]).unwrap_err();
        assert!(error.reason().contains("duplicate SKU"));
    }

    #[test]
    fn total_equals_sum_of_line_totals() {
        let order = Order::new(vec![line("SKU-A", 2, 300), line("SKU-B", 3, 700)]).unwrap();
        assert_eq!(order.total().unwrap().minor_units(), 2_700);
    }

    #[test]
    fn new_order_pays_then_ships() {
        let mut order = Order::new(vec![line("SKU-A", 1, 100)]).unwrap();
        assert_eq!(order.status(), OrderStatus::New);
        assert_eq!(order.pay(), Ok(()));
        assert_eq!(order.status(), OrderStatus::Paid);
        assert_eq!(order.ship(), Ok(()));
        assert_eq!(order.status(), OrderStatus::Shipped);
    }

    #[test]
    fn double_pay_is_rejected() {
        let mut order = Order::new(vec![line("SKU-A", 1, 100)]).unwrap();
        assert_eq!(order.pay(), Ok(()));
        match order.pay() {
            Err(DomainError::InvalidOrder(error)) => {
                assert!(error.reason().contains("already been paid"));
            }
            other => panic!("expected invalid-order verdict, got {other:?}"),
        }
    }

    #[test]
    fn shipping_unpaid_order_is_rejected() {
        let mut order = Order::new(vec![line("SKU-A", 1, 100)]).unwrap();
        match order.ship() {
            Err(DomainError::InvalidOrder(error)) => {
                assert!(error.reason().contains("only paid"));
            }
            other => panic!("expected invalid-order verdict, got {other:?}"),
        }
    }

    #[test]
    fn shipped_order_refuses_every_mutation() {
        let mut order = Order::new(vec![line("SKU-A", 1, 100)]).unwrap();
        assert_eq!(order.pay(), Ok(()));
        assert_eq!(order.ship(), Ok(()));
        let id = order.id();
        match order.pay() {
            Err(DomainError::AlreadyShipped(error)) => assert_eq!(error.id(), id),
            other => panic!("expected already-shipped verdict, got {other:?}"),
        }
        match order.ship() {
            Err(DomainError::AlreadyShipped(_)) => {}
            other => panic!("expected already-shipped verdict, got {other:?}"),
        }
    }
}
