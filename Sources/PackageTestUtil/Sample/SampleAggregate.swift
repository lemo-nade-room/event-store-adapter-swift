import EventStoreAdaptor
import Foundation

package struct SampleAggregate: EventStoreAdaptor.Aggregate {
    package var id: SampleAggregateId
    package var value: String
    package var sequenceNumber: Int
    package var version: Int
    package var lastUpdatedAt: Date

    package init(
        id: SampleAggregateId,
        value: String,
        sequenceNumber: Int,
        version: Int,
        lastUpdatedAt: Date
    ) {
        self.id = id
        self.value = value
        self.sequenceNumber = sequenceNumber
        self.version = version
        self.lastUpdatedAt = lastUpdatedAt
    }
}
