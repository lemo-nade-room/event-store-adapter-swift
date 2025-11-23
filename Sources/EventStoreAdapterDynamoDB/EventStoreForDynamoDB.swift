@preconcurrency public import AWSDynamoDB
public import EventStoreAdapter
public import Foundation
public import Logging

///
///  # EventStoreForDynamoDB
///
///  A DynamoDB-backed event store implementation for CQRS/Event Sourcing that conforms to
///  the ``EventStoreAdapter/EventStore`` protocol. This struct allows you to store and retrieve
///  both events and snapshots for a given aggregate in a DynamoDB table.
///
///  ---
///
///  ## English Description
///
///  **EventStoreForDynamoDB** is designed to make it easy to persist and query events and snapshots
///  using AWS DynamoDB as the underlying data store. By associating each event and snapshot with a
///  partition key and sort key, this implementation leverages DynamoDB’s scalability and fault tolerance
///  to handle large volumes of event data.
///
///  - It manages two DynamoDB tables:
///    1. **Journal Table** for events.
///    2. **Snapshot Table** for snapshots.
///  - It uses global secondary indexes (GSI) for efficient queries by aggregate IDs.
///  - It supports key-based sharding (`shardCount`), so you can distribute data across multiple
///    partitions to avoid “hot partition” problems.
///  - It provides optional automatic snapshot purging or TTL-based cleanup, so older snapshots
///    can be pruned to conserve storage.
///
///  This struct implements the core functions required by an event store:
///  - Storing events (`persistEvent`) with optimistic concurrency checks.
///  - Storing events with snapshots (`persistEventAndSnapshot`) for newly created aggregates or
///    when you explicitly want to store a snapshot.
///  - Retrieving the latest snapshot by aggregate ID (`getLatestSnapshotByAID`).
///  - Retrieving a set of events (in chronological order) for an aggregate since a specified
///    sequence number (`getEventsByAIDSinceSequenceNumber`).
///
///  ### Common Use Cases
///
///  1. **New Aggregate Creation**
///    When creating a new aggregate, call ``persistEventAndSnapshot(event:aggregate:)`` with the
///    creation event and the initial snapshot. This ensures the aggregate is fully tracked.
///
///  2. **Updating Existing Aggregate**
///    When an event is generated for an existing aggregate, use ``persistEvent(event:version:)``
///    if you do not need to store a snapshot at the same time. Otherwise, use
///    ``persistEventAndSnapshot(event:aggregate:)`` to store both the event and a new snapshot.
///
///  3. **Querying Events**
///    After retrieving the latest snapshot, call
///    ``getEventsByAIDSinceSequenceNumber(aid:seqNr:)`` to get all subsequent events and rebuild
///    the current state of your aggregate.
///
///  ### DynamoDB Setup
///
///  - **Journal Table** (`journalTableName`):
///    Stores all events. Each item typically contains a partition key (`pkey`), a sort key (`skey`),
///    and a GSI for querying by aggregate ID (`journalAidIndexName`).
///  - **Snapshot Table** (`snapshotTableName`):
///    Stores snapshots. Each item contains a partition key (`pkey`) and sort key (`skey`). A second GSI
///    (`snapshotAidIndexName`) is used to query by aggregate ID.
///
///  ### Example Initialization
///
///  ```swift
///  let client = try await DynamoDBClient(...)
///  let eventStore = EventStoreForDynamoDB<MyAggregate, MyAggregate.MyEvent>(
///      client: client,
///      journalTableName: "my_journal",
///      journalAidIndexName: "my_journal_aid_index",
///      snapshotTableName: "my_snapshot",
///      snapshotAidIndexName: "my_snapshot_aid_index",
///      shardCount: 64,
///      keepSnapshotCount: 3,
///      deleteTTL: 3600
///  )
///  ```
///
///  ### Properties
///
///  - ``logger``: A Swift-Log `Logger` for diagnostic output.
///  - ``client``: The `DynamoDBClient` used for all table operations.
///  - ``journalTableName``: The name of the DynamoDB table for storing events.
///  - ``journalAidIndexName``: The name of the GSI for events, enabling queries by aggregate ID.
///  - ``snapshotTableName``: The name of the DynamoDB table for storing snapshots.
///  - ``snapshotAidIndexName``: The name of the GSI for snapshots, enabling queries by aggregate ID.
///  - ``shardCount``: The number of shards used by the partition key resolver to spread out data.
///  - ``keepSnapshotCount``: (Optional) The number of recent snapshots to keep. Older ones may be purged.
///  - ``deleteTTL``: (Optional) The TTL in seconds used for marking older snapshots for expiration.
///  - ``keyResolver``: A custom or default `KeyResolver` that computes partition keys and sort keys.
///  - ``eventSerializer``: Serializes and deserializes event objects to/from DynamoDB binary payloads.
///  - ``snapshotSerializer``: Serializes and deserializes aggregate snapshots to/from DynamoDB binary payloads.
///
///  ---
///
///  ## 日本語説明
///
///  **EventStoreForDynamoDB** は、AWS DynamoDB を用いた CQRS/Event Sourcing 向けのイベントストア実装です。
///  ``EventStoreAdapter/EventStore`` プロトコルに準拠しており、特定の集約に紐づくイベントやスナップショットを
///  DynamoDB テーブルに保存・取得できます。
///
///  - **2つのDynamoDBテーブル**を使用:
///    1. イベントを保存する「ジャーナルテーブル（`journalTableName`）」
///    2. スナップショットを保存する「スナップショットテーブル（`snapshotTableName`）」
///  - Global Secondary Index (GSI) を活用して、集約IDによる検索を効率化します。
///  - シャーディング機能（`shardCount`）を使い、パーティションを分散させることで大規模データへの拡張性を確保できます。
///  - スナップショットの古いデータを自動的に削除できる機能（スナップショット数の上限 `keepSnapshotCount` またはTTL `deleteTTL`）も利用可能です。
///
///  イベントストアとして必要な以下の機能を提供します:
///  - 楽観的ロックに対応したイベント保存（``persistEvent(event:version:)``）。
///  - 新規集約やスナップショットも同時に保存したい場合の ``persistEventAndSnapshot(event:aggregate:)``。
///  - 集約IDを使った最新スナップショットの取得（``getLatestSnapshotByAID(aid:)``）。
///  - 指定したシーケンス番号以降のイベント取得（``getEventsByAIDSinceSequenceNumber(aid:seqNr:)``）で、
///    集約の現在状態を再現できます。
///
///  ### 代表的なユースケース
///
///  1. **新規集約の作成**
///    新規に集約を作成した際は、生成イベントと初期スナップショットを
///    ``persistEventAndSnapshot(event:aggregate:)`` で保存します。
///
///  2. **既存集約の更新**
///    既存集約で新たなイベントが発生した場合は ``persistEvent(event:version:)`` を使用します。
///    スナップショットも同時に保存したいなら ``persistEventAndSnapshot(event:aggregate:)`` を利用します。
///
///  3. **イベントの取得**
///    最新のスナップショットを取得後、 ``getEventsByAIDSinceSequenceNumber(aid:seqNr:)`` を呼び出すと、
///    指定したシーケンス番号以降に発生したイベントを昇順で取得し、集約の最新状態を再構築できます。
///
///  ### DynamoDB の設定
///
///  - **ジャーナルテーブル**（`journalTableName`）
///    イベントを格納。`pkey`（パーティションキー）と `skey`（ソートキー）を用い、
///    集約IDでクエリをするための GSI（`journalAidIndexName`）を設定します。
///  - **スナップショットテーブル**（`snapshotTableName`）
///    スナップショットを格納。こちらも `pkey` と `skey` を持ち、
///    集約IDでクエリをするための GSI（`snapshotAidIndexName`）を設定します。
///
///  ### 各プロパティの詳細
///
///  - ``logger``: Swift-Log の `Logger`。デバッグ用のログ出力に使用。
///  - ``client``: `DynamoDBClient`。全ての DynamoDB との通信はこのクライアントを介して行われる。
///  - ``journalTableName``: イベントを保存するテーブル名。
///  - ``journalAidIndexName``: 集約IDでイベントを検索するための GSI 名。
///  - ``snapshotTableName``: スナップショットを保存するテーブル名。
///  - ``snapshotAidIndexName``: 集約IDでスナップショットを検索するための GSI 名。
///  - ``shardCount``: パーティションキーを計算する際に使用するシャード数。大量データへのスケールを考慮した設定。
///  - ``keepSnapshotCount``: (オプション) 保存しておくスナップショットの最大数。超過したスナップショットは削除対象となる。
///  - ``deleteTTL``: (オプション) スナップショットに TTL を設定し、古いものを自動削除するための秒数。
///  - ``keyResolver``: パーティションキーやソートキーの計算ロジックをカスタマイズできる `KeyResolver`。
///  - ``eventSerializer``: イベントを DynamoDB のバイナリカラムにシリアライズ/デシリアライズするためのロジック。
///  - ``snapshotSerializer``: スナップショットを同様にシリアライズ/デシリアライズするロジック。
public struct EventStoreForDynamoDB<
  Aggregate: EventStoreAdapter.Aggregate,
  Event: EventStoreAdapter.Event
