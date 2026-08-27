package domain_test

import (
	"errors"
	"math"
	"math/rand"
	"testing"

	"warehouse/internal/domain"
)

func TestNewMoneyAcceptsValidAmounts(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name       string
		minorUnits int64
		currency   string
		want       domain.Money
	}{
		{name: "zero usd", minorUnits: 0, currency: "USD", want: domain.Money{MinorUnits: 0, Currency: "USD"}},
		{name: "one cent", minorUnits: 1, currency: "EUR", want: domain.Money{MinorUnits: 1, Currency: "EUR"}},
		{name: "large amount", minorUnits: 999999999999, currency: "GBP", want: domain.Money{MinorUnits: 999999999999, Currency: "GBP"}},
		{name: "shared maximum", minorUnits: domain.MoneyMinorUnitsMax, currency: "USD", want: domain.Money{MinorUnits: domain.MoneyMinorUnitsMax, Currency: "USD"}},
		{name: "iso-style zzz", minorUnits: 0, currency: "ZZZ", want: domain.Money{MinorUnits: 0, Currency: "ZZZ"}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			got, err := domain.NewMoney(tt.minorUnits, tt.currency)
			if err != nil {
				t.Fatalf("NewMoney(%d, %q) returned error: %v", tt.minorUnits, tt.currency, err)
			}
			if got != tt.want {
				t.Fatalf("NewMoney(%d, %q) = %+v, want %+v", tt.minorUnits, tt.currency, got, tt.want)
			}
		})
	}
}

func TestNewMoneyRejectsInvalidValues(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name       string
		minorUnits int64
		currency   string
	}{
		{name: "negative amount", minorUnits: -1, currency: "USD"},
		{name: "lowercase currency", minorUnits: 5, currency: "usd"},
		{name: "two-letter currency", minorUnits: 5, currency: "US"},
		{name: "four-letter currency", minorUnits: 5, currency: "USDD"},
		{name: "empty currency", minorUnits: 5, currency: ""},
		{name: "above shared maximum", minorUnits: domain.MoneyMinorUnitsMax + 1, currency: "USD"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			got, err := domain.NewMoney(tt.minorUnits, tt.currency)
			if err == nil {
				t.Fatalf("NewMoney(%d, %q) = %+v, want error", tt.minorUnits, tt.currency, got)
			}
			var invalid domain.InvalidOrder
			if !errors.As(err, &invalid) {
				t.Fatalf("NewMoney(%d, %q) error = %v, want wrapped domain.InvalidOrder", tt.minorUnits, tt.currency, err)
			}
		})
	}
}

// TestMoneyAdditionIsCommutative is invariant suite 1 of the template's
// required table-driven pair (CONTRACTS.md §2): addition over same-currency
// amounts commutes. The case grid combines a fixed boundary grid with
// seeded pseudo-random pairs; Go's ecosystem has no standard property
// framework, so this suite stands in honestly (LANG_SPEC.md).
func TestMoneyAdditionIsCommutative(t *testing.T) {
	t.Parallel()

	const currencies = 3
	rng := rand.New(rand.NewSource(20260826))

	type pair struct {
		left  domain.Money
		right domain.Money
	}

	boundaries := []int64{0, 1, 99, 100, 1000000}
	grid := make([]pair, 0, len(boundaries)*len(boundaries)*currencies)
	for _, currency := range []string{"USD", "EUR", "JPY"} {
		for _, left := range boundaries {
			for _, right := range boundaries {
				grid = append(grid, pair{
					left:  domain.MustMoney(left, currency),
					right: domain.MustMoney(right, currency),
				})
			}
		}
	}
	for range 200 {
		currency := []string{"USD", "EUR", "JPY"}[rng.Intn(currencies)]
		grid = append(grid, pair{
			left:  domain.MustMoney(rng.Int63n(1_000_000_000), currency),
			right: domain.MustMoney(rng.Int63n(1_000_000_000), currency),
		})
	}

	for _, tt := range grid {
		leftSum, err := tt.left.Add(tt.right)
		if err != nil {
			t.Fatalf("Add(%+v, %+v) returned error: %v", tt.left, tt.right, err)
		}
		rightSum, err := tt.right.Add(tt.left)
		if err != nil {
			t.Fatalf("Add(%+v, %+v) returned error: %v", tt.right, tt.left, err)
		}
		if leftSum != rightSum {
			t.Fatalf("addition not commutative: %+v vs %+v", leftSum, rightSum)
		}
	}
}

