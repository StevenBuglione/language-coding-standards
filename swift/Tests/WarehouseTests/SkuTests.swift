import Testing
import Warehouse

@Suite("Sku")
struct SkuTests {
  @Test func trimsSurroundingWhitespace() throws {
    #expect(try Sku("  ABC-1  ").code == "ABC-1")
  }

  @Test func trimsTabCrLf() throws {
    #expect(try Sku(" \tSKU-A\r\n ").code == "SKU-A")
  }

  @Test func rejectsBlankAfterTrim() {
    expectInvalidOrder({ _ = try Sku("   ") }, contains: "non-empty")
  }

  @Test func rejectsEmptyString() {
    expectInvalidOrder({ _ = try Sku("") }, contains: "non-empty")
  }

  @Test func preservesNbspPrefix() throws {
    #expect(try Sku("\u{00a0}ABC").code == "\u{00a0}ABC")
  }

  @Test func preservesInteriorTextAndCase() throws {
    #expect(try Sku("sku-a").code == "sku-a")
    #expect(try Sku("SKU A").code == "SKU A")
  }

  @Test func rejectsOverByteLimit() {
    expectInvalidOrder({ _ = try Sku(String(repeating: "A", count: 65)) }, contains: "UTF-8 bytes")
  }

  @Test func acceptsMaxUtf8Bytes() throws {
    let code = String(repeating: "A", count: skuMaxUtf8Bytes)
    #expect(try Sku(code).code == code)
  }
}
