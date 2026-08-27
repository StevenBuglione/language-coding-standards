// Command warehouse demonstrates the canonical place-order pipeline end to
// end: it wires the in-memory adapters into the use case, places one order,
// and reports the outcome. It exists so the module has a build/vet target
// and a runnable wiring example.
package main

import (
	"context"
	"fmt"
	"os"
	"strings"

	"warehouse/internal/adapters"
	"warehouse/internal/application"
	"warehouse/internal/domain"
)

func main() {
	if err := run(); err != nil {
		// A failing diagnostics write must not mask the original exit path.
		_, _ = fmt.Fprintf(os.Stderr, "warehouse: %v\n", err)
		os.Exit(1)
	}
}

// run wires the pipeline and places one canonical order.
func run() error {
	ctx := context.Background()

	inventory := adapters.NewInMemoryInventoryGateway(map[domain.Sku]int64{
		domain.MustSku("SKU-1000"): 10,
	})
	payments := adapters.NewFakePaymentProcessor(false)
	orders := adapters.NewInMemoryOrderRepository()
	useCase := application.NewPlaceOrderUseCase(
		inventory,
		payments,
		orders,
		adapters.NewSequenceOrderIDGenerator(),
	)

	line := domain.MustOrderLine(
		domain.MustSku("SKU-1000"),
		domain.MustQuantity(2),
		domain.MustMoney(1999, "USD"),
	)
	result := useCase.Execute(ctx, []domain.OrderLine{line}, "demo-1")
	if result.Failed() {
		return fmt.Errorf("demo run failed: %w", result.Failure)
	}
	total, err := result.Order.Total()
	if err != nil {
		return fmt.Errorf("demo run failed: %w", err)
	}
	// Demo stdout report; a failed print must not fail the demo run.
	_, _ = fmt.Fprintf(
		os.Stdout,
		"placed order %s: %d x %s @ %d minor units = %d %s (%s)\n",
		result.Order.ID().Value,
		int64(line.Quantity),
		string(line.SKU),
		line.UnitPrice.MinorUnits,
		total.MinorUnits,
		total.Currency,
		strings.ToUpper(result.Order.Status().Label()),
	)
	return nil
}
