package adapters

import (
	"context"

	"warehouse/internal/application"
	"warehouse/internal/domain"
)

// InMemoryOrderRepository is an application.OrderRepository double keeping
// orders in a map keyed by immutable order id.
type InMemoryOrderRepository struct {
	orders map[domain.OrderID]*domain.Order
	saved  []*domain.Order
}

// NewInMemoryOrderRepository starts with an empty store.
func NewInMemoryOrderRepository() *InMemoryOrderRepository {
	return &InMemoryOrderRepository{orders: make(map[domain.OrderID]*domain.Order)}
}

// Saved returns every persisted order, in save order, for test assertions.
func (r *InMemoryOrderRepository) Saved() []*domain.Order {
	return r.saved
}

// Save stores the order under its id and returns it as persisted.
func (r *InMemoryOrderRepository) Save(_ context.Context, order *domain.Order) (*domain.Order, error) {
	r.orders[order.ID()] = order
	r.saved = append(r.saved, order)
	return order, nil
}

// Get returns the stored order and true, or nil and false; an unknown id
// never raises.
func (r *InMemoryOrderRepository) Get(_ context.Context, id domain.OrderID) (*domain.Order, bool) {
	order, ok := r.orders[id]
	return order, ok
}

// compile-time proof that the adapter satisfies its port.
var _ application.OrderRepository = (*InMemoryOrderRepository)(nil)
