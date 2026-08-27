/// Shared quantity maximum (`Int32.max`).
public let quantityMax = 2_147_483_647

/// An amount of stock that must be strictly positive.
public struct Quantity: Equatable, Hashable, Sendable {
  public let value: Int

  public init(_ value: Int) throws {
    if value <= 0 {
      throw InvalidOrder("quantity must be strictly positive, got \(value)")
    }
    if value > quantityMax {
      throw InvalidOrder("quantity exceeds \(quantityMax), got \(value)")
    }
    self.value = value
  }
}
