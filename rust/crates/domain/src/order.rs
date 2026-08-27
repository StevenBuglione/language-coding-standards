//! Order entity: the `NEW -> PAID -> SHIPPED` state machine and its invariants.

use std::collections::HashSet;
use std::fmt;

use crate::error::{DomainError, InvalidOrder, OrderAlreadyShipped};
use crate::money::Money;
use crate::quantity::Quantity;
use crate::sku::Sku;

/// Immutable unique identifier of an order, injected by the application.
///
/// The domain never reads randomness, a process-global counter, or the
/// clock. Generators live in adapters.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct OrderId(String);

impl OrderId {
    /// Allocates an identifier from a numeric sequence (used by generators).
    #[must_use]
    pub fn from_sequence(value: u64) -> Self {
        Self(format!("ord-{value}"))
    }

    /// Validates and constructs an identifier from an injected token.
    ///
    /// # Errors
    ///
    /// Returns [`InvalidOrder`] when `value` is empty or whitespace-only.
    pub fn new(value: impl Into<String>) -> Result<Self, InvalidOrder> {
        let value = value.into();
        if value.is_empty() || value.trim().is_empty() {
            return Err(InvalidOrder::new("order id must be non-empty"));
        }
        Ok(Self(value))
    }

    /// Returns the identifier token.
    #[must_use]
    pub fn value(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for OrderId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
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

/// Order entity enforcing the canonical invariants:
///
/// 1. injected id; at least one line (`Order::new` rejects empty input);
/// 2. no duplicate normalized SKUs across lines;
/// 3. a single currency at construction, not delayed until `total()`;
/// 4. the total always equals the sum of line totals (computed on demand);
/// 5. only `NEW -> PAID -> SHIPPED` is legal; optimistic version starts at 0.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Order {
    id: OrderId,
    lines: Vec<OrderLine>,
    status: OrderStatus,
    version: u32,
}

impl Order {
    /// Places a new order from an injected id and validated lines.
    ///
    /// # Errors
    ///
    /// Returns [`InvalidOrder`] when `lines` is empty, contains two lines
    /// with the same normalized SKU, or mixes currencies.
    pub fn new(id: OrderId, lines: Vec<OrderLine>) -> Result<Self, InvalidOrder> {
        validate_lines(&lines)?;
        Ok(Self {
            id,
            lines,
            status: OrderStatus::New,
            version: 0,
        })
    }

    /// Returns the immutable order identifier.
    #[must_use]
    pub fn id(&self) -> &OrderId {
        &self.id
    }

    /// Returns the current state-machine state.
    #[must_use]
    pub fn status(&self) -> OrderStatus {
        self.status
    }

    /// Returns the optimistic concurrency version.
    #[must_use]
    pub fn version(&self) -> u32 {
        self.version
    }

    /// Returns the immutable set of order lines.
    #[must_use]
    pub fn lines(&self) -> &[OrderLine] {
        &self.lines
    }

    /// Returns a detached copy so repositories cannot alias stored state.
    #[must_use]
    pub fn snapshot(&self) -> Self {
        self.clone()
    }

    /// Increments the optimistic version after a successful save.
    pub fn bump_version(&mut self) {
        self.version = self.version.saturating_add(1);
    }

