"""
Ports: interfaces the application owns and the adapters layer implements.

Every fallible port returns a result union instead of raising: success carries
a frozen outcome marker, failure carries exactly one typed domain error.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING, Protocol

if TYPE_CHECKING:
    from warehouse.domain.errors import InsufficientStock, InvalidOrder
    from warehouse.domain.order import Order, OrderId
    from warehouse.domain.quantity import Quantity
    from warehouse.domain.sku import Sku


@dataclass(frozen=True, slots=True)
class Reserved:
    """Success marker proving a stock reservation happened."""


@dataclass(frozen=True, slots=True)
class Charged:
    """Success marker proving a payment collection happened."""


class InventoryGateway(Protocol):
    """Outbound port for reserving stock on the inventory edge."""

    def reserve(self, sku: Sku, quantity: Quantity) -> Reserved | InsufficientStock:
        """Attempt a reservation; report shortage as a typed failure."""
        ...


class PaymentProcessor(Protocol):
    """Outbound port for collecting payment on the payments edge."""

    def charge(self, order: Order) -> Charged | InvalidOrder:
        """Attempt collection; report refusal as a typed failure."""
        ...


class OrderRepository(Protocol):
    """Outbound port that persists and retrieves orders."""

    def save(self, order: Order) -> Order:
        """Persist the order and return the persisted snapshot."""
        ...

    def get(self, order_id: OrderId) -> Order | None:
        """Return the stored order or None; absence never raises."""
        ...
