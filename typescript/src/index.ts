/**
 * Thin public surface of the template: re-exports the canonical domain,
 * the ports, the use-case factory, and the in-memory adapters.
 *
 * Every re-export is explicit by name — deliberately no `export *`. A
 * wildcard barrel at the entry would forward any future export sight
 * unseen, and knip exempts the entry file's own exports, so dead exports
 * could hide behind it forever. Explicit lists keep the public surface a
 * reviewed artifact and knip's unused-export analysis sound.
 */

export { InMemoryInventoryGateway } from "./adapters/inventory";
export { FakePaymentProcessor } from "./adapters/payments";
export type { FakePaymentProcessorOptions } from "./adapters/payments";
export { InMemoryOrderRepository } from "./adapters/repository";
export type {
  ChargeResult,
  InventoryGateway,
  OrderRepository,
  PaymentProcessor,
  ReserveResult,
} from "./application/ports";
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
