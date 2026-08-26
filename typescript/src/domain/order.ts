/**
 * Order entity: the NEW → PAID → SHIPPED state machine and its invariants.
 */

import { InvalidOrder, OrderAlreadyShipped } from "./errors";
import type { Money } from "./money";
import type { Quantity } from "./quantity";
import type { Sku } from "./sku";

declare const brand: unique symbol;

/**
 * Branded immutable unique identifier of an order.
 */
export type OrderId = string & { readonly [brand]: "OrderId" };

/**
 * Generates a fresh unique order identifier (UUID v4).
 *
 * @returns the branded identifier value.
 */
export function generateOrderId(): OrderId {
  return crypto.randomUUID() as OrderId;
}

/**
 * States of the canonical order life cycle.
 */
export type OrderStatus = "NEW" | "PAID" | "SHIPPED";

/**
 * One SKU/quantity/unit-price row of an order.
 */
export interface OrderLine {
  /**
   * The ordered stock-keeping unit.
   */
  readonly sku: Sku;

  /**
   * The strictly positive amount of the SKU.
   */
  readonly quantity: Quantity;

  /**
   * The per-unit price in a single currency.
   */
  readonly unitPrice: Money;
}

/**
 * Returns the unit price scaled by the ordered quantity.
 *
 * @param line - the order line to total.
 * @returns the line total in the line's currency.
 */
export function lineTotal(line: OrderLine): Money {
  return line.unitPrice.times(line.quantity.value);
}

/**
 * Order entity enforcing the four canonical invariants.
 *
 * Invariants: at least one line; no duplicate SKUs across lines; the total
 * always equals the sum of line totals (computed, never stored stale); no
 * mutation once shipped. Transitions follow NEW → PAID → SHIPPED exactly;
 * every illegal transition raises a typed domain error.
 */
export class Order {
  private status: OrderStatus = "NEW";

  /**
   * Immutable unique identifier assigned at construction.
   */
  readonly id: OrderId;

  /**
   * Defensive copy of the validated lines; never mutated afterwards.
   */
  readonly lines: readonly OrderLine[];

  /**
   * Places a new order from validated lines, assigning a fresh id.
   *
   * @param lines - at least one line, with no SKU repeated across lines.
   * @throws InvalidOrder when the line set is empty or has duplicate SKUs.
   */
  constructor(lines: readonly OrderLine[]) {
    if (lines.length === 0) {
      throw new InvalidOrder("an order requires at least one line");
    }
    const skus = new Set(lines.map((line) => line.sku));
    if (skus.size !== lines.length) {
      throw new InvalidOrder("duplicate SKUs across order lines are not allowed");
    }
    this.id = generateOrderId();
    this.lines = [...lines];
  }

  /**
   * Rejects any mutation of an already-shipped order.
   */
  private ensureNotShipped(): void {
    if (this.status === "SHIPPED") {
      throw new OrderAlreadyShipped(`order ${this.id} has already shipped`);
    }
  }

  /**
   * Returns the current state-machine state.
   */
  get state(): OrderStatus {
    return this.status;
  }

  /**
   * Returns the sum of all line totals in a single currency.
   *
   * @throws InvalidOrder when line totals mix currencies.
   */
  total(): Money {
    const [firstLine, ...remainingLines] = this.lines;
    if (firstLine === undefined) {
      // Unreachable: the constructor rejects empty line sets; this branch
      // only satisfies noUncheckedIndexedAccess honestly.
      throw new InvalidOrder("an order requires at least one line");
    }
    let sum = lineTotal(firstLine);
    for (const line of remainingLines) {
      sum = sum.add(lineTotal(line));
    }
    return sum;
  }

  /**
   * Transitions NEW to PAID; refuses paid or already-shipped orders.
   *
   * @throws OrderAlreadyShipped when the order has already shipped.
   * @throws InvalidOrder when the order was already paid.
   */
  pay(): void {
    this.ensureNotShipped();
    if (this.status === "PAID") {
      throw new InvalidOrder("order has already been paid");
    }
    this.status = "PAID";
  }

  /**
   * Transitions PAID to SHIPPED; only paid orders may ship.
   *
   * @throws OrderAlreadyShipped when the order has already shipped.
   * @throws InvalidOrder when the order is not paid yet.
   */
  ship(): void {
    this.ensureNotShipped();
    if (this.status !== "PAID") {
      throw new InvalidOrder("only paid orders can be shipped");
    }
    this.status = "SHIPPED";
  }
}
