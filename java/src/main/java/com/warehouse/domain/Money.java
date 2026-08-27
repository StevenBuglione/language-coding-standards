package com.warehouse.domain;

import java.util.regex.Pattern;

/**
 * A non-negative amount in integer minor units of a single currency.
 *
 * <p>Currency codes are ISO-style ({@code ^[A-Z]{3}$}), not ISO-4217 membership. {@code ZZZ} is
 * valid. Cross-currency operations raise {@link InvalidOrderException}.
 *
 * @param minorUnits amount in the currency's smallest unit; non-negative
 * @param currency ISO-style three-letter code of the amount
 */
public record Money(long minorUnits, String currency) {

  /** Inclusive maximum minor units shared with every language pack. */
  public static final long MAX_MINOR_UNITS = 9_007_199_254_740_991L;

  private static final Pattern CURRENCY_PATTERN = Pattern.compile("[A-Z]{3}");

  /**
   * Validates the non-negative amount, shared maximum, and ISO-style currency.
   *
   * @throws InvalidOrderException when {@code minorUnits} is negative, exceeds the shared maximum,
   *     or {@code currency} is not three uppercase ASCII letters
   */
  public Money {
    if (minorUnits < 0) {
      throw new InvalidOrderException("money amount must be non-negative, got " + minorUnits);
    }
    if (minorUnits > MAX_MINOR_UNITS) {
      throw new InvalidOrderException(
          "money amount exceeds " + MAX_MINOR_UNITS + ", got " + minorUnits);
    }
    if (!CURRENCY_PATTERN.matcher(currency).matches()) {
      throw new InvalidOrderException(
          "currency must be a 3-letter uppercase ISO-style code, got " + currency);
    }
  }

  /**
   * Returns the sum of two amounts of the same currency.
   *
   * @param other addend in the same currency
   * @return a new amount equal to this plus {@code other}
   * @throws InvalidOrderException when currencies differ or the sum overflows the shared maximum
   */
  public Money add(Money other) {
    requireSameCurrency(other);
    if (other.minorUnits > MAX_MINOR_UNITS - minorUnits) {
      throw new InvalidOrderException("money addition overflows the shared maximum");
    }
    return new Money(Math.addExact(minorUnits, other.minorUnits), currency);
  }

  /**
   * Returns this amount scaled by a non-negative integer multiplier.
   *
   * @param multiplier scaling factor; non-negative
   * @return a new amount equal to this scaled by {@code multiplier}
   * @throws InvalidOrderException when {@code multiplier} is negative or the product overflows
   */
  public Money times(int multiplier) {
    if (multiplier < 0) {
      throw new InvalidOrderException("multiplier must be non-negative, got " + multiplier);
    }
    try {
      long product = Math.multiplyExact(minorUnits, multiplier);
      if (product > MAX_MINOR_UNITS) {
        throw new InvalidOrderException("money scaling overflows the shared maximum");
      }
      return new Money(product, currency);
    } catch (ArithmeticException overflow) {
      throw new InvalidOrderException("money scaling overflows the shared maximum", overflow);
    }
  }

  private void requireSameCurrency(Money other) {
    if (!currency.equals(other.currency())) {
      throw new InvalidOrderException("currency mismatch: " + currency + " vs " + other.currency());
    }
  }
}
