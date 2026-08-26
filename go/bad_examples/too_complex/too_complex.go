// Package too_complex holds a deliberately unreadable router: more decision
// points than the complexity gate allows.
//
// The lint gate must reject this function (cyclop ceiling is 10). See
// bad_examples/README.md for the manifest of expected signals.
package too_complex

// OrderRouter routes an order through a wall of branches instead of a table.
func OrderRouter(status string, priority int) string {
	if status == "new" {
		return "intake"
	} else if status == "validated" {
		return "reservation"
	} else if status == "reserved" {
		return "charging"
	} else if status == "charged" {
		return "persistence"
	} else if status == "paid" {
		return "fulfillment"
	} else if status == "shipped" {
		return "tracking"
	} else if status == "delivered" {
		return "archive"
	} else if status == "cancelled" {
		return "refund"
	} else if status == "returned" {
		return "restock"
	} else if status == "held" {
		return "review"
	} else if status == "fraud" && priority > 3 {
		return "escalation"
	}
	return "unknown"
}
