//! Negative fixture: code that violates rustfmt's canonical layout.
//! Expected trip: `cargo fmt --check` exits nonzero with a diff.

#[must_use]
pub   fn cramped( a :u32,b:u32)->u32   {a+b}
