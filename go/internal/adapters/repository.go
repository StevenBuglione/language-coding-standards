package adapters

import (
	"context"
	"fmt"
	"sync"

	"warehouse/internal/application"
	"warehouse/internal/domain"
)

type idempotencyRecord struct {
	fingerprint string
	order       *domain.Order
}

// InMemoryOrderRepository is an application.OrderRepository double keeping
// snapshots keyed by immutable order id. Saves use compare-and-set versions
// and never expose a mutable alias to stored state.
type InMemoryOrderRepository struct {
	mu       sync.Mutex
	orders   map[domain.OrderID]*domain.Order
	saved    []*domain.Order
	byKey    map[string]idempotencyRecord
	FailSave bool
}

// NewInMemoryOrderRepository starts with an empty store.
func NewInMemoryOrderRepository() *InMemoryOrderRepository {
	return &InMemoryOrderRepository{
		orders: make(map[domain.OrderID]*domain.Order),
		byKey:  make(map[string]idempotencyRecord),
	}
}

// Saved returns every persisted snapshot, in save order, for test assertions.
func (r *InMemoryOrderRepository) Saved() []*domain.Order {
	r.mu.Lock()
	defer r.mu.Unlock()
	out := make([]*domain.Order, len(r.saved))
	copy(out, r.saved)
	return out
}

// Save stores a snapshot under compare-and-set version rules and returns a
// detached copy. A lost race wraps domain.PersistenceConflict.
func (r *InMemoryOrderRepository) Save(_ context.Context, order *domain.Order, expectedVersion int) (*domain.Order, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.FailSave {
		return nil, fmt.Errorf(
			"save order: %w",
			domain.PersistenceConflict{Reason: fmt.Sprintf("forced save failure for %s", order.ID().Value)},
		)
	}
	currentVersion := 0
	if current, ok := r.orders[order.ID()]; ok {
		currentVersion = current.Version()
	}
	if currentVersion != expectedVersion {
		return nil, fmt.Errorf(
			"save order: %w",
			domain.PersistenceConflict{Reason: fmt.Sprintf(
				"version conflict for %s: expected %d, stored %d",
				order.ID().Value, expectedVersion, currentVersion,
			)},
		)
	}
	snapshot := order.Snapshot()
	snapshot.BumpVersion()
	r.orders[order.ID()] = snapshot
	r.saved = append(r.saved, snapshot.Snapshot())
	return snapshot.Snapshot(), nil
}

// Get returns a stored snapshot and true, or nil and false; an unknown id
// never raises.
func (r *InMemoryOrderRepository) Get(_ context.Context, id domain.OrderID) (*domain.Order, bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	order, ok := r.orders[id]
	if !ok {
		return nil, false
	}
	return order.Snapshot(), true
}

// GetByIdempotencyKey returns the fingerprint and snapshot for a previous
// successful command.
func (r *InMemoryOrderRepository) GetByIdempotencyKey(_ context.Context, key string) (string, *domain.Order, bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	record, ok := r.byKey[key]
	if !ok {
		return "", nil, false
	}
	return record.fingerprint, record.order.Snapshot(), true
}

// RememberIdempotency records a successful command so retries can replay.
func (r *InMemoryOrderRepository) RememberIdempotency(_ context.Context, key, fingerprint string, order *domain.Order) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.byKey[key] = idempotencyRecord{fingerprint: fingerprint, order: order.Snapshot()}
}

// compile-time proof that the adapter satisfies its port.
var _ application.OrderRepository = (*InMemoryOrderRepository)(nil)
