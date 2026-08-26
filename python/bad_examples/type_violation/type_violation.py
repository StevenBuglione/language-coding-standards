"""Deliberately type-unsafe code: wrong argument types and untyped parameters.

The types gate must reject both patterns. See bad_examples/README.md for the
manifest of expected signals.
"""


def add_units(left: int, right: int) -> int:
    """Add two unit counts."""
    return left + right


total = add_units("3", 4)


def combine(raw_left, raw_right):
    """Parameters carry no annotations at all."""
    return raw_left + raw_right
