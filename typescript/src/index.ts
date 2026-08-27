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

export { FixedOrderIdGenerator, SequenceOrderIdGenerator } from "./adapters/ids";
export { InMemoryInventoryGateway } from "./adapters/inventory";
export { FakePaymentProcessor } from "./adapters/payments";
export type { FakePaymentProcessorOptions } from "./adapters/payments";
export { InMemoryOrderRepository } from "./adapters/repository";
export type {
  ChargeReceipt,
  IdempotencyRecord,
  InventoryGateway,
  OrderIdGenerator,
  OrderRepository,
  PaymentProcessor,
  ReservationToken,
} from "./application/ports";
export { createPlaceOrderUseCase, PlaceOrderUseCase } from "./application/place-order";
export type {
  PlaceOrderCommand,
  PlaceOrderFailure,
  PlaceOrderResult,
  PlaceOrderSuccess,
} from "./application/place-order";
export {
  CompensationFailure,
  DomainError,
  InsufficientStock,
  InvalidOrder,
  OrderAlreadyShipped,
  PaymentDeclined,
  PersistenceConflict,
} from "./domain/errors";
export { Money, MONEY_MINOR_UNITS_MAX } from "./domain/money";
export { createOrderId, lineTotal, Order } from "./domain/order";
export type { OrderId, OrderLine, OrderStatus } from "./domain/order";
export { Quantity, QUANTITY_MAX } from "./domain/quantity";
export { createSku, normalizeSkuCode, SKU_MAX_UTF8_BYTES } from "./domain/sku";
export type { Sku } from "./domain/sku";
