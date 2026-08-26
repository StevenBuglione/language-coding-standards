//! Adapter layer: in-memory and fake implementations of the ports the
//! application layer owns.
//!
//! These doubles are production-grade test fixtures ([CONTRACTS.md
//! §2](../../docs/CONTRACTS.md)): finite stock, configurable decline, real
//! persistence semantics — used by integration tests and by anyone wiring
//! the use case end to end.

#![allow(
    clippy::module_name_repetitions,
    reason = "adapter names intentionally echo their port (InMemoryInventoryGateway)"
)]

pub mod inventory;
pub mod payments;
pub mod repository;
