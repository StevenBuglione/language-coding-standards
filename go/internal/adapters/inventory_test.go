package adapters_test

import (
	"context"
	"errors"
	"testing"

	"warehouse/internal/adapters"
	"warehouse/internal/application"
	"warehouse/internal/domain"
)

func TestReserveAllIsAtomicAndIdempotent(t *testing.T) {
	t.Parallel()

	ctx := context.Background()
	skuA := domain.MustSku("SKU-A")
	skuB := domain.MustSku("SKU-B")
	gateway := adapters.NewInMemoryInventoryGateway(map[domain.Sku]int64{skuA: 5, skuB: 1})
	id := domain.MustOrderID("ord-1")
	lines := []domain.OrderLine{
		domain.MustOrderLine(skuA, domain.MustQuantity(2), domain.MustMoney(1, "USD")),
		domain.MustOrderLine(skuB, domain.MustQuantity(2), domain.MustMoney(1, "USD")),
	}

	_, err := gateway.ReserveAll(ctx, id, lines, "idem-a")
	if err == nil {
		t.Fatal("ReserveAll succeeded, want shortage on SKU-B")
	}
	var shortage domain.InsufficientStock
	if !errors.As(err, &shortage) || shortage.SKU != skuB {
		t.Fatalf("error = %v, want InsufficientStock for SKU-B", err)
	}
	if gateway.SnapshotStock()[skuA] != 5 || gateway.SnapshotStock()[skuB] != 1 {
		t.Fatalf("partial reserve leaked: %+v", gateway.SnapshotStock())
	}

	okLines := []domain.OrderLine{domain.MustOrderLine(skuA, domain.MustQuantity(2), domain.MustMoney(1, "USD"))}
	token, err := gateway.ReserveAll(ctx, id, okLines, "idem-b")
	if err != nil {
		t.Fatalf("ReserveAll returned error: %v", err)
	}
	replay, err := gateway.ReserveAll(ctx, id, okLines, "idem-b")
	if err != nil {
		t.Fatalf("idempotent ReserveAll returned error: %v", err)
	}
	if replay.IdempotencyKey != token.IdempotencyKey {
		t.Fatalf("replay token = %+v, want %+v", replay, token)
	}
	if gateway.SnapshotStock()[skuA] != 3 {
		t.Fatalf("double reserve: stock = %d, want 3", gateway.SnapshotStock()[skuA])
	}
}

func TestReleaseUnknownTokenIsNoop(t *testing.T) {
	t.Parallel()

	gateway := adapters.NewInMemoryInventoryGateway(map[domain.Sku]int64{domain.MustSku("SKU-A"): 1})
	err := gateway.Release(context.Background(), application.ReservationToken{
		OrderID:        domain.MustOrderID("ord-missing"),
		IdempotencyKey: "missing",
	})
	if err != nil {
		t.Fatalf("Release(unknown) = %v, want nil", err)
	}
}
