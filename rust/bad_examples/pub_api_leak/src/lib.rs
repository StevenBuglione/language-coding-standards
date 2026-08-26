//! Negative fixture: an item marked `pub` that is not reachable from the
//! crate's public API — the pub-by-default discipline leak. Expected trip:
//! the compiler's `unreachable_pub` lint (warn-by-default in edition 2024,
//! fatal under the template's warnings-are-errors posture).

mod internal {
    /// Marked `pub` but its module is private, so no external consumer can
    /// ever reach it.
    pub fn helper() -> u32 {
        4
    }
}

#[must_use]
pub fn visible() -> u32 {
    internal::helper()
}
