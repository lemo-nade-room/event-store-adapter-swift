import EventStoreAdaptor
import Foundation

package struct SampleEvent: Event {
    package var id: Int
    package var aggregateId: SampleAggregateId
    package var sequenceNumber: Int
    package var occurredAt: Date
    package var isCreated: Bool

    package init(
        id: Int,
        aggregateId: SampleAggregateId,
        sequenceNumber: Int,
        occurredAt: Date,
        isCreated: Bool
    ) {
        self.id = id
        self.aggregateId = aggregateId
        self.sequenceNumber = sequenceNumber
        self.occurredAt = occurredAt
        self.isCreated = isCreated
    }
}
