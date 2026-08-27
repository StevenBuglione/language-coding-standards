"""Sku value object: a non-empty stock-keeping-unit code."""

from __future__ import annotations

from dataclasses import dataclass

from warehouse.domain.errors import InvalidOrder

_END_WHITESPACE = frozenset(" \t\r\n")
SKU_MAX_UTF8_BYTES = 64


def normalize_sku_code(code: str) -> str:
    """Strip only ASCII space, tab, CR, and LF from both ends."""
    start = 0
    end = len(code)
    while start < end and code[start] in _END_WHITESPACE:
        start += 1
    while end > start and code[end - 1] in _END_WHITESPACE:
        end -= 1
    return code[start:end]


@dataclass(frozen=True, slots=True)
class Sku:
    """A stock-keeping-unit code, normalized on creation."""

    code: str

    def __post_init__(self) -> None:
        """Normalize ASCII edge whitespace and reject empty or oversized codes."""
        trimmed = normalize_sku_code(self.code)
        if not trimmed:
            raise InvalidOrder("sku code must be non-empty")
        if len(trimmed.encode("utf-8")) > SKU_MAX_UTF8_BYTES:
            raise InvalidOrder(
                f"sku code exceeds {SKU_MAX_UTF8_BYTES} UTF-8 bytes",
            )
        if trimmed != self.code:
            object.__setattr__(self, "code", trimmed)
