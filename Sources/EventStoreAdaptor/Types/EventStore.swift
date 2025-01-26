/// イベントストアを表すプロトコル
public protocol EventStore: Sendable {
    associatedtype Event: EventStoreAdaptor.Event
    associatedtype Aggregate: EventStoreAdaptor.Aggregate
    associatedtype AggregateId: EventStoreAdaptor.AggregateId
    
    func persistEvent(event: Event, version: Int) async throws

    func persistEventAndSnapshot(event: Event, aggregate: Aggregate) async throws
    
    func getLatestSnapshotById(aggregateId: AggregateId) async throws -> Aggregate?
    
    func getEventsByIdSinceSequenceNumber(aggregateId: AggregateId, sequenceNumber: Int) async throws -> [Event]
}
