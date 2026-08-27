/**
 * Deterministic and sequence-based order id generators.
 */

import type { OrderIdGenerator } from "../application/ports";
import { createOrderId, type OrderId } from "../domain/order";

/**
 * Test double that issues `ord-1`, `ord-2`, ...
 */
export class SequenceOrderIdGenerator implements OrderIdGenerator {
  private n = 0;

  private readonly prefix: string;

  /**
   * Starts at zero so the first id is prefix-1.
   *
   * @param prefix - leading text of each issued identifier.
   */
  constructor(prefix = "ord") {
    this.prefix = prefix;
  }

  /**
   * Returns the next sequenced identifier.
   */
  next(): OrderId {
    this.n += 1;
    return createOrderId(`${this.prefix}-${String(this.n)}`);
  }
}

/**
 * Test double that always returns the same injected identifier.
 */
export class FixedOrderIdGenerator implements OrderIdGenerator {
  private readonly orderId: OrderId;

  /**
   * Holds a single identifier.
   *
   * @param orderId - the identifier every `next` call returns.
   */
  constructor(orderId: OrderId) {
    this.orderId = orderId;
  }

  /**
   * Returns the configured identifier.
   */
  next(): OrderId {
    return this.orderId;
  }
}
