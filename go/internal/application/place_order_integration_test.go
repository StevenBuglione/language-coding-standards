package application_test

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"testing"

	"warehouse/internal/adapters"
	"warehouse/internal/application"
	"warehouse/internal/domain"
)

// pipeline wires the use case to the in-memory adapter doubles: the
// canonical design's fakes ARE the test doubles, so no mocking framework
// appears anywhere in this template.
type pipeline struct {
	useCase    *application.PlaceOrderUseCase
	inventory  *adapters.InMemoryInventoryGateway
	payments   *adapters.FakePaymentProcessor
	repository *adapters.InMemoryOrderRepository
}

func newPipeline(stock map[domain.Sku]int64, decline bool) *pipeline {
	inventory := adapters.NewInMemoryInventoryGateway(stock)
	payments := adapters.NewFakePaymentProcessor(decline)
	repository := adapters.NewInMemoryOrderRepository()
	ids := adapters.NewFixedOrderIDGenerator(domain.MustOrderID("ord-1"))
	return &pipeline{
		useCase:    application.NewPlaceOrderUseCase(inventory, payments, repository, ids),
		inventory:  inventory,
		payments:   payments,
		repository: repository,
	}
}

func orderLines(skus ...string) []domain.OrderLine {
	lines := make([]domain.OrderLine, len(skus))
	for i, sku := range skus {
		lines[i] = domain.MustOrderLine(
			domain.MustSku(sku),
			domain.MustQuantity(2),
			domain.MustMoney(1500, "USD"),
		)
	}
	return lines
}

func requireSuccessfulOrder(t *testing.T, result application.PlaceOrderResult) *domain.Order {
	t.Helper()
	if result.Failed() {
		t.Fatalf("Execute failed: %v", result.Failure)
	}
	if result.Order == nil {
		t.Fatal("success result carried nil order")
	}
	return result.Order
}

func assertHappyPathOrder(t *testing.T, order *domain.Order) {
	t.Helper()
	if got := order.Status(); got != domain.StatusPaid {
		t.Fatalf("persisted status = %s, want paid", got.Label())
	}
	if order.Version() != 1 {
		t.Fatalf("persisted version = %d, want 1", order.Version())
	}
	if order.ID().Value != "ord-1" {
		t.Fatalf("id = %q, want injected ord-1", order.ID().Value)
	}
}

func requireStoredOrder(
	ctx context.Context,
	t *testing.T,
	repository *adapters.InMemoryOrderRepository,
	id domain.OrderID,
) *domain.Order {
	t.Helper()
	stored, ok := repository.Get(ctx, id)
	if !ok || stored == nil {
		t.Fatal("repository did not persist the order")
	}
	return stored
}

func assertHappyPathSideEffects(t *testing.T, p *pipeline) {
	t.Helper()
	if len(p.payments.Charges()) != 1 {
		t.Fatalf("payment attempts = %d, want 1", len(p.payments.Charges()))
	}
	stockSku := domain.MustSku("SKU-A")
	if p.inventory.SnapshotStock()[stockSku] != 3 {
		t.Fatalf("remaining stock = %d, want 3", p.inventory.SnapshotStock()[stockSku])
	}
}

func assertOrderTotal(t *testing.T, order *domain.Order) {
	t.Helper()
	total, err := order.Total()
	if err != nil {
		t.Fatalf("Total returned error: %v", err)
	}
	want := domain.Money{MinorUnits: 3000, Currency: "USD"}
	if total != want {
		t.Fatalf("total = %+v, want %+v", total, want)
	}
}

func TestPlaceOrderHappyPath(t *testing.T) {
	t.Parallel()

	ctx := context.Background()
	stockSku := domain.MustSku("SKU-A")
	p := newPipeline(map[domain.Sku]int64{stockSku: 5}, false)

	order := requireSuccessfulOrder(
		t,
		p.useCase.Execute(ctx, orderLines("SKU-A"), "idem-1"),
	)
	assertHappyPathOrder(t, order)
	stored := requireStoredOrder(ctx, t, p.repository, order.ID())
	assertHappyPathOrder(t, stored)
	assertHappyPathSideEffects(t, p)
	assertOrderTotal(t, stored)
}

