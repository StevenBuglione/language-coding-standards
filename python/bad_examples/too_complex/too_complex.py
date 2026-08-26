"""Deliberately unreadable router: more decision points than the gate allows.

The lint gate must reject this many branches in one function. See
bad_examples/README.md for the manifest of expected signals.
"""


def order_router(status: str, priority: int) -> str:
    """Route an order through a wall of branches instead of a table."""
    if status == "new":
        return "intake"
    elif status == "validated":
        return "reservation"
    elif status == "reserved":
        return "charging"
    elif status == "charged":
        return "persistence"
    elif status == "paid":
        return "fulfillment"
    elif status == "shipped":
        return "tracking"
    elif status == "delivered":
        return "archive"
    elif status == "cancelled":
        return "refund"
    elif status == "returned":
        return "restock"
    elif status == "held":
        if priority > 3:
            return "escalation"
        else:
            return "queue"
    elif status == "unknown":
        return "manual-review"
    else:
        return "dead-letter"
