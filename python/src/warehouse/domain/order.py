"""Order entity: the NEW -> PAID -> SHIPPED state machine and its invariants."""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from enum import Enum
from typing import TYPE_CHECKING

from warehouse.domain.errors import InvalidOrder, OrderAlreadyShipped

if TYPE_CHECKING:
    from collections.abc import Sequence

    from warehouse.domain.money import Money
    from warehouse.domain.quantity import Quantity
    from warehouse.domain.sku import Sku


class OrderStatus(Enum):
    """States of the canonical order life cycle."""

    NEW = "new"
    PAID = "paid"
    SHIPPED = "shipped"


@dataclass(frozen=True, slots=True)
class OrderId:
    """Immutable unique identifier of an order."""

    value: uuid.UUID


@dataclass(frozen=True, slots=True)
class OrderLine:
    """One SKU/quantity/unit-price row of an order."""

    sku: Sku
    quantity: Quantity
    unit_price: Money

    @property
    def line_total(self) -> Money:
        """Return the unit price scaled by the ordered quantity."""
        return self.unit_price.times(self.quantity.value)


class Order:
    """
    Order entity enforcing the four canonical invariants.

    Invariants: at least one line; no duplicate SKUs across lines; the total
    always equals the sum of line totals (computed, never stored stale); no
    mutation once shipped.
    """

    def __init__(self, lines: Sequence[OrderLine]) -> None:
        """Place a new order from validated lines, assigning a fresh id."""
        if not lines:
            raise InvalidOrder("an order requires at least one line")
        codes = [line.sku.code for line in lines]
        if len(set(codes)) != len(codes):
            raise InvalidOrder("duplicate SKUs across order lines are not allowed")
        self._id = OrderId(value=uuid.uuid4())
        self._lines: tuple[OrderLine, ...] = tuple(lines)
        self._status = OrderStatus.NEW

    @property
    def id(self) -> OrderId:
        """Return the immutable order identifier."""
        return self._id

    @property
    def status(self) -> OrderStatus:
        """Return the current state-machine state."""
        return self._status

    @property
    def lines(self) -> tuple[OrderLine, ...]:
        """Return the immutable set of order lines."""
        return self._lines

    def total(self) -> Money:
        """Return the sum of all line totals in a single currency."""
        total = self._lines[0].line_total
        for line in self._lines[1:]:
            total = total.add(line.line_total)
        return total

    def pay(self) -> None:
        """Transition NEW to PAID; refuse paid or already-shipped orders."""
        self._ensure_not_shipped()
        if self._status is OrderStatus.PAID:
            raise InvalidOrder("order has already been paid")
        self._status = OrderStatus.PAID

    def ship(self) -> None:
        """Transition PAID to SHIPPED; only paid orders may ship."""
        self._ensure_not_shipped()
        if self._status is not OrderStatus.PAID:
            raise InvalidOrder("only paid orders can be shipped")
        self._status = OrderStatus.SHIPPED

    def _ensure_not_shipped(self) -> None:
        """Reject any mutation of an already-shipped order."""
        if self._status is OrderStatus.SHIPPED:
            raise OrderAlreadyShipped(
                f"order {self._id.value} has already shipped",
            )
