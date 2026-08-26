"""Typed domain errors raised by the pure domain layer."""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from warehouse.domain.quantity import Quantity
    from warehouse.domain.sku import Sku


class DomainError(Exception):
    """Base class for every recoverable domain-rule violation."""


class InvalidOrder(DomainError):
    """An order or value violates a structural domain invariant."""


class InsufficientStock(DomainError):
    """The inventory cannot cover the requested quantity for a SKU."""

    def __init__(self, sku: Sku, requested: Quantity, available: int) -> None:
        """Record which SKU fell short, by how much, and what remained."""
        super().__init__(
            f"insufficient stock for {sku.code}: "
            f"requested {requested.value}, available {available}",
        )
        self.sku = sku
        self.requested = requested
        self.available = available


class OrderAlreadyShipped(DomainError):
    """A shipped order can no longer be mutated."""