func TestPlaceOrderFailurePaths(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		stock   map[domain.Sku]int64
		decline bool
		lines   func() []domain.OrderLine
		match   func(error) bool
	}{
		{
			name:    "invalid order: empty line set",
			stock:   map[domain.Sku]int64{},
			decline: false,
			lines:   func() []domain.OrderLine { return nil },
			match: func(err error) bool {
				var invalid domain.InvalidOrder
				return errors.As(err, &invalid)
			},
		},
		{
			name:    "insufficient stock",
			stock:   map[domain.Sku]int64{domain.MustSku("SKU-A"): 1},
			decline: false,
			lines:   func() []domain.OrderLine { return orderLines("SKU-A") },
			match: func(err error) bool {
				var shortage domain.InsufficientStock
				return errors.As(err, &shortage)
			},
		},
		{
			name:    "payment declined",
			stock:   map[domain.Sku]int64{domain.MustSku("SKU-A"): 10},
			decline: true,
			lines:   func() []domain.OrderLine { return orderLines("SKU-A") },
			match: func(err error) bool {
				var declined domain.PaymentDeclined
				return errors.As(err, &declined)
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			p := newPipeline(tt.stock, tt.decline)
			result := p.useCase.Execute(context.Background(), tt.lines(), "idem-fail")
			if !result.Failed() || result.Order != nil {
				t.Fatalf("Execute succeeded with %+v, want typed failure", result.Order)
			}
			if !tt.match(result.Failure) {
				t.Fatalf("failure = %v, want the expected typed domain failure", result.Failure)
			}
			if len(p.repository.Saved()) != 0 {
				t.Fatalf("failed run persisted %+v", p.repository.Saved())
			}
		})
	}
}

func TestPlaceOrderInsufficientStockReportsDetails(t *testing.T) {
	t.Parallel()

	shortSku := domain.MustSku("SKU-SHORT")
	p := newPipeline(map[domain.Sku]int64{shortSku: 1}, false)
	result := p.useCase.Execute(context.Background(), orderLines("SKU-SHORT"), "idem-short")
	if !result.Failed() {
		t.Fatal("Execute succeeded, want shortage failure")
	}
	var shortage domain.InsufficientStock
	if !errors.As(result.Failure, &shortage) {
		t.Fatalf("failure = %v, want wrapped domain.InsufficientStock", result.Failure)
	}
	if shortage.SKU != shortSku || int64(shortage.Requested) != 2 || shortage.Available != 1 {
		t.Fatalf("shortage payload = %+v, want sku %s requested 2 available 1", shortage, shortSku)
	}
	if p.inventory.SnapshotStock()[shortSku] != 1 {
		t.Fatal("shortage mutated stock")
	}
}

func TestPlaceOrderPaymentDeclineReleasesReservation(t *testing.T) {
	t.Parallel()

	sku := domain.MustSku("SKU-A")
	p := newPipeline(map[domain.Sku]int64{sku: 10}, true)
	result := p.useCase.Execute(context.Background(), orderLines("SKU-A"), "idem-decline")
	if !result.Failed() {
		t.Fatal("Execute succeeded, want payment decline")
	}
	var declined domain.PaymentDeclined
	if !errors.As(result.Failure, &declined) {
		t.Fatalf("failure = %v, want wrapped domain.PaymentDeclined", result.Failure)
	}
	var invalid domain.InvalidOrder
	if errors.As(result.Failure, &invalid) {
		t.Fatalf("decline misreported as InvalidOrder: %v", result.Failure)
	}
	if p.inventory.SnapshotStock()[sku] != 10 {
		t.Fatalf("stock after decline = %d, want 10", p.inventory.SnapshotStock()[sku])
	}
}

func TestRepositoryGetUnknownIdNeverRaises(t *testing.T) {
	t.Parallel()

	p := newPipeline(map[domain.Sku]int64{}, false)
	order, ok := p.repository.Get(context.Background(), domain.OrderID{Value: "missing"})
	if ok {
		t.Fatalf("Get(missing) = %+v, want absent", order)
	}
	if order != nil {
		t.Fatalf("Get(missing) order = %+v, want nil", order)
	}
}

