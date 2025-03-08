import EventStoreAdapter
import Foundation

package struct SampleAggregate: EventStoreAdapter.Aggregate {
    package var aid: AID
    package var value: String
    package var seqNr: Int
    package var version: Int
    package var lastUpdatedAt: Date

    package init(
        aid: AID,
        value: String,
        seqNr: Int,
        version: Int,
        lastUpdatedAt: Date
    ) {
        self.aid = aid
        self.value = value
        self.seqNr = seqNr
        self.version = version
        self.lastUpdatedAt = lastUpdatedAt
    }
}
