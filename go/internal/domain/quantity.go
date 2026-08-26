package domain

import "fmt"

// Quantity is a strictly positive number of stock units.
type Quantity int64

// NewQuantity validates that the amount is strictly positive.
func NewQuantity(value int64) (Quantity, error) {
	if value <= 0 {
		return 0, fmt.Errorf(
			"new quantity: %w",
			InvalidOrder{Reason: fmt.Sprintf("quantity must be strictly positive, got %d", value)},
		)
	}
	return Quantity(value), nil
}

// MustQuantity is NewQuantity for infallible literals; it panics on violation
// and is intended for tests and wiring code with compile-time-known inputs.
func MustQuantity(value int64) Quantity {
	q, err := NewQuantity(value)
	if err != nil {
		panic(err)
	}
	return q
}
