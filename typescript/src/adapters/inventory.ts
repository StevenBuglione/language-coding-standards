/**
 * In-memory inventory adapter with atomic reserve-all.
 */

import type { InventoryGateway, ReservationToken } from "../application/ports";
import { CompensationFailure, InsufficientStock } from "../domain/errors";
import type { OrderId, OrderLine } from "../domain/order";
import type { Sku } from "../domain/sku";

/**
 * `InventoryGateway` double enforcing finite stock, for tests and demos.
 *
 * The stock map is keyed by the branded `Sku`, so raw strings cannot leak
 * into reservations. `reserveAll` is atomic: every line is reserved, or none.
 */
export class InMemoryInventoryGateway implements InventoryGateway {
  private readonly stock: Map<Sku, number>;

  private readonly reservations = new Map<string, { sku: Sku; amount: number }[]>();

  /**
   * When true, `release` returns `CompensationFailure` without restoring stock.
   */
  failRelease = false;

  /**
   * Starts from an optional initial stock map, copied defensively.
   *
   * @param stock - initial per-SKU units; defaults to an empty warehouse.
   */
  constructor(stock: ReadonlyMap<Sku, number> = new Map()) {
    this.stock = new Map(stock);
  }

  /**
   * Returns a copy of remaining units per SKU.
   */
  snapshotStock(): Map<Sku, number> {
    return new Map(this.stock);
  }

  /**
   * Reserves every line atomically, or none.
   *
   * @param orderId - the order the reservation belongs to.
   * @param lines - the lines to reserve.
   * @param idempotencyKey - key that replays an existing reservation.
   * @returns a reservation token, or `InsufficientStock` when any line falls short.
   */
  reserveAll(
    orderId: OrderId,
    lines: readonly OrderLine[],
    idempotencyKey: string,
  ): ReservationToken | InsufficientStock {
    if (this.reservations.has(idempotencyKey)) {
      return { orderId, idempotencyKey };
    }
    const needed: { sku: Sku; amount: number }[] = [];
    for (const line of lines) {
      const available = this.stock.get(line.sku) ?? 0;
      if (available < line.quantity.value) {
        return new InsufficientStock(line.sku, line.quantity, available);
      }
      needed.push({ sku: line.sku, amount: line.quantity.value });
    }
    for (const item of needed) {
      this.stock.set(item.sku, (this.stock.get(item.sku) ?? 0) - item.amount);
    }
    this.reservations.set(idempotencyKey, needed);
    return { orderId, idempotencyKey };
  }

  /**
   * Puts reserved units back.
   *
   * @param token - token from a successful `reserveAll`.
   * @returns `undefined` on success, or `CompensationFailure` when configured to fail.
   */
  release(token: ReservationToken): CompensationFailure | undefined {
    if (this.failRelease) {
      return new CompensationFailure("release", "forced failure");
    }
    const held = this.reservations.get(token.idempotencyKey);
    this.reservations.delete(token.idempotencyKey);
    if (held === undefined) {
      return undefined;
    }
    for (const item of held) {
      this.stock.set(item.sku, (this.stock.get(item.sku) ?? 0) + item.amount);
    }
    return undefined;
  }
}
