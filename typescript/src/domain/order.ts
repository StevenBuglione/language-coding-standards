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
 * Brands a non-empty identifier. The domain never mints ids itself.
 *
 * @param value - caller-supplied identifier text.
 * @returns the branded identifier.
 * @throws InvalidOrder when the value is empty or whitespace-only.
 */
export function createOrderId(value: string): OrderId {
  if (value.trim().length === 0) {
    throw new InvalidOrder("order id must be non-empty");
  }
  return value as OrderId;
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
 * Order entity enforcing the canonical invariants.
 *
 * Invariants: injected id; at least one line; no duplicate normalized SKUs;
 * single currency at construction; total equals the checked sum of line
 * totals; only NEW → PAID → SHIPPED is legal. Optimistic version starts at 0.
 */
export class Order {
  private currentStatus: OrderStatus = "NEW";

  private currentVersion = 0;

  /**
   * Immutable unique identifier assigned at construction.
   */
  readonly id: OrderId;

  /**
   * Defensive copy of the validated lines; never mutated afterwards.
   */
  readonly lines: readonly OrderLine[];

  /**
   * Places a new order from validated lines and an injected id.
   *
   * @param lines - at least one line, with no SKU repeated across lines.
   * @param id - identifier minted by the application, not by this entity.
   * @throws InvalidOrder when the line set is empty, has duplicate SKUs, or
   * mixes currencies.
   */
  constructor(lines: readonly OrderLine[], id: OrderId) {
    const firstLine = lines[0];
    if (firstLine === undefined) {
      throw new InvalidOrder("an order requires at least one line");
    }
    const skus = new Set(lines.map((line) => line.sku));
    if (skus.size !== lines.length) {
      throw new InvalidOrder("duplicate SKUs across order lines are not allowed");
    }
    if (lines.some((line) => line.unitPrice.currency !== firstLine.unitPrice.currency)) {
      throw new InvalidOrder("mixed currencies are not allowed");
    }
    this.id = id;
    this.lines = [...lines];
  }

  /**
   * Rejects any mutation of an already-shipped order.
   */
  private ensureNotShipped(): void {
    if (this.currentStatus === "SHIPPED") {
      throw new OrderAlreadyShipped(`order ${this.id} has already shipped`);
    }
  }

  /**
   * Returns the current state-machine state.
   */
  get state(): OrderStatus {
    return this.currentStatus;
  }

  /**
   * Returns the optimistic concurrency version; 0 for a newly constructed order.
   */
  get version(): number {
    return this.currentVersion;
  }

  /**
   * Returns the sum of all line totals in a single currency.
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
    if (this.currentStatus === "PAID") {
      throw new InvalidOrder("order has already been paid");
    }
    this.currentStatus = "PAID";
  }

  /**
   * Transitions PAID to SHIPPED; only paid orders may ship.
   *
   * @throws OrderAlreadyShipped when the order has already shipped.
   * @throws InvalidOrder when the order is not paid yet.
   */
  ship(): void {
    this.ensureNotShipped();
    if (this.currentStatus !== "PAID") {
      throw new InvalidOrder("only paid orders can be shipped");
    }
    this.currentStatus = "SHIPPED";
  }

  /**
   * Increments the optimistic version after a successful save.
   */
  bumpVersion(): void {
    this.currentVersion += 1;
  }

  /**
   * Returns a detached copy so repositories cannot alias stored state.
   *
   * @returns an independent order with the same id, lines, status, and version.
   */
  snapshot(): Order {
    const clone = new Order(this.lines, this.id);
    clone.currentStatus = this.currentStatus;
    clone.currentVersion = this.currentVersion;
    return clone;
  }
}
