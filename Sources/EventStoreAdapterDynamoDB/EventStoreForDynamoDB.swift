import AsyncAlgorithms
public import EventStoreAdapter
import Foundation
public import Logging
public import SotoDynamoDB

/// A DynamoDB-backed event store for events and aggregate snapshots.
///
/// The store writes events to a journal table and keeps one current snapshot
/// record per aggregate in a snapshot table. Both tables use `pkey` (String)
/// and `skey` (String) as their primary key. Each table also needs the
/// configured aggregate-ID index with `aid` (String) as its partition key and
/// `seq_nr` (Number) as its sort key. The library does not create or validate
/// this schema.
///
/// The default key resolver maps each aggregate ID to one of
/// `config.shardCount` logical shards by hashing it. The default serializers
/// store event and snapshot bytes as DynamoDB binary attributes. Use the
/// custom serializers when the table contains a different wire format, and
/// keep them compatible with all records that must remain readable.
///
/// Writes that include a snapshot use one DynamoDB transaction. A creation
/// event (`seqNr == 1`) inserts the initial snapshot at snapshot `seq_nr == 0`
/// with version `1`. Later events update that same snapshot record only when
/// its stored version equals the supplied snapshot version, then persist the
/// event and the incremented snapshot version atomically.
///
/// The current implementation does not implement
/// ``EventStoreForDynamoDB/persistEvent(event:version:)``; calling it traps.
/// Event reads issue one query and do not follow a `LastEvaluatedKey`, so
/// callers that can accumulate more than one DynamoDB page must account for
/// that limitation before using this release.
public struct EventStoreForDynamoDB<
  Event: EventStoreAdapter.Event,
  Snapshot: EventStoreAdapter.Snapshot,
