/**
 * In-memory order repository keyed by immutable order id.
 */

import type { IdempotencyRecord, OrderRepository } from "../application/ports";
import { PersistenceConflict } from "../domain/errors";
import type { Order, OrderId } from "../domain/order";

/**
 * `OrderRepository` double keeping snapshots, never aliases.
 *
 * Lookup of an unknown id returns undefined and never raises (CONTRACTS.md
 * §2 binding clarification).
 */
export class InMemoryOrderRepository implements OrderRepository {
  private readonly orders = new Map<OrderId, Order>();

  private readonly byKey = new Map<string, IdempotencyRecord>();

  /**
   * When true, `save` returns `PersistenceConflict` without storing.
   */
  failSave = false;

  /**
   * Every snapshot returned from save, in call order — for assertions.
   */
  readonly saved: Order[] = [];

  /**
   * Stores a snapshot under compare-and-set version rules.
   *
   * @param order - the order to persist.
   * @param expectedVersion - the version the caller believes is stored.
   * @returns a detached snapshot, or `PersistenceConflict` on a lost race.
   */
  save(order: Order, expectedVersion: number): Order | PersistenceConflict {
    if (this.failSave) {
      return new PersistenceConflict(`forced save failure for ${order.id}`);
    }
    const current = this.orders.get(order.id);
    const currentVersion = current === undefined ? 0 : current.version;
    if (currentVersion !== expectedVersion) {
      return new PersistenceConflict(
        `version conflict for ${order.id}: expected ${String(expectedVersion)}, stored ${String(currentVersion)}`,
      );
    }
    const snapshot = order.snapshot();
    snapshot.bumpVersion();
    this.orders.set(order.id, snapshot);
    this.saved.push(snapshot.snapshot());
    return snapshot.snapshot();
  }

  /**
   * Records a successful command so retries can replay the snapshot.
   *
   * @param key - the idempotency key of the command.
   * @param fingerprint - stable payload identity of the command.
   * @param order - the persisted paid snapshot to replay.
   */
  rememberIdempotency(key: string, fingerprint: string, order: Order): void {
    this.byKey.set(key, { fingerprint, order: order.snapshot() });
  }

  /**
   * Returns the fingerprint and snapshot for a previous command.
   *
   * @param key - the idempotency key to look up.
   * @returns the record, or undefined when this key has not succeeded.
   */
  getByIdempotencyKey(key: string): IdempotencyRecord | undefined {
    const found = this.byKey.get(key);
    if (found === undefined) {
      return undefined;
    }
    return { fingerprint: found.fingerprint, order: found.order.snapshot() };
  }

  /**
   * Looks up an order by identifier; absence is undefined, never a throw.
   *
   * @param orderId - the identifier to look up.
   * @returns a detached snapshot, or undefined when absent.
   */
  get(orderId: OrderId): Order | undefined {
    const stored = this.orders.get(orderId);
    if (stored === undefined) {
      return undefined;
    }
    return stored.snapshot();
  }
}
