/**
 * Unit tests covering every Order invariant and state transition.
 */

import { describe, expect, it } from "vitest";

import { InvalidOrder, OrderAlreadyShipped } from "../../src/domain/errors";
import { Money } from "../../src/domain/money";
import { createOrderId, Order, type OrderLine, type OrderStatus } from "../../src/domain/order";
import { Quantity } from "../../src/domain/quantity";
import { createSku } from "../../src/domain/sku";

function orderId(value = "ord-1") {
  return createOrderId(value);
}

function line(code = "SKU-1", qty = 2, minorUnits = 500, currency = "USD"): OrderLine {
  return {
    sku: createSku(code),
    quantity: Quantity.create(qty),
    unitPrice: Money.create(minorUnits, currency),
  };
}

describe("Order", () => {
  it("rejects an empty line set", () => {
    expect(() => new Order([], orderId())).toThrow(/at least one line/);
  });

  it("rejects duplicate SKUs across lines", () => {
    expect(() => new Order([line("SKU-1"), line("SKU-1")], orderId())).toThrow(/duplicate/);
  });

  it("rejects duplicate SKUs after normalization", () => {
    expect(() => new Order([line("SKU-1"), line(" SKU-1 ")], orderId())).toThrow(/duplicate/);
  });

  it("totals the sum of line totals", () => {
    const order = new Order([line("SKU-1", 2, 500), line("SKU-2", 1, 1000)], orderId());
    expect(order.total().equals(Money.create(2000, "USD"))).toBe(true);
  });

  it("rejects mixed currencies at construction", () => {
    expect(() => new Order([line("SKU-1"), line("SKU-2", 1, 100, "EUR")], orderId())).toThrow(
      /mixed currencies/,
    );
  });

  it("uses the injected id and starts NEW at version 0", () => {
    const order = new Order([line()], orderId("ord-fixed-9"));
    expect(order.id).toBe("ord-fixed-9");
    expect(order.state).toBe("NEW" satisfies OrderStatus);
    expect(order.version).toBe(0);
  });

  it("rejects an empty order id", () => {
    expect(() => createOrderId("")).toThrow(/non-empty/);
    expect(() => createOrderId(" ".repeat(3))).toThrow(/non-empty/);
  });

  it("transitions NEW to PAID on pay()", () => {
    const order = new Order([line()], orderId());
    order.pay();
    expect(order.state).toBe("PAID");
  });

  it("refuses double payment", () => {
    const order = new Order([line()], orderId());
    order.pay();
    expect(() => {
      order.pay();
    }).toThrow(InvalidOrder);
    expect(() => {
      order.pay();
    }).toThrow(/already been paid/);
  });

  it("refuses shipping an unpaid order", () => {
    const order = new Order([line()], orderId());
    expect(() => {
      order.ship();
    }).toThrow(/paid/);
  });

  it("transitions PAID to SHIPPED on ship()", () => {
    const order = new Order([line()], orderId());
    order.pay();
    order.ship();
    expect(order.state).toBe("SHIPPED");
  });

  it("raises OrderAlreadyShipped for pay() after shipping", () => {
    const order = new Order([line()], orderId());
    order.pay();
    order.ship();
    expect(() => {
      order.pay();
    }).toThrow(OrderAlreadyShipped);
  });

  it("raises OrderAlreadyShipped for ship() after shipping", () => {
    const order = new Order([line()], orderId());
    order.pay();
    order.ship();
    expect(() => {
      order.ship();
    }).toThrow(OrderAlreadyShipped);
  });

  it("snapshots are detached copies", () => {
    const order = new Order([line()], orderId());
    const copy = order.snapshot();
    expect(copy).not.toBe(order);
    expect(copy.id).toBe(order.id);
    expect(copy.state).toBe("NEW");
    copy.pay();
    expect(order.state).toBe("NEW");
    expect(copy.state).toBe("PAID");
  });
});