> where Aggregate.AID == Event.AID {
  public var logger: Logger
  public var client: DynamoDBClient
  public var journalTableName: String
  public var journalAidIndexName: String
  public var snapshotTableName: String
  public var snapshotAidIndexName: String
  public var shardCount: Int
  public var keepSnapshotCount: Int?
  public var deleteTTL: TimeInterval?
  public var keyResolver: KeyResolver<Aggregate.AID>
  public var eventSerializer: EventSerializer<Event>
  public var snapshotSerializer: SnapshotSerializer<Aggregate>

  public init(
    logger: Logger? = nil,
    client: DynamoDBClient,
    journalTableName: String? = nil,
    journalAidIndexName: String? = nil,
    snapshotTableName: String? = nil,
    snapshotAidIndexName: String? = nil,
    shardCount: Int? = nil,
    keepSnapshotCount: Int? = nil,
    deleteTTL: TimeInterval? = nil,
    keyResolver: KeyResolver<Aggregate.AID>? = nil,
    eventSerializer: EventSerializer<Event>? = nil,
    snapshotSerializer: SnapshotSerializer<Aggregate>? = nil
  ) {
    self.logger = logger ?? Self.defaultLogger
    self.client = client
    self.journalTableName = journalTableName ?? Self.defaultJournalTableName
    self.journalAidIndexName = journalAidIndexName ?? Self.defaultJournalAidIndexName
    self.snapshotTableName = snapshotTableName ?? Self.defaultSnapshotTableName
    self.snapshotAidIndexName = snapshotAidIndexName ?? Self.defaultSnapshotAidIndexName
    self.shardCount = shardCount ?? Self.defaultShardCount
    self.keepSnapshotCount = keepSnapshotCount
    self.deleteTTL = deleteTTL
    self.keyResolver = keyResolver ?? .init()
    self.eventSerializer = eventSerializer ?? .init()
    self.snapshotSerializer = snapshotSerializer ?? .init()
  }
}

