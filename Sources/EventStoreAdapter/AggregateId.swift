/// A stable identifier for an aggregate.
///
/// An aggregate ID can be used across concurrency domains and can be converted to
/// and from its lossless string representation. When an implementation uses that
/// representation in storage keys, it should be canonical and stable over the
/// lifetime of the persisted data.
///
/// `AggregateId` does not require `Codable`. A store can choose a serializer that
/// matches the representation of its events and snapshots.
public protocol AggregateId: Sendable, Hashable, LosslessStringConvertible {
  /// The stable name of the aggregate type.
  ///
  /// Stores may use this name when deriving partition and sort keys. Choose a
  /// value that is unique within the store's key space and keep it unchanged for
  /// as long as the corresponding data is retained.
  static var name: String { get }
}
