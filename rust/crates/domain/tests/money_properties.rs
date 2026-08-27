//! Property tests for `Money` arithmetic (proptest).

// Documented test-side suppressions (see src/order.rs): strategies build
// known-valid values; shrinking failures report through panics.
#![allow(
    clippy::unwrap_used,
    reason = "tests build known-valid values and read errors"
)]
#![allow(clippy::panic, reason = "a failed assertion IS the test failing")]

use proptest::prelude::*;
use warehouse_domain::money::{Currency, Money};

/// Amount cap keeps every sum in these properties far below the shared max.
const MAX_AMOUNT: u64 = 1_000_000_000_000;

/// Fixed valid currency pool; index selects into it without slicing.
fn currency(index: usize) -> Currency {
    let codes = ["EUR", "USD", "JPY"];
    let code = codes
        .iter()
        .copied()
        .nth(index % codes.len())
        .unwrap_or("EUR");
    Currency::new(code).unwrap()
}

proptest! {
    /// Money addition is commutative within one currency.
    #[test]
    fn addition_is_commutative(
        left in 0u64..MAX_AMOUNT,
        right in 0u64..MAX_AMOUNT,
        currency_index in any::<usize>(),
    ) {
        let currency = currency(currency_index);
        let a = Money::from_minor(left, currency.clone()).unwrap();
        let b = Money::from_minor(right, currency).unwrap();
        assert_eq!(a.add(&b).unwrap(), b.add(&a).unwrap());
    }

    /// Cross-currency arithmetic is rejected as invalid — in BOTH argument
    /// orders (CONTRACTS.md §2 binding clarification).
    #[test]
    fn currency_mismatch_is_rejected_in_both_orders(
        left in 0u64..MAX_AMOUNT,
        right in 0u64..MAX_AMOUNT,
        a_index in 0usize..3usize,
        offset in 1usize..3usize,
    ) {
        // offset is 1 or 2, so `(a_index + offset) % 3` never equals
        // `a_index`: the two currencies are always distinct.
        let b_index = (a_index + offset) % 3;
        let first = Money::from_minor(left, currency(a_index)).unwrap();
        let second = Money::from_minor(right, currency(b_index)).unwrap();
        prop_assert_ne!(first.currency(), second.currency());
        let forward = first.add(&second).unwrap_err();
        let backward = second.add(&first).unwrap_err();
        prop_assert!(forward.reason().contains("currency mismatch"));
        prop_assert!(backward.reason().contains("currency mismatch"));
    }
}
