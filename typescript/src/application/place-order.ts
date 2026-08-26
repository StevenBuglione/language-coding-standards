/**
 * PlaceOrderUseCase: validate → reserve → charge → persist, Result-typed.
 */

import { type InsufficientStock, InvalidOrder, type OrderAlreadyShipped } from "../domain/errors";
import { Order, type OrderLine } from "../domain/order";
import type { InventoryGateway, OrderRepository, PaymentProcessor } from "./ports";

/**
 * Failure payload: exactly one typed domain error, never an exception.
 */
export interface PlaceOrderFailure {
  /**
   * The outcome discriminant.
   */
  readonly outcome: "failure";

  /**
   * Exactly one of the three canonical domain errors.
   */
  readonly error: InsufficientStock | InvalidOrder | OrderAlreadyShipped;
}

/**
 * Success payload: the persisted order.
 */
export interface PlaceOrderSuccess {
  /**
   * The outcome discriminant.
   */
  readonly outcome: "success";

  /**
   * The order as persisted by the repository.
   */
  readonly order: Order;
}

/**
 * The use-case boundary result (CONTRACTS.md §2): a tagged union, so no
 * exception ever crosses it.
 */
export type PlaceOrderResult = PlaceOrderSuccess | PlaceOrderFailure;

/**
 * Orchestrates validate → reserve → charge → persist without raising.
 *
 * No exception crosses the use-case boundary: every outcome is a
 * `PlaceOrderSuccess` or `PlaceOrderFailure` value.
 */
export class PlaceOrderUseCase {
  private readonly inventory: InventoryGateway;

  private readonly payments: PaymentProcessor;

  private readonly repository: OrderRepository;

  /**
   * Wires the use case to its outbound ports.
   *
   * @param inventory - the inventory edge to reserve stock through.
   * @param payments - the payments edge to collect through.
   * @param repository - the persistence edge to save through.
   */
  constructor(
    inventory: InventoryGateway,
    payments: PaymentProcessor,
    repository: OrderRepository,
  ) {
    this.inventory = inventory;
    this.payments = payments;
    this.repository = repository;
  }

  /**
   * Validates the order, reserves stock, collects payment, then persists.
   *
   * @param lines - the raw requested line set; validation failures come
   * back as typed failures rather than thrown errors.
   * @returns the discriminated success/failure result.
   */
  execute(lines: readonly OrderLine[]): PlaceOrderResult {
    let order: Order;
    try {
      order = new Order(lines);
    } catch (error: unknown) {
      if (error instanceof InvalidOrder) {
        return { outcome: "failure", error };
      }
      throw error;
    }
    for (const line of order.lines) {
      const reserved = this.inventory.reserve(line.sku, line.quantity);
      if (reserved.outcome !== "reserved") {
        return { outcome: "failure", error: reserved.error };
      }
    }
    const charged = this.payments.charge(order);
    if (charged.outcome !== "charged") {
      return { outcome: "failure", error: charged.error };
    }
    return { outcome: "success", order: this.repository.save(order) };
  }
}

/**
 * Factory over the public entry point: builds the use case from its ports.
 *
 * @param inventory - the inventory edge to reserve stock through.
 * @param payments - the payments edge to collect through.
 * @param repository - the persistence edge to save through.
 * @returns a fully wired use case.
 */
export function createPlaceOrderUseCase(
  inventory: InventoryGateway,
  payments: PaymentProcessor,
  repository: OrderRepository,
): PlaceOrderUseCase {
  return new PlaceOrderUseCase(inventory, payments, repository);
}
