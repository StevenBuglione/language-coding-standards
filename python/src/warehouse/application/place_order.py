"""PlaceOrderUseCase: validate -> reserve -> charge -> persist, Result-typed."""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING

from warehouse.domain.errors import InsufficientStock, InvalidOrder
from warehouse.domain.order import Order

if TYPE_CHECKING:
    from collections.abc import Sequence

    from warehouse.application.ports import (
        InventoryGateway,
        OrderRepository,
        PaymentProcessor,
    )
    from warehouse.domain.errors import OrderAlreadyShipped
    from warehouse.domain.order import OrderLine


@dataclass(frozen=True, slots=True)
class PlaceOrderSuccess:
    """Success payload: the persisted order."""

    order: Order


@dataclass(frozen=True, slots=True)
class PlaceOrderFailure:
    """Failure payload: exactly one typed domain error, never an exception."""

    error: InsufficientStock | InvalidOrder | OrderAlreadyShipped


class PlaceOrderUseCase:
    """
    Orchestrate validate -> reserve -> charge -> persist without raising.

    No exception ever crosses the use-case boundary: every outcome is a
    ``PlaceOrderSuccess`` or ``PlaceOrderFailure`` value.
    """

    def __init__(
        self,
        inventory: InventoryGateway,
        payments: PaymentProcessor,
        repository: OrderRepository,
    ) -> None:
        """Wire the use case to its outbound ports."""
        self._inventory = inventory
        self._payments = payments
        self._repository = repository

    def execute(
        self,
        lines: Sequence[OrderLine],
    ) -> PlaceOrderSuccess | PlaceOrderFailure:
        """Validate the order, reserve stock, collect payment, then persist."""
        try:
            order = Order(tuple(lines))
        except InvalidOrder as error:
            return PlaceOrderFailure(error=error)
        for line in order.lines:
            reserved = self._inventory.reserve(line.sku, line.quantity)
            if isinstance(reserved, InsufficientStock):
                return PlaceOrderFailure(error=reserved)
        charged = self._payments.charge(order)
        if isinstance(charged, InvalidOrder):
            return PlaceOrderFailure(error=charged)
        return PlaceOrderSuccess(order=self._repository.save(order))
