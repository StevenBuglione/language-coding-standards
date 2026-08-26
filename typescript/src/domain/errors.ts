/**
 * Typed domain errors raised by the pure domain layer.
 *
 * Domain code raises these internally; the use-case boundary never lets one
 * escape — `PlaceOrderUseCase` converts them into typed failure results
 * instead (CONTRACTS.md §2).
 */

import type { Quantity } from "./quantity";
import type { Sku } from "./sku";

/**
 * Base class for every recoverable domain-rule violation.
 *
 * Catching this catches any domain rule breach while leaving programming
 * errors (TypeError, RangeError, ...) untouched.
 */
export class DomainError extends Error {}

/**
 * An order or value violates a structural domain invariant.
 */
export class InvalidOrder extends DomainError {
  /**
   * @param message - human-readable description of the violated invariant.
   */
  constructor(message: string) {
    super(message);
    this.name = "InvalidOrder";
  }
}

/**
 * The inventory cannot cover the requested quantity for a SKU.
 */
export class InsufficientStock extends DomainError {
  /**
   * The SKU whose stock fell short.
   */
  readonly sku: Sku;

  /**
   * The quantity that was requested.
   */
  readonly requested: Quantity;

  /**
   * The stock that was actually available at reservation time.
   */
  readonly available: number;

  /**
   * Records which SKU fell short, by how much, and what remained.
   *
   * @param sku - the SKU whose reservation failed.
   * @param requested - the strictly positive requested quantity.
   * @param available - the finite stock available when the request arrived.
   */
  constructor(sku: Sku, requested: Quantity, available: number) {
    super(
      `insufficient stock for ${sku}: requested ${String(requested.value)}, available ${String(available)}`,
    );
    this.sku = sku;
    this.requested = requested;
    this.available = available;
    this.name = "InsufficientStock";
  }
}

/**
 * A shipped order can no longer be mutated.
 */
export class OrderAlreadyShipped extends DomainError {
  /**
   * @param message - details about which transition was refused and why.
   */
  constructor(message: string) {
    super(message);
    this.name = "OrderAlreadyShipped";
  }
}
