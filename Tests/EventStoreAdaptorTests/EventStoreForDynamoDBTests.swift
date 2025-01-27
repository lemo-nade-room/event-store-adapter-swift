@preconcurrency import AWSDynamoDB
@preconcurrency import ClientRuntime
import EventStoreAdaptor
import Foundation
import Logging
import PackageTestUtil
@preconcurrency import SmithyHTTPAPI
import Testing

struct UserAccount: Aggregate {
    var id: Id
    var name: String
    var sequenceNumber: Int
    var version: Int
    var lastUpdatedAt: Date

    static func make(id: Id, name: String) -> (Self, Event) {
        var mySelf = Self.init(
            id: id,
            name: name,
            sequenceNumber: 0,
            version: 1,
            lastUpdatedAt: Date()
        )
        mySelf.sequenceNumber += 1
        let event: Event = .created(
            .init(
                id: .init(),
                aggregateId: id,
                sequenceNumber: mySelf.sequenceNumber,
                name: mySelf.name,
                occurredAt: Date()
            )
        )
        return (mySelf, event)
    }

    static func replay(events: [Event], snapshot: UserAccount) -> Self {
        events.reduce(into: snapshot) { snapshot, event in
            snapshot.applyEvent(event: event)
        }
    }

    mutating func applyEvent(event: Event) {
        if case .renamed(let renamed) = event {
            _ = try? rename(name: renamed.name)
        }
    }

    mutating func rename(name: String) throws -> Event {
        if self.name == name {
            throw Error.alreadyRenamed(name: name)
        }
        self.name = name
        self.sequenceNumber += 1
        return .renamed(
            .init(
                id: .init(),
                aggregateId: id,
                sequenceNumber: sequenceNumber,
                name: name,
                occurredAt: Date()
            )
        )
    }

    enum Error: Swift.Error {
        case alreadyRenamed(name: String)
    }

    struct Id: AggregateId {
        static let name = "UserAccount"
        var value: UUID

        init(value: UUID) {
            self.value = value
        }
        init?(_ description: String) {
            guard let value = UUID(uuidString: description) else { return nil }
            self.value = value
        }
        var description: String { value.uuidString }
    }

    enum Event: EventStoreAdaptor.Event {
        case created(Created)
        case renamed(Renamed)

        var id: UUID {
            switch self {
            case .created(let event): event.id
            case .renamed(let event): event.id
            }
        }
        var aggregateId: Id {
            switch self {
            case .created(let event): event.aggregateId
            case .renamed(let event): event.aggregateId
            }
        }
        var occurredAt: Date {
            switch self {
            case .created(let event): event.occurredAt
            case .renamed(let event): event.occurredAt
            }
        }
        var sequenceNumber: Int {
            switch self {
            case .created(let event): event.sequenceNumber
            case .renamed(let event): event.sequenceNumber
            }
        }
        var isCreated: Bool {
            switch self {
            case .created(_): true
            case .renamed(_): false
            }
        }

        struct Created: Sendable, Hashable, Codable {
            var id: UUID
            var aggregateId: UserAccount.Id
            var sequenceNumber: Int
            var name: String
            var occurredAt: Date
        }
        struct Renamed: Sendable, Hashable, Codable {
            var id: UUID
            var aggregateId: UserAccount.Id
            var sequenceNumber: Int
            var name: String
            var occurredAt: Date
        }
    }
}

func findById<Store: EventStore>(
    store: Store,
    id: UserAccount.Id
) async throws -> UserAccount?
where
    Store.Aggregate == UserAccount,
    Store.AggregateId == UserAccount.Id,
    Store.Event == UserAccount.Event
{
    guard let snapshot = try await store.getLatestSnapshotById(aggregateId: id) else {
        return nil
    }
    let events = try await store.getEventsByIdSinceSequenceNumber(
        aggregateId: id, sequenceNumber: snapshot.sequenceNumber + 1)
    return UserAccount.replay(events: events, snapshot: snapshot)
}

@Suite struct EventStoreForDynamoDBTests {
    @Test(.enabled(if: medium))
    func test() async throws {
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = .debug
            return handler
        }
        let logger = Logger(label: "EventStoreForDynamoDBTests.test")
        let client = try await DynamoDBClient(
            config: .init(
                ignoreConfiguredEndpointURLs: true,
                region: "ap-northeast-1",
                endpoint: "http://localhost:8000",
                httpClientEngine: AsyncHTTPClientEngine(httpClient: .shared)
            ))

        let testTimeFactor =
            ProcessInfo.processInfo.environment["TEST_TIME_FACTOR"].flatMap(TimeInterval.init) ?? 1

        let journalTableName = "journal"
        let journalAidIndexName = "journal-aid-index"
        while try await waitTable(client: client, targetTableName: journalTableName) {
            _ = try? await client.deleteTable(input: .init(tableName: journalTableName))
            try await Task.sleep(nanoseconds: UInt64(testTimeFactor) * 1_000_000_00)
        }
        try await createJournalTable(
            logger: logger, client: client, tableName: journalTableName,
            gsiName: journalAidIndexName)

        let snapshotTableName = "snapshot"
        let snapshotAidIndexName = "snapshot-aid-index"
        while try await waitTable(client: client, targetTableName: snapshotTableName) {
            _ = try? await client.deleteTable(input: .init(tableName: snapshotTableName))
            try await Task.sleep(nanoseconds: UInt64(testTimeFactor) * 1_000_000_00)
        }
        try await createSnapshotTable(
            logger: logger, client: client, tableName: snapshotTableName,
            gsiName: snapshotAidIndexName)

        while !(try await waitTable(client: client, targetTableName: journalTableName)) {
            try await Task.sleep(nanoseconds: UInt64(testTimeFactor) * 1_000_000_00)
        }

        while !(try await waitTable(client: client, targetTableName: snapshotTableName)) {
            try await Task.sleep(nanoseconds: UInt64(testTimeFactor) * 1_000_000_00)
        }

        let eventStore: EventStoreForDynamoDB<UserAccount, UserAccount.Event> = .init(
            logger: logger,
            client: client,
            journalTableName: journalTableName,
            journalAidIndexName: journalAidIndexName,
            snapshotTableName: snapshotTableName,
            snapshotAidIndexName: snapshotAidIndexName,
            shardCount: 64,
            keepSnapshotCount: 1,
            deleteTTL: 5
        )

        let id = UserAccount.Id(value: UUID())

        var (userAccount, event) = UserAccount.make(id: id, name: "test")
        try await eventStore.persistEventAndSnapshot(event: event, aggregate: userAccount)

        userAccount = try #require(try await findById(store: eventStore, id: id))
        #expect(userAccount.name == "test")
        #expect(userAccount.sequenceNumber == 1)
        #expect(userAccount.version == 1)

        event = try userAccount.rename(name: "test2")
        try await eventStore.persistEvent(event: event, version: userAccount.version)

        userAccount = try #require(try await findById(store: eventStore, id: id))
        #expect(userAccount.name == "test2")
        #expect(userAccount.sequenceNumber == 2)
        #expect(userAccount.version == 2)

        event = try userAccount.rename(name: "test3")
        try await eventStore.persistEventAndSnapshot(event: event, aggregate: userAccount)

        userAccount = try #require(try await findById(store: eventStore, id: id))
        #expect(userAccount.name == "test3")
        #expect(userAccount.sequenceNumber == 3)
        #expect(userAccount.version == 3)
    }
}