func TestMoneyScalingDistributesOverAddition(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name   string
		base   int64
		scale  int64
		extra  int64
		wanted int64
	}{
		{name: "zero scale", base: 250, scale: 0, extra: 125, wanted: 31250},
		{name: "unit scale", base: 250, scale: 1, extra: 0, wanted: 250},
		{name: "multi line order", base: 1999, scale: 3, extra: 499, wanted: 1003498},
		{name: "boundary amounts", base: 0, scale: 7, extra: 0, wanted: 0},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			money := domain.MustMoney(tt.base, "USD")
			scaledBase, err := money.Times(tt.scale)
			if err != nil {
				t.Fatalf("Times(%d) returned error: %v", tt.scale, err)
			}
			scaledExtra, err := money.Times(tt.extra)
			if err != nil {
				t.Fatalf("Times(%d) returned error: %v", tt.extra, err)
			}
			distributed, err := scaledBase.Add(scaledExtra)
			if err != nil {
				t.Fatalf("distribution returned error: %v", err)
			}
			want := domain.MustMoney(tt.wanted, "USD")
			if distributed != want {
				t.Fatalf("distributed = %+v, want %+v", distributed, want)
			}
		})
	}
}

func TestMoneyCrossCurrencyAdditionIsInvalid(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name     string
		leftCur  string
		rightCur string
	}{
		{name: "usd vs eur", leftCur: "USD", rightCur: "EUR"},
		{name: "eur vs usd", leftCur: "EUR", rightCur: "USD"},
		{name: "jpy vs gbp", leftCur: "JPY", rightCur: "GBP"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			left := domain.MustMoney(500, tt.leftCur)
			right := domain.MustMoney(500, tt.rightCur)
			got, err := left.Add(right)
			if err == nil {
				t.Fatalf("Add across %s/%s = %+v, want error", tt.leftCur, tt.rightCur, got)
			}
			var invalid domain.InvalidOrder
			if !errors.As(err, &invalid) {
				t.Fatalf("cross-currency error = %v, want wrapped domain.InvalidOrder", err)
			}
		})
	}
}

func TestMoneyTimesRejectsNegativeMultiplier(t *testing.T) {
	t.Parallel()

	money := domain.MustMoney(500, "USD")
	got, err := money.Times(-1)
	if err == nil {
		t.Fatalf("Times(-1) = %+v, want error", got)
	}
	var invalid domain.InvalidOrder
	if !errors.As(err, &invalid) {
		t.Fatalf("Times(-1) error = %v, want wrapped domain.InvalidOrder", err)
	}
}

type moneyOperation func() (domain.Money, error)

func assertInvalidMoneyOperation(t *testing.T, operation moneyOperation) {
	t.Helper()
	got, err := operation()
	if err == nil {
		t.Fatalf("operation returned %+v, want error", got)
	}
	var invalid domain.InvalidOrder
	if !errors.As(err, &invalid) {
		t.Fatalf("operation error = %v, want wrapped domain.InvalidOrder", err)
	}
}

// Arithmetic on minor units must never silently wrap: overflow against the
// shared maximum or int64 is InvalidOrder, never a coerced amount.
func TestMoneyArithmeticRejectsOverflow(t *testing.T) {
	t.Parallel()

	maxMoney := domain.MustMoney(domain.MoneyMinorUnitsMax, "USD")
	oneCent := domain.MustMoney(1, "USD")
	small := domain.MustMoney(2, "USD")
	tests := []struct {
		name      string
		operation moneyOperation
	}{
		{
			name: "addition overflow is invalid",
			operation: func() (domain.Money, error) {
				return maxMoney.Add(oneCent)
			},
		},
		{
			name: "scaling past shared maximum is invalid",
			operation: func() (domain.Money, error) {
				return maxMoney.Times(2)
			},
		},
		{
			name: "scaling that overflows int64 is invalid",
			operation: func() (domain.Money, error) {
				return small.Times(math.MaxInt64)
			},
		},
		{
			name: "addition that overflows int64 is invalid",
			operation: func() (domain.Money, error) {
				huge := domain.Money{MinorUnits: math.MaxInt64, Currency: "USD"}
				return huge.Add(oneCent)
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			assertInvalidMoneyOperation(t, tt.operation)
		})
	}
}
