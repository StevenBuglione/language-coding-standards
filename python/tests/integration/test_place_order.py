"""Integration tests: the full place-order pipeline over in-memory adapters."""

import uuid

from warehouse.adapters.inventory import InMemoryInventoryGateway
from warehouse.adapters.payments import FakePaymentProcessor
from warehouse.adapters.repository import InMemoryOrderRepository
from warehouse.application.place_order import (
    PlaceOrderFailure,
    PlaceOrderSuccess,
    PlaceOrderUseCase,
)
from warehouse.domain.errors import InsufficientStock, InvalidOrder
from warehouse.domain.money import Money
from warehouse.domain.order import OrderId, OrderLine, OrderStatus
from warehouse.domain.quantity import Quantity
from warehouse.domain.sku import Sku


def _pipeline(
    stock: dict[str, int],
    *,
    decline: bool = False,
) -> tuple[PlaceOrderUseCase, FakePaymentProcessor, InMemoryOrderRepository]:
    inventory = InMemoryInventoryGateway(
        {Sku(code): units for code, units in stock.items()},
    )
    payments = FakePaymentProcessor(decline=decline)
    repository = InMemoryOrderRepository()
    use_case = PlaceOrderUseCase(
        inventory=inventory,
        payments=payments,
        repository=repository,
    )
    return use_case, payments, repository


def _lines(*specs: tuple[str, int, int]) -> list[OrderLine]:
    return [
        OrderLine(
            sku=Sku(code),
            quantity=Quantity(qty),
            unit_price=Money(minor_units=minor_units, currency="USD"),
        )
        for code, qty, minor_units in specs
    ]


def test_happy_path_reserves_charges_and_persists() -> None:
    use_case, payments, repository = _pipeline({"SKU-1": 10})
    result = use_case.execute(_lines(("SKU-1", 2, 500)))

    assert isinstance(result, PlaceOrderSuccess)
    assert result.order.status is OrderStatus.NEW
    assert result.order.total() == Money(minor_units=1000, currency="USD")
    assert len(payments.charged_orders) == 1
    assert repository.get(result.order.id) is result.order


def test_insufficient_stock_fails_without_charge_or_persist() -> None:
    use_case, payments, repository = _pipeline({"SKU-1": 1})
    result = use_case.execute(_lines(("SKU-1", 5, 500)))

    assert isinstance(result, PlaceOrderFailure)
    assert isinstance(result.error, InsufficientStock)
    assert result.error.available == 1
    assert payments.charged_orders == []
    assert repository.saved == []


def test_payment_decline_fails_without_persist() -> None:
    use_case, payments, repository = _pipeline({"SKU-1": 10}, decline=True)
    result = use_case.execute(_lines(("SKU-1", 1, 500)))

    assert isinstance(result, PlaceOrderFailure)
    assert isinstance(result.error, InvalidOrder)
    assert "declined" in str(result.error)
    assert len(payments.charged_orders) == 1
    assert repository.saved == []


def test_invalid_lines_fail_validation() -> None:
    use_case, _, _ = _pipeline({})
    result = use_case.execute([])

    assert isinstance(result, PlaceOrderFailure)
    assert isinstance(result.error, InvalidOrder)


def test_get_returns_none_for_unknown_id() -> None:
    _, _, repository = _pipeline({"SKU-1": 10})

    assert repository.get(OrderId(value=uuid.uuid4())) is None
