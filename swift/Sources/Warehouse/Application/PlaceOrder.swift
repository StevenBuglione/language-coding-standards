/// Typed place-order failure. Decline is `paymentDeclined`, never `invalidOrder`.
public enum PlaceOrderFailure: Error, Equatable, Sendable {
  case invalidOrder(InvalidOrder)
  case insufficientStock(InsufficientStock)
  case paymentDeclined(PaymentDeclined)
  case persistenceConflict(PersistenceConflict)
  case compensationFailure(CompensationFailure)
  case infrastructureFailure(InfrastructureFailure)
}

/// Orchestrates validate -> reserveAll -> charge -> pay -> persist, with compensation.
public struct PlaceOrderUseCase: Sendable {
  private let inventory: any InventoryGateway
  private let payments: any PaymentProcessor
  private let repository: any OrderRepository
  private let ids: any OrderIdGenerator

  public init(
    inventory: any InventoryGateway,
    payments: any PaymentProcessor,
    repository: any OrderRepository,
    ids: any OrderIdGenerator
  ) {
    self.inventory = inventory
    self.payments = payments
    self.repository = repository
    self.ids = ids
  }

  /// Validate, reserve, charge, mark PAID, persist; compensate on failure.
  public func execute(
    lines: [OrderLine],
    idempotencyKey: String
  ) -> Result<Order, PlaceOrderFailure> {
    let fingerprint = Self.fingerprint(lines)
    if let remembered = repository.getByIdempotencyKey(idempotencyKey) {
      if remembered.fingerprint != fingerprint {
        return .failure(
          .invalidOrder(InvalidOrder("idempotency key reused with different payload"))
        )
      }
      return .success(remembered.order)
    }

    let order: Order
    do {
      order = try Order(id: ids.next(), lines: lines)
    } catch let error as InvalidOrder {
      return .failure(.invalidOrder(error))
    } catch {
      return .failure(.invalidOrder(InvalidOrder("invalid order")))
    }

    let reserved: ReservationToken
    switch inventory.reserveAll(
      orderId: order.id,
      lines: order.lines,
      idempotencyKey: idempotencyKey
    ) {
    case .failure(let shortage):
      return .failure(.insufficientStock(shortage))
    case .success(let token):
      reserved = token
    }

    let receipt: ChargeReceipt
    switch payments.charge(order, idempotencyKey: idempotencyKey) {
    case .failure(let declined):
      return releaseOrFail(reserved, declined)
    case .success(let charged):
      receipt = charged
    }

    var paid = order
    do {
      try paid.pay()
    } catch let error as InvalidOrder {
      return compensate(token: reserved, receipt: receipt, fallback: .invalidOrder(error))
    } catch let error as OrderAlreadyShipped {
      return compensate(
        token: reserved,
        receipt: receipt,
        fallback: .invalidOrder(InvalidOrder(error.description))
      )
    } catch {
      return compensate(
        token: reserved,
        receipt: receipt,
        fallback: .invalidOrder(InvalidOrder("pay failed"))
      )
    }

    switch repository.save(paid, expectedVersion: 0) {
    case .failure(let conflict):
      return compensate(
        token: reserved,
        receipt: receipt,
        fallback: .persistenceConflict(conflict)
      )
    case .success(let saved):
      repository.rememberIdempotency(
        key: idempotencyKey,
        fingerprint: fingerprint,
        order: saved
      )
      return .success(saved)
    }
  }

  private func releaseOrFail(
    _ token: ReservationToken,
    _ declined: PaymentDeclined
  ) -> Result<Order, PlaceOrderFailure> {
    switch inventory.release(token: token) {
    case .failure(let failure):
      return .failure(.compensationFailure(failure))
    case .success(()):
      return .failure(.paymentDeclined(declined))
    }
  }

  private func compensate(
    token: ReservationToken,
    receipt: ChargeReceipt,
    fallback: PlaceOrderFailure
  ) -> Result<Order, PlaceOrderFailure> {
    if case .failure(let failure) = payments.refund(receipt) {
      return .failure(.compensationFailure(failure))
    }
    if case .failure(let failure) = inventory.release(token: token) {
      return .failure(.compensationFailure(failure))
    }
    return .failure(fallback)
  }

  static func fingerprint(_ lines: [OrderLine]) -> String {
    lines.map { line in
      let sku = line.sku.code
      let qty = line.quantity.value
      let currency = line.unitPrice.currency
      let units = line.unitPrice.minorUnits
      return "\(sku):\(qty):\(currency):\(units)"
    }.joined(separator: "|")
  }
}
