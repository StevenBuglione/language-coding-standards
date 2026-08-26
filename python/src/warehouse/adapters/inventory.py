"""In-memory inventory adapter backed by a finite per-SKU stock map."""

from __future__ import annotations

from typing import TYPE_CHECKING

from warehouse.application.ports import Reserved
from warehouse.domain.errors import InsufficientStock

if TYPE_CHECKING:
    from warehouse.domain.quantity import Quantity
    from warehouse.domain.sku import Sku


class InMemoryInventoryGateway:
    """InventoryGateway double enforcing finite stock, for tests and demos."""

    def __init__(self, stock: dict[Sku, int] | None = None) -> None:
        """Start from an optional initial stock map, copied defensively."""
        self._stock: dict[Sku, int] = dict(stock) if stock is not None else {}

    def reserve(self, sku: Sku, quantity: Quantity) -> Reserved | InsufficientStock:
        """Reserve when stock covers the request; otherwise report shortage."""
        available = self._stock.get(sku, 0)
        if available < quantity.value:
            return InsufficientStock(
                sku=sku,
                requested=quantity,
                available=available,
            )
        self._stock[sku] = available - quantity.value
        return Reserved()
