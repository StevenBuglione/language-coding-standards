//! Quantity value object: a strictly positive integer.

use std::fmt;

use crate::error::InvalidOrder;

/// Shared quantity maximum (`i32::MAX`) so every language pack can represent it.
pub const QUANTITY_MAX: u32 = 2_147_483_647;

/// An amount of stock that must be strictly positive.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Quantity {
    value: u32,
}

impl Quantity {
    /// Validates and constructs a quantity.
    ///
    /// # Errors
    ///
    /// Returns [`InvalidOrder`] when `value` is zero or above [`QUANTITY_MAX`];
    /// the type cannot hold negatives at all.
    pub fn new(value: u32) -> Result<Self, InvalidOrder> {
        if value == 0 {
            return Err(InvalidOrder::new(
                "quantity must be strictly positive, got 0",
            ));
        }
        if value > QUANTITY_MAX {
            return Err(InvalidOrder::new(format!(
                "quantity exceeds {QUANTITY_MAX}, got {value}"
            )));
        }
        Ok(Self { value })
    }

    /// Returns the strictly positive amount.
    #[must_use]
    pub fn value(self) -> u32 {
        self.value
    }
}

impl fmt::Display for Quantity {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.value)
    }
}

#[cfg(test)]
mod tests {
    // Documented test-side suppressions (see src/order.rs).
    #![allow(
        clippy::unwrap_used,
        reason = "tests build known-valid values and read errors"
    )]

    use super::*;

    #[test]
    fn zero_is_rejected() {
        let error = Quantity::new(0).unwrap_err();
        assert!(error.reason().contains("strictly positive"));
    }

    #[test]
    fn positive_values_are_accepted_and_preserved() {
        assert_eq!(Quantity::new(1).unwrap().value(), 1);
        assert_eq!(Quantity::new(QUANTITY_MAX).unwrap().value(), QUANTITY_MAX);
    }

    #[test]
    fn above_max_is_rejected() {
        let error = Quantity::new(QUANTITY_MAX + 1).unwrap_err();
        assert!(error.reason().contains("exceeds"));
    }

    #[test]
    fn display_renders_the_value() {
        assert_eq!(Quantity::new(7).unwrap().to_string(), "7");
    }
}
