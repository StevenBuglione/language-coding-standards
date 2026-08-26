"""Deliberate dead code: a module-level function nothing ever calls.

Expected signal: unused function 'orphaned_helper' (vulture, confidence 60).
"""


def orphaned_helper(units: int) -> int:
    """No caller anywhere in the tree."""
    return units * 2
