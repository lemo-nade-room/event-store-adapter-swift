public import EventStoreAdapter
public import Foundation

/// Encodes and decodes events stored by a DynamoDB event store.
///
/// The encoded value is stored as the DynamoDB binary `payload` attribute. The
/// serializer therefore defines part of the persistent storage format: keep
/// the encoder and decoder compatible with records that are already stored.
/// The closures are `Sendable` and asynchronous because a custom format may
/// perform work outside the calling task.
public struct EventSerializer<Event: EventStoreAdapter.Event>: Sendable {
  /// Converts an event into the bytes written to DynamoDB.
  ///
  /// If byte-for-byte reproducibility is required, the closure must produce a
  /// deterministic representation for the event. DynamoDB's transaction
  /// conditions still determine whether a retry is accepted, and the closure
  /// must be safe to invoke concurrently.
  public var serialize: @Sendable (Event) async throws -> Foundation.Data

  /// Reconstructs an event from the bytes read from DynamoDB.
  ///
  /// This closure should be the inverse of ``EventSerializer/serialize`` for
  /// every persisted format that the application still supports. A decoding
  /// failure is surfaced by the event store as a read deserialization error.
  /// The closure must be safe to invoke concurrently.
  public var deserialize: @Sendable (Foundation.Data) async throws -> Event

  /// Creates an event serializer from paired encoding and decoding closures.
  ///
  /// - Parameters:
  ///   - serialize: Converts an event to its persisted bytes.
  ///   - deserialize: Reconstructs an event from persisted bytes.
  ///
  /// The two closures are captured without modification. They are expected to
  /// agree on the format and to remain compatible with existing records.
  public init(
    serialize: @escaping @Sendable (Event) async throws -> Foundation.Data,
    deserialize: @escaping @Sendable (Foundation.Data) async throws -> Event,
  ) {
    self.serialize = serialize
    self.deserialize = deserialize
  }
}

extension EventSerializer where Event: Codable {
  /// Creates an event serializer that uses the supplied Foundation JSON coder pair.
  ///
  /// The encoder is updated to include sorted keys before it is captured. This
  /// stabilizes JSON object-key order when the encoded value is otherwise
  /// deterministic; it does not canonicalize every possible `Codable` value.
  /// Other encoder and decoder strategies are preserved, so the pair must be
  /// configured compatibly with one another and with existing records.
  /// Encoding and decoding errors are propagated to the caller.
  ///
  /// - Parameters:
  ///   - encoder: The encoder used for event values. Its `outputFormatting` is
  ///     augmented with `.sortedKeys`.
  ///   - decoder: The decoder used for event values.
  /// - Returns: A serializer configured with the supplied JSON encoder and decoder.
  public static func json(encoder: JSONEncoder = JSONEncoder(), decoder: JSONDecoder = JSONDecoder()) -> Self {
    encoder.outputFormatting.insert(.sortedKeys)
    return .init(
      serialize: encoder.encode,
      deserialize: { try decoder.decode(Event.self, from: $0) },
    )
  }
}
