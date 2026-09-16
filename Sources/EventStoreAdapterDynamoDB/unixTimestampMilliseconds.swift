import Foundation

internal func unixTimestampMilliseconds(_ date: Date) -> Int64? {
  Int64(exactly: (date.timeIntervalSince1970 * 1_000).rounded(.down))
}
