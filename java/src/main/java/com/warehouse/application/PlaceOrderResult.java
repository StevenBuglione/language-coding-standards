package com.warehouse.application;

import com.warehouse.domain.DomainError;
import com.warehouse.domain.Order;

/**
 * Typed outcome of placing an order.
 *
 * <p>No exception crosses the use-case boundary: every execution returns a {@code Success} carrying
 * the persisted order or a {@code Failure} carrying exactly one sealed {@link DomainError} payload.
 */
public sealed interface PlaceOrderResult
    permits PlaceOrderResult.Success, PlaceOrderResult.Failure {

  /** Success payload: the persisted order. */
  record Success(Order order) implements PlaceOrderResult {}

  /** Failure payload: exactly one typed domain error, never an exception. */
  record Failure(DomainError error) implements PlaceOrderResult {}
}