>: EventStoreAdapter.EventStore where Snapshot.AID == Event.AID {
  /// The logger used for DynamoDB requests.
  public var logger: Logger

  /// The Soto DynamoDB service client used for all reads and writes.
  ///
  /// The event store does not manage the lifecycle of the underlying AWS
  /// client. The caller is responsible for shutting it down when it is no
  /// longer needed.
  public var dynamoDB: DynamoDB

  /// The table names, index names, and shard count used by this store.
  ///
  /// Changing this value after data has been written can make existing items
  /// unreachable or cause requests to target a different schema.
  public var config: EventStoreForDynamoDBConfiguration

  /// The resolver used to derive the DynamoDB primary-key strings.
  ///
  /// It must remain compatible with the resolver used for existing records.
  public var keyResolver: KeyResolver<AID>

  /// The serializer used for journal event payloads.
  public var eventSerializer: EventSerializer<Event>

  /// The serializer used for snapshot payloads.
  public var snapshotSerializer: SnapshotSerializer<Snapshot>

  /// The aggregate ID type shared by `Event` and `Snapshot`.
  public typealias AID = Snapshot.AID

  /// Creates a DynamoDB event store with explicit serializers.
  ///
  /// - Parameters:
  ///   - logger: The logger passed to Soto DynamoDB operations.
  ///   - dynamoDB: The configured Soto DynamoDB service client.
  ///   - config: The table, index, and shard configuration. Defaults to
  ///     ``EventStoreForDynamoDBConfiguration/default``.
  ///   - keyResolver: The primary-key resolver. Defaults to ``KeyResolver``'s
  ///     SHA-256 based resolver.
  ///   - eventSerializer: The event payload serializer.
  ///   - snapshotSerializer: The snapshot payload serializer.
  ///
  /// The referenced tables and GSIs must already exist and match the schema
  /// described by `config`. This initializer does not perform a schema check.
  /// The event and snapshot serializers must be able to read any existing
  /// records that this store will query.
  public init(
    logger: Logger,
    dynamoDB: DynamoDB,
    config: EventStoreForDynamoDBConfiguration = .default,
    keyResolver: KeyResolver<AID> = .init(),
    eventSerializer: EventSerializer<Event>,
    snapshotSerializer: SnapshotSerializer<Snapshot>,
  ) {
    self.logger = logger
    self.dynamoDB = dynamoDB
    self.config = config
    self.keyResolver = keyResolver
    self.eventSerializer = eventSerializer
    self.snapshotSerializer = snapshotSerializer
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
  public func persistEvent(event: Event, version: Int) async throws {
    fatalError("unimplemented persistEvent")
  }

  /// Persists an event and its corresponding snapshot in one DynamoDB transaction.
  ///
  /// The event and snapshot must describe the same aggregate and sequence
  /// number. The adapter serializes both values before issuing the transaction.
  /// If either serializer fails, no write is attempted and the error is
  /// wrapped as `EventStoreWriteError.serializationError`.
  ///
  /// For a creation event (`event.seqNr == 1`), the adapter conditionally
  /// inserts the snapshot row at snapshot `seq_nr == 0` with `version == 1`
  /// and the event row at the event's sequence number. For every other
  /// sequence number, it conditionally updates the existing snapshot row when
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
  /// The initial snapshot item contains a numeric `ttl` attribute set to `0`.
  /// This adapter does not calculate or update an expiration time. DynamoDB
  /// TTL values are Unix epoch timestamps in seconds, and a value of `0` is
  /// the Unix epoch rather than a relative duration. Do not rely on this
  /// placeholder for cleanup; if TTL is enabled for the table, DynamoDB's TTL
  /// rules apply (including its handling of timestamps more than five years in
  /// the past).
  ///
  /// - Parameters:
  ///   - event: The event to persist. Its `aid` and `seqNr` must match the
  ///     snapshot. A sequence number of `1` selects creation behavior; the
  ///     implementation treats other values as update behavior.
  ///   - snapshot: The aggregate snapshot at the event's sequence number. Its
  ///     `version` is the expected stored snapshot version for an update and
  ///     is replaced by the incremented version in the persisted copy. For a
  ///     creation event, the supplied version is ignored and `1` is persisted.
  ///     `Snapshot` does not require value semantics, so if it is a reference
  ///     type, assigning the local copy's version may also mutate the caller's
  ///     instance.
  ///
  /// - Throws: `EventStoreWriteError.otherError` when aggregate IDs or sequence
  ///   numbers differ, or when the event date cannot be represented as an
  ///   `Int64` Unix epoch timestamp in milliseconds. It also wraps serializer
  ///   and DynamoDB transaction failures as described above.
  public func persistEventAndSnapshot(event: Event, snapshot: Snapshot) async throws {
    guard event.aid == snapshot.aid else {
      throw EventStoreWriteError.otherError("event and snapshot aggregate IDs do not match")
    }
    guard event.seqNr == snapshot.seqNr else {
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
            conditionExpression: "attribute_not_exists(pkey) AND attribute_not_exists(skey)",
            item: [
              "pkey": .s(keyResolver.resolvePartitionKey(event.aid, config.shardCount)),
              "skey": .s(keyResolver.resolveSortKey(event.aid, 0)),
              "aid": .s(event.aid.description),
              "seq_nr": .n("0"),
              "payload": .b(.data(snapshotPayload)),
              "version": .n("1"),
              "ttl": .n("0"),
              "last_updated_at": .n(String(occurredAtMilliseconds)),
            ],
            tableName: config.snapshotTableName,
          )
        )
      } else {
        .update(
          .init(
            conditionExpression: "#version = :before_version",
            expressionAttributeNames: [
              "#payload": "payload",
              "#seq_nr": "seq_nr",
              "#version": "version",
              "#last_updated_at": "last_updated_at",
            ],
            expressionAttributeValues: [
              ":payload": .b(.data(snapshotPayload)),
              ":seq_nr": .n("0"),
              ":before_version": .n(String(snapshot.version)),
              ":after_version": .n(String(snapshot.version + 1)),
              ":last_updated_at": .n(String(occurredAtMilliseconds)),
            ],
            key: [
              "pkey": .s(keyResolver.resolvePartitionKey(event.aid, config.shardCount)),
              "skey": .s(keyResolver.resolveSortKey(event.aid, 0)),
            ],
            tableName: config.snapshotTableName,
            updateExpression:
              "SET #seq_nr = :seq_nr, #payload = :payload, #version = :after_version, #last_updated_at = :last_updated_at",
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
                conditionExpression: "attribute_not_exists(pkey) AND attribute_not_exists(skey)",
                item: [
                  "pkey": .s(keyResolver.resolvePartitionKey(event.aid, config.shardCount)),
                  "skey": .s(keyResolver.resolveSortKey(event.aid, event.seqNr)),
                  "aid": .s(event.aid.description),
                  "seq_nr": .n(String(event.seqNr)),
                  "payload": .b(.data(eventPayload)),
                  "occurred_at": .n(String(occurredAtMilliseconds)),
                ],
                tableName: config.journalTableName,
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
  /// Snapshots are stored as one row per aggregate with `seq_nr == 0`; the
  /// row's `version` identifies the latest snapshot version. This method
  /// queries `snapshotAidIndexName` for that row, deserializes its binary
  /// `payload`, and restores the stored version on the returned snapshot.
  /// The query uses DynamoDB's default eventually consistent read behavior.
  ///
  /// The method returns `nil` when the query has no matching row. It does not
  /// reconstruct a snapshot from journal events.
  ///
  /// - Parameter aid: The aggregate ID to look up.
  /// - Returns: The snapshot available for `aid`, or `nil` when no matching
  ///   snapshot is available in the configured index.
  /// - Throws: `EventStoreReadError.IOError` when the DynamoDB query fails;
  ///   `EventStoreReadError.otherError` when the item has no binary payload or
  ///   has a missing or invalid numeric version; or
  ///   `EventStoreReadError.deserializationError` when the snapshot serializer
  ///   cannot decode the payload.
  public func getLatestSnapshotByAID(aid: AID) async throws -> Snapshot? {
    let output: DynamoDB.QueryOutput
    do {
      output = try await dynamoDB.query(
        .init(
          expressionAttributeNames: [
            "#aid": "aid",
            "#seq_nr": "seq_nr",
          ],
          expressionAttributeValues: [
            ":aid": .s(aid.description),
            ":seq_nr": .n("0"),
          ],
          indexName: config.snapshotAidIndexName,
          keyConditionExpression: "#aid = :aid AND #seq_nr = :seq_nr",
          limit: 1,
          tableName: config.snapshotTableName,
        ),
        logger: logger,
      )
    } catch {
      throw EventStoreReadError.IOError(error)
    }

    guard let item = output.items?.first else {
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

    var snapshot: Snapshot
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
  /// The method queries `journalAidIndexName` with `seq_nr >= seqNr`. DynamoDB
  /// returns the matching GSI items in ascending numeric sort-key order by
  /// default, so the resulting array follows sequence order for a correctly
  /// configured index. The query uses DynamoDB's default eventually consistent
  /// read behavior.
  ///
  /// Only the first `Query` response is processed. If DynamoDB returns a
  /// `LastEvaluatedKey`, this method does not issue another request and the
  /// returned array is incomplete. Callers that may have more than one page
  /// of events must use a paginated access path or address this limitation
  /// before relying on the result for full aggregate reconstruction.
  ///
  /// A missing, non-binary, or invalid payload aborts the entire read rather
  /// than skipping that item.
  ///
  /// - Parameters:
  ///   - aid: The aggregate ID whose events are requested.
  ///   - seqNr: The inclusive lower bound for the event sequence number.
  /// - Returns: The decoded events included in the first DynamoDB query page,
  ///   in ascending sequence-number order. Returns an empty array when no
  ///   items are present in that page.
  /// - Throws: `EventStoreReadError.IOError` when the DynamoDB query fails;
  ///   `EventStoreReadError.otherError` when an item has a missing, non-binary,
  ///   or invalid Base64 payload; or
  ///   `EventStoreReadError.deserializationError` when an event serializer
  ///   cannot decode a payload.
  public func getEventsByAIDSinceSequenceNumber(aid: AID, seqNr: Int) async throws -> [Event] {
    let output: DynamoDB.QueryOutput
    do {
      output = try await dynamoDB.query(
        .init(
          expressionAttributeNames: [
            "#aid": "aid",
            "#seq_nr": "seq_nr",
          ],
          expressionAttributeValues: [
            ":aid": .s(aid.description),
            ":seq_nr": .n(String(seqNr)),
          ],
          indexName: config.journalAidIndexName,
          keyConditionExpression: "#aid = :aid AND #seq_nr >= :seq_nr",
          tableName: config.journalTableName,
        ),
        logger: logger,
      )
    } catch {
      throw EventStoreReadError.IOError(error)
    }

    var events: [Event] = []
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

extension EventStoreForDynamoDB where Event: Codable, Snapshot: Codable {
  /// Creates a DynamoDB event store using sorted-key JSON for events and snapshots.
  ///
  /// This convenience initializer is available when both generic types conform
  /// to `Codable`. It uses the default
  /// ``EventSerializer/json(encoder:decoder:)`` and ``SnapshotSerializer/json()``
  /// implementations, including Foundation's default coding strategies. Use
  /// the designated initializer when either persisted format requires custom
  /// encoding.
  ///
  /// - Parameters:
  ///   - logger: The logger passed to Soto DynamoDB operations.
  ///   - dynamoDB: The configured Soto DynamoDB service client.
  ///   - config: The table, index, and shard configuration.
  ///   - keyResolver: The primary-key resolver.
  public init(
    logger: Logger,
    dynamoDB: DynamoDB,
    config: EventStoreForDynamoDBConfiguration = .default,
    keyResolver: KeyResolver<AID> = .init(),
  ) {
    self.init(
      logger: logger,
      dynamoDB: dynamoDB,
      config: config,
      keyResolver: keyResolver,
      eventSerializer: .json(),
      snapshotSerializer: .json(),
    )
  }
}

extension EventStoreForDynamoDB where Snapshot: Codable {
  /// Creates a DynamoDB event store using sorted-key JSON for snapshots.
  ///
  /// This initializer leaves event serialization to the supplied
  /// `eventSerializer` and uses ``SnapshotSerializer/json()`` for snapshots.
  /// The JSON serializer uses Foundation's default coding strategies and
  /// requests sorted JSON object keys.
  ///
  /// - Parameters:
  ///   - logger: The logger passed to Soto DynamoDB operations.
  ///   - dynamoDB: The configured Soto DynamoDB service client.
  ///   - config: The table, index, and shard configuration.
  ///   - keyResolver: The primary-key resolver.
  ///   - eventSerializer: The serializer for event payloads.
  public init(
    logger: Logger,
    dynamoDB: DynamoDB,
    config: EventStoreForDynamoDBConfiguration = .default,
    keyResolver: KeyResolver<AID> = .init(),
    eventSerializer: EventSerializer<Event>,
  ) {
    self.init(
      logger: logger,
      dynamoDB: dynamoDB,
      config: config,
      keyResolver: keyResolver,
      eventSerializer: eventSerializer,
      snapshotSerializer: .json(),
    )
  }
}

extension EventStoreForDynamoDB where Event: Codable {
  /// Creates a DynamoDB event store using sorted-key JSON for events.
  ///
  /// This initializer uses ``EventSerializer/json(encoder:decoder:)`` for
  /// events and leaves snapshot serialization to the supplied
  /// `snapshotSerializer`. The JSON serializer uses Foundation's default
  /// coding strategies and requests sorted JSON object keys.
  ///
  /// - Parameters:
  ///   - logger: The logger passed to Soto DynamoDB operations.
  ///   - dynamoDB: The configured Soto DynamoDB service client.
  ///   - config: The table, index, and shard configuration.
  ///   - keyResolver: The primary-key resolver.
  ///   - snapshotSerializer: The serializer for snapshot payloads.
  public init(
    logger: Logger,
    dynamoDB: DynamoDB,
    config: EventStoreForDynamoDBConfiguration = .default,
    keyResolver: KeyResolver<AID> = .init(),
    snapshotSerializer: SnapshotSerializer<Snapshot>,
  ) {
    self.init(
      logger: logger,
      dynamoDB: dynamoDB,
      config: config,
      keyResolver: keyResolver,
      eventSerializer: .json(),
      snapshotSerializer: snapshotSerializer,
    )
  }
}
