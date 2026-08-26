//! Money value object: integer minor units plus an ISO 4217 currency code.

use crate::error::InvalidOrder;

/// An ISO 4217 currency code: exactly three uppercase ASCII letters.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct Currency {
    code: String,
}

impl Currency {
    /// Validates and constructs a currency from its three-letter code.
    ///
    /// # Errors
    ///
    /// Returns [`InvalidOrder`] when `code` is not exactly three uppercase
    /// ASCII letters.
    pub fn new(code: &str) -> Result<Self, InvalidOrder> {
        let is_valid = code.len() == 3 && code.bytes().all(|byte| byte.is_ascii_uppercase());
        if !is_valid {
            return Err(InvalidOrder::new(format!(
                "currency must be a three-letter uppercase code, got `{code}`"
            )));
        }
        Ok(Self {
            code: code.to_owned(),
        })
    }

    /// Returns the three-letter code.
    #[must_use]
    pub fn code(&self) -> &str {
        &self.code
    }
}

impl std::fmt::Display for Currency {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.code)
    }
}

/// A non-negative amount in integer minor units of a single currency.
///
/// The minor-unit field is `u64`, so negativity is unrepresentable by
/// construction; [`Money::new`] exists for signed boundaries (other
/// languages, wire formats) and rejects negative input explicitly.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Money {
    minor_units: u64,
    currency: Currency,
}

impl Money {
    /// Constructs money from an unsigned amount and a currency.
    ///
    /// The non-negative invariant holds structurally; this constructor
    /// cannot fail.
    #[must_use]
    pub fn from_minor(minor_units: u64, currency: Currency) -> Self {
        Self {
            minor_units,
            currency,
        }
    }

    /// Constructs money from a signed boundary value.
    ///
    /// # Errors
    ///
    /// Returns [`InvalidOrder`] when `minor_units` is negative.
    pub fn new(minor_units: i64, currency: Currency) -> Result<Self, InvalidOrder> {
        let amount = u64::try_from(minor_units).map_err(|_| {
            InvalidOrder::new(format!(
                "money amount must be non-negative, got {minor_units}"
            ))
        })?;
        Ok(Self::from_minor(amount, currency))
    }

    /// Returns the amount in minor units.
    #[must_use]
    pub fn minor_units(&self) -> u64 {
        self.minor_units
    }

    /// Returns the currency of the amount.
    #[must_use]
    pub fn currency(&self) -> &Currency {
        &self.currency
    }

    /// Returns the sum of two amounts.
    ///
    /// # Errors
    ///
    /// Returns [`InvalidOrder`] on a currency mismatch (cross-currency
    /// arithmetic is invalid per [CONTRACTS.md §2](../../docs/CONTRACTS.md))
    /// or on `u64` overflow.
    pub fn add(&self, other: &Self) -> Result<Self, InvalidOrder> {
        if self.currency != other.currency {
            return Err(InvalidOrder::new(format!(
                "currency mismatch: {} vs {}",
                self.currency, other.currency
            )));
        }
        let total = self
            .minor_units
            .checked_add(other.minor_units)
            .ok_or_else(|| InvalidOrder::new("money addition overflowed"))?;
        Ok(Self::from_minor(total, self.currency.clone()))
    }

    /// Returns this amount scaled by a non-negative multiplier.
    ///
    /// # Errors
    ///
    /// Returns [`InvalidOrder`] when `multiplier` is negative or scaling
    /// overflows `u64`.
    pub fn times(&self, multiplier: i64) -> Result<Self, InvalidOrder> {
        let factor = u64::try_from(multiplier).map_err(|_| {
            InvalidOrder::new(format!("multiplier must be non-negative, got {multiplier}"))
        })?;
        let scaled = self.minor_units.checked_mul(factor).ok_or_else(|| {
            InvalidOrder::new(format!(
                "scaling {} by {multiplier} overflowed",
                self.minor_units
            ))
        })?;
        Ok(Self::from_minor(scaled, self.currency.clone()))
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
    fn currency_rejects_non_uppercase_codes() {
        assert!(Currency::new("eur").is_err());
    }

    #[test]
    fn currency_rejects_wrong_length_codes() {
        assert!(Currency::new("EURO").is_err());
        assert!(Currency::new("EU").is_err());
        assert!(Currency::new("").is_err());
    }

    #[test]
    fn signed_negative_amounts_are_rejected() {
        let error = Money::new(-1, Currency::new("EUR").unwrap()).unwrap_err();
        assert!(error.reason().contains("non-negative"));
    }

    #[test]
    fn signed_constructor_accepts_zero() {
        let money = Money::new(0, Currency::new("EUR").unwrap()).unwrap();
        assert_eq!(money.minor_units(), 0);
    }

    #[test]
    fn addition_sums_minor_units_within_one_currency() {
        let a = Money::from_minor(250, Currency::new("USD").unwrap());
        let b = Money::from_minor(175, Currency::new("USD").unwrap());
        assert_eq!(a.add(&b).unwrap().minor_units(), 425);
    }

    #[test]
    fn cross_currency_addition_is_rejected() {
        let euros = Money::from_minor(100, Currency::new("EUR").unwrap());
        let dollars = Money::from_minor(100, Currency::new("USD").unwrap());
        let error = euros.add(&dollars).unwrap_err();
        assert!(error.reason().contains("currency mismatch"));
    }

    #[test]
    fn overflowing_addition_is_rejected() {
        let max = Money::from_minor(u64::MAX, Currency::new("EUR").unwrap());
        let one = Money::from_minor(1, Currency::new("EUR").unwrap());
        assert!(max.add(&one).is_err());
    }

    #[test]
    fn times_scales_by_a_positive_factor() {
        let money = Money::from_minor(300, Currency::new("EUR").unwrap());
        assert_eq!(money.times(3).unwrap().minor_units(), 900);
        assert_eq!(money.times(0).unwrap().minor_units(), 0);
    }

    #[test]
    fn negative_multipliers_are_rejected() {
        let money = Money::from_minor(300, Currency::new("EUR").unwrap());
        let error = money.times(-2).unwrap_err();
        assert!(error.reason().contains("multiplier must be non-negative"));
    }

    #[test]
    fn overflowing_scaling_is_rejected() {
        let max = Money::from_minor(u64::MAX, Currency::new("EUR").unwrap());
        assert!(max.times(2).is_err());
    }

    #[test]
    fn display_renders_the_currency_code() {
        assert_eq!(Currency::new("JPY").unwrap().to_string(), "JPY");
    }
}
