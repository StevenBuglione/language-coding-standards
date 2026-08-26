"""Unit tests for the Money value object and its invariants."""

import pytest

from warehouse.domain.errors import InvalidOrder
from warehouse.domain.money import Money


def test_rejects_negative_amount() -> None:
    with pytest.raises(InvalidOrder, match="non-negative"):
        Money(minor_units=-1, currency="USD")


def test_rejects_malformed_currency() -> None:
    with pytest.raises(InvalidOrder, match="currency"):
        Money(minor_units=1, currency="usd")


def test_add_sums_same_currency() -> None:
    assert Money(minor_units=150, currency="USD").add(Money(275, "USD")) == Money(
        425,
        "USD",
    )


def test_add_rejects_currency_mismatch() -> None:
    with pytest.raises(InvalidOrder, match="mismatch"):
        Money(minor_units=100, currency="USD").add(Money(100, "EUR"))


def test_times_scales_amount() -> None:
    assert Money(minor_units=250, currency="USD").times(3) == Money(750, "USD")


def test_times_rejects_negative_multiplier() -> None:
    with pytest.raises(InvalidOrder, match="multiplier"):
        Money(minor_units=1, currency="USD").times(-2)


def test_equality_is_value_based() -> None:
    assert Money(minor_units=10, currency="EUR") == Money(10, "EUR")
