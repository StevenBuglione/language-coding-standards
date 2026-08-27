package domain_test

import (
	"testing"

	"warehouse/internal/domain"
)

// The Must constructors promise a panic on invalid input instead of an
// error return; these tests pin that contract for wiring code.
func TestMustConstructorsPanicOnInvalidInput(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name string
		act  func()
	}{
		{
			name: "MustMoney rejects negative amount",
			act:  func() { domain.MustMoney(-1, "USD") },
		},
		{
			name: "MustMoney rejects bad currency",
			act:  func() { domain.MustMoney(1, "usd") },
		},
		{
			name: "MustQuantity rejects zero",
			act:  func() { domain.MustQuantity(0) },
		},
		{
			name: "MustSku rejects empty code",
			act:  func() { domain.MustSku("   ") },
		},
		{
			name: "MustOrderID rejects empty id",
			act:  func() { domain.MustOrderID("  ") },
		},
		{
			name: "MustOrderLine rejects zero quantity",
			act: func() {
				domain.MustOrderLine(domain.MustSku("SKU-A"), domain.Quantity(0), domain.MustMoney(1, "USD"))
			},
		},
		{
			name: "MustOrder rejects empty lines",
			act:  func() { domain.MustOrder(nil, domain.MustOrderID("ord-1")) },
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			defer func() {
				if recover() == nil {
					t.Fatal("constructor returned normally, want panic")
				}
			}()
			tt.act()
		})
	}
}
