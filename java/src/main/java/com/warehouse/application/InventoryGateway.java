package com.warehouse.application;

import com.warehouse.domain.DomainError.CompensationFailureError;
import com.warehouse.domain.DomainError.InsufficientStockError;
import com.warehouse.domain.OrderId;
import com.warehouse.domain.OrderLine;
import java.util.List;

/**
 * Outbound port for atomic stock reservation.
 *
 * <p>Every fallible outcome is a typed result value; implementations never raise to report a
 * business failure.
 */
public interface InventoryGateway {

  /**
   * Proof that stock for an order was reserved atomically.
   *
   * @param orderId the order whose lines were reserved
   * @param idempotencyKey key that makes retries of this reservation a no-op
   */
  record ReservationToken(OrderId orderId, String idempotencyKey) {}

  /**
   * Reserves every line or none.
   *
   * @param orderId the order being reserved for
   * @param lines the lines that must all be covered
   * @param idempotencyKey retries with the same key must not reserve twice
   * @return a reservation token, or a typed shortage carrying exactly why stock fell short
   */
  ReservationOutcome reserveAll(OrderId orderId, List<OrderLine> lines, String idempotencyKey);

  /**
   * Releases a previous reservation.
   *
   * @param token the token returned by a successful {@link #reserveAll}
   * @return released marker, or compensation failure when release itself fails
   */
  ReleaseOutcome release(ReservationToken token);

  /** Outcome vocabulary of an atomic reservation attempt. */
  sealed interface ReservationOutcome
      permits ReservationOutcome.Reserved, ReservationOutcome.Shortage {

    /**
     * Success payload proving a stock reservation happened.
     *
     * @param token proof of the reservation, used later to release
     */
    record Reserved(ReservationToken token) implements ReservationOutcome {}

    /** Failure payload: the inventory cannot cover every line. */
    record Shortage(InsufficientStockError error) implements ReservationOutcome {}
  }

  /** Outcome vocabulary of a reservation release. */
  sealed interface ReleaseOutcome permits ReleaseOutcome.Released, ReleaseOutcome.Failed {

    /** Success marker proving reserved units were put back. */
    record Released() implements ReleaseOutcome {}

    /** Failure payload: release itself failed after a partial success. */
    record Failed(CompensationFailureError error) implements ReleaseOutcome {}
  }
}
