"""
Ports: interfaces the application owns and the adapters layer implements.

Fallible ports return a result union instead of raising.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING, Protocol

if TYPE_CHECKING:
    from collections.abc import Sequence

    from warehouse.domain.errors import (
        CompensationFailure,
        InsufficientStock,
        PaymentDeclined,
        PersistenceConflict,
    )
    from warehouse.domain.order import Order, OrderId, OrderLine


@dataclass(frozen=True, slots=True)
class ReservationToken:
    """Proof that stock for an order was reserved atomically."""

    order_id: OrderId
    idempotency_key: str


@dataclass(frozen=True, slots=True)
class ChargeReceipt:
    """Proof that payment was collected for an idempotency key."""

    order_id: OrderId
    idempotency_key: str


class OrderIdGenerator(Protocol):
    """Outbound port that mints deterministic-in-tests order identifiers."""

    def next(self) -> OrderId:
        """Return the next identifier."""
        ...


class InventoryGateway(Protocol):
    """Outbound port for atomic stock reservation."""

    def reserve_all(
        self,
        order_id: OrderId,
        lines: Sequence[OrderLine],
        idempotency_key: str,
    ) -> ReservationToken | InsufficientStock:
        """Reserve every line or none."""
        ...

    def release(
        self,
        token: ReservationToken,
    ) -> None | CompensationFailure:
        """Release a previous reservation."""
        ...


class PaymentProcessor(Protocol):
    """Outbound port for idempotent payment collection."""

    def charge(
        self,
        order: Order,
        idempotency_key: str,
    ) -> ChargeReceipt | PaymentDeclined:
        """Charge the order total; identical retries return the same receipt."""
        ...

    def refund(
        self,
        receipt: ChargeReceipt,
    ) -> None | CompensationFailure:
        """Void or refund a prior charge."""
        ...


class OrderRepository(Protocol):
    """Outbound port that persists and retrieves immutable snapshots."""

    def save(self, order: Order, expected_version: int) -> Order | PersistenceConflict:
        """Persist with compare-and-set semantics; return a snapshot."""
        ...

    def get(self, order_id: OrderId) -> Order | None:
        """Return a stored snapshot or None; absence never raises."""
        ...

    def get_by_idempotency_key(self, key: str) -> tuple[str, Order] | None:
        """Return fingerprint and snapshot for a previous successful command."""
        ...

    def remember_idempotency(self, key: str, fingerprint: str, order: Order) -> None:
        """Record a successful command so retries can replay."""
        ...