func TestPlaceOrderSaveFailureRefundsAndReleases(t *testing.T) {
	t.Parallel()

	sku := domain.MustSku("SKU-A")
	p := newPipeline(map[domain.Sku]int64{sku: 10}, false)
	p.repository.FailSave = true
	result := p.useCase.Execute(context.Background(), orderLines("SKU-A"), "idem-save")
	if !result.Failed() {
		t.Fatal("Execute succeeded despite failing repository, want persist failure")
	}
	var conflict domain.PersistenceConflict
	if !errors.As(result.Failure, &conflict) {
		t.Fatalf("failure = %v, want wrapped domain.PersistenceConflict", result.Failure)
	}
	if len(p.payments.Refunds()) != 1 {
		t.Fatalf("refunds = %d, want 1", len(p.payments.Refunds()))
	}
	if p.inventory.SnapshotStock()[sku] != 10 {
		t.Fatalf("stock after save failure = %d, want 10", p.inventory.SnapshotStock()[sku])
	}
}

func TestPlaceOrderCompensationFailureAfterSaveFailure(t *testing.T) {
	t.Parallel()

	p := newPipeline(map[domain.Sku]int64{domain.MustSku("SKU-A"): 10}, false)
	p.repository.FailSave = true
	p.payments.FailRefund = true
	result := p.useCase.Execute(context.Background(), orderLines("SKU-A"), "idem-comp")
	if !result.Failed() {
		t.Fatal("Execute succeeded, want compensation failure")
	}
	var compensation domain.CompensationFailure
	if !errors.As(result.Failure, &compensation) {
		t.Fatalf("failure = %v, want wrapped domain.CompensationFailure", result.Failure)
	}
}

func TestPlaceOrderIdempotentReplayDoesNotDoubleCharge(t *testing.T) {
	t.Parallel()

	ctx := context.Background()
	p := newPipeline(map[domain.Sku]int64{domain.MustSku("SKU-A"): 10}, false)
	first := p.useCase.Execute(ctx, orderLines("SKU-A"), "idem-7")
	if first.Failed() {
		t.Fatalf("first Execute failed: %v", first.Failure)
	}
	second := p.useCase.Execute(ctx, orderLines("SKU-A"), "idem-7")
	if second.Failed() {
		t.Fatalf("replay Execute failed: %v", second.Failure)
	}
	if second.Order.Status() != domain.StatusPaid {
		t.Fatalf("replay status = %s, want paid", second.Order.Status().Label())
	}
	if len(p.payments.Charges()) != 1 {
		t.Fatalf("payment attempts = %d, want 1", len(p.payments.Charges()))
	}
}

func TestPlaceOrderIdempotencyKeyReuseRejected(t *testing.T) {
	t.Parallel()

	ctx := context.Background()
	p := newPipeline(map[domain.Sku]int64{domain.MustSku("SKU-A"): 10}, false)
	first := p.useCase.Execute(ctx, orderLines("SKU-A"), "idem-8")
	if first.Failed() {
		t.Fatalf("first Execute failed: %v", first.Failure)
	}
	other := []domain.OrderLine{
		domain.MustOrderLine(domain.MustSku("SKU-A"), domain.MustQuantity(1), domain.MustMoney(1500, "USD")),
	}
	second := p.useCase.Execute(ctx, other, "idem-8")
	if !second.Failed() {
		t.Fatal("reused key with different payload succeeded, want InvalidOrder")
	}
	var invalid domain.InvalidOrder
	if !errors.As(second.Failure, &invalid) {
		t.Fatalf("failure = %v, want wrapped domain.InvalidOrder", second.Failure)
	}
}

func TestPlaceOrderConcurrentNoOversell(t *testing.T) {
	t.Parallel()

	ctx := context.Background()
	sku := domain.MustSku("SKU-A")
	inventory := adapters.NewInMemoryInventoryGateway(map[domain.Sku]int64{sku: 5})
	payments := adapters.NewFakePaymentProcessor(false)
	repository := adapters.NewInMemoryOrderRepository()
	useCase := application.NewPlaceOrderUseCase(inventory, payments, repository, adapters.NewSequenceOrderIDGenerator())
	lines := []domain.OrderLine{domain.MustOrderLine(sku, domain.MustQuantity(5), domain.MustMoney(100, "USD"))}

	var wg sync.WaitGroup
	results := make([]application.PlaceOrderResult, 2)
	for i := range results {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			results[i] = useCase.Execute(ctx, lines, fmt.Sprintf("idem-c-%d", i))
		}(i)
	}
	wg.Wait()

	var paid, short int
	for _, result := range results {
		var shortage domain.InsufficientStock
		switch {
		case !result.Failed() && result.Order.Status() == domain.StatusPaid:
			paid++
		case errors.As(result.Failure, &shortage):
			short++
		default:
			t.Fatalf("unexpected result: order=%v failure=%v", result.Order, result.Failure)
		}
	}
	if paid != 1 || short != 1 {
		t.Fatalf("paid=%d short=%d, want 1 and 1", paid, short)
	}
	if inventory.SnapshotStock()[sku] != 0 {
		t.Fatalf("remaining stock = %d, want 0", inventory.SnapshotStock()[sku])
	}
}

