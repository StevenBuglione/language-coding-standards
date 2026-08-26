/**
 * In-memory order repository keyed by immutable order id.
 */

import type { OrderRepository } from "../application/ports";
import type { Order, OrderId } from "../domain/order";

/**
 * `OrderRepository` double keeping orders in a dictionary, for tests.
 *
 * Lookup of an unknown id returns undefined and never raises (CONTRACTS.md
 * §2 binding clarification).
 */
export class InMemoryOrderRepository implements OrderRepository {
  private readonly orders = new Map<OrderId, Order>();

  /**
   * Every order passed to save, in call order — for assertions.
   */
  readonly saved: Order[] = [];

  /**
   * Stores the order under its id and returns it as persisted.
   *
   * @param order - the order to persist.
   * @returns the persisted order.
   */
  save(order: Order): Order {
    this.orders.set(order.id, order);
    this.saved.push(order);
    return order;
  }

  /**
   * Looks up an order by identifier; absence is undefined, never a throw.
   *
   * @param orderId - the identifier to look up.
   * @returns the stored order, or undefined when absent.
   */
  get(orderId: OrderId): Order | undefined {
    return this.orders.get(orderId);
  }
}
