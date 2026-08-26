/**
 * Ports: interfaces the application owns and the adapters layer implements.
 *
 * Every fallible port returns a discriminated-union result instead of
 * raising: success carries its marker payload, failure carries exactly one
 * typed domain error (CONTRACTS.md §2).
 */

import type { InsufficientStock, InvalidOrder } from "../domain/errors";
import type { Order, OrderId } from "../domain/order";
import type { Quantity } from "../domain/quantity";
import type { Sku } from "../domain/sku";

/**
 * Result of an inventory reservation attempt.
 */
export type ReserveResult =
  | { readonly outcome: "reserved" }
  | {
      /**
       * The reservation was refused: stock did not cover the request.
       */
      readonly outcome: "out-of-stock";

      /**
       * Exactly one typed failure: the stock shortage details.
       */
      readonly error: InsufficientStock;
    };

/**
 * Result of a payment collection attempt.
 */
export type ChargeResult =
  | { readonly outcome: "charged" }
  | {
      /**
       * The collection was refused by the payment edge.
       */
      readonly outcome: "declined";

      /**
       * Exactly one typed failure: the refusal reason.
       */
      readonly error: InvalidOrder;
    };

/**
 * Outbound port for reserving stock on the inventory edge.
 */
export interface InventoryGateway {
  /**
   * Attempts a reservation; reports shortage as a typed failure.
   *
   * @param sku - the SKU to reserve.
   * @param quantity - the strictly positive amount to reserve.
   * @returns a discriminated success/shortage result.
   */
  reserve(sku: Sku, quantity: Quantity): ReserveResult;
}

/**
 * Outbound port for collecting payment on the payments edge.
 */
export interface PaymentProcessor {
  /**
   * Attempts collection; reports refusal as a typed failure.
   *
   * @param order - the order to charge for.
   * @returns a discriminated charged/declined result.
   */
  charge(order: Order): ChargeResult;
}

/**
 * Outbound port that persists and retrieves orders.
 */
export interface OrderRepository {
  /**
   * Persists the order and returns the persisted snapshot.
   *
   * @param order - the order to persist.
   * @returns the persisted order.
   */
  save(order: Order): Order;

  /**
   * Looks up an order by identifier.
   *
   * Absence is modeled as `undefined` and never raises (CONTRACTS.md §2:
   * get never throws for an unknown identifier).
   *
   * @param orderId - the identifier to look up.
   * @returns the stored order, or undefined when absent.
   */
  get(orderId: OrderId): Order | undefined;
}
