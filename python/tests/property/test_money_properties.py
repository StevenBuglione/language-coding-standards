"""Property-based tests for Money arithmetic over randomly generated amounts."""

import pytest
from hypothesis import given, settings
from hypothesis import strategies as st

from warehouse.domain.errors import InvalidOrder
from warehouse.domain.money import Money

amounts = st.integers(min_value=0, max_value=10**9)
currencies = st.sampled_from(["USD", "EUR", "GBP"])
same_currency_pairs = st.tuples(amounts, amounts, currencies).map(
    lambda triple: (
        Money(minor_units=triple[0], currency=triple[2]),
        Money(minor_units=triple[1], currency=triple[2]),
    ),
)
mismatched_currencies = st.tuples(amounts, currencies, currencies).filter(
    lambda triple: triple[1] != triple[2],
)


@settings(deadline=None)
@given(pair=same_currency_pairs)
def test_addition_is_commutative(pair: tuple[Money, Money]) -> None:
    first, second = pair
    assert first.add(second) == second.add(first)


@settings(deadline=None)
@given(
    base=amounts,
    scale=st.integers(min_value=0, max_value=100),
    extra=amounts,
    currency=currencies,
)
def test_scaling_distributes_over_addition(
    base: int,
    scale: int,
    extra: int,
    currency: str,
) -> None:
    money = Money(minor_units=base, currency=currency)
    distributed = money.times(scale).add(money.times(extra))
    assert distributed == money.times(scale + extra)


@settings(deadline=None)
@given(triple=mismatched_currencies)
def test_cross_currency_addition_is_invalid(triple: tuple[int, str, str]) -> None:
    amount, left_currency, right_currency = triple
    left = Money(minor_units=amount, currency=left_currency)
    right = Money(minor_units=amount, currency=right_currency)
    with pytest.raises(InvalidOrder, match="mismatch"):
        left.add(right)
