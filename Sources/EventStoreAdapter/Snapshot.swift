public import Foundation

/// A materialized view of an aggregate's state at a point in its event history.
///
/// A snapshot is associated with an aggregate ID and records the sequence number
/// of the latest event represented by its payload. The event store may use
/// `version` to detect concurrent updates and `lastUpdatedAt` to retain the
/// snapshot's update time.
///
/// - Important: Implement snapshots as structs with value semantics. Class-based
///   conformances are unsupported, even though Swift permits them: protocols
///   cannot restrict conformance to structs. Modifying a copy must not change the
///   original snapshot. Using a struct alone is not sufficient if its copies
///   share mutable reference state; the snapshot must preserve value semantics,
///   including for its payload and version.
public protocol Snapshot<Payload, AID>: Swift.Sendable, Swift.Hashable {
  /// The type of the aggregate state held by the snapshot.
  associatedtype Payload: Swift.Sendable, Swift.Hashable

  /// The type of aggregate ID associated with the snapshot.
  associatedtype AID: EventStoreAdapter.AggregateId

  /// The aggregate state represented by the snapshot.
  var payload: Payload { get }

  /// The ID of the aggregate represented by the snapshot.
  var aid: AID { get }

  /// The sequence number of the latest event represented by the snapshot.
  var seqNr: Swift.Int { get }

  /// The optimistic-concurrency version of the snapshot.
  ///
  /// The event store may update this value as it persists a newer snapshot. A
  /// caller should use the version read from the latest snapshot when attempting
  /// a subsequent write.
  var version: Swift.Int { get set }

  /// The date and time at which the snapshot was last updated.
  var lastUpdatedAt: Foundation.Date { get }
}
