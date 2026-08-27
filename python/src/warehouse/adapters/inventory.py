"""In-memory inventory adapter with atomic reserve-all."""

from __future__ import annotations

import threading
from typing import TYPE_CHECKING

from warehouse.application.ports import ReservationToken
from warehouse.domain.errors import CompensationFailure, InsufficientStock

if TYPE_CHECKING:
    from collections.abc import Sequence

    from warehouse.domain.order import OrderId, OrderLine
    from warehouse.domain.sku import Sku


class InMemoryInventoryGateway:
    """InventoryGateway double enforcing finite stock, for tests and demos."""

    def __init__(self, stock: dict[Sku, int] | None = None) -> None:
        """Start from an optional initial stock map, copied defensively."""
        self._lock = threading.Lock()
        self._stock: dict[Sku, int] = dict(stock) if stock is not None else {}
        self._reservations: dict[str, list[tuple[Sku, int]]] = {}
        self.fail_release = False

    def snapshot_stock(self) -> dict[Sku, int]:
        """Return a copy of remaining units per SKU."""
        with self._lock:
            return dict(self._stock)

    def reserve_all(
        self,
        order_id: OrderId,
        lines: Sequence[OrderLine],
        idempotency_key: str,
    ) -> ReservationToken | InsufficientStock:
        """Reserve every line atomically, or none."""
        with self._lock:
            if idempotency_key in self._reservations:
                return ReservationToken(order_id=order_id, idempotency_key=idempotency_key)
            needed: list[tuple[Sku, int]] = []
            for line in lines:
                available = self._stock.get(line.sku, 0)
                if available < line.quantity.value:
                    return InsufficientStock(
                        sku=line.sku,
                        requested=line.quantity,
                        available=available,
                    )
                needed.append((line.sku, line.quantity.value))
            for sku, amount in needed:
                self._stock[sku] = self._stock[sku] - amount
            self._reservations[idempotency_key] = needed
            return ReservationToken(order_id=order_id, idempotency_key=idempotency_key)

    def release(
        self,
        token: ReservationToken,
    ) -> None | CompensationFailure:
        """Put reserved units back."""
        with self._lock:
            if self.fail_release:
                return CompensationFailure(stage="release", detail="forced failure")
            held = self._reservations.pop(token.idempotency_key, None)
            if held is None:
                return None
            for sku, amount in held:
                self._stock[sku] = self._stock.get(sku, 0) + amount
            return None
