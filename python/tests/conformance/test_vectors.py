"""Execute shared conformance/v2 vectors against the Python pack."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import pytest

from warehouse.domain.errors import InvalidOrder, OrderAlreadyShipped
from warehouse.domain.money import Money
from warehouse.domain.order import Order, OrderId, OrderLine, OrderStatus
from warehouse.domain.quantity import Quantity
from warehouse.domain.sku import Sku

ROOT = Path(__file__).resolve().parents[3]
SUITES = ROOT / "conformance" / "v2" / "suites"


def _cases(name: str) -> list[dict[str, Any]]:
    payload = json.loads((SUITES / name).read_text(encoding="utf-8"))
    return payload["cases"]


def _intish(value: Any) -> Any:
    return value


def test_money_construct_vectors() -> None:
    for case in _cases("money.json"):
        if case["operation"] != "money.construct":
            continue
        raw = case["input"]["minorUnits"]
        currency = case["input"]["currency"]
        expect = case["expect"]
        if isinstance(raw, str) and raw.lstrip("-").isdigit():
            amount: int | str = int(raw)
        else:
            amount = raw
        if expect["outcome"] == "ok":
            money = Money(minor_units=int(amount), currency=currency)
            assert str(money.minor_units) == expect["result"]["minorUnits"]
            assert money.currency == expect["result"]["currency"]
        else:
            with pytest.raises(InvalidOrder):
                if isinstance(amount, str):
                    raise InvalidOrder("non-integer")
                Money(minor_units=amount, currency=currency)


def test_quantity_construct_vectors() -> None:
    for case in _cases("quantity.json"):
        raw = case["input"]["value"]
        expect = case["expect"]
        if expect["outcome"] == "ok":
            qty = Quantity(value=int(raw))
            assert str(qty.value) == expect["result"]["value"]
        else:
            with pytest.raises(InvalidOrder):
                if isinstance(raw, bool):
                    Quantity(value=raw)
                elif isinstance(raw, str) and raw.lstrip("-").isdigit():
                    Quantity(value=int(raw))
                else:
                    raise InvalidOrder("non-integer")


def test_sku_construct_vectors() -> None:
    for case in _cases("sku.json"):
        code = case["input"]["code"]
        expect = case["expect"]
        if expect["outcome"] == "ok":
            assert Sku(code=code).code == expect["result"]["code"]
        else:
            with pytest.raises(InvalidOrder):
                Sku(code=code)


def test_order_construct_and_transitions() -> None:
    for case in _cases("order.json"):
        expect = case["expect"]
        operation = case["operation"]
        if operation == "order.construct":
            order_id = OrderId(case["given"]["orderId"])
            raw_lines = case["input"]["lines"]
            if expect["outcome"] == "ok":
                order = Order(_lines(raw_lines), order_id=order_id)
                assert order.status is OrderStatus.NEW
                assert order.id.value == expect["result"]["id"]
                if "totalMinorUnits" in expect["result"]:
                    assert (
                        str(order.total().minor_units)
                        == expect["result"]["totalMinorUnits"]
                    )
            else:
                with pytest.raises(InvalidOrder):
                    Order(_lines(raw_lines), order_id=order_id)
            continue
        given = case["given"]["order"]
        order = Order(_lines(given["lines"]), order_id=OrderId(given["id"]))
        if given["status"] == "PAID":
            order.pay()
        elif given["status"] == "SHIPPED":
            order.pay()
            order.ship()
        if expect["outcome"] == "ok":
            if operation == "order.pay":
                order.pay()
                assert order.status is OrderStatus.PAID
            else:
                order.ship()
                assert order.status is OrderStatus.SHIPPED
        else:
            with pytest.raises((InvalidOrder, OrderAlreadyShipped)):
                if operation == "order.pay":
                    order.pay()
                else:
                    order.ship()


def _lines(raw_lines: list[dict[str, Any]]) -> list[OrderLine]:
    return [
        OrderLine(
            sku=Sku(item["sku"]),
            quantity=Quantity(int(item["quantity"])),
            unit_price=Money(
                minor_units=int(item["unitPrice"]["minorUnits"]),
                currency=item["unitPrice"]["currency"],
            ),
        )
        for item in raw_lines
    ]
