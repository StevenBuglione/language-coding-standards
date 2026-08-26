"""Quantity value object: a strictly positive integer."""

from __future__ import annotations

from dataclasses import dataclass

from warehouse.domain.errors import InvalidOrder


@dataclass(frozen=True, slots=True)
class Quantity:
    """An amount of stock that must be strictly positive."""

    value: int

    def __post_init__(self) -> None:
        """Reject zero and negative amounts as structurally invalid."""
        if self.value <= 0:
            raise InvalidOrder(f"quantity must be strictly positive, got {self.value}")
