"""Money value object: integer minor units plus an ISO-style currency code."""

from __future__ import annotations

import re
from dataclasses import dataclass

from warehouse.domain.errors import InvalidOrder

_CURRENCY_PATTERN = re.compile(r"[A-Z]{3}")
MONEY_MINOR_UNITS_MAX = 9_007_199_254_740_991


@dataclass(frozen=True, slots=True)
class Money:
    """
    A non-negative amount in integer minor units of a single currency.

    Currency codes are ISO-style (``^[A-Z]{3}$``), not ISO-4217 membership.
    ``ZZZ`` is valid. Cross-currency operations raise ``InvalidOrder``.
    """

    minor_units: int
    currency: str

    def __post_init__(self) -> None:
        """Validate the non-negative amount, shared maximum, and currency."""
        if isinstance(self.minor_units, bool) or not isinstance(self.minor_units, int):
            raise InvalidOrder(
                f"money amount must be an integer, got {self.minor_units!r}",
            )
        if self.minor_units < 0:
            raise InvalidOrder(
                f"money amount must be non-negative, got {self.minor_units}",
            )
        if self.minor_units > MONEY_MINOR_UNITS_MAX:
            raise InvalidOrder(
                f"money amount exceeds {MONEY_MINOR_UNITS_MAX}, got {self.minor_units}",
            )
        if not _CURRENCY_PATTERN.fullmatch(self.currency):
            raise InvalidOrder(
                f"currency must be a 3-letter uppercase ISO-style code, "
                f"got {self.currency!r}",
            )

    def add(self, other: Money) -> Money:
        """Return the sum of two amounts of the same currency."""
        self._require_same_currency(other)
        total = self.minor_units + other.minor_units
        if total > MONEY_MINOR_UNITS_MAX:
            raise InvalidOrder("money addition overflows the shared maximum")
        return Money(minor_units=total, currency=self.currency)

    def times(self, multiplier: int) -> Money:
        """Return this amount scaled by a non-negative integer multiplier."""
        if isinstance(multiplier, bool) or not isinstance(multiplier, int):
            raise InvalidOrder(f"multiplier must be an integer, got {multiplier!r}")
        if multiplier < 0:
            raise InvalidOrder(f"multiplier must be non-negative, got {multiplier}")
        product = self.minor_units * multiplier
        if product > MONEY_MINOR_UNITS_MAX:
            raise InvalidOrder("money scaling overflows the shared maximum")
        return Money(minor_units=product, currency=self.currency)

    def _require_same_currency(self, other: Money) -> None:
        """Reject cross-currency arithmetic as an invalid order state."""
        if self.currency != other.currency:
            raise InvalidOrder(
                f"currency mismatch: {self.currency} vs {other.currency}",
            )