    /// Returns the sum of all line totals in a single currency.
    ///
    /// The total is computed, never cached, so it cannot go stale.
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
                self.id.clone(),
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
                self.id.clone(),
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

fn validate_lines(lines: &[OrderLine]) -> Result<(), InvalidOrder> {
    if lines.is_empty() {
        return Err(InvalidOrder::new("an order requires at least one line"));
    }
    reject_duplicate_skus(lines)?;
    reject_mixed_currencies(lines)
}

fn reject_duplicate_skus(lines: &[OrderLine]) -> Result<(), InvalidOrder> {
    let mut seen = HashSet::with_capacity(lines.len());
    for line in lines {
        if !seen.insert(line.sku().clone()) {
            return Err(InvalidOrder::new(format!(
                "duplicate SKU `{}` across order lines are not allowed",
                line.sku()
            )));
        }
    }
    Ok(())
}

fn reject_mixed_currencies(lines: &[OrderLine]) -> Result<(), InvalidOrder> {
    let Some(first) = lines.first() else {
        return Ok(());
    };
    let currency = first.unit_price().currency();
    if lines
        .iter()
        .any(|line| line.unit_price().currency() != currency)
    {
        return Err(InvalidOrder::new("mixed currencies are not allowed"));
    }
    Ok(())
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

    fn money(units: u64) -> Money {
        Money::from_minor(units, currency()).unwrap()
    }

    fn money_in(units: u64, code: &str) -> Money {
        Money::from_minor(units, Currency::new(code).unwrap()).unwrap()
    }

    fn currency() -> Currency {
        Currency::new("EUR").unwrap()
    }

    fn sku(code: &str) -> Sku {
        Sku::new(code).unwrap()
    }

    fn quantity(value: u32) -> Quantity {
        Quantity::new(value).unwrap()
    }

    fn line(code: &str, amount: u32, units: u64) -> OrderLine {
        OrderLine::new(sku(code), quantity(amount), money(units))
    }

    fn order_id(value: &str) -> OrderId {
        OrderId::new(value).unwrap()
    }

    fn placed(lines: Vec<OrderLine>) -> Order {
        Order::new(order_id("ord-1"), lines).unwrap()
    }

    #[test]
    fn empty_lines_are_rejected() {
        let error = Order::new(order_id("ord-1"), Vec::new()).unwrap_err();
        assert!(error.reason().contains("at least one line"));
    }

    #[test]
    fn duplicate_skus_are_rejected() {
        let error = placed_err(vec![line("SKU-A", 1, 100), line("SKU-A", 2, 200)]);
        assert!(error.reason().contains("duplicate SKU"));
    }

    #[test]
    fn duplicate_skus_after_normalization_are_rejected() {
        let error = placed_err(vec![line("SKU-A", 1, 100), line(" SKU-A ", 1, 100)]);
        assert!(error.reason().contains("duplicate SKU"));
    }

    fn placed_err(lines: Vec<OrderLine>) -> InvalidOrder {
        Order::new(order_id("ord-1"), lines).unwrap_err()
    }

    #[test]
    fn mixed_currencies_are_rejected_at_construction() {
        let mixed = vec![
            line("SKU-A", 1, 100),
            OrderLine::new(sku("SKU-B"), quantity(1), money_in(100, "USD")),
        ];
        let error = Order::new(order_id("ord-6"), mixed).unwrap_err();
        assert!(error.reason().contains("mixed currencies"));
    }

    #[test]
    fn injected_id_is_stored_and_version_starts_at_zero() {
        let order = Order::new(order_id("ord-fixed-9"), vec![line("SKU-A", 1, 100)]).unwrap();
        assert_eq!(order.id().value(), "ord-fixed-9");
        assert_eq!(order.status(), OrderStatus::New);
        assert_eq!(order.version(), 0);
    }

    #[test]
    fn empty_order_id_is_rejected() {
        let error = OrderId::new("   ").unwrap_err();
        assert!(error.reason().contains("non-empty"));
    }

    #[test]
    fn total_equals_sum_of_line_totals() {
        let order = placed(vec![line("SKU-A", 2, 300), line("SKU-B", 3, 700)]);
        assert_eq!(order.total().unwrap().minor_units(), 2_700);
    }

    #[test]
    fn new_order_pays_then_ships() {
        let mut order = placed(vec![line("SKU-A", 1, 100)]);
        assert_eq!(order.status(), OrderStatus::New);
        assert_eq!(order.pay(), Ok(()));
        assert_eq!(order.status(), OrderStatus::Paid);
        assert_eq!(order.ship(), Ok(()));
        assert_eq!(order.status(), OrderStatus::Shipped);
    }

    #[test]
    fn double_pay_is_rejected() {
        let mut order = placed(vec![line("SKU-A", 1, 100)]);
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
        let mut order = placed(vec![line("SKU-A", 1, 100)]);
        match order.ship() {
            Err(DomainError::InvalidOrder(error)) => {
                assert!(error.reason().contains("only paid"));
            }
            other => panic!("expected invalid-order verdict, got {other:?}"),
        }
    }

    #[test]
    fn shipped_order_refuses_every_mutation() {
        let mut order = placed(vec![line("SKU-A", 1, 100)]);
        assert_eq!(order.pay(), Ok(()));
        assert_eq!(order.ship(), Ok(()));
        let id = order.id().clone();
        match order.pay() {
            Err(DomainError::AlreadyShipped(error)) => assert_eq!(error.id(), &id),
            other => panic!("expected already-shipped variant, got {other:?}"),
        }
        match order.ship() {
            Err(DomainError::AlreadyShipped(_)) => {}
            other => panic!("expected already-shipped verdict, got {other:?}"),
        }
    }

    #[test]
    fn snapshot_is_detached_from_the_original() {
        let order = placed(vec![line("SKU-A", 1, 100)]);
        let mut copy = order.snapshot();
        copy.pay().unwrap();
        copy.bump_version();
        assert_eq!(order.status(), OrderStatus::New);
        assert_eq!(order.version(), 0);
    }

    #[test]
    fn sequence_ids_are_never_empty() {
        assert_eq!(OrderId::from_sequence(7).value(), "ord-7");
        assert_eq!(OrderId::from_sequence(7).to_string(), "ord-7");
    }
}
