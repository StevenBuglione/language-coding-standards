import Testing
import Warehouse

@Suite("property")
struct PropertyTests {
  @Test func moneyAdditionIsCommutative() throws {
    let amounts = [0, 1, 17, 250, 1_000_000]
    for left in amounts {
      for right in amounts {
        let a = try Money(minorUnits: left, currency: "USD")
        let b = try Money(minorUnits: right, currency: "USD")
        let leftSum = try a.add(b)
        let rightSum = try b.add(a)
        #expect(leftSum == rightSum)
      }
    }
  }

  @Test func timesZeroIsZero() throws {
    let money = try Money(minorUnits: 300, currency: "EUR")
    let scaled = try money.times(0)
    let expected = try Money(minorUnits: 0, currency: "EUR")
    #expect(scaled == expected)
  }
}
