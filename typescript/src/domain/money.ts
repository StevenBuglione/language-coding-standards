/**
 * Money value object: integer minor units plus an ISO-4217 currency code.
 */

import { InvalidOrder } from "./errors";

const CURRENCY_PATTERN = /^[A-Z]{3}$/;

/**
 * A non-negative amount in integer minor units of a single currency.
 *
 * Cross-currency arithmetic is invalid and raises `InvalidOrder`
 * (CONTRACTS.md §2 binding clarification). Create instances through
 * {@link Money.create}; the constructor is private so no unvalidated money
 * can exist.
 */
export class Money {
  /**
   * Creates a validated `Money`, raising `InvalidOrder` on violation.
   *
   * @param minorUnits - non-negative integer amount in minor units.
   * @param currency - three-letter uppercase currency code.
   * @returns the validated value object.
   * @throws InvalidOrder when the amount is negative or fractional, or the
   * code is not a three-letter uppercase string.
   */
  static create(minorUnits: number, currency: string): Money {
    if (!Number.isSafeInteger(minorUnits) || minorUnits < 0) {
      throw new InvalidOrder(
        `money amount must be a non-negative integer, got ${String(minorUnits)}`,
      );
    }
    if (!CURRENCY_PATTERN.test(currency)) {
      throw new InvalidOrder(`currency must be a 3-letter uppercase code, got "${currency}"`);
    }
    return new Money(minorUnits, currency);
  }

  /**
   * Amount in integer minor units; never negative.
   */
  readonly minorUnits: number;

  /**
   * Three-letter uppercase ISO-4217-style currency code.
   */
  readonly currency: string;

  private constructor(minorUnits: number, currency: string) {
    this.minorUnits = minorUnits;
    this.currency = currency;
  }

  /**
   * Rejects cross-currency arithmetic as an invalid order state.
   */
  private requireSameCurrency(other: Money): void {
    if (this.currency !== other.currency) {
      throw new InvalidOrder(`currency mismatch: ${this.currency} vs ${other.currency}`);
    }
  }

  /**
   * Returns the sum of two amounts of the same currency.
   *
   * @param other - addend in the same currency.
   * @throws InvalidOrder on currency mismatch.
   */
  add(other: Money): Money {
    this.requireSameCurrency(other);
    return Money.create(this.minorUnits + other.minorUnits, this.currency);
  }

  /**
   * Returns this amount scaled by a non-negative integer multiplier.
   *
   * @param multiplier - non-negative integer scale factor.
   * @throws InvalidOrder when the multiplier is negative or fractional.
   */
  times(multiplier: number): Money {
    if (!Number.isSafeInteger(multiplier) || multiplier < 0) {
      throw new InvalidOrder(
        `multiplier must be a non-negative integer, got ${String(multiplier)}`,
      );
    }
    return Money.create(this.minorUnits * multiplier, this.currency);
  }

  /**
   * Value equality: same minor units and same currency.
   *
   * @param other - the money to compare against.
   * @returns true when both fields match.
   */
  equals(other: Money): boolean {
    return this.minorUnits === other.minorUnits && this.currency === other.currency;
  }
}
