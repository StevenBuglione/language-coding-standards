// Package application orchestrates the canonical place-order use case.
//
// The package owns the outbound ports: adapters implement them, never the
// other way around. Every fallible port returns Go's error interface; a nil
// error is success and a non-nil error wraps a typed domain failure
// (InvalidOrder, InsufficientStock, PaymentDeclined, PersistenceConflict,
// CompensationFailure, or OrderAlreadyShipped), recoverable with errors.As.
package application

import (
	"context"
	"time"

	"warehouse/internal/domain"
)

// ReservationToken is proof that stock for an order was reserved atomically.
type ReservationToken struct {
	OrderID        domain.OrderID
	IdempotencyKey string
}

// ChargeReceipt is proof that payment was collected for an idempotency key.
type ChargeReceipt struct {
	OrderID        domain.OrderID
	IdempotencyKey string
}

// OrderIDGenerator is the outbound port that mints order identifiers.
// Production adapters may use a CSPRNG; tests inject deterministic fakes.
// The domain never reads randomness itself.
type OrderIDGenerator interface {
	Next() domain.OrderID
}

// InventoryGateway is the outbound port for atomic stock reservation.
// ReserveAll covers every line or none; a shortage wraps InsufficientStock.
// Release failure wraps CompensationFailure.
type InventoryGateway interface {
	ReserveAll(ctx context.Context, orderID domain.OrderID, lines []domain.OrderLine, idempotencyKey string) (ReservationToken, error)
	Release(ctx context.Context, token ReservationToken) error
}

// PaymentProcessor is the outbound port for idempotent payment collection.
// Charge wraps PaymentDeclined when refused. Refund failure wraps
// CompensationFailure. Identical idempotency keys replay the original outcome.
type PaymentProcessor interface {
	Charge(ctx context.Context, order *domain.Order, idempotencyKey string) (ChargeReceipt, error)
	Refund(ctx context.Context, receipt ChargeReceipt) error
}

// OrderRepository is the outbound port that persists and retrieves snapshots.
// Save uses compare-and-set expectedVersion and wraps PersistenceConflict on
// a lost race. Get reports absence with the second return value; an unknown
// identifier never raises. Reads and writes never expose a mutable alias.
type OrderRepository interface {
	Save(ctx context.Context, order *domain.Order, expectedVersion int) (*domain.Order, error)
	Get(ctx context.Context, id domain.OrderID) (*domain.Order, bool)
	GetByIdempotencyKey(ctx context.Context, key string) (fingerprint string, order *domain.Order, ok bool)
	RememberIdempotency(ctx context.Context, key, fingerprint string, order *domain.Order)
}

// Clock provides the current instant. Production code must inject it instead
// of calling time.Now directly, so tests pin time deterministically.
type Clock interface {
	Now() time.Time
}
