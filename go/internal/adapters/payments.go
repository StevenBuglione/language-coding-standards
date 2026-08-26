package adapters

import (
	"context"
	"fmt"

	"warehouse/internal/application"
	"warehouse/internal/domain"
)

// FakePaymentProcessor is an application.PaymentProcessor double that records
// every charge attempt. Configure decline to make each collection fail with
// a typed refusal.
type FakePaymentProcessor struct {
	decline       bool
	chargedOrders []*domain.Order
}

// NewFakePaymentProcessor starts in the configured outcome mode with an empty
// attempt log.
func NewFakePaymentProcessor(decline bool) *FakePaymentProcessor {
	return &FakePaymentProcessor{decline: decline}
}

// Charges returns the orders passed so far, in attempt order.
func (p *FakePaymentProcessor) Charges() []*domain.Order {
	return p.chargedOrders
}

// Charge records the attempt, then honors the configured outcome.
func (p *FakePaymentProcessor) Charge(_ context.Context, order *domain.Order) error {
	p.chargedOrders = append(p.chargedOrders, order)
	if p.decline {
		return fmt.Errorf(
			"charge: %w",
			domain.InvalidOrder{Reason: fmt.Sprintf("payment declined for order %s", order.ID().Value)},
		)
	}
	return nil
}

// compile-time proof that the adapter satisfies its port.
var _ application.PaymentProcessor = (*FakePaymentProcessor)(nil)
