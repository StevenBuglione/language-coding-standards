"""Unit tests for the Sku value object invariant."""

import pytest

from warehouse.domain.errors import InvalidOrder
from warehouse.domain.sku import Sku


def test_trims_surrounding_whitespace() -> None:
    assert Sku(code="  ABC-1  ").code == "ABC-1"


def test_rejects_blank_after_trim() -> None:
    with pytest.raises(InvalidOrder, match="non-empty"):
        Sku(code="   ")


def test_rejects_empty_string() -> None:
    with pytest.raises(InvalidOrder, match="non-empty"):
        Sku(code="")


def test_preserves_nbsp_prefix() -> None:
    assert Sku(code="\u00a0ABC").code == "\u00a0ABC"


def test_rejects_over_byte_limit() -> None:
    with pytest.raises(InvalidOrder, match="UTF-8 bytes"):
        Sku(code="A" * 65)
