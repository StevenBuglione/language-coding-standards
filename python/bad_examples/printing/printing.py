"""Deliberate console output that the lint gate must reject.

See bad_examples/README.md for the manifest of expected signals.
"""


def debug_pipeline() -> None:
    """Print diagnostics instead of using structured logging."""
    print("debug: entering order pipeline")
