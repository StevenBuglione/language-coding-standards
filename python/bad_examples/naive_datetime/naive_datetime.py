"""Deliberate timezone-naive timestamp that the lint gate must reject.

See bad_examples/README.md for the manifest of expected signals.
"""

from datetime import datetime


def audit_stamp() -> datetime:
    """Capture a naive local timestamp, which the lint gate forbids."""
    return datetime.now()
