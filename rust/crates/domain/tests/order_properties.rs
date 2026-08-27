//! Property test: the order total always equals the sum of line totals.

// Documented test-side suppressions (see src/order.rs).
#![allow(
    clippy::unwrap_used,
    reason = "tests build known-valid values and read errors"
)]
#![allow(clippy::panic, reason = "a failed assertion IS the test failing")]

use proptest::prelude::*;
use warehouse_domain::money::{Currency, Money};
use warehouse_domain::order::{Order, OrderId, OrderLine};
use warehouse_domain::quantity::Quantity;
use warehouse_domain::sku::Sku;

/// Caps keep `sum(qty_i * price_i)` for up to 8 lines far below the shared
/// money maximum, so the only observable failures are genuine logic bugs.
const MAX_LINES: usize = 8;
const MAX_PRICE: u64 = 1_000_000_000_000;
const MAX_QUANTITY: u32 = 1_000;

/// A valid line strategy: (sku seed, quantity, unit price). The SKU seed is
/// only used for generation; lines get unique SKUs from their index.
fn line_strategy() -> impl Strategy<Value = (u32, u32, u64)> {
    (0u32..100_000, 1u32..MAX_QUANTITY, 0u64..MAX_PRICE)
}

fn order_lines(lines: &[(u32, u32, u64)]) -> Vec<OrderLine> {
    let currency = Currency::new("EUR").unwrap();
    lines
        .iter()
        .enumerate()
        .map(|(index, &(_seed, quantity_value, price))| {
            OrderLine::new(
                Sku::new(format!("SKU-{index}")).unwrap(),
                Quantity::new(quantity_value).unwrap(),
                Money::from_minor(price, currency.clone()).unwrap(),
            )
        })
        .collect()
}

fn expected_total(lines: &[OrderLine]) -> u64 {
    lines
        .iter()
        .map(|line| line.unit_price().minor_units() * u64::from(line.quantity().value()))
        .sum()
}

proptest! {
    /// The computed total equals the sum of line totals over randomly
    /// generated valid line sets (CONTRACTS.md §2 required property).
    #[test]
    fn total_equals_sum_of_line_totals(
        lines in proptest::collection::vec(line_strategy(), 1..MAX_LINES),
    ) {
        let order_lines = order_lines(&lines);
        let expected = expected_total(&order_lines);
        let order = Order::new(OrderId::from_sequence(1), order_lines).unwrap();
        prop_assert_eq!(order.total().unwrap().minor_units(), expected);
    }
}
