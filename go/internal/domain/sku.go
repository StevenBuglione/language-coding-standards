package domain

import (
	"fmt"
	"strings"
)

// SkuMaxUTF8Bytes is the shared inclusive UTF-8 byte length limit for a SKU.
const SkuMaxUTF8Bytes = 64

// skuEdgeWhitespace is the only set of characters stripped from SKU ends:
// ASCII space, tab, CR, and LF. U+00A0 and other non-ASCII whitespace stay.
const skuEdgeWhitespace = " \t\r\n"

// Sku is a non-empty stock-keeping-unit code, normalized to its trimmed form.
type Sku string

// NewSku strips ASCII space/tab/CR/LF from both ends and rejects codes that
// end up empty or exceed the UTF-8 byte limit. Interior text and case are
// preserved; NBSP is not stripped.
func NewSku(code string) (Sku, error) {
	trimmed := strings.Trim(code, skuEdgeWhitespace)
	if trimmed == "" {
		return "", fmt.Errorf("new sku: %w", InvalidOrder{Reason: "sku code must be non-empty"})
	}
	if len(trimmed) > SkuMaxUTF8Bytes {
		return "", fmt.Errorf(
			"new sku: %w",
			InvalidOrder{Reason: fmt.Sprintf("sku code exceeds %d UTF-8 bytes", SkuMaxUTF8Bytes)},
		)
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
