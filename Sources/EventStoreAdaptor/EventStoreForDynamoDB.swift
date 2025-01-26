@preconcurrency import AWSDynamoDB
import Foundation
import Logging

public let defaultLogger = Logger(label: "event-store-for-dynamo-db")
public let defaultJournalTableName = "journal"
public let defaultJournalAidIndexName = "aid-index"
public let defaultSnapshotTableName = "snapshot"
public let defaultSnapshotAidIndexName = "aid-index"
public let defaultShardCount = 64

public struct EventStoreForDynamoDB<
    Aggregate: EventStoreAdaptor.Aggregate,
    Event: EventStoreAdaptor.Event
> where Aggregate.Id == Event.AggregateId {
    public var logger: Logger
    public var client: DynamoDBClient
    public var journalTableName: String
    public var journalAidIndexName: String
    public var snapshotTableName: String
    public var snapshotAidIndexName: String
    public var shardCount: Int
    public var keepSnapshotCount: Int?
    public var deleteTTL: TimeInterval?
    public var keyResolver: KeyResolver<Aggregate.Id>
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
        keyResolver: KeyResolver<Aggregate.Id>? = nil,
        eventSerializer: EventSerializer<Event>? = nil,
        snapshotSerializer: SnapshotSerializer<Aggregate>? = nil
    ) {
        self.logger = logger ?? defaultLogger
        self.client = client
        self.journalTableName = journalTableName ?? defaultJournalTableName
        self.journalAidIndexName = journalAidIndexName ?? defaultJournalAidIndexName
        self.snapshotTableName = snapshotTableName ?? defaultSnapshotTableName
        self.snapshotAidIndexName = snapshotAidIndexName ?? defaultSnapshotAidIndexName
        self.shardCount = shardCount ?? defaultShardCount
        self.keepSnapshotCount = keepSnapshotCount
        self.deleteTTL = deleteTTL
        self.keyResolver = keyResolver ?? .init()
        self.eventSerializer = eventSerializer ?? .init()
        self.snapshotSerializer = snapshotSerializer ?? .init()
    }
}

extension EventStoreForDynamoDB: EventStore {
    public typealias AggregateId = Aggregate.Id

    public func getLatestSnapshotById(aggregateId: AggregateId) async throws -> Aggregate? {
        let output = try await client.query(
            input: .init(
                expressionAttributeNames: ["#aid": "aid", "#seq_nr": "seq_nr"],
                expressionAttributeValues: [
                    ":aid": .s(aggregateId.description), ":seq_nr": .n("0"),
                ],
                indexName: snapshotAidIndexName,
                keyConditionExpression: "#aid = :aid AND #seq_nr = :seq_nr",
                limit: 1,
                tableName: snapshotTableName
            )
        )
        guard
            let items = output.items,
            let item = items.first,
            case .b(let data) = item["payload"],
            case .n(let versionString) = item["version"],
            let version = Int(versionString)
        else {
            return nil
        }

        var aggregate = try snapshotSerializer.deserialize(data)
        logger.debug(
            "EventStoreForDynamoDB.getLatestSnapshotById seq_nr: \(aggregate.sequenceNumber)")
        aggregate.version = version
        return aggregate
    }

    public func getEventsByIdSinceSequenceNumber(
        aggregateId: AggregateId,
        sequenceNumber: Int
    ) async throws -> [Event] {
        let output = try await client.query(
            input: .init(
                expressionAttributeNames: ["#aid": "aid", "#seq_nr": "seq_nr"],
                expressionAttributeValues: [
                    ":aid": .s(aggregateId.description),
                    ":seq_nr": .n(String(sequenceNumber)),
                ],
                indexName: journalAidIndexName,
                keyConditionExpression: "#aid = :aid AND #seq_nr >= :seq_nr",
                tableName: journalTableName
            ))
        guard let items = output.items else {
            throw EventStoreReadError.itemsIsNIl
        }
        return try items.map { item in
            guard case .b(let data) = item["payload"] else {
                throw EventStoreReadError.payloadNotFound
            }
            return try eventSerializer.deserialize(data)
        }
    }

