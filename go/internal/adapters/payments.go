package adapters

import (
	"context"
	"fmt"
	"sync"

	"warehouse/internal/application"
	"warehouse/internal/domain"
)

type chargeOutcome struct {
	receipt application.ChargeReceipt
	err     error
}

// FakePaymentProcessor is an application.PaymentProcessor double that records
// every charge attempt. Configure decline to make each collection fail with
// PaymentDeclined. Identical idempotency keys replay the original outcome.
type FakePaymentProcessor struct {
	mu            sync.Mutex
	decline       bool
	chargedOrders []*domain.Order
	receipts      map[string]chargeOutcome
	refunded      []application.ChargeReceipt
	FailRefund    bool
}

// NewFakePaymentProcessor starts in the configured outcome mode with an empty
// attempt log.
func NewFakePaymentProcessor(decline bool) *FakePaymentProcessor {
	return &FakePaymentProcessor{
		decline:  decline,
		receipts: make(map[string]chargeOutcome),
	}
}

// Charges returns the orders passed so far, in attempt order.
func (p *FakePaymentProcessor) Charges() []*domain.Order {
	p.mu.Lock()
	defer p.mu.Unlock()
	out := make([]*domain.Order, len(p.chargedOrders))
	copy(out, p.chargedOrders)
	return out
}

// Refunds returns receipts voided so far, in attempt order.
func (p *FakePaymentProcessor) Refunds() []application.ChargeReceipt {
	p.mu.Lock()
	defer p.mu.Unlock()
	out := make([]application.ChargeReceipt, len(p.refunded))
	copy(out, p.refunded)
	return out
}

// Charge records the attempt, then honors the configured outcome. A retry
// with the same key returns the original receipt or decline.
func (p *FakePaymentProcessor) Charge(_ context.Context, order *domain.Order, idempotencyKey string) (application.ChargeReceipt, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if existing, ok := p.receipts[idempotencyKey]; ok {
		if existing.err != nil {
			return existing.receipt, fmt.Errorf("charge: %w", existing.err)
		}
		return existing.receipt, nil
	}
	p.chargedOrders = append(p.chargedOrders, order)
	if p.decline {
		declined := domain.PaymentDeclined{Reason: fmt.Sprintf("payment declined for order %s", order.ID().Value)}
		p.receipts[idempotencyKey] = chargeOutcome{err: declined}
		return application.ChargeReceipt{}, fmt.Errorf("charge: %w", declined)
	}
	receipt := application.ChargeReceipt{OrderID: order.ID(), IdempotencyKey: idempotencyKey}
	p.receipts[idempotencyKey] = chargeOutcome{receipt: receipt}
	return receipt, nil
}

// Refund voids a prior successful charge.
func (p *FakePaymentProcessor) Refund(_ context.Context, receipt application.ChargeReceipt) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.FailRefund {
		return fmt.Errorf(
			"refund: %w",
			domain.CompensationFailure{Stage: "refund", Detail: "forced failure"},
		)
	}
	p.refunded = append(p.refunded, receipt)
	return nil
}

// compile-time proof that the adapter satisfies its port.
var _ application.PaymentProcessor = (*FakePaymentProcessor)(nil)
