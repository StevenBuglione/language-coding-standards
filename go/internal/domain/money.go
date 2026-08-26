package domain

import (
	"fmt"
	"math"
	"regexp"
)

// currencyPattern matches ISO-4217 style codes: exactly three uppercase letters.
var currencyPattern = regexp.MustCompile(`^[A-Z]{3}$`)

// Money is a non-negative amount in integer minor units of a single currency.
//
// Money is an immutable value: every operation validates its inputs and
// returns a new value or a wrapped InvalidOrder. Cross-currency arithmetic
// is invalid by contract (CONTRACTS.md §2).
type Money struct {
	MinorUnits int64
	Currency   string
}

// NewMoney validates and returns a Money value.
func NewMoney(minorUnits int64, currency string) (Money, error) {
	m := Money{MinorUnits: minorUnits, Currency: currency}
	if err := m.validate(); err != nil {
		return Money{}, fmt.Errorf("new money: %w", err)
	}
	return m, nil
}

// MustMoney is NewMoney for infallible literals; it panics on violation and
// is intended for tests and wiring code with compile-time-known inputs.
func MustMoney(minorUnits int64, currency string) Money {
	m, err := NewMoney(minorUnits, currency)
	if err != nil {
		panic(err)
	}
	return m
}

// Add returns the sum of two same-currency amounts.
func (m Money) Add(other Money) (Money, error) {
	if m.Currency != other.Currency {
		return Money{}, fmt.Errorf(
			"add money: %w",
			InvalidOrder{Reason: fmt.Sprintf("currency mismatch: %s vs %s", m.Currency, other.Currency)},
		)
	}
	sum, err := NewMoney(m.MinorUnits+other.MinorUnits, m.Currency)
	if err != nil {
		return Money{}, fmt.Errorf("add money: %w", err)
	}
	return sum, nil
}

// Times returns this amount scaled by a non-negative integer multiplier.
func (m Money) Times(multiplier int64) (Money, error) {
	if multiplier < 0 {
		return Money{}, fmt.Errorf(
			"times money: %w",
			InvalidOrder{Reason: fmt.Sprintf("multiplier must be non-negative, got %d", multiplier)},
		)
	}
	// Precondition before multiplying: unlike Add, whose sum wraps into the
	// negative range and is therefore always caught by NewMoney's
	// non-negative check, a wrapping product can land back in positive
	// territory and masquerade as valid money.
	if multiplier != 0 && m.MinorUnits > math.MaxInt64/multiplier {
		return Money{}, fmt.Errorf(
			"times money: %w",
			InvalidOrder{Reason: fmt.Sprintf("scaling overflows int64 minor units: %d * %d", m.MinorUnits, multiplier)},
		)
	}
	scaled, err := NewMoney(m.MinorUnits*multiplier, m.Currency)
	if err != nil {
		return Money{}, fmt.Errorf("times money: %w", err)
	}
	return scaled, nil
}

func (m Money) validate() error {
	if m.MinorUnits < 0 {
		return InvalidOrder{Reason: fmt.Sprintf("money amount must be non-negative, got %d", m.MinorUnits)}
	}
	if !currencyPattern.MatchString(m.Currency) {
		return InvalidOrder{Reason: fmt.Sprintf("currency must be 3 uppercase letters, got %q", m.Currency)}
	}
	return nil
}
