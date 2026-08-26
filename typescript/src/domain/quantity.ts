/**
 * Quantity value object: a strictly positive integer.
 */

import { InvalidOrder } from "./errors";

/**
 * An amount of stock that must be strictly positive.
 *
 * Create instances through {@link Quantity.create}; the constructor is
 * private so no unvalidated quantity can exist.
 */
export class Quantity {
  /**
   * Creates a validated `Quantity`, raising `InvalidOrder` on violation.
   *
   * @param value - the raw integer amount; zero and negatives are invalid.
   * @returns the validated value object.
   * @throws InvalidOrder when the value is not a strictly positive integer.
   */
  static create(value: number): Quantity {
    if (!Number.isSafeInteger(value) || value <= 0) {
      throw new InvalidOrder(`quantity must be a strictly positive integer, got ${String(value)}`);
    }
    return new Quantity(value);
  }

  /**
   * The validated strictly positive integer amount.
   */
  readonly value: number;

  private constructor(value: number) {
    this.value = value;
  }
}
