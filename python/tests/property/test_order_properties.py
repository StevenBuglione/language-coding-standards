"""Property-based tests for Order invariants under random valid inputs."""

import pytest
from hypothesis import given, settings
from hypothesis import strategies as st

from warehouse.domain.errors import OrderAlreadyShipped
from warehouse.domain.money import Money
from warehouse.domain.order import Order, OrderLine
from warehouse.domain.quantity import Quantity
from warehouse.domain.sku import Sku

sku_codes = st.integers(min_value=0, max_value=9999).map(lambda n: f"SKU-{n}")
quantities = st.integers(min_value=1, max_value=5)
unit_prices = st.integers(min_value=0, max_value=5000)
valid_line_sets = st.lists(
    st.tuples(sku_codes, quantities, unit_prices),
    min_size=1,
    max_size=6,
    unique_by=lambda spec: spec[0],
).map(
    lambda specs: [
        OrderLine(
            sku=Sku(code),
            quantity=Quantity(qty),
            unit_price=Money(minor_units=price, currency="USD"),
        )
        for code, qty, price in specs
    ],
)


@settings(deadline=None)
@given(lines=valid_line_sets)
def test_total_always_equals_sum_of_line_totals(lines: list[OrderLine]) -> None:
    order = Order(lines)
    expected = lines[0].line_total
    for line in lines[1:]:
        expected = expected.add(line.line_total)
    assert order.total() == expected


@settings(deadline=None)
@given(lines=valid_line_sets)
def test_full_life_cycle_preserves_total_and_locks_mutation(
    lines: list[OrderLine],
) -> None:
    order = Order(lines)
    original_total = order.total()

    order.pay()
    assert order.status.value == "paid"
    order.ship()
    assert order.total() == original_total
    with pytest.raises(OrderAlreadyShipped):
        order.pay()
