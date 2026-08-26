//! Negative fixture: unchecked slice indexing that can panic on a short
//! input. Expected trip: clippy::indexing_slicing (denied by workspace
//! lints).

#[must_use]
pub fn third(items: &[u32]) -> u32 {
    items[2]
}