extension EventStoreForDynamoDB: EventStore {
  /// The type representing the Aggregate ID, mirroring the type in the `Aggregate` constraint.
  public typealias AID = Aggregate.AID

  /// Retrieves the latest snapshot associated with a given aggregate ID from DynamoDB.
  ///
  /// # English
  /// - Parameter aid: The aggregate ID.
  /// - Returns: The latest snapshot of the aggregate, or `nil` if none is found.
  /// - Throws: ``EventStoreAdapter/EventStoreReadError`` if a query or deserialization fails.
  ///
  /// This method queries the snapshot table by the given `aid` (aggregate ID) to find
  /// the item whose `seq_nr` is `0`. It then deserializes the snapshot payload and sets
  /// its `version` property based on the stored data.
  ///
  /// # Japanese
  /// 指定した集約IDに対応する最新のスナップショットを DynamoDB から取得します。
  /// - Parameter aid: 集約ID
  /// - Returns: 最新のスナップショット。存在しない場合は `nil` を返します。
  /// - Throws: クエリ失敗やデシリアライズ失敗の場合は ``EventStoreAdapter/EventStoreReadError`` をスローします。
  ///
  /// スナップショットテーブルで `aid` と `seq_nr = 0` を条件に検索し、取得したスナップショットを
  /// デシリアライズします。取り出したデータの `version` プロパティを更新したうえで返します。
  public func getLatestSnapshotByAID(aid: AID) async throws -> Aggregate? {
    let output: QueryOutput
    do {
      output = try await client.query(
        input: .init(
          expressionAttributeNames: ["#aid": "aid", "#seq_nr": "seq_nr"],
          expressionAttributeValues: [
            ":aid": .s(aid.description), ":seq_nr": .n("0"),
          ],
          indexName: snapshotAidIndexName,
          keyConditionExpression: "#aid = :aid AND #seq_nr = :seq_nr",
          limit: 1,
          tableName: snapshotTableName
        )
      )
    } catch {
      throw EventStoreReadError.IOError(error)
    }

    guard let items = output.items else {
      throw EventStoreReadError.otherError(
        "No snapshot found for aggregate id: \(aid)"
      )
    }
    guard let item = items.first else {
      return nil
    }
    guard
      case .b(let data) = item["payload"],
      case .n(let versionString) = item["version"],
      let version = Int(versionString)
    else {
      fatalError("payload or version is invalid")
    }

    var aggregate = try snapshotSerializer.deserialize(data)
    logger.debug(
      "EventStoreForDynamoDB.getLatestSnapshotByAID seq_nr: \(aggregate.seqNr)"
    )
    aggregate.version = version
    return aggregate
  }

