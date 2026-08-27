"""Fake payment adapter with idempotent charge and refund."""

from __future__ import annotations

from typing import TYPE_CHECKING

from warehouse.application.ports import ChargeReceipt
from warehouse.domain.errors import CompensationFailure, PaymentDeclined

if TYPE_CHECKING:
    from warehouse.domain.order import Order


class FakePaymentProcessor:
    """
    PaymentProcessor test double that records every charge attempt.

    Configure ``decline=True`` to refuse collection. Identical idempotency
    keys replay the original outcome without a second charge.
    """

    def __init__(self, *, decline: bool = False) -> None:
        """Start in the configured outcome mode with an empty attempt log."""
        self._decline = decline
        self.charged_orders: list[Order] = []
        self._receipts: dict[str, ChargeReceipt | PaymentDeclined] = {}
        self.fail_refund = False
        self.refunded: list[ChargeReceipt] = []

    def charge(
        self,
        order: Order,
        idempotency_key: str,
    ) -> ChargeReceipt | PaymentDeclined:
        """Record the attempt unless this key already completed."""
        existing = self._receipts.get(idempotency_key)
        if existing is not None:
            return existing
        self.charged_orders.append(order)
        if self._decline:
            declined = PaymentDeclined(f"payment declined for order {order.id.value}")
            self._receipts[idempotency_key] = declined
            return declined
        receipt = ChargeReceipt(order_id=order.id, idempotency_key=idempotency_key)
        self._receipts[idempotency_key] = receipt
        return receipt

    def refund(
        self,
        receipt: ChargeReceipt,
    ) -> None | CompensationFailure:
        """Void a prior successful charge."""
        if self.fail_refund:
            return CompensationFailure(stage="refund", detail="forced failure")
        self.refunded.append(receipt)
        return None
