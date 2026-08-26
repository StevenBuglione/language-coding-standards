//! Negative fixture: a private helper nothing calls. Expected trip: the
//! compiler's `dead_code` lint ("never used"), fatal under the template's
//! warnings-are-errors posture.

/// Orphaned helper that no public item ever reaches.
fn orphaned_helper() -> u32 {
    7
}

#[must_use]
pub fn entry_point() -> u32 {
    1
}
