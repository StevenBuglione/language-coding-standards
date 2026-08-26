"""Money value object: integer minor units plus an ISO 4217 currency code."""

from __future__ import annotations

import re
from dataclasses import dataclass

from warehouse.domain.errors import InvalidOrder

_CURRENCY_PATTERN = re.compile(r"[A-Z]{3}")


@dataclass(frozen=True, slots=True)
class Money:
    """
    A non-negative amount in integer minor units of a single currency.

    Cross-currency operations are invalid and raise ``InvalidOrder``.
    """

    minor_units: int
    currency: str

    def __post_init__(self) -> None:
        """Validate the non-negative amount and ISO-style currency code."""
        if self.minor_units < 0:
            raise InvalidOrder(
                f"money amount must be non-negative, got {self.minor_units}",
            )
        if not _CURRENCY_PATTERN.fullmatch(self.currency):
            raise InvalidOrder(
                f"currency must be a 3-letter uppercase code, got {self.currency!r}",
            )

    def add(self, other: Money) -> Money:
        """Return the sum of two amounts of the same currency."""
        self._require_same_currency(other)
        return Money(
            minor_units=self.minor_units + other.minor_units,
            currency=self.currency,
        )

    def times(self, multiplier: int) -> Money:
        """Return this amount scaled by a non-negative integer multiplier."""
        if multiplier < 0:
            raise InvalidOrder(f"multiplier must be non-negative, got {multiplier}")
        return Money(minor_units=self.minor_units * multiplier, currency=self.currency)

    def _require_same_currency(self, other: Money) -> None:
        """Reject cross-currency arithmetic as an invalid order state."""
        if self.currency != other.currency:
            raise InvalidOrder(
                f"currency mismatch: {self.currency} vs {other.currency}",
            )
