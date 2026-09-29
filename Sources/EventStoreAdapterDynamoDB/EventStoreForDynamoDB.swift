import AsyncAlgorithms
public import Configuration
public import EventStoreAdapter
import Foundation
public import Logging
public import SotoDynamoDB

/// A DynamoDB-backed event store for events and aggregate snapshots.
///
/// The store writes events to a journal table and keeps one current snapshot
/// record per aggregate in a snapshot table. Both tables use `aid_pkey` (String)
/// as their partition key. Only the journal has a sort key: `seq_nr` (Number).
/// Events and snapshots are read directly with strongly consistent reads; secondary
/// indexes are not required. The library does not create or validate this schema.
///
/// Each aggregate's partition key is `<AID.name>-<aid.description>`. Type names
/// and ID descriptions must be stable, and their hyphen-joined keys must be
/// unambiguous across aggregate types sharing a table. Neither component is
/// escaped. The default serializers store event and snapshot bytes as DynamoDB
/// binary attributes. Use the
/// custom serializers when the table contains a different wire format, and
/// keep them compatible with all records that must remain readable.
///
/// Writes that include a snapshot use one DynamoDB transaction. A creation
/// event (`seqNr == 1`) inserts the initial snapshot with version `1`. The
/// snapshot's `last_committed_seq_nr` and `applied_seq_nr` both store the event's
/// sequence number. Later events update that same snapshot record only when
/// its stored version equals the supplied
/// snapshot version, then persist the event and the incremented snapshot
/// version atomically.
///
/// The current implementation does not implement
/// ``EventStoreForDynamoDB/persistEvent(event:version:)``; calling it traps.
/// Event reads return one query page.
public struct EventStoreForDynamoDB<
  EventEnvelope: EventStoreAdapter.EventEnvelopeProtocol,
  SnapshotEnvelope: EventStoreAdapter.SnapshotEnvelopeProtocol,
