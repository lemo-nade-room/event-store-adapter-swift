import EventStoreAdapter
package import Foundation

package struct SampleEvent: Event {
  package var id: Int
  package var aid: SampleAggregate.AID
  package var seqNr: Int
  package var occurredAt: Date
  package var isCreated: Bool

  package init(
    id: Int,
    aid: SampleAggregate.AID,
    seqNr: Int,
    occurredAt: Date,
    isCreated: Bool
  ) {
    self.id = id
    self.aid = aid
    self.seqNr = seqNr
    self.occurredAt = occurredAt
    self.isCreated = isCreated
  }
}
