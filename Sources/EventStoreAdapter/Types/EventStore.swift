/// イベントストアを表すプロトコル
public protocol EventStore: Sendable {
    associatedtype Event: EventStoreAdapter.Event
    associatedtype Aggregate: EventStoreAdapter.Aggregate
    associatedtype AID: EventStoreAdapter.AggregateId

    func persistEvent(event: Event, version: Int) async throws

    func persistEventAndSnapshot(event: Event, aggregate: Aggregate) async throws

    func getLatestSnapshotByAID(aid: AID) async throws -> Aggregate?

    func getEventsByAIDSinceSequenceNumber(aid: AID, seqNr: Int) async throws -> [Event]
}

public enum EventStoreWriteError: Swift.Error {
    case serializationError(any Error)
    case optimisticLockError((any Error)?)
    case IOError(any Error)
    case otherError(String)
}

public enum EventStoreReadError: Swift.Error {
    case deserializationError(any Swift.Error)
    case IOError(any Swift.Error)
    case otherError(String)
}
