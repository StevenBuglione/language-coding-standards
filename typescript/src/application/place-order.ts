/**
 * PlaceOrderUseCase: validate, reserveAll, charge, pay, persist, compensate.
 */

import {
  type CompensationFailure,
  InsufficientStock,
  InvalidOrder,
  PaymentDeclined,
  PersistenceConflict,
} from "../domain/errors";
import { Order, type OrderLine } from "../domain/order";
import type {
  ChargeReceipt,
  IdempotencyRecord,
  InventoryGateway,
  OrderIdGenerator,
  OrderRepository,
  PaymentProcessor,
  ReservationToken,
} from "./ports";

/**
 * Command options for {@link PlaceOrderUseCase.execute}.
 */
export interface PlaceOrderCommand {
  /**
   * Caller-supplied key that makes retries of the same payload safe.
   */
  readonly idempotencyKey: string;
}

/**
 * Failure payload: exactly one typed domain error, never an exception.
 */
export interface PlaceOrderFailure {
  /**
   * The outcome discriminant.
   */
  readonly outcome: "failure";

  /**
   * Exactly one of the canonical place-order failures.
   */
  readonly error:
    InvalidOrder | InsufficientStock | PaymentDeclined | PersistenceConflict | CompensationFailure;
}

/**
 * Success payload: the persisted paid order snapshot.
 */
export interface PlaceOrderSuccess {
  /**
   * The outcome discriminant.
   */
  readonly outcome: "success";

  /**
   * The order as persisted by the repository.
   */
  readonly order: Order;
}

/**
 * The use-case boundary result (CONTRACTS.md §2): a tagged union, so no
 * exception ever crosses it.
 */
export type PlaceOrderResult = PlaceOrderSuccess | PlaceOrderFailure;

/**
 * Orchestrates the v2 place-order policy without raising.
 *
 * No exception crosses the use-case boundary: every outcome is a
 * `PlaceOrderSuccess` or `PlaceOrderFailure` value.
 */
export class PlaceOrderUseCase {
  private readonly inventory: InventoryGateway;

  private readonly payments: PaymentProcessor;

  private readonly repository: OrderRepository;

  private readonly idGenerator: OrderIdGenerator;

  /**
   * Wires the use case to its outbound ports.
   *
   * @param inventory - the inventory edge to reserve stock through.
   * @param payments - the payments edge to collect through.
   * @param repository - the persistence edge to save through.
   * @param idGenerator - the source of injected order identifiers.
   */
  constructor(
    inventory: InventoryGateway,
    payments: PaymentProcessor,
    repository: OrderRepository,
    idGenerator: OrderIdGenerator,
  ) {
    this.inventory = inventory;
    this.payments = payments;
    this.repository = repository;
    this.idGenerator = idGenerator;
  }

  /**
   * Reserve, charge, pay, and persist a freshly constructed NEW order.
   */
  private fulfill(order: Order, idempotencyKey: string, fingerprint: string): PlaceOrderResult {
    const reserved = this.inventory.reserveAll(order.id, order.lines, idempotencyKey);
    if (reserved instanceof InsufficientStock) {
      return { outcome: "failure", error: reserved };
    }
    const charged = this.payments.charge(order, idempotencyKey);
    if (charged instanceof PaymentDeclined) {
      return this.releaseOrFail(reserved, charged);
    }
    try {
      order.pay();
    } catch (error: unknown) {
      if (!(error instanceof InvalidOrder)) {
        throw error;
      }
      return this.compensate(reserved, charged, error);
    }
    return this.persistPaid(
      order,
      { token: reserved, receipt: charged },
      { idempotencyKey, fingerprint },
    );
  }

  /**
   * Persist the paid order; refund and release if the save loses the race.
   */
  private persistPaid(
    order: Order,
    compensation: { readonly token: ReservationToken; readonly receipt: ChargeReceipt },
    command: { readonly idempotencyKey: string; readonly fingerprint: string },
  ): PlaceOrderResult {
    const saved = this.repository.save(order, 0);
    if (saved instanceof PersistenceConflict) {
      return this.compensate(compensation.token, compensation.receipt, saved);
    }
    this.repository.rememberIdempotency(command.idempotencyKey, command.fingerprint, saved);
    return { outcome: "success", order: saved };
  }

  /**
   * Release stock after a declined charge.
   */
  private releaseOrFail(token: ReservationToken, error: PaymentDeclined): PlaceOrderResult {
    const released = this.inventory.release(token);
    if (released !== undefined) {
      return { outcome: "failure", error: released };
    }
    return { outcome: "failure", error };
  }

  /**
   * Refund and release after a pay or save failure.
   */
  private compensate(
    token: ReservationToken,
    receipt: ChargeReceipt,
    error: InvalidOrder | PersistenceConflict,
  ): PlaceOrderResult {
    return pickCompensationError(
      this.payments.refund(receipt),
      this.inventory.release(token),
      error,
    );
  }

  /**
   * Validates, reserves, charges, marks PAID, persists; compensates on failure.
   *
   * @param lines - the raw requested line set; validation failures come
   * back as typed failures rather than thrown errors.
   * @param command - includes the idempotency key for the command.
   * @returns the discriminated success/failure result.
   */
  execute(lines: readonly OrderLine[], command: PlaceOrderCommand): PlaceOrderResult {
    const fingerprint = payloadFingerprint(lines);
    const remembered = this.repository.getByIdempotencyKey(command.idempotencyKey);
    if (remembered !== undefined) {
      return replayOrReject(remembered, fingerprint);
    }
    let order: Order;
    try {
      order = new Order(lines, this.idGenerator.next());
    } catch (error: unknown) {
      if (error instanceof InvalidOrder) {
        return { outcome: "failure", error };
      }
      throw error;
    }
    return this.fulfill(order, command.idempotencyKey, fingerprint);
  }
}

/**
 * Factory over the public entry point: builds the use case from its ports.
 *
 * @param inventory - the inventory edge to reserve stock through.
 * @param payments - the payments edge to collect through.
 * @param repository - the persistence edge to save through.
 * @param idGenerator - the source of injected order identifiers.
 * @returns a fully wired use case.
 */
export function createPlaceOrderUseCase(
  inventory: InventoryGateway,
  payments: PaymentProcessor,
  repository: OrderRepository,
  idGenerator: OrderIdGenerator,
): PlaceOrderUseCase {
  return new PlaceOrderUseCase(inventory, payments, repository, idGenerator);
}

function payloadFingerprint(lines: readonly OrderLine[]): string {
  return lines
    .map(
      (line) =>
        `${line.sku}:${String(line.quantity.value)}:${line.unitPrice.currency}:${String(line.unitPrice.minorUnits)}`,
    )
    .join("|");
}

function replayOrReject(remembered: IdempotencyRecord, fingerprint: string): PlaceOrderResult {
  if (remembered.fingerprint !== fingerprint) {
    return {
      outcome: "failure",
      error: new InvalidOrder("idempotency key reused with different payload"),
    };
  }
  return { outcome: "success", order: remembered.order };
}

function pickCompensationError(
  refunded: CompensationFailure | undefined,
  released: CompensationFailure | undefined,
  error: InvalidOrder | PersistenceConflict,
): PlaceOrderResult {
  if (refunded !== undefined) {
    return { outcome: "failure", error: refunded };
  }
  if (released !== undefined) {
    return { outcome: "failure", error: released };
  }
  return { outcome: "failure", error };
}
