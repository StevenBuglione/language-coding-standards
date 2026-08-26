package com.warehouse.domain;

/**
 * One SKU/quantity/unit-price row of an order.
 *
 * @param sku the ordered stock-keeping unit
 * @param quantity how many units are ordered; strictly positive
 * @param unitPrice price per single unit in one currency
 */
public record OrderLine(Sku sku, Quantity quantity, Money unitPrice) {

  /**
   * Returns the unit price scaled by the ordered quantity.
   *
   * @return the line total in the line's currency
   */
  public Money lineTotal() {
    return unitPrice.times(quantity.value());
  }
}
