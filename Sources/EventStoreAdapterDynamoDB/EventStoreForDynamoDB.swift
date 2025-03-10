@preconcurrency public import AWSDynamoDB
public import EventStoreAdapter
public import Foundation
public import Logging

/// DynamoDBを永続化に使用するイベントストア
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
    /// 集約ID
    public typealias AID = Aggregate.AID

    /// 最新のスナップショットを集約IDで取得する。
    /// 存在しない場合はnilを消す
    /// - Parameter aid: 集約ID
    /// - Returns: 最新のスナップショット
    /// - Throws: クエリに失敗、あるいはデシリアライズに失敗した際にエラーが投げられる
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
                "No snapshot found for aggregate id: \(aid)")
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
            "EventStoreForDynamoDB.getLatestSnapshotByAID seq_nr: \(aggregate.seqNr)")
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
                ))
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

    /// イベントを永続化する
    /// - Parameters:
    ///   - event: 永続化するイベント
    ///   - version: 楽観的ロック用バージョン
    /// - Throws: クエリに失敗した際にエラーがスローされる
    public func persistEvent(event: Event, version: Int) async throws {
        if event.isCreated {
            fatalError("Invalid event: \(event)")
        }

        try await updateEventAndSnapshotOpt(event: event, version: version, aggregate: nil)
        try await tryPurgeExcessSnapshots(aid: event.aid)
    }

    /// イベントと集約のスナップショットを永続化する
    /// - Parameters:
    ///   - event: イベント
    ///   - aggregate: 集約
    /// - Throws: クエリに失敗した際にエラーがスローされる
    public func persistEventAndSnapshot(event: Event, aggregate: Aggregate) async throws {
        if event.isCreated {
            try await createEventAndSnapshot(event: event, aggregate: aggregate)
        } else {
            try await updateEventAndSnapshotOpt(
                event: event, version: aggregate.version, aggregate: aggregate)
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
                        event: event, seqNr: aggregate.seqNr, aggregate: aggregate
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
            aid: aid, excessCount: excessCount)
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
            "EventStoreForDynamoDB.updateTTLOfExcessSnapshots excess_count: \(excessCount)")
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
            updateSnapshot.expressionAttributeNames?.merge([
                "#seq_nr": "seq_nr",
                "#payload": "payload",
            ]) { $1 }
            updateSnapshot.expressionAttributeValues?.merge([
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
        return .init(
            conditionExpression: "attribute_not_exists(pkey) AND attribute_not_exists(skey)",
            item: [
                "pkey": .s(resolvePkey(id: event.aid, shardCount: shardCount)),
                "skey": .s(
                    resolveSkey(id: event.aid, seqNr: event.seqNr)
                ),
                "aid": .s(event.aid.description),
                "seq_nr": .n(String(event.seqNr)),
                "payload": .b(try eventSerializer.serialize(event)),
                "occurered_at": .n(String(Int(event.occurredAt.timeIntervalSince1970 * 1000))),
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
    /// Loggerのデフォルト値
    public static var defaultLogger: Logger { Logger(label: "event-store-for-dynamo-db") }
    /// Journalテーブル名のデフォルト値
    public static var defaultJournalTableName: String { "journal" }
    /// Journalテーブルの集約IDのインデックス名のデフォルト値
    public static var defaultJournalAidIndexName: String { "aid-index" }
    /// Snapshotテーブル名のデフォルト値
    public static var defaultSnapshotTableName: String { "snapshot" }
    /// Snapshotテーブルの集約IDのインデックス名のデフォルト値
    public static var defaultSnapshotAidIndexName: String { "aid-index" }
    /// デフォルトのシャード数
    public static var defaultShardCount: Int { 64 }
}
