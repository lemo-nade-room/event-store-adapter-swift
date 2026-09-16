import Configuration
import EventStoreAdapter
import EventStoreAdapterDynamoDB
import Foundation
import Logging
import SotoDynamoDB
import SystemPackage
import Testing

@Suite struct EventStoreForDynamoDBTests {
  @Test(.enabled(if: .medium))
  func `A creation event and initial snapshot are persisted together`() async throws {
    try await withEventStoreForDynamoDB { sut in
      // Arrange
      let aid = UserAccount.ID(value: UUID())
      let now = try Date.ISO8601FormatStyle.iso8601.parse("2026-02-03T12:34:56Z")

      let (account, created) = UserAccount.create(id: aid, name: "Alice")

      let event = try EventEnvelope(
        id: UUID(),
        aid: aid,
        seqNr: 1,
        occurredAt: now,
        event: created,
        metadata: ["source": "event-store-test"],
      )
      let snapshot = try await SnapshotEnvelope(
        snapshot: account.snapshot,
        seqNr: 1,
        version: 1,
        lastUpdatedAt: now,
      )

      // Act
      try await sut.persistEventAndSnapshot(event: event, snapshot: snapshot)

      // Assert
      let actualEvents = try await sut.getEventsByAIDSinceSequenceNumber(aid: aid, seqNr: 1)
      #expect(actualEvents == [event])

      let actualSnapshot = try await sut.getLatestSnapshotByAID(aid: aid)
      #expect(actualSnapshot == snapshot)
    }
  }

  @Test(.enabled(if: .medium))
  func `An update event and its updated snapshot are persisted together`() async throws {
    try await withEventStoreForDynamoDB { sut in
      // Arrange
      let aid = UserAccount.ID(value: UUID())

      let createdAt = try Date.ISO8601FormatStyle.iso8601.parse("2026-02-03T12:34:56Z")
      do {
        let (account, created) = UserAccount.create(id: aid, name: "Alice")
        try await sut.persistEventAndSnapshot(
          event: try EventEnvelope(
            id: UUID(),
            aid: aid,
            seqNr: 1,
            occurredAt: createdAt,
            event: created,
            metadata: ["source": "event-store-test"],
          ),
          snapshot: try await SnapshotEnvelope(
            snapshot: account.snapshot,
            seqNr: 1,
            version: 1,
            lastUpdatedAt: createdAt,
          ),
        )
      }

      let updatedAt = try Date.ISO8601FormatStyle.iso8601.parse("2026-02-04T12:35:56Z")
      let accountSnapshot = try #require(try await sut.getLatestSnapshotByAID(aid: aid))
      let account = UserAccount(snapshot: try accountSnapshot.snapshot)
      let deactivated = try await account.deactivate()

      let event = try EventEnvelope(
        id: UUID(),
        aid: aid,
        seqNr: accountSnapshot.seqNr + 1,
        occurredAt: updatedAt,
        event: deactivated,
        metadata: ["source": "event-store-test"],
      )
      let snapshot = try await SnapshotEnvelope(
        snapshot: account.snapshot,
        seqNr: accountSnapshot.seqNr + 1,
        version: accountSnapshot.version,
        lastUpdatedAt: updatedAt,
      )

      // Act
      try await sut.persistEventAndSnapshot(event: event, snapshot: snapshot)

      // Assert
      let actualEvents = try await sut.getEventsByAIDSinceSequenceNumber(aid: aid, seqNr: 2)
      #expect(actualEvents == [event])

      let actualSnapshot = try await sut.getLatestSnapshotByAID(aid: aid)
      var expectedSnapshot = snapshot
      expectedSnapshot.version += 1
      #expect(actualSnapshot == expectedSnapshot)
    }
  }

