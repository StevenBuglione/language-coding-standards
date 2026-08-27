//! SKU value object: a non-empty stock-keeping-unit code.

use crate::error::InvalidOrder;

/// Shared UTF-8 byte length limit for a normalized SKU code.
pub const SKU_MAX_UTF8_BYTES: usize = 64;

/// A stock-keeping-unit code, normalized on creation.
#[derive(Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct Sku {
    code: String,
}

impl Sku {
    /// Strips ASCII space/tab/CR/LF from both ends and validates the result.
    ///
    /// # Errors
    ///
    /// Returns [`InvalidOrder`] when the normalized code is empty or longer
    /// than [`SKU_MAX_UTF8_BYTES`] UTF-8 bytes.
    pub fn new(code: impl Into<String>) -> Result<Self, InvalidOrder> {
        let code = trim_ascii_edges(&code.into()).to_owned();
        if code.is_empty() {
            return Err(InvalidOrder::new("sku code must be non-empty"));
        }
        if code.len() > SKU_MAX_UTF8_BYTES {
            return Err(InvalidOrder::new(format!(
                "sku code exceeds {SKU_MAX_UTF8_BYTES} UTF-8 bytes"
            )));
        }
        Ok(Self { code })
    }

    /// Returns the normalized code.
    #[must_use]
    pub fn code(&self) -> &str {
        &self.code
    }
}

fn trim_ascii_edges(code: &str) -> &str {
    code.trim_matches(|character: char| matches!(character, ' ' | '\t' | '\r' | '\n'))
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
    fn codes_are_trimmed_of_ascii_space_tab_cr_lf() {
        assert_eq!(Sku::new(" \tSKU-A\r\n ").unwrap().code(), "SKU-A");
    }

    #[test]
    fn interior_spaces_and_case_are_preserved() {
        assert_eq!(Sku::new("SKU A").unwrap().code(), "SKU A");
        assert_eq!(Sku::new("sku-a").unwrap().code(), "sku-a");
    }

    #[test]
    fn nbsp_prefix_is_kept() {
        assert_eq!(Sku::new("\u{00a0}ABC").unwrap().code(), "\u{00a0}ABC");
    }

    #[test]
    fn unicode_within_byte_limit_is_accepted() {
        assert_eq!(Sku::new("café").unwrap().code(), "café");
    }

    #[test]
    fn max_utf8_bytes_are_accepted() {
        let code = "A".repeat(SKU_MAX_UTF8_BYTES);
        assert_eq!(Sku::new(code.clone()).unwrap().code(), code);
    }

    #[test]
    fn above_max_utf8_bytes_is_rejected() {
        let error = Sku::new("A".repeat(SKU_MAX_UTF8_BYTES + 1)).unwrap_err();
        assert!(error.reason().contains("UTF-8 bytes"));
    }

    #[test]
    fn whitespace_only_codes_are_rejected() {
        let error = Sku::new(" \t\r\n ").unwrap_err();
        assert!(error.reason().contains("non-empty"));
    }

    #[test]
    fn empty_codes_are_rejected() {
        let error = Sku::new("").unwrap_err();
        assert!(error.reason().contains("non-empty"));
    }

    #[test]
    fn display_renders_the_code() {
        assert_eq!(Sku::new("SKU-B").unwrap().to_string(), "SKU-B");
    }
}