>: EventStoreAdapter.EventStore where SnapshotEnvelope.AID == EventEnvelope.AID {
  /// The default journal table name, `journal`.
  public static var defaultJournalTableName: String { "journal" }

  /// The default snapshot table name, `snapshot`.
  public static var defaultSnapshotTableName: String { "snapshot" }

  /// The logger used for DynamoDB requests.
  public var logger: Logger

  /// The Soto DynamoDB service client used for all reads and writes.
  ///
  /// The event store does not manage the lifecycle of the underlying AWS
  /// client. The caller is responsible for shutting it down when it is no
  /// longer needed.
  public var dynamoDB: DynamoDB

  /// The DynamoDB table that stores journal events.
  public var journalTableName: String

  /// The DynamoDB table that stores the current snapshot for each aggregate.
  public var snapshotTableName: String

  /// The serializer used for journal event envelopes.
  public var eventSerializer: EventEnvelopeSerializer<EventEnvelope>

  /// The serializer used for snapshot envelopes.
  public var snapshotSerializer: SnapshotEnvelopeSerializer<SnapshotEnvelope>

  /// The aggregate ID type shared by `EventEnvelope` and `SnapshotEnvelope`.
  public typealias AID = SnapshotEnvelope.AID

  /// Creates a DynamoDB event store with explicit serializers.
  ///
  /// - Parameters:
  ///   - logger: The logger passed to Soto DynamoDB operations.
  ///   - dynamoDB: The configured Soto DynamoDB service client.
  ///   - journalTableName: The journal table name. Uses ``defaultJournalTableName`` when `nil`.
  ///   - snapshotTableName: The snapshot table name. Uses ``defaultSnapshotTableName`` when `nil`.
  ///   - eventSerializer: The event envelope serializer.
  ///   - snapshotSerializer: The snapshot envelope serializer.
  ///
  /// Both tables must already exist with a string partition key named `aid_pkey`.
  /// The journal must have a numeric sort key named `seq_nr`, and the snapshot
  /// table must have no sort key. This initializer does not perform a schema check.
  /// The event and snapshot serializers must be able to read any existing
  /// records that this store will query.
  public init(
    logger: Logger,
    dynamoDB: DynamoDB,
    journalTableName: String? = nil,
    snapshotTableName: String? = nil,
    eventSerializer: EventEnvelopeSerializer<EventEnvelope>,
    snapshotSerializer: SnapshotEnvelopeSerializer<SnapshotEnvelope>,
  ) {
    self.logger = logger
    self.dynamoDB = dynamoDB
    self.journalTableName = journalTableName ?? Self.defaultJournalTableName
    self.snapshotTableName = snapshotTableName ?? Self.defaultSnapshotTableName
    self.eventSerializer = eventSerializer
    self.snapshotSerializer = snapshotSerializer
  }

  /// Creates a DynamoDB event store from a configuration reader with explicit serializers.
  ///
  /// Reads `journal.table.name` and `snapshot.table.name` from the reader.
  /// Missing values fall back to
  /// ``defaultJournalTableName`` and ``defaultSnapshotTableName``.
  /// The table names are read once during initialization.
  ///
  /// - Parameters:
  ///   - logger: The logger passed to Soto DynamoDB operations.
  ///   - dynamoDB: The configured Soto DynamoDB service client.
  ///   - config: The configuration reader for table names.
  ///   - eventSerializer: The event envelope serializer.
  ///   - snapshotSerializer: The snapshot envelope serializer.
  public init(
    logger: Logger,
    dynamoDB: DynamoDB,
    config: ConfigReader,
    eventSerializer: EventEnvelopeSerializer<EventEnvelope>,
    snapshotSerializer: SnapshotEnvelopeSerializer<SnapshotEnvelope>,
  ) {
    self.init(
      logger: logger,
      dynamoDB: dynamoDB,
      journalTableName: config.string(forKey: "journal.table.name"),
      snapshotTableName: config.string(forKey: "snapshot.table.name"),
      eventSerializer: eventSerializer,
      snapshotSerializer: snapshotSerializer,
    )
  }

  /// Persists an event without updating a snapshot.
  ///
  /// This operation is not implemented in the current release and traps when
  /// called. Use ``EventStoreForDynamoDB/persistEventAndSnapshot(event:snapshot:)``
  /// when the event and its snapshot can be written together, or provide a
  /// different `EventStore` implementation for event-only writes.
  ///
  /// - Parameters:
  ///   - event: The event that would be persisted.
  ///   - version: The expected aggregate version for optimistic concurrency.
  ///     It is currently not evaluated because this operation is unavailable.
  /// - Warning: This operation is unavailable and traps when called.
  /// - Throws: This method does not throw a recoverable error; it terminates by
  ///   trapping before it can throw.
  public func persistEvent(event: EventEnvelope, version: Int) async throws {
    fatalError("unimplemented persistEvent")
  }

  /// Persists an event and its corresponding snapshot in one DynamoDB transaction.
  ///
  /// The event and snapshot must describe the same aggregate, and the event's
  /// `seqNr` must equal the snapshot's `appliedSeqNr`. The adapter serializes
  /// both values before issuing the transaction.
  /// If either serializer fails, no write is attempted and the error is
  /// wrapped as `EventStoreWriteError.serializationError`.
  ///
  /// For a creation event (`event.seqNr == 1`), the adapter conditionally
  /// inserts the snapshot row with `version == 1` and the event row at the
  /// event's sequence number. Both `last_committed_seq_nr` and `applied_seq_nr`
  /// store `event.seqNr`. For every other sequence number, it conditionally
  /// updates the existing snapshot row when
  /// its stored `version` equals `snapshot.version`, writes the event row, and
  /// stores the snapshot with version `snapshot.version + 1`. Both operations
  /// are committed atomically.
  /// The update path does not independently verify that the event sequence
  /// number immediately follows the last stored event; the caller must supply
  /// a valid next sequence number.
  ///
  /// The optimistic check covers the snapshot version and the absence of the
  /// event item's primary key. A transaction cancellation with a
  /// `ConditionalCheckFailed` reason is reported as
  /// `EventStoreWriteError.optimisticLockError`. Supplying a stale
  /// snapshot or an event whose key is already present therefore fails rather
  /// than overwriting data. A different DynamoDB failure is reported as
  /// `EventStoreWriteError.IOError`.
  ///
  /// Both rows retain `aggregate_name` and the original `aid` independently of
  /// the partition key. The snapshot's `last_updated_at` is the event's
  /// occurrence time in Unix epoch milliseconds, rounded down. The serialized
  /// snapshot's `lastUpdatedAt` is retained as supplied by the caller.
  ///
  /// - Parameters:
  ///   - event: The event to persist. Its `aid` and `seqNr` must match the
  ///     snapshot's `aid` and `appliedSeqNr`. A sequence number of `1` selects
  ///     creation behavior; other values select update behavior.
  ///   - snapshot: The aggregate snapshot at the event's sequence number. Its
  ///     `version` is the expected stored snapshot version for an update and
  ///     is replaced by the incremented version in the persisted copy. For a
  ///     creation event, the supplied version is ignored and `1` is persisted.
  ///
  /// - Throws: `EventStoreWriteError.otherError` when aggregate IDs or sequence
  ///   numbers differ, or when the event date cannot be represented as an
  ///   `Int64` Unix epoch timestamp in milliseconds. It also wraps serializer
  ///   and DynamoDB transaction failures as described above.
  public func persistEventAndSnapshot(event: EventEnvelope, snapshot: SnapshotEnvelope) async throws {
    guard event.aid == snapshot.aid else {
      throw EventStoreWriteError.otherError("event and snapshot aggregate IDs do not match")
    }
    guard event.seqNr == snapshot.appliedSeqNr else {
      throw EventStoreWriteError.otherError("event and snapshot sequence numbers do not match")
    }
    guard let occurredAtMilliseconds = unixTimestampMilliseconds(event.occurredAt) else {
      throw EventStoreWriteError.otherError(
        "event occurrence date cannot be represented as Unix timestamp milliseconds"
      )
    }

    let isInitialEvent = event.seqNr == 1
    var persistedSnapshot = snapshot
    persistedSnapshot.version = isInitialEvent ? 1 : snapshot.version + 1

    async let eventSerializing = eventSerializer.serialize(event)
    async let snapshotSerializing = snapshotSerializer.serialize(persistedSnapshot)

    let eventPayload: Data
    let snapshotPayload: Data
    do {
      eventPayload = try await eventSerializing
      snapshotPayload = try await snapshotSerializing
    } catch {
      throw EventStoreWriteError.serializationError(error)
    }

    let snapshotTransactItem: DynamoDB.TransactWriteItem =
      if isInitialEvent {
        .put(
          .init(
            conditionExpression: "attribute_not_exists(aid_pkey)",
            item: [
              "aid_pkey": .s(resolveAIDPartitionKey(aid: event.aid)),
              "aggregate_name": .s(AID.name),
              "aid": .s(event.aid.description),
              "last_committed_seq_nr": .n(String(event.seqNr)),
              "applied_seq_nr": .n(String(snapshot.appliedSeqNr)),
              "payload": .b(.data(snapshotPayload)),
              "version": .n("1"),
              "last_updated_at": .n(String(occurredAtMilliseconds)),
            ],
            tableName: snapshotTableName,
          )
        )
      } else {
        .update(
          .init(
            conditionExpression: "#version = :before_version",
            expressionAttributeNames: [
              "#payload": "payload",
              "#last_committed_seq_nr": "last_committed_seq_nr",
              "#applied_seq_nr": "applied_seq_nr",
              "#version": "version",
              "#last_updated_at": "last_updated_at",
            ],
            expressionAttributeValues: [
              ":payload": .b(.data(snapshotPayload)),
              ":last_committed_seq_nr": .n(String(event.seqNr)),
              ":applied_seq_nr": .n(String(snapshot.appliedSeqNr)),
              ":before_version": .n(String(snapshot.version)),
              ":after_version": .n(String(snapshot.version + 1)),
              ":last_updated_at": .n(String(occurredAtMilliseconds)),
            ],
            key: [
              "aid_pkey": .s(resolveAIDPartitionKey(aid: event.aid))
            ],
            tableName: snapshotTableName,
            updateExpression:
              "SET #last_committed_seq_nr = :last_committed_seq_nr, #applied_seq_nr = :applied_seq_nr, #payload = :payload, #version = :after_version, #last_updated_at = :last_updated_at",
          )
        )
      }
    do {
      _ = try await dynamoDB.transactWriteItems(
        .init(
          transactItems: [
            snapshotTransactItem,
            .put(
              .init(
                conditionExpression: "attribute_not_exists(aid_pkey) AND attribute_not_exists(seq_nr)",
                item: [
                  "aid_pkey": .s(resolveAIDPartitionKey(aid: event.aid)),
                  "aggregate_name": .s(AID.name),
                  "aid": .s(event.aid.description),
                  "seq_nr": .n(String(event.seqNr)),
                  "payload": .b(.data(eventPayload)),
                  "occurred_at": .n(String(occurredAtMilliseconds)),
                ],
                tableName: journalTableName,
              )
            ),
          ]
        ),
        logger: logger,
      )
    } catch let error as DynamoDBErrorType where isOptimisticLockError(error) {
      throw EventStoreWriteError.optimisticLockError(error)
    } catch {
      throw EventStoreWriteError.IOError(error)
    }
  }

  /// Reads the current snapshot for an aggregate ID.
  ///
  /// Snapshots are stored as one row per aggregate, addressed by `aid_pkey`
  /// alone. This method uses a strongly consistent `GetItem`, deserializes the
  /// binary `payload`, and restores `version` from its stored numeric
  /// attribute. The snapshot's `appliedSeqNr` comes from the deserialized
  /// envelope.
  ///
  /// The method returns `nil` when the primary key has no matching row. It does not
  /// reconstruct a snapshot from journal events.
  ///
  /// - Parameter aid: The aggregate ID to look up.
  /// - Returns: The snapshot available for `aid`, or `nil` when no matching
  ///   snapshot is available in the configured table.
  /// - Throws: `EventStoreReadError.IOError` when the DynamoDB request fails;
  ///   `EventStoreReadError.otherError` when the item has no binary payload or
  ///   has a missing or invalid numeric version; or
  ///   `EventStoreReadError.deserializationError` when the snapshot serializer
  ///   cannot decode the payload.
  public func getLatestSnapshotByAID(aid: AID) async throws -> SnapshotEnvelope? {
    let output: DynamoDB.GetItemOutput
    do {
      output = try await dynamoDB.getItem(
        .init(
          consistentRead: true,
          key: [
            "aid_pkey": .s(resolveAIDPartitionKey(aid: aid))
          ],
          tableName: snapshotTableName,
        ),
        logger: logger,
      )
    } catch {
      throw EventStoreReadError.IOError(error)
    }

    guard let item = output.item else {
      return nil
    }
    guard case .b(let binary)? = item["payload"], let payloadData = binary.decoded().map(Data.init(_:)) else {
      throw EventStoreReadError.otherError("snapshot payload is missing")
    }
    guard case .n(let versionValue)? = item["version"] else {
      throw EventStoreReadError.otherError("snapshot version is missing")
    }
    guard let version = Int(versionValue) else {
      throw EventStoreReadError.otherError("snapshot version is invalid")
    }

    var snapshot: SnapshotEnvelope
    do {
      snapshot = try await snapshotSerializer.deserialize(payloadData)
    } catch {
      throw EventStoreReadError.deserializationError(error)
    }
    snapshot.version = version
    return snapshot
  }

  /// Reads events for an aggregate from an inclusive sequence number.
  ///
  /// The method queries the journal table with strongly consistent reads.
  /// The partition key is `<AID.name>-<aid.description>`.
  /// The numeric `seq_nr` sort key provides the inclusive lower bound and
  /// ascending sequence-number order without string padding.
  /// The partition key identifies the aggregate, so no `aid` filter is needed.
  ///
  /// The method returns one query page, subject to DynamoDB's 1 MB limit.
  ///
  /// A missing, non-binary, or invalid payload aborts the entire read rather
  /// than skipping that item.
  ///
  /// - Parameters:
  ///   - aid: The aggregate ID whose events are requested.
  ///   - seqNr: The inclusive lower bound for the event sequence number.
  ///     Used directly as a DynamoDB Number.
  /// - Returns: Matching decoded events from the first query page in ascending
  ///   sequence-number order, or an empty array when no events match.
  /// - Throws: `EventStoreReadError.IOError` when the DynamoDB query fails;
  ///   `EventStoreReadError.otherError` when an item has a missing, non-binary,
  ///   or invalid Base64 payload; or
  ///   `EventStoreReadError.deserializationError` when an event serializer
  ///   cannot decode a payload.
  public func getEventsByAIDSinceSequenceNumber(aid: AID, seqNr: Int) async throws -> [EventEnvelope] {
    let output: DynamoDB.QueryOutput
    do {
      output = try await dynamoDB.query(
        .init(
          consistentRead: true,
          expressionAttributeNames: [
            "#aid_pkey": "aid_pkey",
            "#seq_nr": "seq_nr",
          ],
          expressionAttributeValues: [
            ":aid_pkey": .s(resolveAIDPartitionKey(aid: aid)),
            ":seq_nr": .n(String(seqNr)),
          ],
          keyConditionExpression: "#aid_pkey = :aid_pkey AND #seq_nr >= :seq_nr",
          tableName: journalTableName,
        ),
        logger: logger,
      )
    } catch {
      throw EventStoreReadError.IOError(error)
    }

    var events: [EventEnvelope] = []
    for item in output.items ?? [] {
      guard let payload = item["payload"] else {
        throw EventStoreReadError.otherError("event payload is missing")
      }
      guard case .b(let binary) = payload else {
        throw EventStoreReadError.otherError("event payload is not binary")
      }
      guard let payloadData = binary.decoded().map(Data.init(_:)) else {
        throw EventStoreReadError.otherError("event payload is not valid Base64-encoded data")
      }
      do {
        events.append(try await eventSerializer.deserialize(payloadData))
      } catch {
        throw EventStoreReadError.deserializationError(error)
      }
    }
    return events
  }
}