  @Test(.enabled(if: .medium))
  func `Mismatched aggregate IDs prevent any persistence`() async throws {
    try await withEventStoreForDynamoDB { sut in
      // Arrange
      let eventAID = UserAccount.ID(value: UUID())
      let snapshotAID = UserAccount.ID(value: UUID())

      let now = try Date.ISO8601FormatStyle.iso8601.parse("2026-02-03T12:34:56Z")

      let (account, created) = UserAccount.create(id: snapshotAID, name: "Alice")

      let event = try EventEnvelope(
        id: UUID(),
        aid: eventAID,
        seqNr: 1,
        occurredAt: now,
        event: created,
        metadata: ["source": "event-store-test"],
      )
      let snapshot = try await SnapshotEnvelope(
        snapshot: account.snapshot,
        seqNr: 1,
        version: 1,
        lastUpdatedAt: now,
      )

      // Act
      let error = try await #require(throws: EventStoreWriteError.self) {
        try await sut.persistEventAndSnapshot(event: event, snapshot: snapshot)
      }

      // Assert
      guard case .otherError(_) = error else {
        Issue.record("Expected EventStoreWriteError.otherError")
        return
      }

      let actualEvents = try await sut.getEventsByAIDSinceSequenceNumber(aid: eventAID, seqNr: 1)
      #expect(actualEvents == [])

      let actualSnapshot = try await sut.getLatestSnapshotByAID(aid: snapshotAID)
      #expect(actualSnapshot == nil)
    }
  }

  @Test(.enabled(if: .medium))
  func `Mismatched sequence numbers prevent any persistence`() async throws {
    try await withEventStoreForDynamoDB { sut in
      // Arrange
      let aid = UserAccount.ID(value: UUID())

      let now = try Date.ISO8601FormatStyle.iso8601.parse("2026-02-03T12:34:56Z")

      let (account, created) = UserAccount.create(id: aid, name: "Alice")

      let event = try EventEnvelope(
        id: UUID(),
        aid: aid,
        seqNr: 1,
        occurredAt: now,
        event: created,
        metadata: ["source": "event-store-test"],
      )
      let snapshot = try await SnapshotEnvelope(
        snapshot: account.snapshot,
        seqNr: 2,
        version: 1,
        lastUpdatedAt: now,
      )

      // Act
      let error = try await #require(throws: EventStoreWriteError.self) {
        try await sut.persistEventAndSnapshot(event: event, snapshot: snapshot)
      }

      // Assert
      guard case .otherError(_) = error else {
        Issue.record("Expected EventStoreWriteError.otherError")
        return
      }

      let actualEvents = try await sut.getEventsByAIDSinceSequenceNumber(aid: aid, seqNr: 1)
      #expect(actualEvents == [])

      let actualSnapshot = try await sut.getLatestSnapshotByAID(aid: aid)
      #expect(actualSnapshot == nil)
    }
  }

  @Test(.enabled(if: .medium))
  func `An event serialization failure prevents any persistence`() async throws {
    // Arrange
    struct SerializeError: Error, Sendable, Hashable {}
    var eventSerializer: UserAccountEventSerializer = .json()
    eventSerializer.serialize = { _ in throw SerializeError() }

    try await withEventStoreForDynamoDB(eventSerializer: eventSerializer) { sut in
      let aid = UserAccount.ID(value: UUID())

      let now = try Date.ISO8601FormatStyle.iso8601.parse("2026-02-03T12:34:56Z")

      let (account, created) = UserAccount.create(id: aid, name: "Alice")

      let event = try EventEnvelope(
        id: UUID(),
        aid: aid,
        seqNr: 1,
        occurredAt: now,
        event: created,
        metadata: ["source": "event-store-test"],
      )
      let snapshot = try await SnapshotEnvelope(
        snapshot: account.snapshot,
        seqNr: 1,
        version: 1,
        lastUpdatedAt: now,
      )

      // Act
      let error = try await #require(throws: EventStoreWriteError.self) {
        try await sut.persistEventAndSnapshot(event: event, snapshot: snapshot)
      }

      // Assert
      guard case .serializationError(_) = error else {
        Issue.record("Expected EventStoreWriteError.serializationError")
        return
      }

      let actualEvents = try await sut.getEventsByAIDSinceSequenceNumber(aid: aid, seqNr: 1)
      #expect(actualEvents == [])

      let actualSnapshot = try await sut.getLatestSnapshotByAID(aid: aid)
      #expect(actualSnapshot == nil)
    }
  }

  @Test(.enabled(if: .medium))
  func `A snapshot serialization failure prevents any persistence`() async throws {
    // Arrange
    struct SerializeError: Error, Sendable, Hashable {}
    var snapshotSerializer: UserAccountSnapshotSerializer = .json()
    snapshotSerializer.serialize = { _ in throw SerializeError() }

    try await withEventStoreForDynamoDB(snapshotSerializer: snapshotSerializer) { sut in
      let aid = UserAccount.ID(value: UUID())

      let now = try Date.ISO8601FormatStyle.iso8601.parse("2026-02-03T12:34:56Z")

      let (account, created) = UserAccount.create(id: aid, name: "Alice")

      let event = try EventEnvelope(
        id: UUID(),
        aid: aid,
        seqNr: 1,
        occurredAt: now,
        event: created,
        metadata: ["source": "event-store-test"],
      )
      let snapshot = try await SnapshotEnvelope(
        snapshot: account.snapshot,
        seqNr: 1,
        version: 1,
        lastUpdatedAt: now,
      )

      // Act
      let error = try await #require(throws: EventStoreWriteError.self) {
        try await sut.persistEventAndSnapshot(event: event, snapshot: snapshot)
      }

      // Assert
      guard case .serializationError(_) = error else {
        Issue.record("Expected EventStoreWriteError.serializationError")
        return
      }

      let actualEvents = try await sut.getEventsByAIDSinceSequenceNumber(aid: aid, seqNr: 1)
      #expect(actualEvents == [])

      let actualSnapshot = try await sut.getLatestSnapshotByAID(aid: aid)
      #expect(actualSnapshot == nil)
    }
  }

  @Test(.enabled(if: .medium))
  func `An unrepresentable event timestamp prevents any persistence`() async throws {
    try await withEventStoreForDynamoDB { sut in
      // Arrange
      let aid = UserAccount.ID(value: UUID())

      let now = Date(timeIntervalSince1970: .nan)

      let (account, created) = UserAccount.create(id: aid, name: "Alice")

      let event = try EventEnvelope(
        id: UUID(),
        aid: aid,
        seqNr: 1,
        occurredAt: now,
        event: created,
        metadata: ["source": "event-store-test"],
      )
      let snapshot = try await SnapshotEnvelope(
        snapshot: account.snapshot,
        seqNr: 1,
        version: 1,
        lastUpdatedAt: now,
      )

      // Act
      let error = try await #require(throws: EventStoreWriteError.self) {
        try await sut.persistEventAndSnapshot(event: event, snapshot: snapshot)
      }

      // Assert
      guard case .otherError(_) = error else {
        Issue.record("Expected EventStoreWriteError.otherError")
        return
      }

      let actualEvents = try await sut.getEventsByAIDSinceSequenceNumber(aid: aid, seqNr: 1)
      #expect(actualEvents == [])

      let actualSnapshot = try await sut.getLatestSnapshotByAID(aid: aid)
      #expect(actualSnapshot == nil)
    }
  }

  @Test(.enabled(if: .medium))
  func `A duplicate creation write fails with an optimistic lock error`()
    async throws
  {
    try await withEventStoreForDynamoDB { sut in
      // Arrange
      let aid = UserAccount.ID(value: UUID())
      let createdAt = try Date.ISO8601FormatStyle.iso8601.parse("2026-02-03T12:34:56Z")
      let (account, created) = UserAccount.create(id: aid, name: "Alice")
      let persistedEvent = try EventEnvelope(
        id: UUID(),
        aid: aid,
        seqNr: 1,
        occurredAt: createdAt,
        event: created,
        metadata: ["source": "event-store-test"],
      )
      let persistedSnapshot = try await SnapshotEnvelope(
        snapshot: account.snapshot,
        seqNr: 1,
        version: 1,
        lastUpdatedAt: createdAt,
      )
      try await sut.persistEventAndSnapshot(event: persistedEvent, snapshot: persistedSnapshot)

      let retriedAt = try Date.ISO8601FormatStyle.iso8601.parse("2026-02-04T12:34:56Z")
      let (retriedAccount, retriedCreation) = UserAccount.create(id: aid, name: "Eve")
      let retriedEvent = try EventEnvelope(
        id: UUID(),
        aid: aid,
        seqNr: 1,
        occurredAt: retriedAt,
        event: retriedCreation,
        metadata: ["source": "event-store-test"],
      )
      let retriedSnapshot = try await SnapshotEnvelope(
        snapshot: retriedAccount.snapshot,
        seqNr: 1,
        version: 1,
        lastUpdatedAt: retriedAt,
      )

      // Act
      let error = try await #require(throws: EventStoreWriteError.self) {
        try await sut.persistEventAndSnapshot(event: retriedEvent, snapshot: retriedSnapshot)
      }

      // Assert
      guard case .optimisticLockError(_) = error else {
        Issue.record("Expected EventStoreWriteError.optimisticLockError")
        return
      }

      let actualEvents = try await sut.getEventsByAIDSinceSequenceNumber(aid: aid, seqNr: 1)
      #expect(actualEvents == [persistedEvent])

      let actualSnapshot = try await sut.getLatestSnapshotByAID(aid: aid)
      #expect(actualSnapshot == persistedSnapshot)
    }
  }

  @Test(.enabled(if: .medium))
  func `A stale update fails with an optimistic lock error after another update succeeds`()
    async throws
  {
    try await withEventStoreForDynamoDB { sut in
      // Arrange
      let aid = UserAccount.ID(value: UUID())
      let createdAt = try Date.ISO8601FormatStyle.iso8601.parse("2026-02-03T12:34:56Z")
      let (account, created) = UserAccount.create(id: aid, name: "Alice")
      try await sut.persistEventAndSnapshot(
        event: try EventEnvelope(
          id: UUID(),
          aid: aid,
          seqNr: 1,
          occurredAt: createdAt,
          event: created,
          metadata: ["source": "event-store-test"],
        ),
        snapshot: try await SnapshotEnvelope(
          snapshot: account.snapshot,
          seqNr: 1,
          version: 1,
          lastUpdatedAt: createdAt,
        ),
      )

      let initialSnapshot = try #require(try await sut.getLatestSnapshotByAID(aid: aid))
      let winningAccount = UserAccount(snapshot: try initialSnapshot.snapshot)
      let staleAccount = UserAccount(snapshot: try initialSnapshot.snapshot)

      let winningUpdatedAt = try Date.ISO8601FormatStyle.iso8601.parse("2026-02-04T12:34:56Z")
      let winningEvent = try EventEnvelope(
        id: UUID(),
        aid: aid,
        seqNr: initialSnapshot.seqNr + 1,
        occurredAt: winningUpdatedAt,
        event: try await winningAccount.deactivate(),
        metadata: ["source": "event-store-test"],
      )
      let winningSnapshot = try await SnapshotEnvelope(
        snapshot: winningAccount.snapshot,
        seqNr: initialSnapshot.seqNr + 1,
        version: initialSnapshot.version,
        lastUpdatedAt: winningUpdatedAt,
      )
      try await sut.persistEventAndSnapshot(event: winningEvent, snapshot: winningSnapshot)

      let staleUpdatedAt = try Date.ISO8601FormatStyle.iso8601.parse("2026-02-04T12:35:56Z")
      let staleEvent = try EventEnvelope(
        id: UUID(),
        aid: aid,
        seqNr: initialSnapshot.seqNr + 1,
        occurredAt: staleUpdatedAt,
        event: try await staleAccount.rename(to: "Eve"),
        metadata: ["source": "event-store-test"],
      )
      let staleSnapshot = try await SnapshotEnvelope(
        snapshot: staleAccount.snapshot,
        seqNr: initialSnapshot.seqNr + 1,
        version: initialSnapshot.version,
        lastUpdatedAt: staleUpdatedAt,
      )

      // Act
      let error = try await #require(throws: EventStoreWriteError.self) {
        try await sut.persistEventAndSnapshot(event: staleEvent, snapshot: staleSnapshot)
      }

      // Assert
      guard case .optimisticLockError(_) = error else {
        Issue.record("Expected EventStoreWriteError.optimisticLockError")
        return
      }

      let actualEvents = try await sut.getEventsByAIDSinceSequenceNumber(aid: aid, seqNr: 2)
      #expect(actualEvents == [winningEvent])

      let actualSnapshot = try await sut.getLatestSnapshotByAID(aid: aid)
      var expectedSnapshot = winningSnapshot
      expectedSnapshot.version += 1
      #expect(actualSnapshot == expectedSnapshot)
    }
  }
}

