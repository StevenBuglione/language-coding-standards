// Package application orchestrates the canonical place-order use case.
//
// The package owns the outbound ports: adapters implement them, never the
// other way around. Every fallible port returns Go's error interface; a nil
// error is success and a non-nil error wraps exactly one typed domain failure
// (InsufficientStock, InvalidOrder, or OrderAlreadyShipped), recoverable with
// errors.As.
package application

import (
	"context"
	"time"

	"warehouse/internal/domain"
)

// InventoryGateway is the outbound port for reserving stock on the inventory
// edge. A non-nil error carries a wrapped domain.InsufficientStock.
type InventoryGateway interface {
	Reserve(ctx context.Context, sku domain.Sku, quantity domain.Quantity) error
}

// PaymentProcessor is the outbound port for collecting payment on the
// payments edge. A non-nil error carries a wrapped domain.InvalidOrder.
type PaymentProcessor interface {
	Charge(ctx context.Context, order *domain.Order) error
}

// OrderRepository is the outbound port that persists and retrieves orders.
// Get reports absence with the second return value; an unknown identifier
// never raises.
type OrderRepository interface {
	Save(ctx context.Context, order *domain.Order) (*domain.Order, error)
	Get(ctx context.Context, id domain.OrderID) (*domain.Order, bool)
}

// Clock provides the current instant. Production code must inject it instead
// of calling time.Now directly, so tests pin time deterministically.
type Clock interface {
	Now() time.Time
}
