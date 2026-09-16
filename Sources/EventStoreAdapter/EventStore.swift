/// A concurrency-safe abstraction for storing an aggregate's events and snapshots.
///
/// An event store persists events, optionally alongside the snapshot that results
/// from applying an event, and provides the reads needed to rebuild aggregate
/// state. A conforming implementation chooses how values are serialized and how
/// they are stored.
///
/// Callers should supply an event and snapshot to
/// ``persistEventAndSnapshot(event:snapshot:)`` that represent the same aggregate
/// and sequence number. For a new aggregate, use its creation event and its
/// initial snapshot at sequence number `1` by convention. A conforming store
/// defines how it validates these relationships.
public protocol EventStore<Event, Snapshot>: Swift.Sendable {
  /// The event type stored by this event store.
  associatedtype Event: EventStoreAdapter.Event

  /// The snapshot type stored by this event store.
  associatedtype Snapshot: EventStoreAdapter.Snapshot
  where Snapshot.AID == Event.AID

  /// The aggregate ID type shared by the event and snapshot types.
  typealias AID = Snapshot.AID

  /// Persists an event for an existing aggregate.
  ///
  /// Pass the version read from the current snapshot. Implementations can use
  /// that value as an optimistic-concurrency token and reject the write when the
  /// aggregate has changed since it was read.
  ///
  /// - Parameters:
  ///   - event: The event to persist.
  ///   - version: The caller's current snapshot version.
  /// - Throws: ``EventStoreWriteError`` when the event cannot be persisted.
  func persistEvent(event: Event, version: Swift.Int) async throws

  /// Persists an event together with the snapshot produced after applying it.
  ///
  /// Use this operation when creating an aggregate or when a write should update
  /// the snapshot and append its event as one logical operation. The event and
  /// snapshot should have equal aggregate IDs and equal sequence numbers.
  ///
  /// - Parameters:
  ///   - event: The event to persist.
  ///   - snapshot: The aggregate state after applying `event`.
  /// - Throws: ``EventStoreWriteError`` when either value cannot be persisted.
  func persistEventAndSnapshot(event: Event, snapshot: Snapshot) async throws

  /// Returns the latest snapshot for an aggregate.
  ///
  /// - Parameter aid: The ID of the aggregate to look up.
  /// - Returns: The latest snapshot available to the read, or `nil` when no
  ///   snapshot is available for `aid`.
  /// - Throws: ``EventStoreReadError`` when the snapshot cannot be read or decoded.
  func getLatestSnapshotByAID(aid: AID) async throws -> Snapshot?

  /// Returns an aggregate's events starting at a sequence number.
  ///
  /// The lower bound is inclusive. To replay the events after a snapshot, pass
  /// `snapshot.seqNr + 1` as `seqNr`. Conforming stores are expected to return
  /// results in ascending sequence-number order.
  ///
  /// - Parameters:
  ///   - aid: The ID of the aggregate to read.
  ///   - seqNr: The first sequence number to include.
  /// - Returns: Events for `aid` whose sequence numbers are greater than or equal
  ///   to `seqNr`.
  /// - Throws: ``EventStoreReadError`` when the events cannot be read or decoded.
  func getEventsByAIDSinceSequenceNumber(aid: AID, seqNr: Swift.Int) async throws -> [Event]
}
