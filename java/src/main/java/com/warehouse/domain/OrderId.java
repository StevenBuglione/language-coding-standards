package com.warehouse.domain;

import java.util.UUID;

/**
 * Immutable unique identifier of an order.
 *
 * @param value the underlying universally unique identifier
 */
public record OrderId(UUID value) {}
