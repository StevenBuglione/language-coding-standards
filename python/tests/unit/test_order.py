"""Unit tests covering every Order invariant and state transition."""

import pytest

from warehouse.domain.errors import InvalidOrder, OrderAlreadyShipped
from warehouse.domain.money import Money
from warehouse.domain.order import Order, OrderLine, OrderStatus
from warehouse.domain.quantity import Quantity
from warehouse.domain.sku import Sku


def _line(code: str = "SKU-1", qty: int = 2, minor_units: int = 500) -> OrderLine:
    return OrderLine(
        sku=Sku(code),
        quantity=Quantity(qty),
        unit_price=Money(minor_units=minor_units, currency="USD"),
    )


def test_rejects_empty_line_set() -> None:
    with pytest.raises(InvalidOrder, match="at least one line"):
        Order(lines=[])


def test_rejects_duplicate_skus() -> None:
    with pytest.raises(InvalidOrder, match="duplicate"):
        Order(lines=[_line("SKU-1"), _line("SKU-1")])


def test_total_equals_sum_of_line_totals() -> None:
    order = Order(lines=[_line("SKU-1", 2, 500), _line("SKU-2", 1, 1000)])
    assert order.total() == Money(minor_units=2000, currency="USD")


def test_total_rejects_mixed_currencies() -> None:
    mixed = [
        _line("SKU-1"),
        OrderLine(
            sku=Sku("SKU-2"),
            quantity=Quantity(1),
            unit_price=Money(minor_units=100, currency="EUR"),
        ),
    ]
    with pytest.raises(InvalidOrder, match="mismatch"):
        Order(lines=mixed).total()


def test_starts_in_new_state_with_fresh_id() -> None:
    first = Order(lines=[_line()])
    second = Order(lines=[_line()])
    assert first.status is OrderStatus.NEW
    assert first.id.value != second.id.value


def test_pay_transitions_new_to_paid() -> None:
    order = Order(lines=[_line()])
    order.pay()
    assert order.status is OrderStatus.PAID


def test_double_pay_is_invalid() -> None:
    order = Order(lines=[_line()])
    order.pay()
    with pytest.raises(InvalidOrder, match="already been paid"):
        order.pay()


def test_ship_requires_paid_state() -> None:
    order = Order(lines=[_line()])
    with pytest.raises(InvalidOrder, match="paid"):
        order.ship()


def test_ship_transitions_paid_to_shipped() -> None:
    order = Order(lines=[_line()])
    order.pay()
    order.ship()
    assert order.status is OrderStatus.SHIPPED


def test_pay_after_ship_raises_order_already_shipped() -> None:
    order = Order(lines=[_line()])
    order.pay()
    order.ship()
    with pytest.raises(OrderAlreadyShipped):
        order.pay()


def test_ship_after_ship_raises_order_already_shipped() -> None:
    order = Order(lines=[_line()])
    order.pay()
    order.ship()
    with pytest.raises(OrderAlreadyShipped):
        order.ship()