  /// 指定したシーケンス番号から、指定した集約の全てのイベントを取得する
  /// - Parameters:
  ///   - aid: 集約ID
  ///   - seqNr: シーケンス番号
  /// - Returns: イベント一覧
  /// - Throws: クエリに失敗した場合にエラーが投げられる
  public func getEventsByAIDSinceSequenceNumber(aid: AID, seqNr: Int) async throws -> [Event] {
    let response: QueryOutput
    do {
      response = try await client.query(
        input: .init(
          expressionAttributeNames: ["#aid": "aid", "#seq_nr": "seq_nr"],
          expressionAttributeValues: [
            ":aid": .s(aid.description),
            ":seq_nr": .n(String(seqNr)),
          ],
          indexName: journalAidIndexName,
          keyConditionExpression: "#aid = :aid AND #seq_nr >= :seq_nr",
          tableName: journalTableName
        )
      )
    } catch {
      throw EventStoreReadError.IOError(error)
    }
    guard let items = response.items else {
      return []
    }
    return try items.map { item in
      guard case .b(let data) = item["payload"] else {
        fatalError("payload is invalid")
      }
      return try eventSerializer.deserialize(data)
    }
  }

  /// Persists an event into the DynamoDB journal table, using optimistic concurrency checks.
  ///
  /// # English
  /// - Parameters:
  ///     - event: The event to be persisted.
  ///     - version: The optimistic lock version of the aggregate.
  /// - Throws: An error if the write operation fails.
  ///
  /// Typically called when adding a **new event** to an **existing** aggregate. The method
  /// ensures the event is not marked as a creation event (`isCreated` must be false),
  /// then updates the snapshot with version checks and finally writes the event to the
  /// journal table. It also attempts to purge any old snapshots if configured.
  ///
  /// # Japanese
  /// イベントを DynamoDB のジャーナルテーブルに永続化し、楽観的ロックを使用してチェックを行います。
  ///
  /// - Parameters:
  ///     - event: 保存対象のイベント
  ///     - version: 集約の楽観ロックバージョン
  /// - Throws: 書き込み操作が失敗した場合にエラーをスローします。
  ///
  /// 既存の集約に対して新しいイベントを追加する際に呼び出します。
  /// 生成イベント（`isCreated` が true）でないことを確認し、スナップショットのバージョンチェックを行ったうえで
  /// ジャーナルテーブルにイベントを書き込みます。
  /// その後、古いスナップショットの削除（パージ設定がある場合）を試みます。
  public func persistEvent(event: Event, version: Int) async throws {
    if event.isCreated {
      fatalError("Invalid event: \(event)")
    }

    try await updateEventAndSnapshotOpt(event: event, version: version, aggregate: nil)
    try await tryPurgeExcessSnapshots(aid: event.aid)
  }

