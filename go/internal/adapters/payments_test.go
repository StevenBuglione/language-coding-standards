package adapters_test

import (
	"context"
	"errors"
	"testing"

	"warehouse/internal/adapters"
	"warehouse/internal/domain"
)

func TestChargeIsIdempotentByKey(t *testing.T) {
	t.Parallel()

	ctx := context.Background()
	order := domain.MustOrder(
		[]domain.OrderLine{domain.MustOrderLine(domain.MustSku("SKU-A"), domain.MustQuantity(1), domain.MustMoney(1, "USD"))},
		domain.MustOrderID("ord-1"),
	)
	processor := adapters.NewFakePaymentProcessor(false)
	first, err := processor.Charge(ctx, order, "idem-1")
	if err != nil {
		t.Fatalf("Charge returned error: %v", err)
	}
	second, err := processor.Charge(ctx, order, "idem-1")
	if err != nil {
		t.Fatalf("replay Charge returned error: %v", err)
	}
	if first != second {
		t.Fatalf("replay receipt = %+v, want %+v", second, first)
	}
	if len(processor.Charges()) != 1 {
		t.Fatalf("charges = %d, want 1", len(processor.Charges()))
	}
}

func TestChargeDeclineReplayDoesNotDoubleAttempt(t *testing.T) {
	t.Parallel()

	ctx := context.Background()
	order := domain.MustOrder(
		[]domain.OrderLine{domain.MustOrderLine(domain.MustSku("SKU-A"), domain.MustQuantity(1), domain.MustMoney(1, "USD"))},
		domain.MustOrderID("ord-1"),
	)
	processor := adapters.NewFakePaymentProcessor(true)
	_, err := processor.Charge(ctx, order, "idem-d")
	if err == nil {
		t.Fatal("Charge succeeded, want PaymentDeclined")
	}
	_, replayErr := processor.Charge(ctx, order, "idem-d")
	var declined domain.PaymentDeclined
	if !errors.As(replayErr, &declined) {
		t.Fatalf("replay error = %v, want PaymentDeclined", replayErr)
	}
	if len(processor.Charges()) != 1 {
		t.Fatalf("charges = %d, want 1", len(processor.Charges()))
	}
}
