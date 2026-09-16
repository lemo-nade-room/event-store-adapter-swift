import EventStoreAdapter
import Foundation

struct SnapshotEnvelope<
  Snapshot: Sendable & Hashable & Codable & Identifiable
>: EventStoreAdapter.Snapshot, Codable where Snapshot.ID: AggregateId & Codable {
  var aggregate: String
  var payload: Data
  var aid: Snapshot.ID
  var seqNr: Int
  var version: Int
  var lastUpdatedAt: Date

  init(
    aggregate: String = Snapshot.ID.name,
    snapshot: Snapshot,
    seqNr: Int,
    version: Int,
    lastUpdatedAt: Date,
  ) throws {
    self.aggregate = aggregate
    self.payload = try deterministicJSONData(snapshot)
    self.aid = snapshot.id
    self.seqNr = seqNr
    self.version = version
    self.lastUpdatedAt = lastUpdatedAt
  }

  var snapshot: Snapshot {
    get throws {
      try JSONDecoder().decode(Snapshot.self, from: payload)
    }
  }
}