  /// Persists both an event and its corresponding aggregate snapshot in DynamoDB.
  ///
  /// # English
  /// - Parameters:
  ///     - event: The event to be persisted.
  ///     - aggregate: The snapshot of the aggregate to be persisted.
  /// - Throws: An error if the write operation fails.
  ///
  /// Called when creating a **new aggregate** or when you want to save a snapshot along
  /// with the event. If the event is flagged as a creation event (`isCreated == true`),
  /// this indicates the aggregate is new. Otherwise, it updates the existing snapshot
  /// with version checks. This method also handles snapshot purging if configured.
  ///
  /// # Japanese
  /// イベントと、それに対応する集約のスナップショットを DynamoDB に同時に永続化します。
  ///
  /// - Parameters:
  ///     - event: 保存するイベント
  ///     - aggregate: 保存する集約のスナップショット
  /// - Throws: 書き込み操作が失敗した場合にエラーをスローします。
  ///
  /// **新しい集約を作成した**場合、またはイベントとともにスナップショットも同時に保存したい場合に呼び出します。
  /// イベントが生成イベント（`isCreated == true`）の場合は新規集約として扱い、そうでなければ既存のスナップショットを
  /// バージョンチェックを通して更新します。スナップショットのパージ設定がある場合、その処理も行われます。
  public func persistEventAndSnapshot(event: Event, aggregate: Aggregate) async throws {
    if event.isCreated {
      try await createEventAndSnapshot(event: event, aggregate: aggregate)
    } else {
      try await updateEventAndSnapshotOpt(
        event: event,
        version: aggregate.version,
        aggregate: aggregate
      )
      try await tryPurgeExcessSnapshots(aid: event.aid)
    }
  }

  private func createEventAndSnapshot(event: Event, aggregate: Aggregate) async throws {
    var transactWriteItems: [DynamoDBClientTypes.TransactWriteItem] = [
      try .init(put: putSnapshot(event: event, seqNr: 0, aggregate: aggregate)),
      try .init(put: putJournal(event: event)),
    ]
    if keepSnapshotCount != nil {
      transactWriteItems.append(
        .init(
          put: try putSnapshot(
            event: event,
            seqNr: aggregate.seqNr,
            aggregate: aggregate
          )
        )
      )
    }
    let result = try await client.transactWriteItems(
      input: .init(transactItems: transactWriteItems)
    )
    logger.debug("EventStoreForDynamoDB.createEventAndSnapshot result: \(result)")
  }

  private func updateEventAndSnapshotOpt(
    event: Event,
    version: Int,
    aggregate: Aggregate?
  ) async throws {
    var transactItems: [DynamoDBClientTypes.TransactWriteItem] = [
      .init(
        update: try updateSnapshot(
          event: event,
          seqNr: 0,
          version: version,
          aggregate: aggregate
        )
      ),
      .init(put: try putJournal(event: event)),
    ]
    if keepSnapshotCount != nil, let aggregate {
      try transactItems.append(
        .init(
          put: putSnapshot(
            event: event,
            seqNr: aggregate.seqNr,
            aggregate: aggregate
          )
        )
      )
    }
    let output = try await client.transactWriteItems(input: .init(transactItems: transactItems))
    logger.debug("EventStoreForDynamoDB.updateEventAndSnapshotOpt output: \(output)")
  }

  private func deleteExcessSnapshots(aid: Aggregate.AID) async throws {
    guard let keepSnapshotCount else { return }

    let snapshotCount = try await getSnapshotCountForWrite(aid: aid)
    let excessCount = snapshotCount - keepSnapshotCount

    guard excessCount > 0 else { return }
    logger.debug("EventStoreForDynamoDB.deleteExcessSnapshots excess_count: \(excessCount)")

    let keys = try await getLastSnapshotKeysForWrite(
      aid: aid,
      excessCount: excessCount
    )
    logger.debug("EventStoreForDynamoDB.deleteExcessSnapshots keys: \(keys)")

    if keys.isEmpty { return }
    let requestItems = keys.map { (pkey, skey) -> DynamoDBClientTypes.WriteRequest in
      .init(
        deleteRequest: .init(key: [
          "pkey": .s(pkey),
          "skey": .s(skey),
        ])
      )
    }
    let result = try await client.batchWriteItem(
      input: .init(requestItems: [snapshotTableName: requestItems])
    )
    logger.debug("EventStoreForDynamoDB.deleteExcessSnapshots result: \(result)")
  }

  private func updateTTLOfExcessSnapshots(aid: Aggregate.AID) async throws {
    guard let keepSnapshotCount, let deleteTTL else { return }

    let snapshotCount = try await getSnapshotCountForWrite(aid: aid)
    let excessCount = snapshotCount - keepSnapshotCount

    guard excessCount > 0 else { return }

    logger.debug(
      "EventStoreForDynamoDB.updateTTLOfExcessSnapshots excess_count: \(excessCount)"
    )
    let keys = try await getLastSnapshotKeysForWrite(
      aid: aid,
      excessCount: excessCount
    )
    logger.debug("EventStoreForDynamoDB.updateTTLOfExcessSnapshots keys: \(keys)")
    let ttl = Date().addingTimeInterval(deleteTTL).timeIntervalSince1970

    for (pkey, skey) in keys {
      let output = try await client.updateItem(
        input: .init(
          expressionAttributeNames: ["#ttl": "ttl"],
          expressionAttributeValues: [":ttl": .n(String(Int(ttl)))],
          key: [
            "pkey": .s(pkey),
            "skey": .s(skey),
          ],
          tableName: snapshotTableName,
          updateExpression: "SET #ttl=:ttl"
        )
      )
      logger.debug(
        "EventStoreForDynamoDB.updateTTLOfExcessSnapshots pkey: \(pkey), skey: \(skey), output: \(output)"
      )
    }
  }

