//! Negative fixture: `Option::unwrap` in library code. Expected trip:
//! clippy::unwrap_used (denied by workspace lints).

#[must_use]
pub fn first_word(text: &str) -> &str {
    text.split_whitespace().next().unwrap()
}
