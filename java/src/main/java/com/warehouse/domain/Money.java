package com.warehouse.domain;

import java.util.Currency;

/**
 * A non-negative amount in integer minor units of a single currency.
 *
 * <p>Cross-currency operations are invalid: adding two amounts of different currencies raises
 * {@link InvalidOrderException}, mirroring the contract's rule that a currency mismatch is an
 * invalid order, never a silent coercion.
 *
 * @param minorUnits amount in the currency's smallest unit; non-negative
 * @param currency ISO-4217 currency of the amount
 */
public record Money(int minorUnits, Currency currency) {

  /**
   * Validates the non-negative-amount invariant.
   *
   * @throws InvalidOrderException when {@code minorUnits} is negative
   */
  public Money {
    if (minorUnits < 0) {
      throw new InvalidOrderException("money amount must be non-negative, got " + minorUnits);
    }
  }

  /**
   * Returns the sum of two amounts of the same currency.
   *
   * @param other addend in the same currency
   * @return a new amount equal to this plus {@code other}
   * @throws InvalidOrderException when currencies differ
   */
  public Money add(Money other) {
    requireSameCurrency(other);
    return new Money(minorUnits + other.minorUnits, currency);
  }

  /**
   * Returns this amount scaled by a non-negative integer multiplier.
   *
   * @param multiplier scaling factor; non-negative
   * @return a new amount equal to this scaled by {@code multiplier}
   * @throws InvalidOrderException when {@code multiplier} is negative
   */
  public Money times(int multiplier) {
    if (multiplier < 0) {
      throw new InvalidOrderException("multiplier must be non-negative, got " + multiplier);
    }
    return new Money(minorUnits * multiplier, currency);
  }

  private void requireSameCurrency(Money other) {
    if (!currency.equals(other.currency())) {
      throw new InvalidOrderException(
          "currency mismatch: "
              + currency.getCurrencyCode()
              + " vs "
              + other.currency().getCurrencyCode());
    }
  }
}
