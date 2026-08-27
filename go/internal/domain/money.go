package domain

import (
	"fmt"
	"math"
	"regexp"
)

// MoneyMinorUnitsMax is the shared inclusive maximum for minor units
// (9007199254740991). It is IEEE-754 safe-integer sized so every language
// pack can represent the same range.
const MoneyMinorUnitsMax int64 = 9007199254740991

// currencyPattern matches ISO-style codes: exactly three uppercase ASCII
// letters. This is not ISO-4217 membership; ZZZ is valid.
var currencyPattern = regexp.MustCompile(`^[A-Z]{3}$`)

// Money is a non-negative amount in integer minor units of a single currency.
//
// Money is an immutable value: every operation validates its inputs and
// returns a new value or a wrapped InvalidOrder. Cross-currency arithmetic
// is invalid by contract (CONTRACTS.md §2). Overflow against the shared
// maximum is InvalidOrder, never wrap, saturate, or coerce.
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
	if other.MinorUnits > 0 && m.MinorUnits > math.MaxInt64-other.MinorUnits {
		return Money{}, fmt.Errorf(
			"add money: %w",
			InvalidOrder{Reason: "money addition overflows the shared maximum"},
		)
	}
	sum := m.MinorUnits + other.MinorUnits
	if sum > MoneyMinorUnitsMax {
		return Money{}, fmt.Errorf(
			"add money: %w",
			InvalidOrder{Reason: "money addition overflows the shared maximum"},
		)
	}
	added, err := NewMoney(sum, m.Currency)
	if err != nil {
		return Money{}, fmt.Errorf("add money: %w", err)
	}
	return added, nil
}

// Times returns this amount scaled by a non-negative integer multiplier.
func (m Money) Times(multiplier int64) (Money, error) {
	if multiplier < 0 {
		return Money{}, fmt.Errorf(
			"times money: %w",
			InvalidOrder{Reason: fmt.Sprintf("multiplier must be non-negative, got %d", multiplier)},
		)
	}
	// Reject wrapping products before the multiply: a wrapping product can
	// land back in positive territory and masquerade as valid money.
	if multiplier != 0 && m.MinorUnits > math.MaxInt64/multiplier {
		return Money{}, fmt.Errorf(
			"times money: %w",
			InvalidOrder{Reason: fmt.Sprintf("scaling overflows int64 minor units: %d * %d", m.MinorUnits, multiplier)},
		)
	}
	product := m.MinorUnits * multiplier
	if product > MoneyMinorUnitsMax {
		return Money{}, fmt.Errorf(
			"times money: %w",
			InvalidOrder{Reason: "money scaling overflows the shared maximum"},
		)
	}
	scaled, err := NewMoney(product, m.Currency)
	if err != nil {
		return Money{}, fmt.Errorf("times money: %w", err)
	}
	return scaled, nil
}

func (m Money) validate() error {
	if m.MinorUnits < 0 {
		return InvalidOrder{Reason: fmt.Sprintf("money amount must be non-negative, got %d", m.MinorUnits)}
	}
	if m.MinorUnits > MoneyMinorUnitsMax {
		return InvalidOrder{Reason: fmt.Sprintf("money amount exceeds %d, got %d", MoneyMinorUnitsMax, m.MinorUnits)}
	}
	if !currencyPattern.MatchString(m.Currency) {
		return InvalidOrder{Reason: fmt.Sprintf("currency must be a 3-letter uppercase ISO-style code, got %q", m.Currency)}
	}
	return nil
}
