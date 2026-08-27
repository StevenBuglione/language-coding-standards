/// Test double that returns a pinned unix-epoch millisecond instant.
public struct FixedClock: Clock {
  public let instant: Int64

  public init(_ instant: Int64) {
    self.instant = instant
  }

  public func now() -> Int64 {
    instant
  }
}