func isOptimisticLockError(_ error: DynamoDBErrorType) -> Bool {
  if error == .transactionCanceledException,
    let context = error.context,
    let extendedError = context.extendedError as? DynamoDB.TransactionCanceledException,
    let reasons = extendedError.cancellationReasons,
    reasons.contains(where: { $0.code == "ConditionalCheckFailed" })
  {
    true
  } else {
    false
  }
}

extension EventStoreForDynamoDB where EventEnvelope: Codable, SnapshotEnvelope: Codable {
  /// Creates a DynamoDB event store using sorted-key JSON for events and snapshots.
  ///
  /// This convenience initializer is available when both generic types conform
  /// to `Codable`. It uses the default
  /// ``EventEnvelopeSerializer/json(encoder:decoder:)`` and ``SnapshotEnvelopeSerializer/json()``
  /// implementations, including Foundation's default coding strategies. Use
  /// the designated initializer when either persisted format requires custom
  /// encoding.
  ///
  /// - Parameters:
  ///   - logger: The logger passed to Soto DynamoDB operations.
  ///   - dynamoDB: The configured Soto DynamoDB service client.
  ///   - journalTableName: The journal table name. Uses ``defaultJournalTableName`` when `nil`.
  ///   - snapshotTableName: The snapshot table name. Uses ``defaultSnapshotTableName`` when `nil`.
  public init(
    logger: Logger,
    dynamoDB: DynamoDB,
    journalTableName: String? = nil,
    snapshotTableName: String? = nil,
  ) {
    self.init(
      logger: logger,
      dynamoDB: dynamoDB,
      journalTableName: journalTableName,
      snapshotTableName: snapshotTableName,
      eventSerializer: .json(),
      snapshotSerializer: .json(),
    )
  }

