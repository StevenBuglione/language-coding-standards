package application_test

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"

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
	clock := fixedClock{now: time.Date(2026, time.August, 26, 9, 30, 0, 0, time.UTC)}
	return &pipeline{
		useCase:    application.NewPlaceOrderUseCase(inventory, payments, repository, clock),
		inventory:  inventory,
		payments:   payments,
		repository: repository,
	}
}

// fixedClock is a deterministic Clock double; production code must inject
// time instead of calling time.Now (the forbidigo ban makes this the only path).
type fixedClock struct {
	now time.Time
}

func (c fixedClock) Now() time.Time {
	return c.now
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

func TestPlaceOrderHappyPath(t *testing.T) {
	t.Parallel()

	ctx := context.Background()
	stockSku := domain.MustSku("SKU-A")
	p := newPipeline(map[domain.Sku]int64{stockSku: 5}, false)

	result := p.useCase.Execute(ctx, orderLines("SKU-A"))
	if result.Failed() {
		t.Fatalf("Execute failed: %v", result.Failure)
	}
	if result.Order == nil {
		t.Fatal("success result carried nil order")
	}
	if got := result.Order.Status(); got != domain.StatusNew {
		t.Fatalf("persisted status = %s, want new", got.Label())
	}
	stored, ok := p.repository.Get(ctx, result.Order.ID())
	if !ok {
		t.Fatal("repository did not persist the order")
	}
	if stored.ID() != result.Order.ID() {
		t.Fatalf("stored id %s != returned id %s", stored.ID().Value, result.Order.ID().Value)
	}
	if len(p.payments.Charges()) != 1 {
		t.Fatalf("payment attempts = %d, want 1", len(p.payments.Charges()))
	}
	total, err := stored.Total()
	if err != nil {
		t.Fatalf("Total returned error: %v", err)
	}
	want := domain.Money{MinorUnits: 3000, Currency: "USD"}
	if total != want {
		t.Fatalf("total = %+v, want %+v", total, want)
	}
}

func TestPlaceOrderFailurePaths(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		stock   map[domain.Sku]int64
		decline bool
		lines   func() []domain.OrderLine
		match   func(error) bool // asserts the typed domain failure inside the wrap chain
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
				var invalid domain.InvalidOrder
				return errors.As(err, &invalid)
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			ctx := context.Background()
			p := newPipeline(tt.stock, tt.decline)

			result := p.useCase.Execute(ctx, tt.lines())
			if !result.Failed() {
				t.Fatal("Execute succeeded, want typed failure")
			}
			if result.Order != nil {
				t.Fatalf("failure result carried order %+v", result.Order)
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

	ctx := context.Background()
	shortSku := domain.MustSku("SKU-SHORT")
	p := newPipeline(map[domain.Sku]int64{shortSku: 1}, false)

	result := p.useCase.Execute(ctx, orderLines("SKU-SHORT"))
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
}

func TestRepositoryGetUnknownIdNeverRaises(t *testing.T) {
	t.Parallel()

	ctx := context.Background()
	p := newPipeline(map[domain.Sku]int64{}, false)

	order, ok := p.repository.Get(ctx, domain.OrderID{Value: "missing"})
	if ok {
		t.Fatalf("Get(missing) = %+v, want absent", order)
	}
	if order != nil {
		t.Fatalf("Get(missing) order = %+v, want nil", order)
	}
}

// failingRepository is an OrderRepository whose Save always fails, driving
// the use case's persist-failure branch.
type failingRepository struct{}

var errPersistFailed = errors.New("repository unavailable")

func (r *failingRepository) Save(_ context.Context, _ *domain.Order) (*domain.Order, error) {
	return nil, fmt.Errorf("save order: %w", errPersistFailed)
}

func (r *failingRepository) Get(_ context.Context, _ domain.OrderID) (*domain.Order, bool) {
	return nil, false
}

func TestPlaceOrderReportsPersistFailure(t *testing.T) {
	t.Parallel()

	ctx := context.Background()
	inventory := adapters.NewInMemoryInventoryGateway(map[domain.Sku]int64{
		domain.MustSku("SKU-A"): 10,
	})
	useCase := application.NewPlaceOrderUseCase(
		inventory,
		adapters.NewFakePaymentProcessor(false),
		&failingRepository{},
		fixedClock{now: time.Date(2026, time.August, 26, 9, 30, 0, 0, time.UTC)},
	)

	result := useCase.Execute(ctx, orderLines("SKU-A"))
	if !result.Failed() {
		t.Fatal("Execute succeeded despite failing repository, want persist failure")
	}
	if result.Order != nil {
		t.Fatalf("persist failure carried order %+v", result.Order)
	}
	if !errors.Is(result.Failure, errPersistFailed) {
		t.Fatalf("failure = %v, want it to wrap the repository error", result.Failure)
	}
	var invalid domain.InvalidOrder
	var shortage domain.InsufficientStock
	if errors.As(result.Failure, &invalid) || errors.As(result.Failure, &shortage) {
		t.Fatalf("persist failure misreported as a domain rule violation: %v", result.Failure)
	}
}
