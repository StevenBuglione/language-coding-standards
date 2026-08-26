/**
 * Integration tests: the full place-order pipeline over in-memory adapters.
 */

import { describe, expect, it } from "vitest";

// The integration test consumes the template exactly like an external
// caller would: through the thin public entry point only.
import {
  createPlaceOrderUseCase,
  createSku,
  FakePaymentProcessor,
  generateOrderId,
  InMemoryInventoryGateway,
  InMemoryOrderRepository,
  InsufficientStock,
  InvalidOrder,
  Money,
  Quantity,
  type OrderLine,
  type PlaceOrderResult,
  type Sku,
} from "../../src/index";

function pipeline(stock: Record<string, number>, shouldDecline = false) {
  const inventory = new InMemoryInventoryGateway(
    new Map(Object.entries(stock).map(([code, units]): [Sku, number] => [createSku(code), units])),
  );
  const payments = new FakePaymentProcessor({ decline: shouldDecline });
  const repository = new InMemoryOrderRepository();
  const useCase = createPlaceOrderUseCase(inventory, payments, repository);
  return { useCase, payments, repository };
}

function lines(...specs: [string, number, number][]): OrderLine[] {
  return specs.map(([code, qty, minorUnits]) => ({
    sku: createSku(code),
    quantity: Quantity.create(qty),
    unitPrice: Money.create(minorUnits, "USD"),
  }));
}

describe("place-order pipeline", () => {
  it("reserves, charges, and persists on the happy path", () => {
    const { useCase, payments, repository } = pipeline({ "SKU-1": 10 });

    const result: PlaceOrderResult = useCase.execute(lines(["SKU-1", 2, 500]));

    expect(result.outcome).toBe("success");
    if (result.outcome === "success") {
      expect(result.order.state).toBe("NEW");
      expect(result.order.total().equals(Money.create(1000, "USD"))).toBe(true);
      expect(payments.chargedOrders).toHaveLength(1);
      expect(repository.get(result.order.id)).toBe(result.order);
    }
  });

  it("fails with InsufficientStock and no charge or persist", () => {
    const { useCase, payments, repository } = pipeline({ "SKU-1": 1 });

    const result = useCase.execute(lines(["SKU-1", 5, 500]));

    expect(result.outcome).toBe("failure");
    if (result.outcome === "failure") {
      expect(result.error).toBeInstanceOf(InsufficientStock);
      if (result.error instanceof InsufficientStock) {
        expect(result.error.available).toBe(1);
      }
      expect(payments.chargedOrders).toHaveLength(0);
      expect(repository.saved).toHaveLength(0);
    }
  });

  it("fails with a declined payment and does not persist", () => {
    const { useCase, payments, repository } = pipeline({ "SKU-1": 10 }, true);

    const result = useCase.execute(lines(["SKU-1", 1, 500]));

    expect(result.outcome).toBe("failure");
    if (result.outcome === "failure") {
      expect(result.error).toBeInstanceOf(InvalidOrder);
      expect(result.error.message).toContain("declined");
      expect(payments.chargedOrders).toHaveLength(1);
      expect(repository.saved).toHaveLength(0);
    }
  });

  it("rejects invalid lines as a typed failure", () => {
    const { useCase } = pipeline({});

    const result = useCase.execute([]);

    expect(result.outcome).toBe("failure");
    if (result.outcome === "failure") {
      expect(result.error).toBeInstanceOf(InvalidOrder);
    }
  });

  it("returns undefined for unknown order ids without raising", () => {
    const { repository } = pipeline({ "SKU-1": 10 });

    expect(repository.get(generateOrderId())).toBeUndefined();
  });
});
