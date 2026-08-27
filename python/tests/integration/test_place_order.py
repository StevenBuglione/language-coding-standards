"""Integration tests: the full place-order pipeline over in-memory adapters."""

from warehouse.adapters.ids import FixedOrderIdGenerator, SequenceOrderIdGenerator
from warehouse.adapters.inventory import InMemoryInventoryGateway
from warehouse.adapters.payments import FakePaymentProcessor
from warehouse.adapters.repository import InMemoryOrderRepository
from warehouse.application.place_order import (
    PlaceOrderFailure,
    PlaceOrderSuccess,
    PlaceOrderUseCase,
)
from warehouse.domain.errors import (
    CompensationFailure,
    InsufficientStock,
    InvalidOrder,
    PaymentDeclined,
    PersistenceConflict,
)
from warehouse.domain.money import Money
from warehouse.domain.order import OrderId, OrderLine, OrderStatus
from warehouse.domain.quantity import Quantity
from warehouse.domain.sku import Sku


def _pipeline(
    stock: dict[str, int],
    *,
    decline: bool = False,
    order_id: str = "ord-1",
) -> tuple[
    PlaceOrderUseCase,
    FakePaymentProcessor,
    InMemoryOrderRepository,
    InMemoryInventoryGateway,
]:
    inventory = InMemoryInventoryGateway(
        {Sku(code): units for code, units in stock.items()},
    )
    payments = FakePaymentProcessor(decline=decline)
    repository = InMemoryOrderRepository()
    use_case = PlaceOrderUseCase(
        inventory=inventory,
        payments=payments,
        repository=repository,
        ids=FixedOrderIdGenerator(OrderId(order_id)),
    )
    return use_case, payments, repository, inventory


def _lines(*specs: tuple[str, int, int]) -> list[OrderLine]:
    return [
        OrderLine(
            sku=Sku(code),
            quantity=Quantity(qty),
            unit_price=Money(minor_units=minor_units, currency="USD"),
        )
        for code, qty, minor_units in specs
    ]


def test_happy_path_persists_paid() -> None:
    use_case, payments, repository, inventory = _pipeline({"SKU-1": 10})
    result = use_case.execute(_lines(("SKU-1", 2, 500)), idempotency_key="idem-1")

    assert isinstance(result, PlaceOrderSuccess)
    assert result.order.status is OrderStatus.PAID
    assert result.order.id.value == "ord-1"
    assert result.order.total() == Money(minor_units=1000, currency="USD")
    assert len(payments.charged_orders) == 1
    stored = repository.get(result.order.id)
    assert stored is not None
    assert stored.status is OrderStatus.PAID
    assert stored is not result.order
    assert inventory.snapshot_stock()[Sku("SKU-1")] == 8


def test_insufficient_stock_fails_without_charge_or_persist() -> None:
    use_case, payments, repository, inventory = _pipeline({"SKU-1": 1})
    result = use_case.execute(_lines(("SKU-1", 5, 500)), idempotency_key="idem-2")

    assert isinstance(result, PlaceOrderFailure)
    assert isinstance(result.error, InsufficientStock)
    assert result.error.available == 1
    assert payments.charged_orders == []
    assert repository.saved == []
    assert inventory.snapshot_stock()[Sku("SKU-1")] == 1


def test_payment_decline_releases_reservation() -> None:
    use_case, payments, repository, inventory = _pipeline({"SKU-1": 10}, decline=True)
    result = use_case.execute(_lines(("SKU-1", 1, 500)), idempotency_key="idem-3")

    assert isinstance(result, PlaceOrderFailure)
    assert isinstance(result.error, PaymentDeclined)
    assert len(payments.charged_orders) == 1
    assert repository.saved == []
    assert inventory.snapshot_stock()[Sku("SKU-1")] == 10


def test_save_failure_refunds_and_releases() -> None:
    use_case, payments, repository, inventory = _pipeline({"SKU-1": 10})
    repository.fail_save = True
    result = use_case.execute(_lines(("SKU-1", 1, 500)), idempotency_key="idem-4")

    assert isinstance(result, PlaceOrderFailure)
    assert isinstance(result.error, PersistenceConflict)
    assert len(payments.refunded) == 1
    assert inventory.snapshot_stock()[Sku("SKU-1")] == 10


def test_compensation_failure_after_save_failure() -> None:
    use_case, payments, repository, _inventory = _pipeline({"SKU-1": 10})
    repository.fail_save = True
    payments.fail_refund = True
    result = use_case.execute(_lines(("SKU-1", 1, 500)), idempotency_key="idem-5")

    assert isinstance(result, PlaceOrderFailure)
    assert isinstance(result.error, CompensationFailure)


def test_invalid_lines_fail_validation() -> None:
    use_case, _, _, _ = _pipeline({})
    result = use_case.execute([], idempotency_key="idem-6")

    assert isinstance(result, PlaceOrderFailure)
    assert isinstance(result.error, InvalidOrder)


def test_get_returns_none_for_unknown_id() -> None:
    _, _, repository, _ = _pipeline({"SKU-1": 10})

    assert repository.get(OrderId(value="missing-order")) is None


def test_idempotent_replay_does_not_double_charge() -> None:
    inventory = InMemoryInventoryGateway({Sku("SKU-1"): 10})
    payments = FakePaymentProcessor()
    repository = InMemoryOrderRepository()
    ids = SequenceOrderIdGenerator()
    use_case = PlaceOrderUseCase(
        inventory=inventory,
        payments=payments,
        repository=repository,
        ids=ids,
    )
    first = use_case.execute(_lines(("SKU-1", 2, 300)), idempotency_key="idem-7")
    assert isinstance(first, PlaceOrderSuccess)
    second = use_case.execute(_lines(("SKU-1", 2, 300)), idempotency_key="idem-7")
    assert isinstance(second, PlaceOrderSuccess)
    assert len(payments.charged_orders) == 1
