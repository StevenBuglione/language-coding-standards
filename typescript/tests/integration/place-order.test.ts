/**
 * Integration tests: the full place-order pipeline over in-memory adapters.
 */

import { describe, expect, it } from "vitest";

// The integration test consumes the template exactly like an external
// caller would: through the thin public entry point only.
import {
  createOrderId,
  createPlaceOrderUseCase,
  createSku,
  CompensationFailure,
  FakePaymentProcessor,
  FixedOrderIdGenerator,
  InMemoryInventoryGateway,
  InMemoryOrderRepository,
  InsufficientStock,
  InvalidOrder,
  Money,
  Order,
  PaymentDeclined,
  PersistenceConflict,
  Quantity,
  SequenceOrderIdGenerator,
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
  const useCase = createPlaceOrderUseCase(
    inventory,
    payments,
    repository,
    new FixedOrderIdGenerator(createOrderId("ord-1")),
  );
  return { useCase, payments, repository, inventory };
}

function lines(...specs: [string, number, number][]): OrderLine[] {
  return specs.map(([code, qty, minorUnits]) => ({
    sku: createSku(code),
    quantity: Quantity.create(qty),
    unitPrice: Money.create(minorUnits, "USD"),
  }));
}

describe("place-order pipeline", () => {
  it("reserves, charges, marks PAID, and persists on the happy path", () => {
    const { useCase, payments, repository, inventory } = pipeline({ "SKU-1": 10 });

    const result: PlaceOrderResult = useCase.execute(lines(["SKU-1", 2, 500]), {
      idempotencyKey: "idem-1",
    });

    expect(result.outcome).toBe("success");
    if (result.outcome === "success") {
      expect(result.order.state).toBe("PAID");
      expect(result.order.id).toBe("ord-1");
      expect(result.order.version).toBe(1);
      expect(result.order.total().equals(Money.create(1000, "USD"))).toBe(true);
      expect(payments.chargedOrders).toHaveLength(1);
      const stored = repository.get(result.order.id);
      expect(stored?.state).toBe("PAID");
      expect(stored).not.toBe(result.order);
      expect(inventory.snapshotStock().get(createSku("SKU-1"))).toBe(8);
    }
  });

  it("fails with InsufficientStock and no charge or persist", () => {
    const { useCase, payments, repository, inventory } = pipeline({ "SKU-1": 1 });

    const result = useCase.execute(lines(["SKU-1", 5, 500]), { idempotencyKey: "idem-2" });

    expect(result.outcome).toBe("failure");
    if (result.outcome === "failure") {
      expect(result.error).toBeInstanceOf(InsufficientStock);
      if (result.error instanceof InsufficientStock) {
        expect(result.error.available).toBe(1);
      }
      expect(payments.chargedOrders).toHaveLength(0);
      expect(repository.saved).toHaveLength(0);
      expect(inventory.snapshotStock().get(createSku("SKU-1"))).toBe(1);
    }
  });

  it("fails with PaymentDeclined, releases the reservation, and does not persist", () => {
    const { useCase, payments, repository, inventory } = pipeline({ "SKU-1": 10 }, true);

    const result = useCase.execute(lines(["SKU-1", 1, 500]), { idempotencyKey: "idem-3" });

    expect(result.outcome).toBe("failure");
    if (result.outcome === "failure") {
      expect(result.error).toBeInstanceOf(PaymentDeclined);
      expect(result.error).not.toBeInstanceOf(InvalidOrder);
      expect(result.error.message).toContain("declined");
      expect(payments.chargedOrders).toHaveLength(1);
      expect(repository.saved).toHaveLength(0);
      expect(inventory.snapshotStock().get(createSku("SKU-1"))).toBe(10);
    }
  });

  it("refunds and releases when save fails", () => {
    const { useCase, payments, repository, inventory } = pipeline({ "SKU-1": 10 });
    repository.failSave = true;

    const result = useCase.execute(lines(["SKU-1", 1, 500]), { idempotencyKey: "idem-4" });

    expect(result.outcome).toBe("failure");
    if (result.outcome === "failure") {
      expect(result.error).toBeInstanceOf(PersistenceConflict);
      expect(payments.refunded).toHaveLength(1);
      expect(inventory.snapshotStock().get(createSku("SKU-1"))).toBe(10);
    }
  });

  it("returns CompensationFailure when refund fails after a save failure", () => {
    const { useCase, payments, repository } = pipeline({ "SKU-1": 10 });
    repository.failSave = true;
    payments.failRefund = true;

    const result = useCase.execute(lines(["SKU-1", 1, 500]), { idempotencyKey: "idem-5" });

    expect(result.outcome).toBe("failure");
    if (result.outcome === "failure") {
      expect(result.error).toBeInstanceOf(CompensationFailure);
    }
  });

  it("rejects invalid lines as a typed failure", () => {
    const { useCase } = pipeline({});

    const result = useCase.execute([], { idempotencyKey: "idem-6" });

    expect(result.outcome).toBe("failure");
    if (result.outcome === "failure") {
      expect(result.error).toBeInstanceOf(InvalidOrder);
    }
  });

  it("returns undefined for unknown order ids without raising", () => {
    const { repository } = pipeline({ "SKU-1": 10 });

    expect(repository.get(createOrderId("missing-order"))).toBeUndefined();
  });
});

