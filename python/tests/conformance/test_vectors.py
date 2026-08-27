"""Execute every shared conformance/v2 vector against the Python pack."""

from __future__ import annotations

import json
from pathlib import Path
from typing import cast

import pytest

from warehouse.domain.errors import InvalidOrder, OrderAlreadyShipped
from warehouse.domain.money import Money
from warehouse.domain.order import Order, OrderId, OrderLine
from warehouse.domain.quantity import Quantity
from warehouse.domain.sku import Sku

ROOT = Path(__file__).resolve().parents[3]
SUITES = ROOT / "conformance" / "v2" / "suites"

type JsonValue = (
    None
    | bool
    | int
    | float
    | str
    | list[JsonValue]
    | dict[str, JsonValue]
)
type JsonObject = dict[str, JsonValue]


def _object(value: JsonValue) -> JsonObject:
    if not isinstance(value, dict):
        raise TypeError(f"expected JSON object, got {type(value).__name__}")
    return value


def _array(value: JsonValue) -> list[JsonValue]:
    if not isinstance(value, list):
        raise TypeError(f"expected JSON array, got {type(value).__name__}")
    return value


def _text(value: JsonValue) -> str:
    if not isinstance(value, str):
        raise TypeError(f"expected JSON string, got {type(value).__name__}")
    return value


def _integer(value: JsonValue) -> int:
    if isinstance(value, bool):
        raise InvalidOrder("boolean is not an integer")
    if isinstance(value, int):
        return value
    if isinstance(value, str) and value.lstrip("-").isdigit():
        return int(value)
    raise InvalidOrder(f"expected an integer value, got {value!r}")


def _cases(name: str) -> list[JsonObject]:
    raw = cast(
        "JsonValue",
        json.loads((SUITES / name).read_text(encoding="utf-8")),
    )
    payload = _object(raw)
    return [_object(case) for case in _array(payload["cases"])]


def _case_ids(cases: list[JsonObject]) -> list[str]:
    return [_text(case["id"]) for case in cases]


def _expect(case: JsonObject) -> JsonObject:
    return _object(case["expect"])


def _expected_error(expect: JsonObject) -> type[Exception]:
    error_name = _text(expect["error"])
    if error_name == "InvalidOrder":
        return InvalidOrder
    if error_name == "OrderAlreadyShipped":
        return OrderAlreadyShipped
    raise ValueError(f"unsupported expected error: {error_name}")


def _money(value: JsonValue) -> Money:
    raw = _object(value)
    return Money(
        minor_units=_integer(raw["minorUnits"]),
        currency=_text(raw["currency"]),
    )


def _execute_money(case: JsonObject) -> Money:
    operation = _text(case["operation"])
    values = _object(case["input"])
    match operation:
        case "money.construct":
            return _money(values)
        case "money.add":
            return _money(values["left"]).add(_money(values["right"]))
        case "money.times":
            return _money(values["amount"]).times(_integer(values["multiplier"]))
        case _:
            raise ValueError(f"unsupported money operation: {operation}")


def _assert_money_result(actual: Money, expected: JsonObject) -> None:
    assert str(actual.minor_units) == _text(expected["minorUnits"])
    assert actual.currency == _text(expected["currency"])


_MONEY_CASES = _cases("money.json")


@pytest.mark.parametrize("case", _MONEY_CASES, ids=_case_ids(_MONEY_CASES))
def test_money_vectors(case: JsonObject) -> None:
    expect = _expect(case)
    if _text(expect["outcome"]) == "error":
        with pytest.raises(_expected_error(expect)):
            _execute_money(case)
        return
    _assert_money_result(_execute_money(case), _object(expect["result"]))


def _execute_quantity(case: JsonObject) -> Quantity:
    values = _object(case["input"])
    return Quantity(value=_integer(values["value"]))


_QUANTITY_CASES = _cases("quantity.json")


@pytest.mark.parametrize(
    "case",
    _QUANTITY_CASES,
    ids=_case_ids(_QUANTITY_CASES),
)
def test_quantity_vectors(case: JsonObject) -> None:
    expect = _expect(case)
    if _text(expect["outcome"]) == "error":
        with pytest.raises(_expected_error(expect)):
            _execute_quantity(case)
        return
    actual = _execute_quantity(case)
    expected = _object(expect["result"])
    assert str(actual.value) == _text(expected["value"])


def _execute_sku(case: JsonObject) -> Sku:
    values = _object(case["input"])
    return Sku(code=_text(values["code"]))


_SKU_CASES = _cases("sku.json")


@pytest.mark.parametrize("case", _SKU_CASES, ids=_case_ids(_SKU_CASES))
def test_sku_vectors(case: JsonObject) -> None:
    expect = _expect(case)
    if _text(expect["outcome"]) == "error":
        with pytest.raises(_expected_error(expect)):
            _execute_sku(case)
        return
    actual = _execute_sku(case)
    expected = _object(expect["result"])
    assert actual.code == _text(expected["code"])


def _line(value: JsonValue) -> OrderLine:
    raw = _object(value)
    return OrderLine(
        sku=Sku(_text(raw["sku"])),
        quantity=Quantity(_integer(raw["quantity"])),
        unit_price=_money(raw["unitPrice"]),
    )


def _lines(value: JsonValue) -> list[OrderLine]:
    return [_line(line) for line in _array(value)]


def _construct_order(case: JsonObject) -> Order:
    given = _object(case["given"])
    values = _object(case["input"])
    return Order(
        _lines(values["lines"]),
        order_id=OrderId(_text(given["orderId"])),
    )


def _given_order(case: JsonObject) -> Order:
    given = _object(_object(case["given"])["order"])
    order = Order(
        _lines(given["lines"]),
        order_id=OrderId(_text(given["id"])),
    )
    status = _text(given["status"])
    match status:
        case "NEW":
            return order
        case "PAID":
            order.pay()
        case "SHIPPED":
            order.pay()
            order.ship()
        case _:
            raise ValueError(f"unsupported given order status: {status}")
    return order


def _execute_order(case: JsonObject) -> Order:
    operation = _text(case["operation"])
    if operation == "order.construct":
        return _construct_order(case)
    order = _given_order(case)
    if operation == "order.pay":
        order.pay()
    elif operation == "order.ship":
        order.ship()
    else:
        raise ValueError(f"unsupported order operation: {operation}")
    return order


def _assert_order_result(actual: Order, expected: JsonObject) -> None:
    expected_id = expected.get("id")
    if expected_id is not None:
        assert actual.id.value == _text(expected_id)
    expected_status = expected.get("status")
    if expected_status is not None:
        assert actual.status.value == _text(expected_status)
    expected_version = expected.get("version")
    if expected_version is not None:
        assert str(actual.version) == _text(expected_version)

    expected_total = expected.get("totalMinorUnits")
    expected_currency = expected.get("currency")
    if expected_total is None and expected_currency is None:
        return
    total = actual.total()
    if expected_total is not None:
        assert str(total.minor_units) == _text(expected_total)
    if expected_currency is not None:
        assert total.currency == _text(expected_currency)


_ORDER_CASES = _cases("order.json")


@pytest.mark.parametrize("case", _ORDER_CASES, ids=_case_ids(_ORDER_CASES))
def test_order_vectors(case: JsonObject) -> None:
    expect = _expect(case)
    if _text(expect["outcome"]) == "error":
        with pytest.raises(_expected_error(expect)):
            _execute_order(case)
        return
    _assert_order_result(_execute_order(case), _object(expect["result"]))
