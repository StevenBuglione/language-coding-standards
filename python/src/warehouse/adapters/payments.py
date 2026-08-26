"""Fake payment adapter with a configurable decline switch."""

from __future__ import annotations

from typing import TYPE_CHECKING

from warehouse.application.ports import Charged
from warehouse.domain.errors import InvalidOrder

if TYPE_CHECKING:
    from warehouse.domain.order import Order


class FakePaymentProcessor:
    """
    PaymentProcessor test double that records every charge attempt.

    Configure ``decline=True`` to make each collection fail with a typed
    ``InvalidOrder`` refusal.
    """

    def __init__(self, *, decline: bool = False) -> None:
        """Start in the configured outcome mode with an empty attempt log."""
        self._decline = decline
        self.charged_orders: list[Order] = []

    def charge(self, order: Order) -> Charged | InvalidOrder:
        """Record the attempt, then honor the configured outcome."""
        self.charged_orders.append(order)
        if self._decline:
            return InvalidOrder(f"payment declined for order {order.id.value}")
        return Charged()
