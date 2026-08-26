/**
 * Deliberately unreadable router: more decision points than the gate allows.
 *
 * The lint gate must reject this many branches in one function
 * (core `complexity` > 15). See bad_examples/README.md for the manifest of
 * expected signals.
 */
export function orderRouter(status: string, priority: number): string {
  if (status === "new") {
    return "intake";
  } else if (status === "validated") {
    return "reservation";
  } else if (status === "reserved") {
    return "charging";
  } else if (status === "charged") {
    return "persistence";
  } else if (status === "paid") {
    return "fulfillment";
  } else if (status === "shipped") {
    return "tracking";
  } else if (status === "delivered") {
    return "archive";
  } else if (status === "cancelled") {
    return "refund";
  } else if (status === "returned") {
    return "restock";
  } else if (status === "held") {
    if (priority > 3) {
      return "escalation";
    }
    return "queue";
  } else if (status === "unknown") {
    return "manual-review";
  } else if (status === "quarantined") {
    return "fraud-check";
  } else if (status === "backordered") {
    return "supplier-eta";
  } else if (status === "split") {
    return "multi-warehouse";
  } else if (status === "gift") {
    return "wrapping-station";
  }
  return "dead-letter";
}
