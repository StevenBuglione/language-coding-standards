/// Shared minor-unit maximum (`2^53 - 1`) so every language pack can represent it.
public let moneyMinorUnitsMax = 9_007_199_254_740_991

/// A non-negative amount in integer minor units of a single currency.
///
/// Currency codes are ISO-style (`^[A-Z]{3}$`), not ISO-4217 membership.
/// `ZZZ` is valid. Cross-currency operations throw `InvalidOrder`.
public struct Money: Equatable, Hashable, Sendable {
  public let minorUnits: Int
  public let currency: String

  public init(minorUnits: Int, currency: String) throws {
    if minorUnits < 0 {
      throw InvalidOrder("money amount must be non-negative, got \(minorUnits)")
    }
    if minorUnits > moneyMinorUnitsMax {
      throw InvalidOrder("money amount exceeds \(moneyMinorUnitsMax), got \(minorUnits)")
    }
    guard isIsoStyleCurrency(currency) else {
      throw InvalidOrder(
        "currency must be a 3-letter uppercase ISO-style code, got \(currency)"
      )
    }
    self.minorUnits = minorUnits
    self.currency = currency
  }

  /// Return the sum of two amounts of the same currency.
  public func add(_ other: Money) throws -> Money {
    try requireSameCurrency(other)
    let (total, overflow) = minorUnits.addingReportingOverflow(other.minorUnits)
    if overflow || total > moneyMinorUnitsMax {
      throw InvalidOrder("money addition overflows the shared maximum")
    }
    return try Money(minorUnits: total, currency: currency)
  }

  /// Return this amount scaled by a non-negative integer multiplier.
  public func times(_ multiplier: Int) throws -> Money {
    if multiplier < 0 {
      throw InvalidOrder("multiplier must be non-negative, got \(multiplier)")
    }
    let (product, overflow) = minorUnits.multipliedReportingOverflow(by: multiplier)
    if overflow || product > moneyMinorUnitsMax {
      throw InvalidOrder("money scaling overflows the shared maximum")
    }
    return try Money(minorUnits: product, currency: currency)
  }

  private func requireSameCurrency(_ other: Money) throws {
    if currency != other.currency {
      throw InvalidOrder("currency mismatch: \(currency) vs \(other.currency)")
    }
  }
}

func isIsoStyleCurrency(_ code: String) -> Bool {
  guard code.utf8.count == 3 else { return false }
  return code.utf8.allSatisfy { byte in byte >= 0x41 && byte <= 0x5A }
}
