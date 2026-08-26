package domain_test

import (
	"errors"
	"math/rand"
	"testing"
	"time"

	"warehouse/internal/domain"
)

var placementTime = time.Date(2026, time.August, 26, 12, 0, 0, 0, time.UTC)

func line(sku string, quantity int64, minorUnits int64) domain.OrderLine {
	return domain.MustOrderLine(
		domain.MustSku(sku),
		domain.MustQuantity(quantity),
		domain.MustMoney(minorUnits, "USD"),
	)
}

func TestNewOrderEnforcesStructuralInvariants(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name  string
		lines []domain.OrderLine
	}{
		{
			name:  "no lines",
			lines: nil,
		},
		{
			name: "duplicate skus across lines",
			lines: []domain.OrderLine{
				line("SKU-A", 1, 100),
				line("SKU-A", 2, 100),
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			got, err := domain.NewOrder(tt.lines, placementTime)
			if err == nil {
				t.Fatalf("NewOrder(%v) = %+v, want error", tt.lines, got)
			}
			var invalid domain.InvalidOrder
			if !errors.As(err, &invalid) {
				t.Fatalf("NewOrder error = %v, want wrapped domain.InvalidOrder", err)
			}
		})
	}
}

func TestNewOrderRejectsMixedCurrencies(t *testing.T) {
	t.Parallel()

	mixed := []domain.OrderLine{
		domain.MustOrderLine(domain.MustSku("SKU-A"), domain.MustQuantity(1), domain.MustMoney(100, "USD")),
		domain.MustOrderLine(domain.MustSku("SKU-B"), domain.MustQuantity(1), domain.MustMoney(100, "EUR")),
	}
	got, err := domain.NewOrder(mixed, placementTime)
	if err == nil {
		t.Fatalf("NewOrder with mixed currencies = %+v, want error", got)
	}
	var invalid domain.InvalidOrder
	if !errors.As(err, &invalid) {
		t.Fatalf("mixed currency error = %v, want wrapped domain.InvalidOrder", err)
	}
}

func TestNewOrderStartsNewAndCopiesLines(t *testing.T) {
	t.Parallel()

	lines := []domain.OrderLine{line("SKU-A", 1, 100)}
	order, err := domain.NewOrder(lines, placementTime)
	if err != nil {
		t.Fatalf("NewOrder returned error: %v", err)
	}
	if order.Status() != domain.StatusNew {
		t.Fatalf("fresh order status = %s, want new", order.Status().Label())
	}
	if order.PlacedAt() != placementTime {
		t.Fatalf("placedAt = %v, want %v", order.PlacedAt(), placementTime)
	}
	lines[0] = line("SKU-B", 9, 900)
	stored := order.Lines()
	if stored[0].SKU != domain.Sku("SKU-A") {
		t.Fatalf("order leaked caller's slice: %+v", stored)
	}
	stored[0] = line("SKU-C", 5, 500)
	if order.Lines()[0].SKU != domain.Sku("SKU-A") {
		t.Fatalf("Lines() exposed internal state: %+v", order.Lines())
	}
}

func TestNewOrderLineValidatesRawParts(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name      string
		sku       domain.Sku
		quantity  domain.Quantity
		unitPrice domain.Money
	}{
		{
			name:      "missing sku",
			sku:       domain.Sku(""),
			quantity:  domain.MustQuantity(1),
			unitPrice: domain.MustMoney(100, "USD"),
		},
		{
			name:      "non-positive quantity",
			sku:       domain.MustSku("SKU-A"),
			quantity:  domain.Quantity(0),
			unitPrice: domain.MustMoney(100, "USD"),
		},
		{
			name:      "unvalidated unit price",
			sku:       domain.MustSku("SKU-A"),
			quantity:  domain.MustQuantity(1),
			unitPrice: domain.Money{MinorUnits: -5, Currency: "usd"},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			got, err := domain.NewOrderLine(tt.sku, tt.quantity, tt.unitPrice)
			if err == nil {
				t.Fatalf("NewOrderLine(%+v) = %+v, want error", tt, got)
			}
			var invalid domain.InvalidOrder
			if !errors.As(err, &invalid) {
				t.Fatalf("NewOrderLine error = %v, want wrapped domain.InvalidOrder", err)
			}
		})
	}
}

// TestOrderLineTotalRejectsInvalidPrice pins the line's robustness contract:
// a hand-assembled line carrying an unvalidated price produces a typed error,
// never a corrupted total.
func TestOrderLineTotalRejectsInvalidPrice(t *testing.T) {
	t.Parallel()

	line := domain.OrderLine{
		SKU:       domain.MustSku("SKU-A"),
		Quantity:  domain.MustQuantity(2),
		UnitPrice: domain.Money{MinorUnits: -500, Currency: "USD"},
	}
	got, err := line.LineTotal()
	if err == nil {
		t.Fatalf("LineTotal on invalid price = %+v, want error", got)
	}
	var invalid domain.InvalidOrder
	if !errors.As(err, &invalid) {
		t.Fatalf("LineTotal error = %v, want wrapped domain.InvalidOrder", err)
	}
}