describe("place-order idempotency and compensation", () => {
  it("replays the same key and payload without a second charge", () => {
    const inventory = new InMemoryInventoryGateway(new Map([[createSku("SKU-1"), 10]]));
    const payments = new FakePaymentProcessor();
    const repository = new InMemoryOrderRepository();
    const useCase = createPlaceOrderUseCase(
      inventory,
      payments,
      repository,
      new SequenceOrderIdGenerator(),
    );
    const payload = lines(["SKU-1", 2, 300]);

    const first = useCase.execute(payload, { idempotencyKey: "idem-7" });
    const second = useCase.execute(payload, { idempotencyKey: "idem-7" });

    expect(first.outcome).toBe("success");
    expect(second.outcome).toBe("success");
    if (first.outcome === "success" && second.outcome === "success") {
      expect(first.order.state).toBe("PAID");
      expect(second.order.state).toBe("PAID");
      expect(second.order.id).toBe(first.order.id);
    }
    expect(payments.chargedOrders).toHaveLength(1);
  });

  it("rejects a reused key with a different payload", () => {
    const { useCase } = pipeline({ "SKU-1": 10 });

    const first = useCase.execute(lines(["SKU-1", 1, 100]), { idempotencyKey: "idem-8" });
    const second = useCase.execute(lines(["SKU-1", 2, 100]), { idempotencyKey: "idem-8" });

    expect(first.outcome).toBe("success");
    expect(second.outcome).toBe("failure");
    if (second.outcome === "failure") {
      expect(second.error).toBeInstanceOf(InvalidOrder);
    }
  });

  it("returns CompensationFailure when release fails after a declined charge", () => {
    const { useCase, inventory } = pipeline({ "SKU-1": 10 }, true);
    inventory.failRelease = true;

    const result = useCase.execute(lines(["SKU-1", 1, 500]), { idempotencyKey: "idem-release" });

    expect(result.outcome).toBe("failure");
    if (result.outcome === "failure") {
      expect(result.error).toBeInstanceOf(CompensationFailure);
    }
  });

  it("reports PersistenceConflict when save sees a stale expected version", () => {
    const { useCase, repository } = pipeline({ "SKU-1": 10 });
    const result = useCase.execute(lines(["SKU-1", 1, 100]), { idempotencyKey: "idem-version" });
    expect(result.outcome).toBe("success");
    if (result.outcome === "success") {
      const conflict = repository.save(result.order, 0);
      expect(conflict).toBeInstanceOf(PersistenceConflict);
    }
  });

  it("does not oversell when two commands compete for the last units", () => {
    const inventory = new InMemoryInventoryGateway(new Map([[createSku("SKU-A"), 5]]));
    const payments = new FakePaymentProcessor();
    const repository = new InMemoryOrderRepository();
    const useCase = createPlaceOrderUseCase(
      inventory,
      payments,
      repository,
      new SequenceOrderIdGenerator(),
    );
    const competing = lines(["SKU-A", 5, 100]);

    const first = useCase.execute(competing, { idempotencyKey: "idem-9a" });
    const second = useCase.execute(competing, { idempotencyKey: "idem-9b" });

    const outcomes = [first, second];
    expect(outcomes.filter((result) => result.outcome === "success")).toHaveLength(1);
    expect(
      outcomes.filter(
        (result) => result.outcome === "failure" && result.error instanceof InsufficientStock,
      ),
    ).toHaveLength(1);
    expect(payments.chargedOrders).toHaveLength(1);
    expect(inventory.snapshotStock().get(createSku("SKU-A"))).toBe(0);
  });
});

describe("in-memory adapter edge cases", () => {
  it("replays reserveAll for the same idempotency key without double-deducting", () => {
    const inventory = new InMemoryInventoryGateway(new Map([[createSku("SKU-1"), 2]]));
    const id = createOrderId("ord-1");
    const payload = lines(["SKU-1", 1, 100]);
    const first = inventory.reserveAll(id, payload, "idem-r");
    const second = inventory.reserveAll(id, payload, "idem-r");
    expect(second).toEqual(first);
    expect(inventory.snapshotStock().get(createSku("SKU-1"))).toBe(1);
  });

  it("treats release of an unknown token as a no-op", () => {
    const inventory = new InMemoryInventoryGateway(new Map([[createSku("SKU-1"), 2]]));
    expect(
      inventory.release({ orderId: createOrderId("ord-1"), idempotencyKey: "missing" }),
    ).toBeUndefined();
    expect(inventory.snapshotStock().get(createSku("SKU-1"))).toBe(2);
  });

  it("replays a charge for the same idempotency key without a second attempt", () => {
    const payments = new FakePaymentProcessor();
    const order = new Order(lines(["SKU-1", 1, 100]), createOrderId("ord-1"));
    const first = payments.charge(order, "idem-c");
    const second = payments.charge(order, "idem-c");
    expect(second).toBe(first);
    expect(payments.chargedOrders).toHaveLength(1);
  });

  it("returns CompensationFailure when release fails after a save failure", () => {
    const { useCase, repository, inventory } = pipeline({ "SKU-1": 10 });
    repository.failSave = true;
    inventory.failRelease = true;
    const result = useCase.execute(lines(["SKU-1", 1, 500]), { idempotencyKey: "idem-rel-save" });
    expect(result.outcome).toBe("failure");
    if (result.outcome === "failure") {
      expect(result.error).toBeInstanceOf(CompensationFailure);
    }
  });

  it("reports InsufficientStock when the SKU is absent from the warehouse", () => {
    const { useCase } = pipeline({});
    const result = useCase.execute(lines(["SKU-1", 1, 100]), {
      idempotencyKey: "idem-missing-sku",
    });
    expect(result.outcome).toBe("failure");
    if (result.outcome === "failure") {
      expect(result.error).toBeInstanceOf(InsufficientStock);
    }
  });
});