  /// Creates a store from a configuration reader using sorted-key JSON for events and snapshots.
  ///
  /// Missing table names use ``defaultJournalTableName`` and ``defaultSnapshotTableName``.
  ///
  /// - Parameters:
  ///   - logger: The logger passed to Soto DynamoDB operations.
  ///   - dynamoDB: The configured Soto DynamoDB service client.
  ///   - config: The reader for `journal.table.name` and `snapshot.table.name`.
  public init(
    logger: Logger,
    dynamoDB: DynamoDB,
    config: ConfigReader,
  ) {
    self.init(
      logger: logger,
      dynamoDB: dynamoDB,
      config: config,
      eventSerializer: .json(),
      snapshotSerializer: .json(),
    )
  }
}

extension EventStoreForDynamoDB where SnapshotEnvelope: Codable {
  /// Creates a DynamoDB event store using sorted-key JSON for snapshots.
  ///
  /// This initializer leaves event serialization to the supplied
  /// `eventSerializer` and uses ``SnapshotEnvelopeSerializer/json()`` for snapshots.
  /// The JSON serializer uses Foundation's default coding strategies and
  /// requests sorted JSON object keys.
  ///
  /// - Parameters:
  ///   - logger: The logger passed to Soto DynamoDB operations.
  ///   - dynamoDB: The configured Soto DynamoDB service client.
  ///   - journalTableName: The journal table name. Uses ``defaultJournalTableName`` when `nil`.
  ///   - snapshotTableName: The snapshot table name. Uses ``defaultSnapshotTableName`` when `nil`.
  ///   - eventSerializer: The serializer for event envelopes.
  public init(
    logger: Logger,
    dynamoDB: DynamoDB,
    journalTableName: String? = nil,
    snapshotTableName: String? = nil,
    eventSerializer: EventEnvelopeSerializer<EventEnvelope>,
  ) {
    self.init(
      logger: logger,
      dynamoDB: dynamoDB,
      journalTableName: journalTableName,
      snapshotTableName: snapshotTableName,
      eventSerializer: eventSerializer,
      snapshotSerializer: .json(),
    )
  }

