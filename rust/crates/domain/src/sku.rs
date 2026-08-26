//! SKU value object: a non-empty trimmed stock-keeping-unit code.

use crate::error::InvalidOrder;

/// A stock-keeping-unit code, normalized to its trimmed form on creation.
#[derive(Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct Sku {
    code: String,
}

impl Sku {
    /// Trims surrounding whitespace and validates the result.
    ///
    /// # Errors
    ///
    /// Returns [`InvalidOrder`] when the trimmed code is empty.
    pub fn new(code: impl Into<String>) -> Result<Self, InvalidOrder> {
        let trimmed = code.into().trim().to_owned();
        if trimmed.is_empty() {
            return Err(InvalidOrder::new("sku code must be non-empty"));
        }
        Ok(Self { code: trimmed })
    }

    /// Returns the normalized code.
    #[must_use]
    pub fn code(&self) -> &str {
        &self.code
    }
}

impl std::fmt::Display for Sku {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.code)
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
    fn codes_are_trimmed_on_construction() {
        assert_eq!(Sku::new("  SKU-A  ").unwrap().code(), "SKU-A");
    }

    #[test]
    fn whitespace_only_codes_are_rejected() {
        let error = Sku::new("   ").unwrap_err();
        assert!(error.reason().contains("non-empty"));
    }

    #[test]
    fn display_renders_the_code() {
        assert_eq!(Sku::new("SKU-B").unwrap().to_string(), "SKU-B");
    }
}
