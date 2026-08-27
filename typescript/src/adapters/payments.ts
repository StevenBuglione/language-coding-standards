/**
 * Fake payment adapter with idempotent charge and refund.
 */

import type { ChargeReceipt, PaymentProcessor } from "../application/ports";
import { CompensationFailure, PaymentDeclined } from "../domain/errors";
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
 * Configure `decline: true` to refuse collection. Identical idempotency
 * keys replay the original outcome without a second charge.
 */
export class FakePaymentProcessor implements PaymentProcessor {
  private readonly decline: boolean;

  private readonly receipts = new Map<string, ChargeReceipt | PaymentDeclined>();

  /**
   * When true, `refund` returns `CompensationFailure`.
   */
  failRefund = false;

  /**
   * Every order this processor was asked to charge, in attempt order.
   */
  readonly chargedOrders: Order[] = [];

  /**
   * Receipts successfully refunded, in attempt order.
   */
  readonly refunded: ChargeReceipt[] = [];

  /**
   * Starts in the configured outcome mode with an empty attempt log.
   *
   * @param options - decline switch; defaults to always charging.
   */
  constructor(options: FakePaymentProcessorOptions = {}) {
    this.decline = options.decline === true;
  }

  /**
   * Records the attempt unless this key already completed.
   *
   * @param order - the order being charged.
   * @param idempotencyKey - key that replays an existing charge outcome.
   * @returns a receipt, or `PaymentDeclined` when collection is refused.
   */
  charge(order: Order, idempotencyKey: string): ChargeReceipt | PaymentDeclined {
    const existing = this.receipts.get(idempotencyKey);
    if (existing !== undefined) {
      return existing;
    }
    this.chargedOrders.push(order);
    if (this.decline) {
      const declined = new PaymentDeclined(`payment declined for order ${order.id}`);
      this.receipts.set(idempotencyKey, declined);
      return declined;
    }
    const receipt = { orderId: order.id, idempotencyKey };
    this.receipts.set(idempotencyKey, receipt);
    return receipt;
  }

  /**
   * Voids a prior successful charge.
   *
   * @param receipt - receipt from a successful `charge`.
   * @returns `undefined` on success, or `CompensationFailure` when configured to fail.
   */
  refund(receipt: ChargeReceipt): CompensationFailure | undefined {
    if (this.failRefund) {
      return new CompensationFailure("refund", "forced failure");
    }
    this.refunded.push(receipt);
    return undefined;
  }
}