// TestOrderTotalEqualsSumOfLineTotals is invariant suite 2 of the template's
// required table-driven pair (CONTRACTS.md §2): the computed total always
// equals the sum of line totals over generated-ish valid line sets. The grid
// mixes fixed boundary sets with seeded pseudo-random ones; Go's ecosystem
// has no standard property framework, so this stands in honestly.
func TestOrderTotalEqualsSumOfLineTotals(t *testing.T) {
	t.Parallel()

	rng := rand.New(rand.NewSource(20260826))

	type totalCase struct {
		name      string
		lines     []domain.OrderLine
		wantMinor int64
	}

	buildCase := func(name string, prices []int64, quantities []int64) totalCase {
		lines := make([]domain.OrderLine, len(prices))
		wantMinor := int64(0)
		for i, price := range prices {
			sku := domain.MustSku("SKU-" + string(rune('A'+i)))
			qty := quantities[i]
			lines[i] = domain.MustOrderLine(sku, domain.MustQuantity(qty), domain.MustMoney(price, "EUR"))
			wantMinor += price * qty
		}
		return totalCase{name: name, lines: lines, wantMinor: wantMinor}
	}

	const fixedCases = 3
	cases := make([]totalCase, 0, fixedCases+50)
	cases = append(cases,
		buildCase("single line", []int64{1999}, []int64{2}),
		buildCase("two lines", []int64{100, 250}, []int64{1, 3}),
		buildCase("boundary zeros", []int64{0, 1, 0}, []int64{1, 1, 4}),
	)
	for range 50 {
		lineCount := 1 + rng.Intn(5)
		prices := make([]int64, lineCount)
		quantities := make([]int64, lineCount)
		for j := range prices {
			prices[j] = rng.Int63n(100000)
			quantities[j] = 1 + int64(rng.Intn(4))
		}
		cases = append(cases, buildCase("random set", prices, quantities))
	}

	for _, tt := range cases {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			order, err := domain.NewOrder(tt.lines, placementTime)
			if err != nil {
				t.Fatalf("NewOrder returned error: %v", err)
			}
			got, err := order.Total()
			if err != nil {
				t.Fatalf("Total returned error: %v", err)
			}
			want := domain.MustMoney(tt.wantMinor, "EUR")
			if got != want {
				t.Fatalf("total = %+v, want %+v", got, want)
			}
		})
	}
}

func newPlacedOrder(t *testing.T) *domain.Order {
	t.Helper()
	order, err := domain.NewOrder([]domain.OrderLine{line("SKU-A", 1, 100)}, placementTime)
	if err != nil {
		t.Fatalf("NewOrder returned error: %v", err)
	}
	return order
}

func TestOrderStateMachineHappyPath(t *testing.T) {
	t.Parallel()

	order := newPlacedOrder(t)
	if err := order.Pay(); err != nil {
		t.Fatalf("Pay returned error: %v", err)
	}
	if order.Status() != domain.StatusPaid {
		t.Fatalf("status after pay = %s, want paid", order.Status().Label())
	}
	if err := order.Ship(); err != nil {
		t.Fatalf("Ship returned error: %v", err)
	}
	if order.Status() != domain.StatusShipped {
		t.Fatalf("status after ship = %s, want shipped", order.Status().Label())
	}
}

func TestPayingTwiceIsInvalid(t *testing.T) {
	t.Parallel()

	order := newPlacedOrder(t)
	if err := order.Pay(); err != nil {
		t.Fatalf("first Pay returned error: %v", err)
	}
	payErr := order.Pay()
	if payErr == nil {
		t.Fatal("second Pay succeeded, want error")
	}
	var invalid domain.InvalidOrder
	if !errors.As(payErr, &invalid) {
		t.Fatalf("double-pay error = %v, want wrapped domain.InvalidOrder", payErr)
	}
}

func TestShippingNewOrderIsInvalid(t *testing.T) {
	t.Parallel()

	order := newPlacedOrder(t)
	shipErr := order.Ship()
	if shipErr == nil {
		t.Fatal("Ship on new order succeeded, want error")
	}
	var invalid domain.InvalidOrder
	if !errors.As(shipErr, &invalid) {
		t.Fatalf("ship-new-order error = %v, want wrapped domain.InvalidOrder", shipErr)
	}
}

func TestShippedOrderIsImmutable(t *testing.T) {
	t.Parallel()

	order, err := domain.NewOrder(
		[]domain.OrderLine{line("SKU-A", 1, 100), line("SKU-B", 2, 250)},
		placementTime,
	)
	if err != nil {
		t.Fatalf("NewOrder returned error: %v", err)
	}
	if err := order.Pay(); err != nil {
		t.Fatalf("Pay returned error: %v", err)
	}
	if err := order.Ship(); err != nil {
		t.Fatalf("Ship returned error: %v", err)
	}

	payErr := order.Pay()
	if payErr == nil {
		t.Fatal("Pay on shipped order succeeded, want OrderAlreadyShipped")
	}
	var shipped domain.OrderAlreadyShipped
	if !errors.As(payErr, &shipped) {
		t.Fatalf("pay-after-ship error = %v, want wrapped domain.OrderAlreadyShipped", payErr)
	}
	shipErr := order.Ship()
	if shipErr == nil {
		t.Fatal("Ship on shipped order succeeded, want OrderAlreadyShipped")
	}
	if !errors.As(shipErr, &shipped) {
		t.Fatalf("ship-after-ship error = %v, want wrapped domain.OrderAlreadyShipped", shipErr)
	}
	if shipped.ID.Value == "" {
		t.Fatal("OrderAlreadyShipped carried an empty id")
	}
}

func TestOrderStatusLabelCoversEveryState(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name  string
		state domain.OrderStatus
		want  string
	}{
		{name: "new", state: domain.StatusNew, want: "new"},
		{name: "paid", state: domain.StatusPaid, want: "paid"},
		{name: "shipped", state: domain.StatusShipped, want: "shipped"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			if got := tt.state.Label(); got != tt.want {
				t.Fatalf("Label(%d) = %q, want %q", tt.state, got, tt.want)
			}
		})
	}
}
