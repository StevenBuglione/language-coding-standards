package domain_test

import (
	"errors"
	"testing"

	"warehouse/internal/domain"
)

func TestNewQuantityAcceptsPositiveValues(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name  string
		value int64
		want  domain.Quantity
	}{
		{name: "one", value: 1, want: domain.Quantity(1)},
		{name: "typical order line", value: 12, want: domain.Quantity(12)},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			got, err := domain.NewQuantity(tt.value)
			if err != nil {
				t.Fatalf("NewQuantity(%d) returned error: %v", tt.value, err)
			}
			if got != tt.want {
				t.Fatalf("NewQuantity(%d) = %d, want %d", tt.value, got, tt.want)
			}
		})
	}
}

func TestNewQuantityRejectsNonPositiveValues(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name  string
		value int64
	}{
		{name: "zero", value: 0},
		{name: "negative", value: -3},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			got, err := domain.NewQuantity(tt.value)
			if err == nil {
				t.Fatalf("NewQuantity(%d) = %d, want error", tt.value, got)
			}
			var invalid domain.InvalidOrder
			if !errors.As(err, &invalid) {
				t.Fatalf("NewQuantity(%d) error = %v, want wrapped domain.InvalidOrder", tt.value, err)
			}
		})
	}
}
