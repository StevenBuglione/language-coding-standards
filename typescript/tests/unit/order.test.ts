/**
 * Unit tests covering every Order invariant and state transition.
 */

import { describe, expect, it } from "vitest";

import { InvalidOrder, OrderAlreadyShipped } from "../../src/domain/errors";
import { Money } from "../../src/domain/money";
import { Order, type OrderLine, type OrderStatus } from "../../src/domain/order";
import { Quantity } from "../../src/domain/quantity";
import { createSku } from "../../src/domain/sku";

function line(code = "SKU-1", qty = 2, minorUnits = 500, currency = "USD"): OrderLine {
  return {
    sku: createSku(code),
    quantity: Quantity.create(qty),
    unitPrice: Money.create(minorUnits, currency),
  };
}

describe("Order", () => {
  it("rejects an empty line set", () => {
    expect(() => new Order([])).toThrow(/at least one line/);
  });

  it("rejects duplicate SKUs across lines", () => {
    expect(() => new Order([line("SKU-1"), line("SKU-1")])).toThrow(/duplicate/);
  });

  it("totals the sum of line totals", () => {
    const order = new Order([line("SKU-1", 2, 500), line("SKU-2", 1, 1000)]);
    expect(order.total().equals(Money.create(2000, "USD"))).toBe(true);
  });

  it("refuses mixed-currency totals", () => {
    const order = new Order([line("SKU-1"), line("SKU-2", 1, 100, "EUR")]);
    expect(() => order.total()).toThrow(InvalidOrder);
    expect(() => order.total()).toThrow(/mismatch/);
  });

  it("starts in NEW state with a fresh unique id", () => {
    const first = new Order([line()]);
    const second = new Order([line()]);
    expect(first.state).toBe("NEW" satisfies OrderStatus);
    expect(first.id).not.toBe(second.id);
  });

  it("transitions NEW to PAID on pay()", () => {
    const order = new Order([line()]);
    order.pay();
    expect(order.state).toBe("PAID");
  });

  it("refuses double payment", () => {
    const order = new Order([line()]);
    order.pay();
    expect(() => {
      order.pay();
    }).toThrow(/already been paid/);
  });

  it("refuses shipping an unpaid order", () => {
    const order = new Order([line()]);
    expect(() => {
      order.ship();
    }).toThrow(/paid/);
  });

  it("transitions PAID to SHIPPED on ship()", () => {
    const order = new Order([line()]);
    order.pay();
    order.ship();
    expect(order.state).toBe("SHIPPED");
  });

  it("raises OrderAlreadyShipped for pay() after shipping", () => {
    const order = new Order([line()]);
    order.pay();
    order.ship();
    expect(() => {
      order.pay();
    }).toThrow(OrderAlreadyShipped);
  });

  it("raises OrderAlreadyShipped for ship() after shipping", () => {
    const order = new Order([line()]);
    order.pay();
    order.ship();
    expect(() => {
      order.ship();
    }).toThrow(OrderAlreadyShipped);
  });
});
