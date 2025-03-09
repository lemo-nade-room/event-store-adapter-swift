import EventStoreAdapter

extension SampleAggregate {
    package struct AID: AggregateId {
        package var value: Int
        package static let name = "sample_aggregate_id"
        package init(value: Int) {
            self.value = value
        }
        package init?(_ description: String) {
            guard let value = Int(description) else { return nil }
            self.value = value
        }
        package var description: String { String(value) }
    }
}
