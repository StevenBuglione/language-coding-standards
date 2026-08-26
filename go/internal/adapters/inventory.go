// Package adapters provides in-memory doubles for the application ports:
// the canonical design's InMemory/Fake implementations ARE the test doubles,
// so no mocking framework exists anywhere in this template.
package adapters

import (
	"context"
	"fmt"

	"warehouse/internal/application"
	"warehouse/internal/domain"
)

// InMemoryInventoryGateway is a finite-stock InventoryGateway double backed
// by a per-SKU stock map, used in production wiring demos and tests alike.
type InMemoryInventoryGateway struct {
	stock map[domain.Sku]int64
}

// NewInMemoryInventoryGateway starts from an optional initial stock map,
// copied defensively.
func NewInMemoryInventoryGateway(stock map[domain.Sku]int64) *InMemoryInventoryGateway {
	copied := make(map[domain.Sku]int64, len(stock))
	for sku, units := range stock {
		copied[sku] = units
	}
	return &InMemoryInventoryGateway{stock: copied}
}

// Reserve decrements stock when it covers the request; otherwise it returns
// a wrapped domain.InsufficientStock and leaves the stock untouched.
func (g *InMemoryInventoryGateway) Reserve(_ context.Context, sku domain.Sku, quantity domain.Quantity) error {
	available := g.stock[sku]
	if available < int64(quantity) {
		return fmt.Errorf(
			"reserve: %w",
			domain.InsufficientStock{SKU: sku, Requested: quantity, Available: available},
		)
	}
	g.stock[sku] = available - int64(quantity)
	return nil
}

// compile-time proof that the adapter satisfies its port.
var _ application.InventoryGateway = (*InMemoryInventoryGateway)(nil)