  /// Creates a store from a configuration reader using sorted-key JSON for snapshots.
  ///
  /// Missing table names use ``defaultJournalTableName`` and ``defaultSnapshotTableName``.
  /// Event serialization uses the supplied `eventSerializer`.
  ///
  /// - Parameters:
  ///   - logger: The logger passed to Soto DynamoDB operations.
  ///   - dynamoDB: The configured Soto DynamoDB service client.
  ///   - config: The reader for `journal.table.name` and `snapshot.table.name`.
  ///   - eventSerializer: The serializer for event envelopes.
  public init(
    logger: Logger,
    dynamoDB: DynamoDB,
    config: ConfigReader,
    eventSerializer: EventEnvelopeSerializer<EventEnvelope>,
  ) {
    self.init(
      logger: logger,
      dynamoDB: dynamoDB,
      config: config,
      eventSerializer: eventSerializer,
      snapshotSerializer: .json(),
    )
  }
}

extension EventStoreForDynamoDB where EventEnvelope: Codable {
  /// Creates a DynamoDB event store using sorted-key JSON for events.
  ///
  /// This initializer uses ``EventEnvelopeSerializer/json(encoder:decoder:)`` for
  /// events and leaves snapshot serialization to the supplied
  /// `snapshotSerializer`. The JSON serializer uses Foundation's default
  /// coding strategies and requests sorted JSON object keys.
  ///
  /// - Parameters:
  ///   - logger: The logger passed to Soto DynamoDB operations.
  ///   - dynamoDB: The configured Soto DynamoDB service client.
  ///   - journalTableName: The journal table name. Uses ``defaultJournalTableName`` when `nil`.
  ///   - snapshotTableName: The snapshot table name. Uses ``defaultSnapshotTableName`` when `nil`.
  ///   - snapshotSerializer: The serializer for snapshot envelopes.
  public init(
    logger: Logger,
    dynamoDB: DynamoDB,
    journalTableName: String? = nil,
    snapshotTableName: String? = nil,
    snapshotSerializer: SnapshotEnvelopeSerializer<SnapshotEnvelope>,
  ) {
    self.init(
      logger: logger,
      dynamoDB: dynamoDB,
      journalTableName: journalTableName,
      snapshotTableName: snapshotTableName,
      eventSerializer: .json(),
      snapshotSerializer: snapshotSerializer,
    )
  }

  /// Creates a store from a configuration reader using sorted-key JSON for events.
  ///
  /// Missing table names use ``defaultJournalTableName`` and ``defaultSnapshotTableName``.
  /// Snapshot serialization uses the supplied `snapshotSerializer`.
  ///
  /// - Parameters:
  ///   - logger: The logger passed to Soto DynamoDB operations.
  ///   - dynamoDB: The configured Soto DynamoDB service client.
  ///   - config: The reader for `journal.table.name` and `snapshot.table.name`.
  ///   - snapshotSerializer: The serializer for snapshot envelopes.
  public init(
    logger: Logger,
    dynamoDB: DynamoDB,
    config: ConfigReader,
    snapshotSerializer: SnapshotEnvelopeSerializer<SnapshotEnvelope>,
  ) {
    self.init(
      logger: logger,
      dynamoDB: dynamoDB,
      config: config,
      eventSerializer: .json(),
      snapshotSerializer: snapshotSerializer,
    )
  }
}
