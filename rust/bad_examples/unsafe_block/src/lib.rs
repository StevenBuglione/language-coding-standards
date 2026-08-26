//! Negative fixture: an `unsafe` block where the template forbids unsafe
//! code. The fixture declares the rule itself (`[lints.rust] unsafe_code =
//! "forbid"` in its manifest) so a plain `cargo check` is already a hard
//! compile error — exactly what production code would hit.

/// Reads through a raw pointer — forbidden under `unsafe_code = "forbid"`.
pub fn read_raw(pointer: *const u8) -> u8 {
    unsafe { *pointer }
}
