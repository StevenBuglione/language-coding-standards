package com.warehouse.application;

import com.warehouse.domain.DomainError.InsufficientStockError;
import com.warehouse.domain.Quantity;
import com.warehouse.domain.Sku;

/**
 * Outbound port for reserving stock on the inventory edge.
 *
 * <p>Every fallible outcome is a typed result value; implementations never raise to report a
 * business failure.
 */
@FunctionalInterface
public interface InventoryGateway {

  /**
   * Attempts to reserve {@code quantity} units of {@code sku}.
   *
   * @param sku the stock-keeping unit to reserve
   * @param quantity how many units are requested
   * @return reserved marker, or a typed shortage carrying exactly why stock fell short
   */
  ReservationOutcome reserve(Sku sku, Quantity quantity);

  /** Outcome vocabulary of a reservation attempt. */
  sealed interface ReservationOutcome
      permits ReservationOutcome.Reserved, ReservationOutcome.Shortage {

    /** Success marker proving a stock reservation happened. */
    record Reserved() implements ReservationOutcome {}

    /** Failure payload: the inventory cannot cover the request. */
    record Shortage(InsufficientStockError error) implements ReservationOutcome {}
  }
}
