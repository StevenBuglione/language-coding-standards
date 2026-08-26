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
