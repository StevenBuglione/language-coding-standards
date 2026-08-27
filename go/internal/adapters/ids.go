package adapters

import (
	"fmt"
	"sync"

	"warehouse/internal/application"
	"warehouse/internal/domain"
)

// SequenceOrderIDGenerator issues ord-1, ord-2, ... and is safe for concurrent use.
type SequenceOrderIDGenerator struct {
	mu     sync.Mutex
	n      int
	prefix string
}

// NewSequenceOrderIDGenerator starts at zero so the first id is prefix-1.
func NewSequenceOrderIDGenerator() *SequenceOrderIDGenerator {
	return &SequenceOrderIDGenerator{prefix: "ord"}
}

// Next returns the next sequenced identifier.
func (g *SequenceOrderIDGenerator) Next() domain.OrderID {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.n++
	return domain.MustOrderID(fmt.Sprintf("%s-%d", g.prefix, g.n))
}

// compile-time proof that the adapter satisfies its port.
var _ application.OrderIDGenerator = (*SequenceOrderIDGenerator)(nil)

// FixedOrderIDGenerator always returns the same injected identifier.
type FixedOrderIDGenerator struct {
	id domain.OrderID
}

// NewFixedOrderIDGenerator holds a single identifier.
func NewFixedOrderIDGenerator(id domain.OrderID) *FixedOrderIDGenerator {
	return &FixedOrderIDGenerator{id: id}
}

// Next returns the configured identifier.
func (g *FixedOrderIDGenerator) Next() domain.OrderID {
	return g.id
}

// compile-time proof that the adapter satisfies its port.
var _ application.OrderIDGenerator = (*FixedOrderIDGenerator)(nil)
