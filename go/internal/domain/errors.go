// Package domain holds the pure warehouse-order value objects and entity.
//
// The package imports nothing from the application or adapters layers and
// never touches time.Now, I/O, or context: all nondeterminism enters as
// plain values. Every failure is a typed domain error carried by the error
// interface and wrapped with %w at the call site that gives it context.
package domain

import "fmt"

// InvalidOrder marks an order or value that violates a structural domain
// invariant: bad amounts, currency mismatches, illegal transitions.
type InvalidOrder struct {
	Reason string
}

// Error returns the lowercase, punctuation-free violation description.
func (e InvalidOrder) Error() string {
	return "invalid order: " + e.Reason
}

// OrderAlreadyShipped marks a mutation attempt against an order whose state
// machine already reached SHIPPED; shipped orders are immutable.
type OrderAlreadyShipped struct {
	ID OrderID
}

// Error returns the lowercase, punctuation-free violation description.
func (e OrderAlreadyShipped) Error() string {
	return fmt.Sprintf("order %s has already shipped", e.ID.Value)
}

// InsufficientStock reports the reservation that could not be covered:
// which SKU fell short, how much was requested, and what remained.
type InsufficientStock struct {
	SKU       Sku
	Requested Quantity
	Available int64
}

// Error returns the lowercase, punctuation-free shortage description.
func (e InsufficientStock) Error() string {
	return fmt.Sprintf(
		"insufficient stock for %s: requested %d, available %d",
		string(e.SKU), int64(e.Requested), e.Available,
	)
}
