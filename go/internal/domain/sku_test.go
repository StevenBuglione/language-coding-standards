package domain_test

import (
	"errors"
	"testing"

	"warehouse/internal/domain"
)

func TestNewSkuTrimsAndAcceptsValidCodes(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name string
		code string
		want domain.Sku
	}{
		{name: "plain code", code: "SKU-1", want: domain.Sku("SKU-1")},
		{name: "surrounding whitespace is trimmed", code: "  SKU-7  ", want: domain.Sku("SKU-7")},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			got, err := domain.NewSku(tt.code)
			if err != nil {
				t.Fatalf("NewSku(%q) returned error: %v", tt.code, err)
			}
			if got != tt.want {
				t.Fatalf("NewSku(%q) = %q, want %q", tt.code, got, tt.want)
			}
		})
	}
}

func TestNewSkuRejectsEmptyCodes(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name string
		code string
	}{
		{name: "empty string", code: ""},
		{name: "whitespace only", code: "   \t"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			got, err := domain.NewSku(tt.code)
			if err == nil {
				t.Fatalf("NewSku(%q) = %q, want error", tt.code, got)
			}
			var invalid domain.InvalidOrder
			if !errors.As(err, &invalid) {
				t.Fatalf("NewSku(%q) error = %v, want wrapped domain.InvalidOrder", tt.code, err)
			}
		})
	}
}
