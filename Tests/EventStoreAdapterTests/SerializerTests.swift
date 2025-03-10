import EventStoreAdapter
import EventStoreAdapterDynamoDB
import Foundation
import Testing

@Suite struct SerializerTests {
    @Test(.enabled(if: small))
    func event() throws {
        // Arrange
        let sut = EventSerializer<SampleEvent>()

        let event = SampleEvent(
            id: 2,
            aid: .init(value: 3),
            seqNr: 4,
            occurredAt: ISO8601DateFormatter().date(from: "2024-01-24T12:34:56Z")!,
            isCreated: false
        )
        let serialized = try sut.serialize(event)

        // Act
        let deserialized = try sut.deserialize(serialized)

        // Assert
        #expect(deserialized == event)
    }

    @Test(.enabled(if: small))
    func snapshot() throws {
        // Arrange
        let sut = SnapshotSerializer<SampleAggregate>()

        let aggregate = SampleAggregate(
            aid: .init(value: 5),
            value: "Hello, World!",
            seqNr: 23,
            version: 45,
            lastUpdatedAt: ISO8601DateFormatter().date(from: "2020-01-01T00:00:00Z")!
        )
        let serialized = try sut.serialize(aggregate)

        // Act
        let deserialized = try sut.deserialize(serialized)

        // Assert
        #expect(deserialized == aggregate)
    }
}
