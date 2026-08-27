package adapters_test

import (
	"testing"

	"warehouse/internal/adapters"
	"warehouse/internal/domain"
)

func TestSequenceOrderIDGeneratorIssuesIncrementingIds(t *testing.T) {
	t.Parallel()

	gen := adapters.NewSequenceOrderIDGenerator()
	first := gen.Next()
	second := gen.Next()
	if first.Value != "ord-1" || second.Value != "ord-2" {
		t.Fatalf("sequence = %s, %s, want ord-1, ord-2", first.Value, second.Value)
	}
}

func TestFixedOrderIDGeneratorRepeatsInjectedId(t *testing.T) {
	t.Parallel()

	id := domain.MustOrderID("ord-fixed-9")
	gen := adapters.NewFixedOrderIDGenerator(id)
	if got := gen.Next(); got != id {
		t.Fatalf("Next() = %s, want %s", got.Value, id.Value)
	}
	if got := gen.Next(); got != id {
		t.Fatalf("second Next() = %s, want %s", got.Value, id.Value)
	}
}