fileprivate typealias UserAccountEventStore = EventStoreForDynamoDB<
  EventEnvelope<UserAccount.Event, UserAccount.ID>,
  SnapshotEnvelope<UserAccount.Snapshot>,
>
fileprivate typealias UserAccountEventSerializer = EventSerializer<EventEnvelope<UserAccount.Event, UserAccount.ID>>
fileprivate typealias UserAccountSnapshotSerializer = SnapshotSerializer<SnapshotEnvelope<UserAccount.Snapshot>>

fileprivate func withEventStoreForDynamoDB(
  eventSerializer: UserAccountEventSerializer? = nil,
  snapshotSerializer: UserAccountSnapshotSerializer? = nil,
  action: @Sendable (UserAccountEventStore) async throws -> Void,
) async throws {
  let config = await ConfigReader(providers: [
    EnvironmentVariablesProvider(),
    try EnvironmentVariablesProvider(environmentFilePath: ".env.testing", allowMissing: true),
  ])
  let awsAccessKeyID = config.string(forKey: "aws.access.key.id") ?? "dummy"
  let awsSecretAccessKey = config.string(forKey: "aws.secret.access.key") ?? "dummy"
  let awsRegion: Region = config.string(forKey: "aws.region").flatMap(Region.init(awsRegionName:)) ?? .apnortheast1
  let awsEndpointURLDynamoDB = try config.requiredString(forKey: "aws.endpoint.url.dynamodb")

  let awsClient = AWSClient(
    credentialProvider: .static(accessKeyId: awsAccessKeyID, secretAccessKey: awsSecretAccessKey)
  )
  let dynamoDB = DynamoDB(client: awsClient, region: awsRegion, endpoint: awsEndpointURLDynamoDB)
  let eventStoreConfiguration = EventStoreForDynamoDBConfiguration(config: config)
  let logger = Logger(label: "EventStoreForDynamoDBTests")
  let eventStore = UserAccountEventStore(
    logger: logger,
    dynamoDB: dynamoDB,
    config: eventStoreConfiguration,
    eventSerializer: eventSerializer ?? .json(),
    snapshotSerializer: snapshotSerializer ?? .json(),
  )

  do {
    try await action(eventStore)
    try await awsClient.shutdown()
  } catch {
    try? await awsClient.shutdown()
    throw error
  }
}
