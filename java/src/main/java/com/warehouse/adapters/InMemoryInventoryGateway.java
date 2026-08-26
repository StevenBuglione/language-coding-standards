package com.warehouse.adapters;

import com.warehouse.application.InventoryGateway;
import com.warehouse.domain.DomainError.InsufficientStockError;
import com.warehouse.domain.Quantity;
import com.warehouse.domain.Sku;
import java.util.HashMap;
import java.util.Map;

/**
 * {@link InventoryGateway} double enforcing a finite stock map, for tests and demos.
 *
 * <p>Deliberately single-threaded: concurrency here would be accidental complexity in a test
 * double.
 */
public final class InMemoryInventoryGateway implements InventoryGateway {

  private final Map<Sku, Integer> stock;

  /**
   * Starts from an initial per-SKU stock map, copied defensively.
   *
   * @param initialStock available units per SKU; missing SKUs mean zero stock
   */
  public InMemoryInventoryGateway(Map<Sku, Integer> initialStock) {
    this.stock = new HashMap<>(initialStock);
  }

  @Override
  public ReservationOutcome reserve(Sku sku, Quantity quantity) {
    int available = stock.getOrDefault(sku, 0);
    if (available < quantity.value()) {
      return new ReservationOutcome.Shortage(new InsufficientStockError(sku, quantity, available));
    }
    stock.put(sku, available - quantity.value());
    return new ReservationOutcome.Reserved();
  }
}
