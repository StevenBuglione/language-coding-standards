package com.warehouse.adapters;

import com.warehouse.application.PaymentProcessor;
import com.warehouse.domain.DomainError.CompensationFailureError;
import com.warehouse.domain.DomainError.PaymentDeclinedError;
import com.warehouse.domain.Order;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.locks.Lock;
import java.util.concurrent.locks.ReentrantLock;

/**
 * {@link PaymentProcessor} double with a configurable decline switch, for tests and demos.
 *
 * <p>Every charge attempt is recorded so tests can prove whether collection was attempted at all.
 * Identical idempotency keys replay the original outcome without a second charge.
 */
public final class FakePaymentProcessor implements PaymentProcessor {

  private final Lock lock = new ReentrantLock();
  private final boolean decline;
  private final List<Order> chargedOrders = new ArrayList<>();
  private final List<ChargeReceipt> refunded = new ArrayList<>();
  private final Map<String, ChargeOutcome> outcomes = new HashMap<>();
  private boolean failRefund;

  /**
   * Starts in the configured outcome mode.
   *
   * @param decline when true, every new charge is refused with a typed refusal
   */
  public FakePaymentProcessor(boolean decline) {
    this.decline = decline;
  }

  /**
   * Configures whether subsequent {@link #refund} calls fail compensation.
   *
   * @param fail when true, {@link #refund} returns {@link RefundOutcome.Failed}
   */
  public void failRefund(boolean fail) {
    lock.lock();
    try {
      this.failRefund = fail;
    } finally {
      lock.unlock();
    }
  }

  @Override
  public ChargeOutcome charge(Order order, String idempotencyKey) {
    lock.lock();
    try {
      ChargeOutcome existing = outcomes.get(idempotencyKey);
      if (existing != null) {
        return existing;
      }
      chargedOrders.add(order);
      if (decline) {
        ChargeOutcome declined =
            new ChargeOutcome.Declined(
                new PaymentDeclinedError("payment declined for order " + order.id().value()));
        outcomes.put(idempotencyKey, declined);
        return declined;
      }
      ChargeReceipt receipt = new ChargeReceipt(order.id(), idempotencyKey);
      ChargeOutcome charged = new ChargeOutcome.Charged(receipt);
      outcomes.put(idempotencyKey, charged);
      return charged;
    } finally {
      lock.unlock();
    }
  }

  @Override
  public RefundOutcome refund(ChargeReceipt receipt) {
    lock.lock();
    try {
      if (failRefund) {
        return new RefundOutcome.Failed(new CompensationFailureError("refund", "forced failure"));
      }
      refunded.add(receipt);
      return new RefundOutcome.Refunded();
    } finally {
      lock.unlock();
    }
  }

  /**
   * Returns the orders charged so far, defensively copied.
   *
   * @return one entry per first-time collection, in attempt order
   */
  public List<Order> chargedOrders() {
    lock.lock();
    try {
      return List.copyOf(chargedOrders);
    } finally {
      lock.unlock();
    }
  }

  /**
   * Returns the receipts refunded so far, defensively copied.
   *
   * @return one entry per successful refund, in attempt order
   */
  public List<ChargeReceipt> refunded() {
    lock.lock();
    try {
      return List.copyOf(refunded);
    } finally {
      lock.unlock();
    }
  }
}
