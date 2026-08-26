package domain

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"time"
)

// OrderStatus is the state machine NEW -> PAID -> SHIPPED.
type OrderStatus int8

// The three canonical order states. Nothing outside this set exists.
const (
	StatusNew OrderStatus = iota
	StatusPaid
	StatusShipped
)

// Label returns the lowercase state name used in reports and tests. The
// trailing return is unreachable while the enum stays closed over exactly
// these three states.
func (s OrderStatus) Label() string {
	switch s {
	case StatusNew:
		return "new"
	case StatusPaid:
		return "paid"
	case StatusShipped:
		return "shipped"
	}
	return "unknown"
}

// OrderID uniquely identifies a placed order.
type OrderID struct {
	Value string
}

// NewOrderID mints a random 128-bit hexadecimal identifier.
func NewOrderID() (OrderID, error) {
	buf := make([]byte, 16)
	if _, err := rand.Read(buf); err != nil {
		return OrderID{}, fmt.Errorf("new order id: %w", err)
	}
	return OrderID{Value: hex.EncodeToString(buf)}, nil
}

// OrderLine is one SKU/quantity/unit-price row of an order.
type OrderLine struct {
	SKU       Sku
	Quantity  Quantity
	UnitPrice Money
}

// NewOrderLine validates its parts and returns an immutable line.
func NewOrderLine(sku Sku, quantity Quantity, unitPrice Money) (OrderLine, error) {
	line := OrderLine{SKU: sku, Quantity: quantity, UnitPrice: unitPrice}
	if sku == "" {
		return OrderLine{}, fmt.Errorf(
			"new order line: %w",
			InvalidOrder{Reason: "order line requires a validated sku"},
		)
	}
	if quantity <= 0 {
		return OrderLine{}, fmt.Errorf(
			"new order line: %w",
			InvalidOrder{Reason: fmt.Sprintf("order line quantity must be positive, got %d", int64(quantity))},
		)
	}
	if unitPrice.Currency == "" || unitPrice.MinorUnits < 0 {
		return OrderLine{}, fmt.Errorf(
			"new order line: %w",
			InvalidOrder{Reason: "order line requires a validated unit price"},
		)
	}
	return line, nil
}

// MustOrderLine is NewOrderLine for infallible literals; it panics on
// violation and is intended for tests and wiring code with known-good parts.
func MustOrderLine(sku Sku, quantity Quantity, unitPrice Money) OrderLine {
	line, err := NewOrderLine(sku, quantity, unitPrice)
	if err != nil {
		panic(err)
	}
	return line
}

// LineTotal returns the unit price scaled by the ordered quantity.
func (l OrderLine) LineTotal() (Money, error) {
	total, err := l.UnitPrice.Times(int64(l.Quantity))
	if err != nil {
		return Money{}, fmt.Errorf("line total: %w", err)
	}
	return total, nil
}

// Order is the aggregate root enforcing the four canonical invariants:
// at least one line; no duplicate SKUs across lines; the total always equals
// the sum of line totals (computed on demand, never stored stale); and no
// mutation once shipped. All lines must share one currency so the total is
// well-defined.
type Order struct {
	id       OrderID
	status   OrderStatus
	lines    []OrderLine
	placedAt time.Time
}

// NewOrder places a new order from validated lines, assigning a fresh id and
// the caller-supplied placement instant. The lines are copied: later edits to
// the slice never leak into the order.
func NewOrder(lines []OrderLine, placedAt time.Time) (*Order, error) {
	if len(lines) == 0 {
		return nil, fmt.Errorf(
			"new order: %w",
			InvalidOrder{Reason: "an order requires at least one line"},
		)
	}
	currency := lines[0].UnitPrice.Currency
	seen := make(map[Sku]struct{}, len(lines))
	for _, line := range lines {
		if _, dup := seen[line.SKU]; dup {
			return nil, fmt.Errorf(
				"new order: %w",
				InvalidOrder{Reason: fmt.Sprintf("duplicate sku across order lines: %s", string(line.SKU))},
			)
		}
		seen[line.SKU] = struct{}{}
		if line.UnitPrice.Currency != currency {
			return nil, fmt.Errorf(
				"new order: %w",
				InvalidOrder{Reason: fmt.Sprintf("order lines must share one currency, got %s vs %s", currency, line.UnitPrice.Currency)},
			)
		}
	}
	id, err := NewOrderID()
	if err != nil {
		return nil, fmt.Errorf("new order: %w", err)
	}
	stored := make([]OrderLine, len(lines))
	copy(stored, lines)
	return &Order{id: id, status: StatusNew, lines: stored, placedAt: placedAt}, nil
}

// ID returns the immutable order identifier.
func (o *Order) ID() OrderID {
	return o.id
}

// Status returns the current state-machine state.
func (o *Order) Status() OrderStatus {
	return o.status
}

// PlacedAt returns the instant the caller supplied at construction.
func (o *Order) PlacedAt() time.Time {
	return o.placedAt
}

// Lines returns a copy of the order lines; mutating it never affects the order.
func (o *Order) Lines() []OrderLine {
	out := make([]OrderLine, len(o.lines))
	copy(out, o.lines)
	return out
}

// Total returns the sum of all line totals in the order's single currency.
func (o *Order) Total() (Money, error) {
	first, err := o.lines[0].LineTotal()
	if err != nil {
		return Money{}, fmt.Errorf("order total: %w", err)
	}
	total := first
	for _, line := range o.lines[1:] {
		lineTotal, err := line.LineTotal()
		if err != nil {
			return Money{}, fmt.Errorf("order total: %w", err)
		}
		total, err = total.Add(lineTotal)
		if err != nil {
			return Money{}, fmt.Errorf("order total: %w", err)
		}
	}
	return total, nil
}

// Pay transitions NEW -> PAID; refusing paid or already-shipped orders.
func (o *Order) Pay() error {
	if o.status == StatusShipped {
		return fmt.Errorf("pay order: %w", OrderAlreadyShipped{ID: o.id})
	}
	if o.status == StatusPaid {
		return fmt.Errorf(
			"pay order: %w",
			InvalidOrder{Reason: "order has already been paid"},
		)
	}
	o.status = StatusPaid
	return nil
}

// Ship transitions PAID -> SHIPPED; only paid orders may ship.
func (o *Order) Ship() error {
	if o.status == StatusShipped {
		return fmt.Errorf("ship order: %w", OrderAlreadyShipped{ID: o.id})
	}
	if o.status != StatusPaid {
		return fmt.Errorf(
			"ship order: %w",
			InvalidOrder{Reason: "only paid orders can be shipped"},
		)
	}
	o.status = StatusShipped
	return nil
}
