package com.warehouse.adapters;

import com.warehouse.application.PaymentProcessor;
import com.warehouse.domain.DomainError.InvalidOrderError;
import com.warehouse.domain.Order;
import java.util.ArrayList;
import java.util.List;

/**
 * {@link PaymentProcessor} double with a configurable decline switch, for tests and demos.
 *
 * <p>Every charge attempt is recorded so tests can prove whether collection was attempted at all.
 */
public final class FakePaymentProcessor implements PaymentProcessor {

  private final boolean decline;
  private final List<Order> chargedOrders = new ArrayList<>();

  /**
   * Starts in the configured outcome mode.
   *
   * @param decline when true, every charge is refused with a typed refusal
   */
  public FakePaymentProcessor(boolean decline) {
    this.decline = decline;
  }

  @Override
  public ChargeOutcome charge(Order order) {
    chargedOrders.add(order);
    if (decline) {
      return new ChargeOutcome.Declined(
          new InvalidOrderError("payment declined for order " + order.id().value()));
    }
    return new ChargeOutcome.Charged();
  }

  /**
   * Returns the orders charged so far, defensively copied.
   *
   * @return one entry per attempted collection, in attempt order
   */
  public List<Order> chargedOrders() {
    return List.copyOf(chargedOrders);
  }
}