func TestRepositorySaveThenGetSnapshotAndAliasSafety(t *testing.T) {
	t.Parallel()

	ctx := context.Background()
	repo := adapters.NewInMemoryOrderRepository()
	order := domain.MustOrder(
		[]domain.OrderLine{domain.MustOrderLine(domain.MustSku("SKU-A"), domain.MustQuantity(1), domain.MustMoney(100, "USD"))},
		domain.MustOrderID("ord-1"),
	)
	if err := order.Pay(); err != nil {
		t.Fatalf("Pay returned error: %v", err)
	}
	saved, err := repo.Save(ctx, order, 0)
	if err != nil {
		t.Fatalf("Save returned error: %v", err)
	}
	if saved.Version() != 1 || saved.Status() != domain.StatusPaid {
		t.Fatalf("saved = status %s version %d, want paid/1", saved.Status().Label(), saved.Version())
	}
	if err := saved.Ship(); err != nil {
		t.Fatalf("Ship on returned snapshot returned error: %v", err)
	}
	got, ok := repo.Get(ctx, order.ID())
	if !ok {
		t.Fatal("Get after save returned absent")
	}
	if got.Status() != domain.StatusPaid || got.Version() != 1 {
		t.Fatalf("stored after alias mutation = %s v%d, want paid v1", got.Status().Label(), got.Version())
	}
}

func TestRepositorySaveVersionConflict(t *testing.T) {
	t.Parallel()

	ctx := context.Background()
	repo := adapters.NewInMemoryOrderRepository()
	order := domain.MustOrder(
		[]domain.OrderLine{domain.MustOrderLine(domain.MustSku("SKU-A"), domain.MustQuantity(1), domain.MustMoney(100, "USD"))},
		domain.MustOrderID("ord-2"),
	)
	if err := order.Pay(); err != nil {
		t.Fatalf("Pay returned error: %v", err)
	}
	if _, err := repo.Save(ctx, order, 0); err != nil {
		t.Fatalf("first Save returned error: %v", err)
	}
	_, err := repo.Save(ctx, order, 0)
	if err == nil {
		t.Fatal("stale Save succeeded, want PersistenceConflict")
	}
	var conflict domain.PersistenceConflict
	if !errors.As(err, &conflict) {
		t.Fatalf("stale Save error = %v, want wrapped domain.PersistenceConflict", err)
	}
}

func TestPlaceOrderReleaseFailureAfterDecline(t *testing.T) {
	t.Parallel()

	p := newPipeline(map[domain.Sku]int64{domain.MustSku("SKU-A"): 10}, true)
	p.inventory.FailRelease = true
	result := p.useCase.Execute(context.Background(), orderLines("SKU-A"), "idem-rel")
	if !result.Failed() {
		t.Fatal("Execute succeeded, want compensation failure")
	}
	var compensation domain.CompensationFailure
	if !errors.As(result.Failure, &compensation) {
		t.Fatalf("failure = %v, want wrapped domain.CompensationFailure", result.Failure)
	}
}

func TestPlaceOrderCompensationReleaseFailureAfterSave(t *testing.T) {
	t.Parallel()

	p := newPipeline(map[domain.Sku]int64{domain.MustSku("SKU-A"): 10}, false)
	p.repository.FailSave = true
	p.inventory.FailRelease = true
	result := p.useCase.Execute(context.Background(), orderLines("SKU-A"), "idem-rel-save")
	if !result.Failed() {
		t.Fatal("Execute succeeded, want compensation failure")
	}
	var compensation domain.CompensationFailure
	if !errors.As(result.Failure, &compensation) {
		t.Fatalf("failure = %v, want wrapped domain.CompensationFailure", result.Failure)
	}
	if len(p.payments.Refunds()) != 1 {
		t.Fatalf("refunds = %d, want 1 before release failure", len(p.payments.Refunds()))
	}
}
