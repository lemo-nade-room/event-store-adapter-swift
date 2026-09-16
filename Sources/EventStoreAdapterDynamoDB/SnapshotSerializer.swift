public import EventStoreAdapter
public import Foundation

/// Encodes and decodes snapshots stored by a DynamoDB event store.
///
/// The encoded value is stored as the DynamoDB binary `payload` attribute. The
/// serializer therefore defines part of the persistent storage format: keep
/// the encoder and decoder compatible with records that are already stored.
/// The closures are `Sendable` and asynchronous because a custom format may
/// perform work outside the calling task.
public struct SnapshotSerializer<Snapshot: EventStoreAdapter.Snapshot>: Sendable {
  /// Converts a snapshot into the bytes written to DynamoDB.
  ///
  /// If byte-for-byte reproducibility is required, the closure must produce a
  /// deterministic representation for the snapshot. DynamoDB's transaction
  /// conditions still determine whether a retry is accepted, and the closure
  /// must be safe to invoke concurrently.
  public var serialize: @Sendable (Snapshot) async throws -> Data

  /// Reconstructs a snapshot from the bytes read from DynamoDB.
  ///
  /// This closure should be the inverse of ``SnapshotSerializer/serialize``
  /// for every persisted format that the application still supports. A
  /// decoding failure is surfaced by the event store as a read deserialization
  /// error. The closure must be safe to invoke concurrently.
  public var deserialize: @Sendable (Data) async throws -> Snapshot

  /// Creates a snapshot serializer from paired encoding and decoding closures.
  ///
  /// - Parameters:
  ///   - serialize: Converts a snapshot to its persisted bytes.
  ///   - deserialize: Reconstructs a snapshot from persisted bytes.
  ///
  /// The two closures are captured without modification. They are expected to
  /// agree on the format and to remain compatible with existing records.
  public init(
    serialize: @escaping @Sendable (Snapshot) async throws -> Data,
    deserialize: @escaping @Sendable (Data) async throws -> Snapshot,
  ) {
    self.serialize = serialize
    self.deserialize = deserialize
  }
}

extension SnapshotSerializer where Snapshot: Codable {
  /// Creates a snapshot serializer that uses Foundation JSON encoding.
  ///
  /// The encoder requests sorted keys for JSON objects. This stabilizes object
  /// key order when the encoded value is otherwise deterministic; it does not
  /// canonicalize every possible `Codable` value. Date, data, and other values
  /// use the default `JSONEncoder` and `JSONDecoder` strategies. Encoding and
  /// decoding errors are propagated to the caller.
  ///
  /// Use a custom ``SnapshotSerializer/init(serialize:deserialize:)`` when the
  /// stored format requires a different coding strategy or a format such as
  /// Protocol Buffers.
  ///
  /// - Returns: A serializer configured with Foundation's JSON encoder and decoder.
  public static func json() -> Self {
    let encoder = JSONEncoder()
    encoder.outputFormatting.insert(.sortedKeys)
    return .init(
      serialize: { snapshot in
        try encoder.encode(snapshot)
      },
      deserialize: { data in
        try JSONDecoder().decode(Snapshot.self, from: data)
      },
    )
  }
}
