package com.warehouse.adapters;

import com.warehouse.application.InventoryGateway;
import com.warehouse.domain.DomainError.CompensationFailureError;
import com.warehouse.domain.DomainError.InsufficientStockError;
import com.warehouse.domain.OrderId;
import com.warehouse.domain.OrderLine;
import com.warehouse.domain.Sku;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.locks.Lock;
import java.util.concurrent.locks.ReentrantLock;

/**
 * {@link InventoryGateway} double enforcing a finite stock map, for tests and demos.
 *
 * <p>{@code reserveAll} is atomic: every line is covered or none are. Concurrent callers serialize
 * on an internal lock so two reservations cannot oversell the last units.
 */
public final class InMemoryInventoryGateway implements InventoryGateway {

  private record Held(Sku sku, int amount) {}

  private final Lock lock = new ReentrantLock();
  private final Map<Sku, Integer> stock;
  private final Map<String, List<Held>> reservations = new HashMap<>();
  private boolean failRelease;

  /**
   * Starts from an initial per-SKU stock map, copied defensively.
   *
   * @param initialStock available units per SKU; missing SKUs mean zero stock
   */
  public InMemoryInventoryGateway(Map<Sku, Integer> initialStock) {
    this.stock = new HashMap<>(initialStock);
  }

  /**
   * Configures whether subsequent {@link #release} calls fail compensation.
   *
   * @param fail when true, {@link #release} returns {@link ReleaseOutcome.Failed}
   */
  public void failRelease(boolean fail) {
    lock.lock();
    try {
      this.failRelease = fail;
    } finally {
      lock.unlock();
    }
  }

  /**
   * Returns a copy of remaining units per SKU.
   *
   * @return remaining stock, independent of internal state
   */
  public Map<Sku, Integer> snapshotStock() {
    lock.lock();
    try {
      return Map.copyOf(stock);
    } finally {
      lock.unlock();
    }
  }

  @Override
  public ReservationOutcome reserveAll(
      OrderId orderId, List<OrderLine> lines, String idempotencyKey) {
    lock.lock();
    try {
      if (reservations.containsKey(idempotencyKey)) {
        return new ReservationOutcome.Reserved(new ReservationToken(orderId, idempotencyKey));
      }
      for (OrderLine line : lines) {
        int available = stock.getOrDefault(line.sku(), 0);
        if (available < line.quantity().value()) {
          return new ReservationOutcome.Shortage(
              new InsufficientStockError(line.sku(), line.quantity(), available));
        }
      }
      List<Held> held = new ArrayList<>();
      for (OrderLine line : lines) {
        int available = stock.getOrDefault(line.sku(), 0);
        stock.put(line.sku(), available - line.quantity().value());
        held.add(new Held(line.sku(), line.quantity().value()));
      }
      reservations.put(idempotencyKey, held);
      return new ReservationOutcome.Reserved(new ReservationToken(orderId, idempotencyKey));
    } finally {
      lock.unlock();
    }
  }

  @Override
  public ReleaseOutcome release(ReservationToken token) {
    lock.lock();
    try {
      if (failRelease) {
        return new ReleaseOutcome.Failed(new CompensationFailureError("release", "forced failure"));
      }
      List<Held> held = reservations.remove(token.idempotencyKey());
      if (held == null) {
        return new ReleaseOutcome.Released();
      }
      for (Held item : held) {
        stock.put(item.sku(), stock.getOrDefault(item.sku(), 0) + item.amount());
      }
      return new ReleaseOutcome.Released();
    } finally {
      lock.unlock();
    }
  }
}
