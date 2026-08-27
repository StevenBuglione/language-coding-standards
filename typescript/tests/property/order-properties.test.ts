/**
 * Property-based tests for Order invariants under random valid inputs.
 */

import fc from "fast-check";
import { describe, expect, it } from "vitest";

import { OrderAlreadyShipped } from "../../src/domain/errors";
import { lineTotal, type OrderLine } from "../../src/domain/order";
import { createOrderId, Order } from "../../src/domain/order";
import { Money } from "../../src/domain/money";
import { Quantity } from "../../src/domain/quantity";
import { createSku } from "../../src/domain/sku";

const lineSpecs = fc.uniqueArray(
  fc.record({
    code: fc.integer({ min: 0, max: 9999 }).map((n) => `SKU-${String(n)}`),
    qty: fc.integer({ min: 1, max: 5 }),
    price: fc.nat(5000),
  }),
  { minLength: 1, maxLength: 6, selector: (spec) => spec.code },
);

function toLines(specs: { code: string; qty: number; price: number }[]): OrderLine[] {
  return specs.map((spec) => ({
    sku: createSku(spec.code),
    quantity: Quantity.create(spec.qty),
    unitPrice: Money.create(spec.price, "USD"),
  }));
}

describe("Order properties", () => {
  it("total always equals the sum of line totals under random valid line sets", () => {
    fc.assert(
      fc.property(lineSpecs, (specs) => {
        const lines = toLines(specs);
        const [firstLine, ...remainingLines] = lines;
        if (firstLine === undefined) {
          throw new Error("unreachable: uniqueArray minLength is 1");
        }
        let expected = lineTotal(firstLine);
        for (const line of remainingLines) {
          expected = expected.add(lineTotal(line));
        }
        expect(new Order(lines, createOrderId("ord-prop")).total().equals(expected)).toBe(true);
      }),
    );
  });

  it("the full life cycle preserves the total and locks mutation", () => {
    fc.assert(
      fc.property(lineSpecs, (specs) => {
        const order = new Order(toLines(specs), createOrderId("ord-prop"));
        const originalTotal = order.total();

        order.pay();
        expect(order.state).toBe("PAID");
        order.ship();
        expect(order.total().equals(originalTotal)).toBe(true);
        expect(() => {
          order.pay();
        }).toThrow(OrderAlreadyShipped);
      }),
    );
  });
});
