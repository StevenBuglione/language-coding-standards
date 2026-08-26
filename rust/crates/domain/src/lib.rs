//! Pure domain model for the canonical warehouse-order example
//! ([CONTRACTS.md §2](../../docs/CONTRACTS.md)).
//!
//! This crate is the innermost layer: it may depend on nothing but
//! [`thiserror`]. Every invariant the business cares about is encoded either
//! in a type (`u64` minor units cannot go negative) or in a fallible
//! constructor returning [`error::InvalidOrder`] — never in prose.

// Type names echoing their module (`money::Money`) is idiomatic Rust naming;
// renaming modules to dodge the lint would hurt readability.
#![allow(
    clippy::module_name_repetitions,
    reason = "idiomatic type-per-module naming"
)]

pub mod error;
pub mod money;
pub mod order;
pub mod quantity;
pub mod sku;
