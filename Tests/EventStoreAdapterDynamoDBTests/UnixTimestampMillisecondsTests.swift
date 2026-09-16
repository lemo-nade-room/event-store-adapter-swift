import Foundation
import Testing

@testable import EventStoreAdapterDynamoDB

@Suite struct UnixTimestampMillisecondsTests {
  @Test func `Unix epoch produces zero milliseconds`() {
    let date = Date(timeIntervalSince1970: 0)

    let actual = unixTimestampMilliseconds(date)

    #expect(actual == 0)
  }

  @Test func `Elapsed whole seconds are converted to milliseconds`() {
    let date = Date(timeIntervalSince1970: 1_645_557_742)

    let actual = unixTimestampMilliseconds(date)

    #expect(actual == 1_645_557_742_000)
  }

  @Test(arguments: [
    (seconds: 1.9999, expected: 1_999),
    (seconds: -0.0005, expected: -1),
  ])
  func `Timestamps with fractional milliseconds are rounded down`(
    seconds: TimeInterval,
    expected: Int64,
  ) {
    let date = Date(timeIntervalSince1970: seconds)

    let actual = unixTimestampMilliseconds(date)

    #expect(actual == expected)
  }

  @Test(arguments: [
    TimeInterval.nan,
    TimeInterval.infinity,
    -TimeInterval.infinity,
    TimeInterval.greatestFiniteMagnitude,
    -TimeInterval.greatestFiniteMagnitude,
  ])
  func `Timestamps that cannot be represented as Int64 milliseconds produce nil`(seconds: TimeInterval) {
    let date = Date(timeIntervalSince1970: seconds)

    #expect(unixTimestampMilliseconds(date) == nil)
  }
}
