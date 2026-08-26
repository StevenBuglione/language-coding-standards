//! Use-case layer for the canonical warehouse-order example.
//!
//! The ports ([`ports`]) are owned HERE — the inner layer defines what it
//! needs, `warehouse-adapters` implements them. Production dependency
//! direction is `adapters -> application -> domain`; nothing in this crate
//! may import `warehouse-adapters` outside `#[cfg(test)]` targets.

// Type names echoing their module (`ports::InventoryGateway` lives beside
// `place_order`) is idiomatic; see domain's matching note.
#![allow(
    clippy::module_name_repetitions,
    reason = "idiomatic type-per-module naming"
)]

pub mod place_order;
pub mod ports;
