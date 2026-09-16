import EventStoreAdapter
import EventStoreAdapterDynamoDB
import Testing

@Suite struct KeyResolverTests {
  struct AID: AggregateId {
    static let name = "account"

    let value: Int

    init(value: Int) {
      self.value = value
    }

    init?(_ description: String) {
      guard let value = Int(description) else { return nil }
      self.value = value
    }

    var description: String { String(value) }
  }

  @Test(arguments: [
    (aid: 1, expected: "account-0"),
    (aid: 2, expected: "account-0"),
    (aid: 3, expected: "account-2"),
    (aid: 4, expected: "account-0"),
    (aid: 5, expected: "account-1"),
  ])
  func `The default partition-key resolver assigns aggregate IDs by SHA-256 remainder`(aid: Int, expected: String) {
    let sut = KeyResolver<AID>()

    let actual = sut.resolvePartitionKey(.init(value: aid), 3)

    #expect(actual == expected)
  }

  @Test(arguments: [
    (seqNr: 0, expected: "account-42-0"),
    (seqNr: 1, expected: "account-42-1"),
    (seqNr: 100, expected: "account-42-100"),
  ])
  func `The default sort key includes the aggregate name, ID description, and sequence number`(
    seqNr: Int,
    expected: String,
  ) {
    let sut = KeyResolver<AID>()

    let actual = sut.resolveSortKey(.init(value: 42), seqNr)

    #expect(actual == expected)
  }
}
