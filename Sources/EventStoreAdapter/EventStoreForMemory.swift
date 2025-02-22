public actor EventStoreForMemory<
    Aggregate: EventStoreAdapter.Aggregate,
    Event: EventStoreAdapter.Event
> where Aggregate.Id == Event.AggregateId {
    public var events: [String: [Event]]
    public var snapshots: [String: Aggregate]

    public init(events: [String: [Event]] = [:], snapshots: [String: Aggregate] = [:]) {
        self.events = events
        self.snapshots = snapshots
    }
}

extension EventStoreForMemory: EventStore {
    public typealias AggreageId = Aggregate.Id

    public func persistEvent(event: Event, version: Int) async throws {
        if event.isCreated {
            fatalError("EventStoreForMemory does not support create event.")
        }
        let aid = event.aggregateId.description
        guard var snapshot = snapshots[aid] else {
            throw EventStoreWriteError.otherError(aid)
        }
        if snapshot.version != version {
            throw EventStoreWriteError.optimisticLockError(nil)
        }
        let newVersion = snapshot.version + 1
        var events = self.events[aid.description, default: []]
        events.append(event)
        self.events[aid] = events
        snapshot.version = newVersion
        snapshots[aid] = snapshot
    }

    public func persistEventAndSnapshot(event: Event, aggregate: Aggregate) async throws {
        let aid = event.aggregateId.description
        var newVersion = 1
        if !event.isCreated {
            guard let snapshot = snapshots[aid] else {
                throw EventStoreWriteError.otherError(aid)
            }
            let version = snapshot.version
            if version != aggregate.version {
                throw EventStoreWriteError.optimisticLockError(nil)
            }
            newVersion = snapshot.version + 1
        }
        var events = self.events[aid, default: []]
        events.append(event)
        self.events[aid] = events

        var aggregate = aggregate
        aggregate.version = newVersion
        snapshots[aid] = aggregate
    }

    public func getLatestSnapshotById(aggregateId: Aggregate.Id) async throws -> Aggregate? {
        snapshots[aggregateId.description]
    }

    public func getEventsByIdSinceSequenceNumber(
        aggregateId: Aggregate.Id,
        sequenceNumber: Int
    ) async throws -> [Event] {
        events[aggregateId.description, default: []].filter { $0.sequenceNumber >= sequenceNumber }
    }
}
