"""In-memory order repository keyed by immutable order id."""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from warehouse.domain.order import Order, OrderId


class InMemoryOrderRepository:
    """OrderRepository double keeping orders in a dictionary, for tests."""

    def __init__(self) -> None:
        """Start with an empty store."""
        self._orders: dict[OrderId, Order] = {}
        self.saved: list[Order] = []

    def save(self, order: Order) -> Order:
        """Store the order under its id and return it as persisted."""
        self._orders[order.id] = order
        self.saved.append(order)
        return order

    def get(self, order_id: OrderId) -> Order | None:
        """Return the stored order or None; an unknown id never raises."""
        return self._orders.get(order_id)
