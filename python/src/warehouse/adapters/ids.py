"""Deterministic and sequence-based order id generators."""

from __future__ import annotations

from warehouse.domain.order import OrderId


class SequenceOrderIdGenerator:
    """Test double that issues ``ord-1``, ``ord-2``, ..."""

    def __init__(self, prefix: str = "ord") -> None:
        """Start at zero so the first id is prefix-1."""
        self._n = 0
        self._prefix = prefix

    def next(self) -> OrderId:
        """Return the next sequenced identifier."""
        self._n += 1
        return OrderId(value=f"{self._prefix}-{self._n}")


class FixedOrderIdGenerator:
    """Test double that always returns the same injected identifier."""

    def __init__(self, order_id: OrderId) -> None:
        """Hold a single identifier."""
        self._order_id = order_id

    def next(self) -> OrderId:
        """Return the configured identifier."""
        return self._order_id
