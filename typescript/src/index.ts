/**
 * Thin public surface of the template: re-exports the canonical domain,
 * the ports, the use-case factory, and the in-memory adapters.
 */

export * from "./adapters/inventory";
export * from "./adapters/payments";
export * from "./adapters/repository";
export * from "./application/ports";
export { createPlaceOrderUseCase, PlaceOrderUseCase } from "./application/place-order";
export type {
  PlaceOrderFailure,
  PlaceOrderResult,
  PlaceOrderSuccess,
} from "./application/place-order";
export { DomainError, InsufficientStock, InvalidOrder, OrderAlreadyShipped } from "./domain/errors";
export { Money } from "./domain/money";
export { generateOrderId, lineTotal, Order } from "./domain/order";
export type { OrderId, OrderLine, OrderStatus } from "./domain/order";
export { Quantity } from "./domain/quantity";
export { createSku } from "./domain/sku";
export type { Sku } from "./domain/sku";
