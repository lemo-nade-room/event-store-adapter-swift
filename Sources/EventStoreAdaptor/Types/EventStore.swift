/// イベントストアを表すプロトコル
public protocol EventStore: Sendable {
    associatedtype Event: EventStoreAdaptor.Event
    associatedtype Aggregate: EventStoreAdaptor.Aggregate
    associatedtype AggregateId: EventStoreAdaptor.AggregateId

    func persistEvent(event: Event, version: Int) async throws

    func persistEventAndSnapshot(event: Event, aggregate: Aggregate) async throws

    func getLatestSnapshotById(aggregateId: AggregateId) async throws -> Aggregate?

    func getEventsByIdSinceSequenceNumber(aggregateId: AggregateId, sequenceNumber: Int)
        async throws -> [Event]
}

public enum EventStoreWriteError: Swift.Error {
    case serializationError(any Error)
    case optimisticLockError((any Error)?)
    case IOError(any Error)
    case otherError(String)
}

public enum EventStoreReadError {
    case deserializationError(any Error)
    case ioError(any Error)
    case otherError(String)
}
