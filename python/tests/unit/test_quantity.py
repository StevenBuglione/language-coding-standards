"""Unit tests for the Quantity value object invariant."""

import pytest

from warehouse.domain.errors import InvalidOrder
from warehouse.domain.quantity import Quantity


def test_accepts_strictly_positive_value() -> None:
    assert Quantity(value=1).value == 1


def test_rejects_zero() -> None:
    with pytest.raises(InvalidOrder, match="strictly positive"):
        Quantity(value=0)


def test_rejects_negative() -> None:
    with pytest.raises(InvalidOrder, match="strictly positive"):
        Quantity(value=-3)


def test_rejects_boolean_true() -> None:
    with pytest.raises(InvalidOrder, match="strictly positive integer"):
        Quantity(value=True)  # type: ignore[arg-type]


def test_rejects_boolean_false() -> None:
    with pytest.raises(InvalidOrder, match="strictly positive integer"):
        Quantity(value=False)  # type: ignore[arg-type]


def test_rejects_above_max() -> None:
    with pytest.raises(InvalidOrder, match="exceeds"):
        Quantity(value=2_147_483_648)
