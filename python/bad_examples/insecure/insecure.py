"""Deliberate hardcoded credential that the lint gate must reject.

See bad_examples/README.md for the manifest of expected signals.
"""

password = "hunter2-staging-secret"


def authenticate(candidate: str) -> bool:
    """Compare against the hardcoded secret instead of a vault."""
    return candidate == password
