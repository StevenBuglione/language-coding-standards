import Dispatch

/// PaymentProcessor test double that records every charge attempt.
public final class FakePaymentProcessor: PaymentProcessor, @unchecked Sendable {
  private let queue = DispatchQueue(label: "warehouse.payments")
  private let decline: Bool
  private var receipts: [String: Result<ChargeReceipt, PaymentDeclined>] = [:]
  public private(set) var chargedOrders: [Order] = []
  public private(set) var refunded: [ChargeReceipt] = []
  public var failRefund = false

  public init(decline: Bool = false) {
    self.decline = decline
  }

  public func charge(
    _ order: Order,
    idempotencyKey: String
  ) -> Result<ChargeReceipt, PaymentDeclined> {
    queue.sync {
      if let existing = receipts[idempotencyKey] {
        return existing
      }
      chargedOrders.append(order)
      if decline {
        let declined = PaymentDeclined("payment declined for order \(order.id.value)")
        receipts[idempotencyKey] = .failure(declined)
        return .failure(declined)
      }
      let receipt = ChargeReceipt(orderId: order.id, idempotencyKey: idempotencyKey)
      receipts[idempotencyKey] = .success(receipt)
      return .success(receipt)
    }
  }

  public func refund(_ receipt: ChargeReceipt) -> Result<Void, CompensationFailure> {
    queue.sync {
      if failRefund {
        return .failure(CompensationFailure(stage: "refund", detail: "forced failure"))
      }
      refunded.append(receipt)
      return .success(())
    }
  }
}
