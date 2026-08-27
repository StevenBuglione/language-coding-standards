"""In-memory order repository keyed by immutable order id."""

from __future__ import annotations

import threading
from typing import TYPE_CHECKING

from warehouse.domain.errors import PersistenceConflict

if TYPE_CHECKING:
    from warehouse.domain.order import Order, OrderId


class InMemoryOrderRepository:
    """OrderRepository double keeping snapshots, never aliases."""

    def __init__(self) -> None:
        """Start with an empty store."""
        self._lock = threading.Lock()
        self._orders: dict[OrderId, Order] = {}
        self._by_key: dict[str, tuple[str, Order]] = {}
        self.saved: list[Order] = []
        self.fail_save = False

    def save(self, order: Order, expected_version: int) -> Order | PersistenceConflict:
        """Store a snapshot under compare-and-set version rules."""
        with self._lock:
            if self.fail_save:
                return PersistenceConflict(
                    f"forced save failure for {order.id.value}",
                )
            current = self._orders.get(order.id)
            current_version = current.version if current is not None else 0
            if current_version != expected_version:
                return PersistenceConflict(
                    f"version conflict for {order.id.value}: "
                    f"expected {expected_version}, stored {current_version}",
                )
            snapshot = order.snapshot()
            snapshot.bump_version()
            self._orders[order.id] = snapshot
            self.saved.append(snapshot.snapshot())
            return snapshot.snapshot()

    def remember_idempotency(self, key: str, fingerprint: str, order: Order) -> None:
        """Record a successful command so retries can replay the snapshot."""
        with self._lock:
            self._by_key[key] = (fingerprint, order.snapshot())

    def get_by_idempotency_key(self, key: str) -> tuple[str, Order] | None:
        """Return the fingerprint and snapshot for a previous command."""
        with self._lock:
            found = self._by_key.get(key)
            if found is None:
                return None
            fingerprint, order = found
            return fingerprint, order.snapshot()

    def get(self, order_id: OrderId) -> Order | None:
        """Return a stored snapshot or None; an unknown id never raises."""
        with self._lock:
            stored = self._orders.get(order_id)
            if stored is None:
                return None
            return stored.snapshot()
