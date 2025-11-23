public import EventStoreAdapter

/// メモリ内のイベントストア
public actor EventStoreForMemory<
  Aggregate: EventStoreAdapter.Aggregate,
  Event: EventStoreAdapter.Event
> where Aggregate.AID == Event.AID {
  public var events: [String: [Event]]
  public var snapshots: [String: Aggregate]

  public init(events: [String: [Event]] = [:], snapshots: [String: Aggregate] = [:]) {
    self.events = events
    self.snapshots = snapshots
  }
}

extension EventStoreForMemory: EventStore {
  public typealias AID = Aggregate.AID

  public func persistEvent(event: Event, version: Int) async throws {
    if event.isCreated {
      fatalError("EventStoreForMemory does not support create event.")
    }
    let aid = event.aid.description
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
    let aid = event.aid.description
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

  public func getLatestSnapshotByAID(aid: Aggregate.AID) async throws -> Aggregate? {
    snapshots[aid.description]
  }

  public func getEventsByAIDSinceSequenceNumber(
    aid: Aggregate.AID,
    seqNr: Int
  ) async throws -> [Event] {
    events[aid.description, default: []].filter { $0.seqNr >= seqNr }
  }
}
