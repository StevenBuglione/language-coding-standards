package com.warehouse.application;

import com.warehouse.domain.Order;
import com.warehouse.domain.OrderId;
import java.util.Optional;

/** Outbound port that persists and retrieves orders. */
public interface OrderRepository {

  /**
   * Persists {@code order} and returns the persisted snapshot.
   *
   * @param order the order to store under its identifier
   * @return the persisted snapshot as observed by this repository
   */
  Order save(Order order);

  /**
   * Looks up an order by identifier; absence never raises.
   *
   * @param orderId the identifier to look up
   * @return the stored order, or empty for an unknown identifier
   */
  Optional<Order> get(OrderId orderId);
}
