"""Sku value object: a non-empty trimmed stock-keeping-unit code."""

from __future__ import annotations

from dataclasses import dataclass

from warehouse.domain.errors import InvalidOrder


@dataclass(frozen=True, slots=True)
class Sku:
    """A stock-keeping-unit code, normalized to its trimmed form on creation."""

    code: str

    def __post_init__(self) -> None:
        """Trim surrounding whitespace and reject codes that end up empty."""
        trimmed = self.code.strip()
        if not trimmed:
            raise InvalidOrder("sku code must be non-empty")
        if trimmed != self.code:
            object.__setattr__(self, "code", trimmed)
