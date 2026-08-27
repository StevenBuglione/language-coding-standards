package application

import (
	"context"
	"fmt"
	"strings"

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

// PlaceOrderUseCase orchestrates validate -> reserveAll -> charge -> pay ->
// persist, compensating on decline or save failure.
type PlaceOrderUseCase struct {
	inventory  InventoryGateway
	payments   PaymentProcessor
	repository OrderRepository
	ids        OrderIDGenerator
}

// NewPlaceOrderUseCase wires the use case to its outbound ports.
func NewPlaceOrderUseCase(
	inventory InventoryGateway,
	payments PaymentProcessor,
	repository OrderRepository,
	ids OrderIDGenerator,
) *PlaceOrderUseCase {
	return &PlaceOrderUseCase{
		inventory:  inventory,
		payments:   payments,
		repository: repository,
		ids:        ids,
	}
}

// Execute validates the order, atomically reserves stock, collects payment,
// marks the order PAID, then persists. Declined charges release the
// reservation. Save failures refund and release. The same idempotency key
// and payload replays the original snapshot without a second charge.
func (uc *PlaceOrderUseCase) Execute(ctx context.Context, lines []domain.OrderLine, idempotencyKey string) PlaceOrderResult {
	fingerprint := fingerprintLines(lines)
	if result, done := uc.replay(ctx, idempotencyKey, fingerprint); done {
		return result
	}
	order, err := domain.NewOrder(lines, uc.ids.Next())
	if err != nil {
		return PlaceOrderResult{Order: nil, Failure: fmt.Errorf("place order: %w", err)}
	}
	token, err := uc.inventory.ReserveAll(ctx, order.ID(), order.Lines(), idempotencyKey)
	if err != nil {
		return PlaceOrderResult{Order: nil, Failure: fmt.Errorf("reserve stock: %w", err)}
	}
	receipt, err := uc.payments.Charge(ctx, order, idempotencyKey)
	if err != nil {
		return uc.releaseAfterDecline(ctx, token, fmt.Errorf("charge payment: %w", err))
	}
	if err := order.Pay(); err != nil {
		return uc.compensate(ctx, token, receipt, fmt.Errorf("pay order: %w", err))
	}
	saved, err := uc.repository.Save(ctx, order, order.Version())
	if err != nil {
		return uc.compensate(ctx, token, receipt, fmt.Errorf("persist order: %w", err))
	}
	uc.repository.RememberIdempotency(ctx, idempotencyKey, fingerprint, saved)
	return PlaceOrderResult{Order: saved, Failure: nil}
}

func (uc *PlaceOrderUseCase) replay(ctx context.Context, key, fingerprint string) (PlaceOrderResult, bool) {
	prior, snapshot, ok := uc.repository.GetByIdempotencyKey(ctx, key)
	if !ok {
		return PlaceOrderResult{Order: nil, Failure: nil}, false
	}
	if prior != fingerprint {
		return PlaceOrderResult{
			Order:   nil,
			Failure: fmt.Errorf("place order: %w", domain.InvalidOrder{Reason: "idempotency key reused with different payload"}),
		}, true
	}
	return PlaceOrderResult{Order: snapshot, Failure: nil}, true
}

func (uc *PlaceOrderUseCase) releaseAfterDecline(ctx context.Context, token ReservationToken, cause error) PlaceOrderResult {
	if err := uc.inventory.Release(ctx, token); err != nil {
		return PlaceOrderResult{Order: nil, Failure: fmt.Errorf("release reservation: %w", err)}
	}
	return PlaceOrderResult{Order: nil, Failure: cause}
}

func (uc *PlaceOrderUseCase) compensate(ctx context.Context, token ReservationToken, receipt ChargeReceipt, cause error) PlaceOrderResult {
	if err := uc.payments.Refund(ctx, receipt); err != nil {
		return PlaceOrderResult{Order: nil, Failure: fmt.Errorf("compensate refund: %w", err)}
	}
	if err := uc.inventory.Release(ctx, token); err != nil {
		return PlaceOrderResult{Order: nil, Failure: fmt.Errorf("compensate release: %w", err)}
	}
	return PlaceOrderResult{Order: nil, Failure: cause}
}

func fingerprintLines(lines []domain.OrderLine) string {
	parts := make([]string, 0, len(lines))
	for _, line := range lines {
		parts = append(parts, fmt.Sprintf(
			"%s:%d:%s:%d",
			string(line.SKU),
			int64(line.Quantity),
			line.UnitPrice.Currency,
			line.UnitPrice.MinorUnits,
		))
	}
	return strings.Join(parts, "|")
}