  private func getLastSnapshotKeysForWrite(
    aid: Aggregate.AID,
    excessCount: Int
  ) async throws -> [(pkey: String, skey: String)] {
    try await getLastSnapshotKeys(aid: aid, limit: excessCount)
  }

  private func getSnapshotCountForWrite(aid: Aggregate.AID) async throws -> Int {
    let count = try await getSnapshotCount(aid: aid)
    return count - 1
  }

  private func getSnapshotCount(aid: Aggregate.AID) async throws -> Int {
    let output = try await client.query(
      input: .init(
        expressionAttributeNames: ["#aid": "aid"],
        expressionAttributeValues: [":aid": .s(aid.description)],
        indexName: snapshotAidIndexName,
        keyConditionExpression: "#aid = :aid",
        select: .count,
        tableName: snapshotTableName
      )
    )
    return output.count
  }

  private func getLastSnapshotKeys(
    aid: Aggregate.AID,
    limit: Int
  ) async throws -> [(pkey: String, skey: String)] {
    var input = QueryInput(
      expressionAttributeNames: [
        "#aid": "aid",
        "#seq_nr": "seq_nr",
      ],
      expressionAttributeValues: [
        ":aid": .s(aid.description),
        ":seq_nr": .n("0"),
      ],
      indexName: snapshotAidIndexName,
      keyConditionExpression: "#aid = :aid AND #seq_nr > :seq_nr",
      limit: limit,
      scanIndexForward: false,
      tableName: snapshotTableName
    )

    if deleteTTL != nil {
      input.expressionAttributeNames?.merge(["#ttl": "ttl"]) { $1 }
      input.expressionAttributeValues?.merge([":ttl": .n("0")]) { $1 }
      input.filterExpression = "#ttl = :ttl"
    }

    let response: QueryOutput
    do {
      response = try await client.query(input: input)
    } catch {
      throw EventStoreReadError.IOError(error)
    }

    guard let items = response.items else {
      throw EventStoreReadError.otherError(
        "No snapshot found for aggregate id: \(aid)"
      )
    }

    return items.map { item in
      guard
        case .s(let aidString) = item["aid"],
        let aid = AID(aidString),
        case .n(let seqNrString) = item["seq_nr"],
        let seqNr = Int(seqNrString),
        case .s(let pkey) = item["pkey"],
        case .s(let skey) = item["skey"]
      else {
        fatalError("aid or seq_nr or pkey or skey is invalid")
      }
      logger.debug("EventStoreForDynamoDB.getLastSnapshotKeys aid: \(aid)")
      logger.debug("EventStoreForDynamoDB.getLastSnapshotKeys seq_nr: \(seqNr)")
      return (pkey, skey)
    }
  }

  private func putSnapshot(
    event: Event,
    seqNr: Int,
    aggregate: Aggregate
  ) throws -> DynamoDBClientTypes.Put {
    let pkey = resolvePkey(id: event.aid, shardCount: shardCount)
    let skey = resolveSkey(id: event.aid, seqNr: seqNr)
    let payload = try snapshotSerializer.serialize(aggregate)
    logger.debug("↓ EventStoreForDynamoDB.putSnapshot ↓")
    logger.debug("pkey: \(pkey)")
    logger.debug("skey: \(skey)")
    logger.debug("aid: \(event.aid.description)")
    logger.debug("seq_nr: \(seqNr)")
    logger.debug("↑ EventStoreForDynamoDB.putSnapshot ↑")
    return .init(
      conditionExpression: "attribute_not_exists(pkey) AND attribute_not_exists(skey)",
      item: [
        "pkey": .s(pkey),
        "skey": .s(skey),
        "payload": .b(payload),
        "aid": .s(event.aid.description),
        "seq_nr": .n(String(seqNr)),
        "version": .n("1"),
        "ttl": .n("0"),
        "last_updated_at": .n(String(Int(event.occurredAt.timeIntervalSince1970 * 1000))),
      ],
      tableName: snapshotTableName
    )
  }

