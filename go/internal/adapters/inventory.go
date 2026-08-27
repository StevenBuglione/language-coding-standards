// Package adapters provides in-memory doubles for the application ports:
// the canonical design's InMemory/Fake implementations ARE the test doubles,
// so no mocking framework exists anywhere in this template.
package adapters

import (
	"context"
	"fmt"
	"sync"

	"warehouse/internal/application"
	"warehouse/internal/domain"
)

type heldUnits struct {
	sku    domain.Sku
	amount int64
}

// InMemoryInventoryGateway is a finite-stock InventoryGateway double backed
// by a per-SKU stock map. ReserveAll is atomic and the adapter is safe for
// concurrent use.
type InMemoryInventoryGateway struct {
	mu           sync.Mutex
	stock        map[domain.Sku]int64
	reservations map[string][]heldUnits
	FailRelease  bool
}

// NewInMemoryInventoryGateway starts from an optional initial stock map,
// copied defensively.
func NewInMemoryInventoryGateway(stock map[domain.Sku]int64) *InMemoryInventoryGateway {
	copied := make(map[domain.Sku]int64, len(stock))
	for sku, units := range stock {
		copied[sku] = units
	}
	return &InMemoryInventoryGateway{
		stock:        copied,
		reservations: make(map[string][]heldUnits),
	}
}

// SnapshotStock returns a copy of remaining units per SKU.
func (g *InMemoryInventoryGateway) SnapshotStock() map[domain.Sku]int64 {
	g.mu.Lock()
	defer g.mu.Unlock()
	out := make(map[domain.Sku]int64, len(g.stock))
	for sku, units := range g.stock {
		out[sku] = units
	}
	return out
}

// ReserveAll decrements stock for every line or none. A shortage wraps
// domain.InsufficientStock and leaves the map untouched. Identical
// idempotency keys replay the original reservation without a second debit.
func (g *InMemoryInventoryGateway) ReserveAll(
	_ context.Context,
	orderID domain.OrderID,
	lines []domain.OrderLine,
	idempotencyKey string,
) (application.ReservationToken, error) {
	g.mu.Lock()
	defer g.mu.Unlock()
	token := application.ReservationToken{OrderID: orderID, IdempotencyKey: idempotencyKey}
	if _, ok := g.reservations[idempotencyKey]; ok {
		return token, nil
	}
	needed := make([]heldUnits, 0, len(lines))
	for _, line := range lines {
		available := g.stock[line.SKU]
		if available < int64(line.Quantity) {
			return application.ReservationToken{}, fmt.Errorf(
				"reserve all: %w",
				domain.InsufficientStock{SKU: line.SKU, Requested: line.Quantity, Available: available},
			)
		}
		needed = append(needed, heldUnits{sku: line.SKU, amount: int64(line.Quantity)})
	}
	for _, held := range needed {
		g.stock[held.sku] -= held.amount
	}
	g.reservations[idempotencyKey] = needed
	return token, nil
}

// Release puts reserved units back. Unknown tokens are a no-op success.
func (g *InMemoryInventoryGateway) Release(_ context.Context, token application.ReservationToken) error {
	g.mu.Lock()
	defer g.mu.Unlock()
	if g.FailRelease {
		return fmt.Errorf(
			"release: %w",
			domain.CompensationFailure{Stage: "release", Detail: "forced failure"},
		)
	}
	held, ok := g.reservations[token.IdempotencyKey]
	if !ok {
		return nil
	}
	delete(g.reservations, token.IdempotencyKey)
	for _, item := range held {
		g.stock[item.sku] += item.amount
	}
	return nil
}

// compile-time proof that the adapter satisfies its port.
var _ application.InventoryGateway = (*InMemoryInventoryGateway)(nil)
