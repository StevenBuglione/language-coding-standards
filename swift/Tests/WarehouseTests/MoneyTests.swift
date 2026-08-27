import Testing
import Warehouse

@Suite("Money")
struct MoneyTests {
  @Test func rejectsNegativeAmount() {
    expectInvalidOrder(
      { _ = try Money(minorUnits: -1, currency: "USD") },
      contains: "non-negative"
    )
  }

  @Test func rejectsMalformedCurrency() {
    expectInvalidOrder(
      { _ = try Money(minorUnits: 1, currency: "usd") },
      contains: "currency"
    )
  }

  @Test func addSumsSameCurrency() throws {
    let sum = try usd(150).add(try usd(275))
    #expect(sum == try usd(425))
  }

  @Test func addRejectsCurrencyMismatch() {
    expectInvalidOrder(
      {
        _ = try Money(minorUnits: 100, currency: "USD").add(
          try Money(minorUnits: 100, currency: "EUR")
        )
      },
      contains: "mismatch"
    )
  }

  @Test func timesScalesAmount() throws {
    #expect(try usd(250).times(3) == try usd(750))
  }

  @Test func timesRejectsNegativeMultiplier() {
    expectInvalidOrder(
      { _ = try usd(1).times(-2) },
      contains: "multiplier"
    )
  }

  @Test func equalityIsValueBased() throws {
    #expect(
      try Money(minorUnits: 10, currency: "EUR")
        == Money(minorUnits: 10, currency: "EUR")
    )
  }

  @Test func acceptsIsoStyleZzz() throws {
    #expect(try Money(minorUnits: 0, currency: "ZZZ").currency == "ZZZ")
  }

  @Test func rejectsAboveSharedMaximum() {
    expectInvalidOrder(
      { _ = try Money(minorUnits: moneyMinorUnitsMax + 1, currency: "USD") },
      contains: "exceeds"
    )
  }

  @Test func addRejectsOverflow() {
    expectInvalidOrder(
      {
        let maxMoney = try Money(minorUnits: moneyMinorUnitsMax, currency: "USD")
        _ = try maxMoney.add(try Money(minorUnits: 1, currency: "USD"))
      },
      contains: "overflows"
    )
  }

  @Test func timesZeroIsZero() throws {
    #expect(try usd(250).times(0) == try usd(0))
  }
}