    public func persistEvent(event: Event, version: Int) async throws {
        if event.isCreated {
            fatalError("Invalid event: \(event)")
        }

        try await updateEventAndSnapshotOpt(event: event, version: version, aggregate: nil)
        try await tryPurgeExcessSnapshots(aggregateId: event.aggregateId)
    }

    public func persistEventAndSnapshot(event: Event, aggregate: Aggregate) async throws {
        if event.isCreated {
            try await createEventAndSnapshot(event: event, aggregate: aggregate)
        } else {
            try await updateEventAndSnapshotOpt(
                event: event, version: aggregate.version, aggregate: aggregate)
            try await tryPurgeExcessSnapshots(aggregateId: event.aggregateId)
        }
    }

    public enum EventStoreReadError: Error {
        case itemsIsNIl
        case payloadNotFound
        case invalidSnapshot(output: QueryOutput)
    }

    private func createEventAndSnapshot(event: Event, aggregate: Aggregate) async throws {
        var transactWriteItems: [DynamoDBClientTypes.TransactWriteItem] = [
            try .init(put: putSnapshot(event: event, sequenceNumber: 0, aggregate: aggregate)),
            try .init(put: putJournal(event: event)),
        ]
        if keepSnapshotCount != nil {
            transactWriteItems.append(
                .init(
                    put: try putSnapshot(
                        event: event,
                        sequenceNumber: aggregate.sequenceNumber,
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
                    sequenceNumber: 0,
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
                        event: event, sequenceNumber: aggregate.sequenceNumber, aggregate: aggregate
                    )
                )
            )
        }
        let output = try await client.transactWriteItems(input: .init(transactItems: transactItems))
        logger.debug("EventStoreForDynamoDB.updateEventAndSnapshotOpt output: \(output)")
    }

