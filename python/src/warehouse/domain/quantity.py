"""Quantity value object: a strictly positive integer."""

from __future__ import annotations

from dataclasses import dataclass

from warehouse.domain.errors import InvalidOrder

QUANTITY_MAX = 2_147_483_647


@dataclass(frozen=True, slots=True)
class Quantity:
    """An amount of stock that must be strictly positive."""

    value: int

    def __post_init__(self) -> None:
        """Reject booleans, zero, negatives, and values above the shared max."""
        if isinstance(self.value, bool) or not isinstance(self.value, int):
            raise InvalidOrder(
                f"quantity must be a strictly positive integer, got {self.value!r}",
            )
        if self.value <= 0:
            raise InvalidOrder(f"quantity must be strictly positive, got {self.value}")
        if self.value > QUANTITY_MAX:
            raise InvalidOrder(
                f"quantity exceeds {QUANTITY_MAX}, got {self.value}",
            )
