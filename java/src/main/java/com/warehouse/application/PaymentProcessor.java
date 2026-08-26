package com.warehouse.application;

import com.warehouse.domain.DomainError.InvalidOrderError;
import com.warehouse.domain.Order;

/**
 * Outbound port for collecting payment on the payments edge.
 *
 * <p>Refusal is a typed result, never an exception: a declined card is a business outcome, not a
 * defect.
 */
@FunctionalInterface
public interface PaymentProcessor {

  /**
   * Attempts to collect payment for {@code order}.
   *
   * @param order the order being charged
   * @return charged marker, or a typed refusal carrying the reason
   */
  ChargeOutcome charge(Order order);

  /** Outcome vocabulary of a charge attempt. */
  sealed interface ChargeOutcome permits ChargeOutcome.Charged, ChargeOutcome.Declined {

    /** Success marker proving a payment collection happened. */
    record Charged() implements ChargeOutcome {}

    /** Failure payload: the processor refused the collection. */
    record Declined(InvalidOrderError error) implements ChargeOutcome {}
  }
}