    private func deleteExcessSnapshots(aggregateId: Aggregate.Id) async throws {
        guard let keepSnapshotCount else { return }

        let snapshotCount = try await getSnapshotCountForWrite(aggregateId: aggregateId)
        let excessCount = snapshotCount - keepSnapshotCount

        guard excessCount > 0 else { return }
        logger.debug("EventStoreForDynamoDB.deleteExcessSnapshots excess_count: \(excessCount)")

        let keys = try await getLastSnapshotKeysForWrite(
            aggregateId: aggregateId, excessCount: excessCount)
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

    private func updateTTLOfExcessSnapshots(aggregateId: Aggregate.Id) async throws {
        guard let keepSnapshotCount, let deleteTTL else { return }

        let snapshotCount = try await getSnapshotCountForWrite(aggregateId: aggregateId)
        let excessCount = snapshotCount - keepSnapshotCount

        guard excessCount > 0 else { return }

        logger.debug(
            "EventStoreForDynamoDB.updateTTLOfExcessSnapshots excess_count: \(excessCount)")
        let keys = try await getLastSnapshotKeysForWrite(
            aggregateId: aggregateId,
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
        aggregateId: Aggregate.Id,
        excessCount: Int
    ) async throws -> [(pkey: String, skey: String)] {
        try await getLastSnapshotKeys(aggregateId: aggregateId, limit: excessCount)
    }

    private func getSnapshotCountForWrite(aggregateId: Aggregate.Id) async throws -> Int {
        let count = try await getSnapshotCount(aggregateId: aggregateId)
        return count - 1
    }

    private func getSnapshotCount(aggregateId: Aggregate.Id) async throws -> Int {
        let output = try await client.query(
            input: .init(
                expressionAttributeNames: ["#aid": "aid"],
                expressionAttributeValues: [":aid": .s(aggregateId.description)],
                indexName: snapshotAidIndexName,
                keyConditionExpression: "#aid = :aid",
                select: .count,
                tableName: snapshotTableName
            )
        )
        return output.count
    }

    private func getLastSnapshotKeys(
        aggregateId: Aggregate.Id,
        limit: Int
    ) async throws -> [(pkey: String, skey: String)] {
        var input = QueryInput(
            expressionAttributeNames: [
                "#aid": "aid",
                "#seq_nr": "seq_nr",
            ],
            expressionAttributeValues: [
                ":aid": .s(aggregateId.description),
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

        let output = try await client.query(input: input)

        guard let items = output.items else { throw EventStoreReadError.itemsIsNIl }

        return try items.map { item in
            guard
                case .s(let aidString) = item["aid"],
                let aggregateId = AggregateId(aidString),
                case .n(let sequenceNumberString) = item["seq_nr"],
                let sequenceNumber = Int(sequenceNumberString),
                case .s(let pkey) = item["pkey"],
                case .s(let skey) = item["skey"]
            else {
                throw EventStoreReadError.invalidSnapshot(output: output)
            }
            logger.debug("EventStoreForDynamoDB.getLastSnapshotKeys aid: \(aggregateId)")
            logger.debug("EventStoreForDynamoDB.getLastSnapshotKeys seq_nr: \(sequenceNumber)")
            return (pkey, skey)
        }
    }

    private func putSnapshot(
        event: Event,
        sequenceNumber: Int,
        aggregate: Aggregate
    ) throws -> DynamoDBClientTypes.Put {
        let pkey = resolvePkey(id: event.aggregateId, shardCount: shardCount)
        let skey = resolveSkey(id: event.aggregateId, sequenceNumber: sequenceNumber)
        let payload = try snapshotSerializer.serialize(aggregate)
        logger.debug("↓ EventStoreForDynamoDB.putSnapshot ↓")
        logger.debug("pkey: \(pkey)")
        logger.debug("skey: \(skey)")
        logger.debug("aid: \(event.aggregateId.description)")
        logger.debug("seq_nr: \(sequenceNumber)")
        logger.debug("↑ EventStoreForDynamoDB.putSnapshot ↑")
        return .init(
            conditionExpression: "attribute_not_exists(pkey) AND attribute_not_exists(skey)",
            item: [
                "pkey": .s(pkey),
                "skey": .s(skey),
                "payload": .b(payload),
                "aid": .s(event.aggregateId.description),
                "seq_nr": .n(String(sequenceNumber)),
                "version": .n("1"),
                "ttl": .n("0"),
                "last_updated_at": .n(String(Int(event.occurredAt.timeIntervalSince1970 * 1000))),
            ],
            tableName: snapshotTableName
        )
    }

    private func updateSnapshot(
        event: Event,
        sequenceNumber: Int,
        version: Int,
        aggregate: Aggregate?
    ) throws -> DynamoDBClientTypes.Update {
        let pkey = resolvePkey(id: event.aggregateId, shardCount: shardCount)
        let skey = resolveSkey(id: event.aggregateId, sequenceNumber: sequenceNumber)
        logger.debug("↓ EventStoreForDynamoDB.updateSnapshot ↓")
        logger.debug("pkey: \(pkey)")
        logger.debug("skey: \(skey)")
        logger.debug("aid: \(event.aggregateId.description)")
        logger.debug("seq_nr: \(sequenceNumber)")
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
                ":seq_nr": .n(String(sequenceNumber)),
                ":payload": .b(payload),
            ]) { $1 }
        }
        return updateSnapshot
    }

    private func resolvePkey(id: AggregateId, shardCount: Int) -> String {
        keyResolver.resolvePartitionKey(id, shardCount)
    }

    private func resolveSkey(id: Aggregate.Id, sequenceNumber: Int) -> String {
        keyResolver.resolveSortKey(id, sequenceNumber)
    }

    private func putJournal(event: Event) throws -> DynamoDBClientTypes.Put {
        return .init(
            conditionExpression: "attribute_not_exists(pkey) AND attribute_not_exists(skey)",
            item: [
                "pkey": .s(resolvePkey(id: event.aggregateId, shardCount: shardCount)),
                "skey": .s(
                    resolveSkey(id: event.aggregateId, sequenceNumber: event.sequenceNumber)
                ),
                "aid": .s(event.aggregateId.description),
                "seq_nr": .n(String(event.sequenceNumber)),
                "payload": .b(try eventSerializer.serialize(event)),
                "occurered_at": .n(String(Int(event.occurredAt.timeIntervalSince1970 * 1000))),
            ],
            tableName: journalTableName
        )
    }

    private func tryPurgeExcessSnapshots(aggregateId: Aggregate.Id) async throws {
        guard keepSnapshotCount != nil else { return }

        if deleteTTL != nil {
            try await updateTTLOfExcessSnapshots(aggregateId: aggregateId)
        } else {
            try await deleteExcessSnapshots(aggregateId: aggregateId)
        }
    }
}
