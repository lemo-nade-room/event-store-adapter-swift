public import struct Foundation.UUID

/// Adds lossless string conversion to Foundation's `UUID` type.
///
/// This conformance allows `UUID` to satisfy the `LosslessStringConvertible`
/// requirement on an event's identifier type.
extension UUID: @retroactive LosslessStringConvertible {
  /// Creates a UUID from its string representation.
  ///
  /// The initializer fails when `description` is not a valid UUID string.
  ///
  /// - Parameter description: A string accepted by Foundation's UUID parser.
  public init?(_ description: String) {
    self.init(uuidString: description)
  }
}
