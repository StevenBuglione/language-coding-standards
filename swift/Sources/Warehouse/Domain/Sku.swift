/// Shared UTF-8 byte length limit for a normalized SKU code.
public let skuMaxUtf8Bytes = 64

/// A stock-keeping-unit code, normalized on creation.
public struct Sku: Equatable, Hashable, Sendable, CustomStringConvertible {
  public let code: String

  /// Strip only ASCII space, tab, CR, and LF from both ends, then validate.
  public init(_ code: String) throws {
    let trimmed = trimAsciiEdges(code)
    if trimmed.isEmpty {
      throw InvalidOrder("sku code must be non-empty")
    }
    if trimmed.utf8.count > skuMaxUtf8Bytes {
      throw InvalidOrder("sku code exceeds \(skuMaxUtf8Bytes) UTF-8 bytes")
    }
    self.code = trimmed
  }

  public var description: String { code }
}

func trimAsciiEdges(_ code: String) -> String {
  let edge: Set<Character> = [" ", "\t", "\r", "\n"]
  var start = code.startIndex
  var end = code.endIndex
  while start < end, edge.contains(code[start]) {
    start = code.index(after: start)
  }
  while end > start {
    let previous = code.index(before: end)
    if !edge.contains(code[previous]) {
      break
    }
    end = previous
  }
  return String(code[start..<end])
}
