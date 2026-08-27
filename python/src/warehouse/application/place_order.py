"""PlaceOrderUseCase: validate, reserveAll, charge, pay, persist, compensate."""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass
from typing import TYPE_CHECKING

from warehouse.application.ports import ChargeReceipt, ReservationToken
from warehouse.domain.errors import (
    CompensationFailure,
    InsufficientStock,
    InvalidOrder,
    PaymentDeclined,
    PersistenceConflict,
)
from warehouse.domain.order import Order, OrderLine

if TYPE_CHECKING:
    from warehouse.application.ports import (
        InventoryGateway,
        OrderIdGenerator,
        OrderRepository,
        PaymentProcessor,
    )


@dataclass(frozen=True, slots=True)
class PlaceOrderSuccess:
    """Success payload: the persisted paid order snapshot."""

    order: Order


@dataclass(frozen=True, slots=True)
class PlaceOrderFailure:
    """Failure payload: exactly one typed error, never an exception."""

    error: (
        InvalidOrder
        | InsufficientStock
        | PaymentDeclined
        | PersistenceConflict
        | CompensationFailure
    )


class PlaceOrderUseCase:
    """Orchestrate the v2 place-order policy without raising."""

    def __init__(
        self,
        inventory: InventoryGateway,
        payments: PaymentProcessor,
        repository: OrderRepository,
        ids: OrderIdGenerator,
    ) -> None:
        """Wire the use case to its outbound ports."""
        self._inventory = inventory
        self._payments = payments
        self._repository = repository
        self._ids = ids

    def execute(
        self,
        lines: Sequence[OrderLine],
        *,
        idempotency_key: str,
    ) -> PlaceOrderSuccess | PlaceOrderFailure:
        """Validate, reserve, charge, mark PAID, persist; compensate on failure."""
        fingerprint = _fingerprint(lines)
        remembered = self._repository.get_by_idempotency_key(idempotency_key)
        if remembered is not None:
            prior_fingerprint, snapshot = remembered
            if prior_fingerprint != fingerprint:
                return PlaceOrderFailure(
                    error=InvalidOrder("idempotency key reused with different payload"),
                )
            return PlaceOrderSuccess(order=snapshot)
        try:
            order = Order(tuple(lines), order_id=self._ids.next())
        except InvalidOrder as error:
            return PlaceOrderFailure(error=error)

        reserved = self._inventory.reserve_all(
            order.id,
            order.lines,
            idempotency_key,
        )
        if isinstance(reserved, InsufficientStock):
            return PlaceOrderFailure(error=reserved)

        charged = self._payments.charge(order, idempotency_key)
        if isinstance(charged, PaymentDeclined):
            return self._release_or_fail(reserved, charged)

        try:
            order.pay()
        except InvalidOrder as error:
            refunded = self._payments.refund(charged)
            released = self._inventory.release(reserved)
            if refunded is not None:
                return PlaceOrderFailure(error=refunded)
            if released is not None:
                return PlaceOrderFailure(error=released)
            return PlaceOrderFailure(error=error)

        saved = self._repository.save(order, expected_version=0)
        if isinstance(saved, PersistenceConflict):
            return self._compensate_save_failure(reserved, charged, saved)
        self._repository.remember_idempotency(idempotency_key, fingerprint, saved)
        return PlaceOrderSuccess(order=saved)

    def _release_or_fail(
        self,
        token: ReservationToken,
        error: PaymentDeclined,
    ) -> PlaceOrderFailure:
        """Release stock after a declined charge."""
        released = self._inventory.release(token)
        if released is not None:
            return PlaceOrderFailure(error=released)
        return PlaceOrderFailure(error=error)

    def _compensate_save_failure(
        self,
        token: ReservationToken,
        receipt: ChargeReceipt,
        error: PersistenceConflict,
    ) -> PlaceOrderFailure:
        """Refund and release after a persistence conflict."""
        refunded = self._payments.refund(receipt)
        released = self._inventory.release(token)
        if refunded is not None:
            return PlaceOrderFailure(error=refunded)
        if released is not None:
            return PlaceOrderFailure(error=released)
        return PlaceOrderFailure(error=error)


def _fingerprint(lines: Sequence[OrderLine]) -> str:
    """Stable payload identity for idempotency-key reuse detection."""
    parts = [
        f"{line.sku.code}:{line.quantity.value}:"
        f"{line.unit_price.currency}:{line.unit_price.minor_units}"
        for line in lines
    ]
    return "|".join(parts)
