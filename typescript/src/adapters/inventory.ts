/**
 * In-memory inventory adapter backed by a finite per-SKU stock map.
 */

import type { InventoryGateway, ReserveResult } from "../application/ports";
import { InsufficientStock } from "../domain/errors";
import type { Quantity } from "../domain/quantity";
import type { Sku } from "../domain/sku";

/**
 * `InventoryGateway` double enforcing finite stock, for tests and demos.
 *
 * The stock map is keyed by the branded `Sku`, so raw strings cannot leak
 * into reservations.
 */
export class InMemoryInventoryGateway implements InventoryGateway {
  private readonly stock: Map<Sku, number>;

  /**
   * Starts from an optional initial stock map, copied defensively.
   *
   * @param stock - initial per-SKU units; defaults to an empty warehouse.
   */
  constructor(stock: ReadonlyMap<Sku, number> = new Map()) {
    this.stock = new Map(stock);
  }

  /**
   * Reserves when stock covers the request; otherwise reports shortage.
   *
   * @param sku - the SKU to reserve.
   * @param quantity - the requested amount.
   * @returns a discriminated reserved/out-of-stock result.
   */
  reserve(sku: Sku, quantity: Quantity): ReserveResult {
    const available = this.stock.get(sku) ?? 0;
    if (available < quantity.value) {
      return {
        outcome: "out-of-stock",
        error: new InsufficientStock(sku, quantity, available),
      };
    }
    this.stock.set(sku, available - quantity.value);
    return { outcome: "reserved" };
  }
}
