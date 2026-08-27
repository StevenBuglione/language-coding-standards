package com.warehouse.application;

import com.warehouse.domain.OrderId;

/**
 * Outbound port that mints order identifiers. The domain never reads randomness or a process-global
 * counter; the application injects this port.
 */
@FunctionalInterface
public interface OrderIdGenerator {

  /**
   * Returns the next identifier.
   *
   * @return a newly minted order id
   */
  OrderId next();
}