  private func updateSnapshot(
    event: Event,
    seqNr: Int,
    version: Int,
    aggregate: Aggregate?
  ) throws -> DynamoDBClientTypes.Update {
    let pkey = resolvePkey(id: event.aid, shardCount: shardCount)
    let skey = resolveSkey(id: event.aid, seqNr: seqNr)
    logger.debug("↓ EventStoreForDynamoDB.updateSnapshot ↓")
    logger.debug("pkey: \(pkey)")
    logger.debug("skey: \(skey)")
    logger.debug("aid: \(event.aid.description)")
    logger.debug("seq_nr: \(seqNr)")
    logger.debug("↑ EventStoreForDynamoDB.updateSnapshot ↑")
    var updateSnapshot = DynamoDBClientTypes.Update(
      conditionExpression: "#version = :before_version",
      expressionAttributeNames: [
        "#version": "version",
        "#last_updated_at": "last_updated_at",
      ],
      expressionAttributeValues: [
        ":before_version": .n(String(version)),
        ":after_version": .n(String(version + 1)),
        ":last_updated_at": .n(String(Int(event.occurredAt.timeIntervalSince1970 * 1000))),
      ],
      key: [
        "pkey": .s(pkey),
        "skey": .s(skey),
      ],
      tableName: snapshotTableName,
      updateExpression: "SET #version=:after_version, #last_updated_at=:last_updated_at"
    )
    if let aggregate {
      let payload = try snapshotSerializer.serialize(aggregate)
      updateSnapshot.updateExpression =
        "SET #payload=:payload, #seq_nr=:seq_nr, #version=:after_version, #last_updated_at=:last_updated_at"
      updateSnapshot.expressionAttributeNames?
        .merge([
          "#seq_nr": "seq_nr",
          "#payload": "payload",
        ]) { $1 }
      updateSnapshot.expressionAttributeValues?
        .merge([
          ":seq_nr": .n(String(seqNr)),
          ":payload": .b(payload),
        ]) { $1 }
    }
    return updateSnapshot
  }

  private func resolvePkey(id: AID, shardCount: Int) -> String {
    keyResolver.resolvePartitionKey(id, shardCount)
  }

  private func resolveSkey(id: AID, seqNr: Int) -> String {
    keyResolver.resolveSortKey(id, seqNr)
  }

  private func putJournal(event: Event) throws -> DynamoDBClientTypes.Put {
    .init(
      conditionExpression: "attribute_not_exists(pkey) AND attribute_not_exists(skey)",
      item: [
        "pkey": .s(resolvePkey(id: event.aid, shardCount: shardCount)),
        "skey": .s(
          resolveSkey(id: event.aid, seqNr: event.seqNr)
        ),
        "aid": .s(event.aid.description),
        "seq_nr": .n(String(event.seqNr)),
        "payload": .b(try eventSerializer.serialize(event)),
        "occurred_at": .n(String(Int(event.occurredAt.timeIntervalSince1970 * 1000))),
      ],
      tableName: journalTableName
    )
  }

  private func tryPurgeExcessSnapshots(aid: Aggregate.AID) async throws {
    guard keepSnapshotCount != nil else { return }

    if deleteTTL != nil {
      try await updateTTLOfExcessSnapshots(aid: aid)
    } else {
      try await deleteExcessSnapshots(aid: aid)
    }
  }
}

extension EventStoreForDynamoDB {
  /// The default logger used if none is provided to the initializer.
  public static var defaultLogger: Logger { Logger(label: "event-store-for-dynamo-db") }
  /// The default name of the journal table to store events.
  public static var defaultJournalTableName: String { "journal" }
  /// The default GSI name for the journal table, used to query events by aggregate ID.
  public static var defaultJournalAidIndexName: String { "aid-index" }
  /// The default name of the snapshot table to store aggregate snapshots.
  public static var defaultSnapshotTableName: String { "snapshot" }
  /// The default GSI name for the snapshot table, used to query snapshots by aggregate ID.
  public static var defaultSnapshotAidIndexName: String { "aid-index" }
  /// The default number of shards for partition key resolution.
  public static var defaultShardCount: Int { 64 }
}
