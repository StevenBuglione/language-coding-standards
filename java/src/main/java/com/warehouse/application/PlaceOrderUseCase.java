package com.warehouse.application;

import com.warehouse.application.InventoryGateway.ReleaseOutcome;
import com.warehouse.application.InventoryGateway.ReservationOutcome;
import com.warehouse.application.InventoryGateway.ReservationToken;
import com.warehouse.application.OrderRepository.IdempotencyRecord;
import com.warehouse.application.OrderRepository.SaveOutcome;
import com.warehouse.application.PaymentProcessor.ChargeOutcome;
import com.warehouse.application.PaymentProcessor.ChargeReceipt;
import com.warehouse.application.PaymentProcessor.RefundOutcome;
import com.warehouse.domain.DomainError;
import com.warehouse.domain.DomainError.InvalidOrderError;
import com.warehouse.domain.InvalidOrderException;
import com.warehouse.domain.Order;
import com.warehouse.domain.OrderLine;
import java.util.List;
import java.util.Objects;
import java.util.Optional;
import java.util.stream.Collectors;

/**
 * Orchestrates validate -&gt; reserveAll -&gt; charge -&gt; pay -&gt; persist, with compensation.
 *
 * <p>Every outcome is a {@link PlaceOrderResult}: structural validation failures become {@link
 * InvalidOrderError}, stock shortages, declined payments, persistence conflicts, and compensation
 * failures short-circuit as their own typed payloads. Only a successful save returns a PAID
 * snapshot.
 */
public final class PlaceOrderUseCase {

  private final InventoryGateway inventory;
  private final PaymentProcessor payments;
  private final OrderRepository repository;
  private final OrderIdGenerator ids;

  /**
   * Wires the use case to its outbound ports.
   *
   * @param inventory stock reservation port
   * @param payments payment collection port
   * @param repository order persistence port
   * @param ids identifier minting port
   */
  public PlaceOrderUseCase(
      InventoryGateway inventory,
      PaymentProcessor payments,
      OrderRepository repository,
      OrderIdGenerator ids) {
    this.inventory = inventory;
    this.payments = payments;
    this.repository = repository;
    this.ids = ids;
  }

  /**
   * Validates the order, reserves stock atomically, collects payment, marks PAID, then persists —
   * compensating (refund/release) at the first failure after a side effect.
   *
   * @param lines the requested order lines; validated by the domain
   * @param idempotencyKey retries with the same key and payload replay the snapshot
   * @return success with the persisted PAID order, or failure with exactly one domain error
   */
  public PlaceOrderResult execute(List<OrderLine> lines, String idempotencyKey) {
    Optional<IdempotencyRecord> remembered = repository.getByIdempotencyKey(idempotencyKey);
    if (remembered.isPresent()) {
      return replay(remembered.get(), lines);
    }
    return placeNew(lines, idempotencyKey);
  }

  private PlaceOrderResult replay(IdempotencyRecord remembered, List<OrderLine> lines) {
    if (!remembered.fingerprint().equals(fingerprint(lines))) {
      return new PlaceOrderResult.Failure(
          new InvalidOrderError("idempotency key reused with different payload"));
    }
    return new PlaceOrderResult.Success(remembered.order());
  }

  private PlaceOrderResult placeNew(List<OrderLine> lines, String idempotencyKey) {
    Order order;
    try {
      order = new Order(ids.next(), lines);
    } catch (InvalidOrderException e) {
      return new PlaceOrderResult.Failure(
          new InvalidOrderError(Objects.requireNonNullElse(e.getMessage(), "invalid order")));
    }
    return switch (inventory.reserveAll(order.id(), order.lines(), idempotencyKey)) {
      case ReservationOutcome.Shortage shortage -> new PlaceOrderResult.Failure(shortage.error());
      case ReservationOutcome.Reserved reserved ->
          chargeAndPersist(order, idempotencyKey, reserved.token(), lines);
    };
  }

  private PlaceOrderResult chargeAndPersist(
      Order order, String idempotencyKey, ReservationToken token, List<OrderLine> lines) {
    return switch (payments.charge(order, idempotencyKey)) {
      case ChargeOutcome.Declined declined -> releaseOrFail(token, declined.error());
      case ChargeOutcome.Charged charged ->
          payAndSave(order, idempotencyKey, fingerprint(lines), token, charged.receipt());
    };
  }

  private PlaceOrderResult payAndSave(
      Order order,
      String idempotencyKey,
      String fingerprint,
      ReservationToken token,
      ChargeReceipt receipt) {
    order.pay();
    return switch (repository.save(order, 0)) {
      case SaveOutcome.Conflict conflict -> compensate(token, receipt, conflict.error());
      case SaveOutcome.Saved saved -> {
        repository.rememberIdempotency(idempotencyKey, fingerprint, saved.snapshot());
        yield new PlaceOrderResult.Success(saved.snapshot());
      }
    };
  }

  private PlaceOrderResult compensate(
      ReservationToken token, ChargeReceipt receipt, DomainError original) {
    return switch (payments.refund(receipt)) {
      case RefundOutcome.Failed failed -> new PlaceOrderResult.Failure(failed.error());
      case RefundOutcome.Refunded _ -> releaseOrFail(token, original);
    };
  }

  private PlaceOrderResult releaseOrFail(ReservationToken token, DomainError original) {
    return switch (inventory.release(token)) {
      case ReleaseOutcome.Failed failed -> new PlaceOrderResult.Failure(failed.error());
      case ReleaseOutcome.Released _ -> new PlaceOrderResult.Failure(original);
    };
  }

  private static String fingerprint(List<OrderLine> lines) {
    return lines.stream()
        .map(
            line ->
                line.sku().code()
                    + ':'
                    + line.quantity().value()
                    + ':'
                    + line.unitPrice().currency()
                    + ':'
                    + line.unitPrice().minorUnits())
        .collect(Collectors.joining("|"));
  }
}
