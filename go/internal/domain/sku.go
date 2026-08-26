package domain

import (
	"fmt"
	"strings"
)

// Sku is a non-empty stock-keeping-unit code, normalized to its trimmed form.
type Sku string

// NewSku trims surrounding whitespace and rejects codes that end up empty.
func NewSku(code string) (Sku, error) {
	trimmed := strings.TrimSpace(code)
	if trimmed == "" {
		return "", fmt.Errorf("new sku: %w", InvalidOrder{Reason: "sku code must be non-empty"})
	}
	return Sku(trimmed), nil
}

// MustSku is NewSku for infallible literals; it panics on violation and is
// intended for tests and wiring code with compile-time-known inputs.
func MustSku(code string) Sku {
	sku, err := NewSku(code)
	if err != nil {
		panic(err)
	}
	return sku
}
