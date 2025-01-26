import EventStoreAdaptor
import PackageTestUtil
import Testing

@Suite struct KeyResolverTests {
    @Test(
        .enabled(if: small),
        arguments: [
            (id: 1, expected: "sample_aggregate_id-0"),
            (id: 2, expected: "sample_aggregate_id-0"),
            (id: 3, expected: "sample_aggregate_id-2"),
            (id: 4, expected: "sample_aggregate_id-0"),
            (id: 5, expected: "sample_aggregate_id-1"),
        ]
    )
    func resolvePartitionKey(id: Int, expected: String) async throws {
        let sut = KeyResolver<SampleAggregateId>()
        let id = SampleAggregateId(value: id)

        let result = sut.resolvePartitionKey(id, 3)

        #expect(result == expected)
    }
    
    @Test(.enabled(if: small))
    func resolveSortKey() async throws {
        let sut = KeyResolver<SampleAggregateId>()
        let id = SampleAggregateId(value: 2)

        let result = sut.resolveSortKey(id, 3)

        #expect(result == "sample_aggregate_id-2-3")
    }
}
