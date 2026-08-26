//! Ports: interfaces the application owns and the adapters layer implements.
//!
//! Every fallible port returns a [`Result`] whose failure side is exactly
//! one typed domain error — no exceptions cross the boundary because Rust
//! has none, and no panics because the workspace denies [`panic!`].

use warehouse_domain::error::{InsufficientStock, InvalidOrder};
use warehouse_domain::order::Order;
use warehouse_domain::order::OrderId;
use warehouse_domain::quantity::Quantity;
use warehouse_domain::sku::Sku;

/// Success marker proving a stock reservation happened.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Reserved;

/// Success marker proving a payment collection happened.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Charged;

/// Outbound port for reserving stock on the inventory edge.
pub trait InventoryGateway {
    /// Attempts a reservation; reports shortage as a typed failure.
    ///
    /// # Errors
    ///
    /// Returns [`InsufficientStock`] when the available stock cannot cover
    /// `quantity`.
    fn reserve(&mut self, sku: Sku, quantity: Quantity) -> Result<Reserved, InsufficientStock>;
}

/// Outbound port for collecting payment on the payments edge.
pub trait PaymentProcessor {
    /// Attempts collection; reports refusal as a typed failure.
    ///
    /// A declined collection is refused by domain rules, hence
    /// [`InvalidOrder`] ([CONTRACTS.md §2](../../docs/CONTRACTS.md)).
    ///
    /// # Errors
    ///
    /// Returns [`InvalidOrder`] when the payment is refused.
    fn charge(&mut self, order: &Order) -> Result<Charged, InvalidOrder>;
}

/// Outbound port that persists and retrieves orders.
pub trait OrderRepository {
    /// Persists the order and returns the persisted snapshot.
    fn save(&mut self, order: Order) -> Order;

    /// Returns the stored order or [`None`]; an unknown id never raises.
    #[must_use]
    fn get(&self, order_id: OrderId) -> Option<Order>;
}
