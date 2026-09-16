import EventStoreAdapter
import Foundation

struct EventEnvelope<
  Event: Sendable & Hashable & Codable,
  AID: AggregateId & Codable,
>: EventStoreAdapter.Event, Codable {
  var id: UUID
  var aggregate: String
  var payload: Data
  var aid: AID
  var seqNr: Int
  var occurredAt: Date
  var metadata: [String: String]

  init(
    id: UUID,
    aggregate: String = AID.name,
    aid: AID,
    seqNr: Int,
    occurredAt: Date,
    event: Event,
    metadata: [String: String],
  ) throws {
    self.id = id
    self.aggregate = aggregate
    self.aid = aid
    self.seqNr = seqNr
    self.occurredAt = occurredAt
    self.payload = try deterministicJSONData(event)
    self.metadata = metadata
  }
}
