package com.warehouse.application;

import com.warehouse.domain.DomainError.InvalidOrderError;
import com.warehouse.domain.InvalidOrderException;
import com.warehouse.domain.Order;
import com.warehouse.domain.OrderLine;
import java.util.List;
import java.util.Objects;

/**
 * Orchestrates validate -&gt; reserve -&gt; charge -&gt; persist without raising.
 *
 * <p>Every outcome is a {@link PlaceOrderResult}: structural validation failures become {@link
 * InvalidOrderError}, stock shortages and declined payments short-circuit as their own typed
 * payloads, and only fully successful pipelines persist an order.
 */
public final class PlaceOrderUseCase {

  private final InventoryGateway inventory;
  private final PaymentProcessor payments;
  private final OrderRepository repository;

  /**
   * Wires the use case to its outbound ports.
   *
   * @param inventory stock reservation port
   * @param payments payment collection port
   * @param repository order persistence port
   */
  public PlaceOrderUseCase(
      InventoryGateway inventory, PaymentProcessor payments, OrderRepository repository) {
    this.inventory = inventory;
    this.payments = payments;
    this.repository = repository;
  }

  /**
   * Validates the order, reserves stock for every line, collects payment, then persists — stopping
   * at the first failure with its typed payload.
   *
   * @param lines the requested order lines; validated by the domain
   * @return success with the persisted order, or failure with exactly one domain error
   */
  public PlaceOrderResult execute(List<OrderLine> lines) {
    Order order;
    try {
      order = new Order(lines);
    } catch (InvalidOrderException e) {
      return new PlaceOrderResult.Failure(
          new InvalidOrderError(Objects.requireNonNullElse(e.getMessage(), "invalid order")));
    }
    for (OrderLine line : order.lines()) {
      switch (inventory.reserve(line.sku(), line.quantity())) {
        case InventoryGateway.ReservationOutcome.Shortage shortage -> {
          return new PlaceOrderResult.Failure(shortage.error());
        }
        case InventoryGateway.ReservationOutcome.Reserved _ -> {
          // Stock secured for this line; continue with the next one.
        }
      }
    }
    switch (payments.charge(order)) {
      case PaymentProcessor.ChargeOutcome.Declined declined -> {
        return new PlaceOrderResult.Failure(declined.error());
      }
      case PaymentProcessor.ChargeOutcome.Charged _ -> {
        // Payment collected; fall through to persistence.
      }
    }
    return new PlaceOrderResult.Success(repository.save(order));
  }
}
