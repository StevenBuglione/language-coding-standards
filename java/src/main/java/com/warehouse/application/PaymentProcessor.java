package com.warehouse.application;

import com.warehouse.domain.DomainError.CompensationFailureError;
import com.warehouse.domain.DomainError.PaymentDeclinedError;
import com.warehouse.domain.Order;
import com.warehouse.domain.OrderId;

/**
 * Outbound port for collecting payment on the payments edge.
 *
 * <p>Refusal is a typed result, never an exception: a declined card is a business outcome, not a
 * defect.
 */
public interface PaymentProcessor {

  /**
   * Proof that payment was collected for an idempotency key.
   *
   * @param orderId the order that was charged
   * @param idempotencyKey key that makes retries of this charge a no-op
   */
  record ChargeReceipt(OrderId orderId, String idempotencyKey) {}

  /**
   * Charges the order total; identical retries return the same receipt.
   *
   * @param order the order being charged
   * @param idempotencyKey retries with the same key must not charge twice
   * @return a charge receipt, or a typed refusal carrying the reason
   */
  ChargeOutcome charge(Order order, String idempotencyKey);

  /**
   * Voids or refunds a prior charge.
   *
   * @param receipt the receipt returned by a successful {@link #charge}
   * @return refunded marker, or compensation failure when refund itself fails
   */
  RefundOutcome refund(ChargeReceipt receipt);

  /** Outcome vocabulary of a charge attempt. */
  sealed interface ChargeOutcome permits ChargeOutcome.Charged, ChargeOutcome.Declined {

    /**
     * Success payload proving a payment collection happened.
     *
     * @param receipt proof of the charge, used later to refund
     */
    record Charged(ChargeReceipt receipt) implements ChargeOutcome {}

    /** Failure payload: the processor refused the collection. */
    record Declined(PaymentDeclinedError error) implements ChargeOutcome {}
  }

  /** Outcome vocabulary of a refund attempt. */
  sealed interface RefundOutcome permits RefundOutcome.Refunded, RefundOutcome.Failed {

    /** Success marker proving the charge was voided. */
    record Refunded() implements RefundOutcome {}

    /** Failure payload: refund itself failed after a partial success. */
    record Failed(CompensationFailureError error) implements RefundOutcome {}
  }
}
