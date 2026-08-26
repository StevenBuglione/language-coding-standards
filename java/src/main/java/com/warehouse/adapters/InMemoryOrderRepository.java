package com.warehouse.adapters;

import com.warehouse.application.OrderRepository;
import com.warehouse.domain.Order;
import com.warehouse.domain.OrderId;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * {@link OrderRepository} double keeping orders in a map, for tests and demos.
 *
 * <p>Stored instances are handed back by identity on purpose: the order aggregate is a mutable
 * state machine, and the port contract is that the persisted snapshot IS the caller's instance
 * (CONTRACTS.md §2).
 */
public final class InMemoryOrderRepository implements OrderRepository {

  private final Map<OrderId, Order> orders = new HashMap<>();
  private final List<Order> savedOrders = new ArrayList<>();

  @Override
  public Order save(Order order) {
    orders.put(order.id(), order);
    savedOrders.add(order);
    return order;
  }

  @Override
  public Optional<Order> get(OrderId orderId) {
    return Optional.ofNullable(orders.get(orderId));
  }

  /**
   * Returns the orders persisted so far, defensively copied.
   *
   * @return one entry per save call, in save order
   */
  public List<Order> saved() {
    return List.copyOf(savedOrders);
  }
}
