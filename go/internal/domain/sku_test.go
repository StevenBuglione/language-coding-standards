package domain_test

import (
	"errors"
	"strings"
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
		{name: "ascii space tab cr lf are trimmed", code: " \tSKU-7\r\n ", want: domain.Sku("SKU-7")},
		{name: "interior space is preserved", code: "SKU A", want: domain.Sku("SKU A")},
		{name: "case is preserved", code: "sku-a", want: domain.Sku("sku-a")},
		{name: "unicode is allowed", code: "café", want: domain.Sku("café")},
		{name: "nbsp prefix is kept", code: "\u00a0ABC", want: domain.Sku("\u00a0ABC")},
		{name: "max utf-8 bytes", code: strings.Repeat("A", domain.SkuMaxUTF8Bytes), want: domain.Sku(strings.Repeat("A", domain.SkuMaxUTF8Bytes))},
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

func TestNewSkuRejectsEmptyOrOversizedCodes(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name string
		code string
	}{
		{name: "empty string", code: ""},
		{name: "ascii whitespace only", code: " \t\r\n "},
		{name: "above max utf-8 bytes", code: strings.Repeat("A", domain.SkuMaxUTF8Bytes+1)},
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
