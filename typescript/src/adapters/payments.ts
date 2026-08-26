/**
 * Fake payment adapter with a configurable decline switch.
 */

import type { ChargeResult, PaymentProcessor } from "../application/ports";
import { InvalidOrder } from "../domain/errors";
import type { Order } from "../domain/order";

/**
 * Options bag for {@link FakePaymentProcessor}; exactOptionalPropertyTypes-safe.
 */
export interface FakePaymentProcessorOptions {
  /**
   * When true, every charge attempt is declined. Defaults to false.
   */
  readonly decline?: boolean;
}

/**
 * `PaymentProcessor` test double that records every charge attempt.
 *
 * Configure `decline: true` to make each collection fail with a typed
 * refusal instead of charging.
 */
export class FakePaymentProcessor implements PaymentProcessor {
  private readonly decline: boolean;

  /**
   * Every order this processor was asked to charge, in attempt order.
   */
  readonly chargedOrders: Order[] = [];

  /**
   * Starts in the configured outcome mode with an empty attempt log.
   *
   * @param options - decline switch; defaults to always charging.
   */
  constructor(options: FakePaymentProcessorOptions = {}) {
    this.decline = options.decline === true;
  }

  /**
   * Records the attempt, then honors the configured outcome.
   *
   * @param order - the order being charged.
   * @returns a discriminated charged/declined result.
   */
  charge(order: Order): ChargeResult {
    this.chargedOrders.push(order);
    if (this.decline) {
      return {
        outcome: "declined",
        error: new InvalidOrder(`payment declined for order ${order.id}`),
      };
    }
    return { outcome: "charged" };
  }
}
