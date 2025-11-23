import EventStoreAdapter
import EventStoreAdapterDynamoDB
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
  func resolvePartitionKey(aid: Int, expected: String) async throws {
    let sut = KeyResolver<SampleAggregate.AID>()
    let aid = SampleAggregate.AID(value: aid)

    let result = sut.resolvePartitionKey(aid, 3)

    #expect(result == expected)
  }

  @Test(.enabled(if: small))
  func resolveSortKey() async throws {
    let sut = KeyResolver<SampleAggregate.AID>()
    let aid = SampleAggregate.AID(value: 2)

    let result = sut.resolveSortKey(aid, 3)

    #expect(result == "sample_aggregate_id-2-3")
  }
}
