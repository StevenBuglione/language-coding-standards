package com.warehouse.adapters;

import com.warehouse.application.OrderRepository;
import com.warehouse.domain.DomainError.PersistenceConflictError;
import com.warehouse.domain.Order;
import com.warehouse.domain.OrderId;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.locks.Lock;
import java.util.concurrent.locks.ReentrantLock;

/**
 * {@link OrderRepository} double keeping snapshots, never aliases, for tests and demos.
 *
 * <p>Saves use compare-and-set on the optimistic version. Gets and idempotency lookups return
 * detached copies so a caller cannot mutate stored state.
 */
public final class InMemoryOrderRepository implements OrderRepository {

  private final Lock lock = new ReentrantLock();
  private final Map<OrderId, Order> orders = new HashMap<>();
  private final Map<String, IdempotencyRecord> byKey = new HashMap<>();
  private final List<Order> savedOrders = new ArrayList<>();
  private boolean failSave;

  /**
   * Configures whether subsequent {@link #save} calls fail with a persistence conflict.
   *
   * @param fail when true, {@link #save} returns {@link SaveOutcome.Conflict}
   */
  public void failSave(boolean fail) {
    lock.lock();
    try {
      this.failSave = fail;
    } finally {
      lock.unlock();
    }
  }

  @Override
  public SaveOutcome save(Order order, int expectedVersion) {
    lock.lock();
    try {
      if (failSave) {
        return new SaveOutcome.Conflict(
            new PersistenceConflictError("forced save failure for " + order.id().value()));
      }
      Order current = orders.get(order.id());
      int currentVersion = current == null ? 0 : current.version();
      if (currentVersion != expectedVersion) {
        return new SaveOutcome.Conflict(
            new PersistenceConflictError(
                "version conflict for "
                    + order.id().value()
                    + ": expected "
                    + expectedVersion
                    + ", stored "
                    + currentVersion));
      }
      Order stored = order.snapshot();
      stored.bumpVersion();
      orders.put(order.id(), stored);
      Order returned = stored.snapshot();
      savedOrders.add(returned.snapshot());
      return new SaveOutcome.Saved(returned);
    } finally {
      lock.unlock();
    }
  }

  @Override
  public Optional<Order> get(OrderId orderId) {
    lock.lock();
    try {
      Order stored = orders.get(orderId);
      if (stored == null) {
        return Optional.empty();
      }
      return Optional.of(stored.snapshot());
    } finally {
      lock.unlock();
    }
  }

  @Override
  public Optional<IdempotencyRecord> getByIdempotencyKey(String key) {
    lock.lock();
    try {
      IdempotencyRecord found = byKey.get(key);
      if (found == null) {
        return Optional.empty();
      }
      return Optional.of(new IdempotencyRecord(found.fingerprint(), found.order().snapshot()));
    } finally {
      lock.unlock();
    }
  }

  @Override
  public void rememberIdempotency(String key, String fingerprint, Order order) {
    lock.lock();
    try {
      byKey.put(key, new IdempotencyRecord(fingerprint, order.snapshot()));
    } finally {
      lock.unlock();
    }
  }

  /**
   * Returns the snapshots persisted so far, defensively copied.
   *
   * @return one entry per successful save call, in save order
   */
  public List<Order> saved() {
    lock.lock();
    try {
      return List.copyOf(savedOrders);
    } finally {
      lock.unlock();
    }
  }
}
