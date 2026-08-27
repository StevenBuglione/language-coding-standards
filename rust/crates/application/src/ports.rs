//! Ports: interfaces the application owns and the adapters layer implements.
//!
//! Every fallible port returns a [`Result`] whose failure side is exactly
//! one typed domain error — no panics, no mislabeled declines.

use warehouse_domain::error::{
    CompensationFailure, InsufficientStock, PaymentDeclined, PersistenceConflict,
};
use warehouse_domain::order::{Order, OrderId, OrderLine};

/// Proof that stock for an order was reserved atomically.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReservationToken {
    order_id: OrderId,
    idempotency_key: String,
}

impl ReservationToken {
    /// Builds a token from the reserved order and the command key.
    #[must_use]
    pub fn new(order_id: OrderId, idempotency_key: impl Into<String>) -> Self {
        Self {
            order_id,
            idempotency_key: idempotency_key.into(),
        }
    }

    /// Returns the order this reservation belongs to.
    #[must_use]
    pub fn order_id(&self) -> &OrderId {
        &self.order_id
    }

    /// Returns the idempotency key that produced this reservation.
    #[must_use]
    pub fn idempotency_key(&self) -> &str {
        &self.idempotency_key
    }
}

/// Proof that payment was collected for an idempotency key.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChargeReceipt {
    order_id: OrderId,
    idempotency_key: String,
}

impl ChargeReceipt {
    /// Builds a receipt from the charged order and the command key.
    #[must_use]
    pub fn new(order_id: OrderId, idempotency_key: impl Into<String>) -> Self {
        Self {
            order_id,
            idempotency_key: idempotency_key.into(),
        }
    }

    /// Returns the order this charge belongs to.
    #[must_use]
    pub fn order_id(&self) -> &OrderId {
        &self.order_id
    }

    /// Returns the idempotency key that produced this charge.
    #[must_use]
    pub fn idempotency_key(&self) -> &str {
        &self.idempotency_key
    }
}

/// Outbound port that mints deterministic-in-tests order identifiers.
pub trait OrderIdGenerator {
    /// Returns the next identifier. The domain never allocates its own.
    fn next(&self) -> OrderId;
}

/// Outbound port for atomic stock reservation.
pub trait InventoryGateway {
    /// Reserves every line or none.
    ///
    /// Identical `idempotency_key` retries return the original token
    /// without a second decrement.
    ///
    /// # Errors
    ///
    /// Returns [`InsufficientStock`] when any line cannot be covered.
    fn reserve_all(
        &self,
        order_id: &OrderId,
        lines: &[OrderLine],
        idempotency_key: &str,
    ) -> Result<ReservationToken, InsufficientStock>;

    /// Puts reserved units back.
    ///
    /// # Errors
    ///
    /// Returns [`CompensationFailure`] when release itself fails.
    fn release(&self, token: &ReservationToken) -> Result<(), CompensationFailure>;
}

/// Outbound port for idempotent payment collection.
pub trait PaymentProcessor {
    /// Charges the order total; identical retries return the same receipt.
    ///
    /// A declined collection is [`PaymentDeclined`], never `InvalidOrder`.
    ///
    /// # Errors
    ///
    /// Returns [`PaymentDeclined`] when the processor refuses the charge.
    fn charge(
        &self,
        order: &Order,
        idempotency_key: &str,
    ) -> Result<ChargeReceipt, PaymentDeclined>;

    /// Voids or refunds a prior charge.
    ///
    /// # Errors
    ///
    /// Returns [`CompensationFailure`] when refund itself fails.
    fn refund(&self, receipt: &ChargeReceipt) -> Result<(), CompensationFailure>;
}

/// Outbound port that persists and retrieves immutable snapshots.
pub trait OrderRepository {
    /// Persists with compare-and-set semantics and returns a snapshot.
    ///
    /// # Errors
    ///
    /// Returns [`PersistenceConflict`] when `expected_version` does not
    /// match the stored version (or `0` for a first insert).
    fn save(&self, order: &Order, expected_version: u32) -> Result<Order, PersistenceConflict>;

    /// Returns a stored snapshot or [`None`]; an unknown id never raises.
    #[must_use]
    fn get(&self, order_id: &OrderId) -> Option<Order>;

    /// Returns fingerprint and snapshot for a previous successful command.
    #[must_use]
    fn get_by_idempotency_key(&self, key: &str) -> Option<(String, Order)>;

    /// Records a successful command so retries can replay.
    fn remember_idempotency(&self, key: &str, fingerprint: &str, order: &Order);
}
