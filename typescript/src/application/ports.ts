/**
 * Ports: interfaces the application owns and the adapters layer implements.
 *
 * Fallible ports return a result union instead of raising (CONTRACTS.md §2).
 */

import type {
  CompensationFailure,
  InsufficientStock,
  PaymentDeclined,
  PersistenceConflict,
} from "../domain/errors";
import type { Order, OrderId, OrderLine } from "../domain/order";

/**
 * Proof that stock for an order was reserved atomically.
 */
export interface ReservationToken {
  /**
   * Identifier of the order the reservation belongs to.
   */
  readonly orderId: OrderId;

  /**
   * Idempotency key that keyed the reservation.
   */
  readonly idempotencyKey: string;
}

/**
 * Proof that payment was collected for an idempotency key.
 */
export interface ChargeReceipt {
  /**
   * Identifier of the charged order.
   */
  readonly orderId: OrderId;

  /**
   * Idempotency key that keyed the charge.
   */
  readonly idempotencyKey: string;
}

/**
 * Fingerprint and snapshot recorded for a previous successful command.
 */
export interface IdempotencyRecord {
  /**
   * Stable payload identity of the original command.
   */
  readonly fingerprint: string;

  /**
   * Snapshot of the persisted paid order.
   */
  readonly order: Order;
}

/**
 * Outbound port that mints deterministic-in-tests order identifiers.
 */
export interface OrderIdGenerator {
  /**
   * Returns the next identifier.
   */
  next(): OrderId;
}

/**
 * Outbound port for atomic stock reservation.
 */
export interface InventoryGateway {
  /**
   * Reserves every line or none.
   *
   * @param orderId - the order the reservation belongs to.
   * @param lines - the lines to reserve.
   * @param idempotencyKey - key that makes retries of the same command safe.
   * @returns a reservation token, or `InsufficientStock` when any line falls short.
   */
  reserveAll(
    orderId: OrderId,
    lines: readonly OrderLine[],
    idempotencyKey: string,
  ): ReservationToken | InsufficientStock;

  /**
   * Releases a previous reservation.
   *
   * @param token - token from a successful `reserveAll`.
   * @returns `undefined` on success, or `CompensationFailure` when release fails.
   */
  release(token: ReservationToken): CompensationFailure | undefined;
}

/**
 * Outbound port for idempotent payment collection.
 */
export interface PaymentProcessor {
  /**
   * Charges the order total; identical retries return the same receipt.
   *
   * @param order - the order to charge for.
   * @param idempotencyKey - key that makes retries of the same command safe.
   * @returns a receipt, or `PaymentDeclined` when collection is refused.
   */
  charge(order: Order, idempotencyKey: string): ChargeReceipt | PaymentDeclined;

  /**
   * Voids or refunds a prior charge.
   *
   * @param receipt - receipt from a successful `charge`.
   * @returns `undefined` on success, or `CompensationFailure` when refund fails.
   */
  refund(receipt: ChargeReceipt): CompensationFailure | undefined;
}

/**
 * Outbound port that persists and retrieves immutable snapshots.
 */
export interface OrderRepository {
  /**
   * Persists with compare-and-set semantics and returns a snapshot.
   *
   * @param order - the order to persist.
   * @param expectedVersion - the version the caller believes is stored.
   * @returns a detached snapshot, or `PersistenceConflict` on a lost race.
   */
  save(order: Order, expectedVersion: number): Order | PersistenceConflict;

  /**
   * Returns a stored snapshot or `undefined`; absence never raises.
   *
   * @param orderId - the identifier to look up.
   * @returns the stored snapshot, or undefined when absent.
   */
  get(orderId: OrderId): Order | undefined;

  /**
   * Returns fingerprint and snapshot for a previous successful command.
   *
   * @param key - the idempotency key to look up.
   * @returns the record, or undefined when this key has not succeeded.
   */
  getByIdempotencyKey(key: string): IdempotencyRecord | undefined;

  /**
   * Records a successful command so retries can replay.
   *
   * @param key - the idempotency key of the command.
   * @param fingerprint - stable payload identity of the command.
   * @param order - the persisted paid snapshot to replay.
   */
  rememberIdempotency(key: string, fingerprint: string, order: Order): void;
}
