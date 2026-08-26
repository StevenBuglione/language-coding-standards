package application

import (
	"context"
	"fmt"

	"warehouse/internal/domain"
)

// PlaceOrderResult is the typed outcome of the place-order use case: no
// exception ever crosses the boundary. Exactly one field is meaningful —
// Order is non-nil on success, Failure carries the wrapped domain error on
// failure.
type PlaceOrderResult struct {
	Order   *domain.Order
	Failure error
}

// Failed reports whether the use case ended in a typed failure.
func (r PlaceOrderResult) Failed() bool {
	return r.Failure != nil
}

// PlaceOrderUseCase orchestrates validate -> reserve -> charge -> persist.
type PlaceOrderUseCase struct {
	inventory  InventoryGateway
	payments   PaymentProcessor
	repository OrderRepository
	clock      Clock
}

// NewPlaceOrderUseCase wires the use case to its outbound ports.
func NewPlaceOrderUseCase(
	inventory InventoryGateway,
	payments PaymentProcessor,
	repository OrderRepository,
	clock Clock,
) *PlaceOrderUseCase {
	return &PlaceOrderUseCase{
		inventory:  inventory,
		payments:   payments,
		repository: repository,
		clock:      clock,
	}
}

// Execute validates the order, reserves stock for every line, collects
// payment, then persists, returning a typed result either way.
func (uc *PlaceOrderUseCase) Execute(ctx context.Context, lines []domain.OrderLine) PlaceOrderResult {
	order, err := domain.NewOrder(lines, uc.clock.Now())
	if err != nil {
		return PlaceOrderResult{Order: nil, Failure: fmt.Errorf("place order: %w", err)}
	}
	for _, line := range order.Lines() {
		if err := uc.inventory.Reserve(ctx, line.SKU, line.Quantity); err != nil {
			return PlaceOrderResult{Order: nil, Failure: fmt.Errorf("reserve stock: %w", err)}
		}
	}
	if err := uc.payments.Charge(ctx, order); err != nil {
		return PlaceOrderResult{Order: nil, Failure: fmt.Errorf("charge payment: %w", err)}
	}
	saved, err := uc.repository.Save(ctx, order)
	if err != nil {
		return PlaceOrderResult{Order: nil, Failure: fmt.Errorf("persist order: %w", err)}
	}
	return PlaceOrderResult{Order: saved, Failure: nil}
}
