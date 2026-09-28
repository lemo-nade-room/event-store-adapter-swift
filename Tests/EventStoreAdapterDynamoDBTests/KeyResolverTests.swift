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
    (aid: 1, expected: "account-1"),
    (aid: 2, expected: "account-2"),
  ])
  func `集約の種類と元の識別子を読める専用の保存先を決める`(aid: Int, expected: String) {
    let sut = KeyResolver<AID>()

    let actual = sut.resolvePartitionKey(.init(value: aid))

    #expect(actual == expected)
  }

  @Test(arguments: [
    (seqNr: 0, expected: "0000000000000000000"),
    (seqNr: 1, expected: "0000000000000000001"),
    (seqNr: 9, expected: "0000000000000000009"),
    (seqNr: 10, expected: "0000000000000000010"),
    (seqNr: 99, expected: "0000000000000000099"),
    (seqNr: 100, expected: "0000000000000000100"),
    (seqNr: Int(Int64.max), expected: "9223372036854775807"),
  ])
  func `19桁にゼロ埋めしたイベント番号だけを並び順のキーにする`(
    seqNr: Int,
    expected: String,
  ) {
    let sut = KeyResolver<AID>()

    let actual = sut.resolveSortKey(seqNr)

    #expect(actual == expected)
  }

  @Test(arguments: [
    (earlier: 0, later: 1),
    (earlier: 9, later: 10),
    (earlier: 99, later: 100),
    (earlier: 999_999_999_999_999_999, later: 1_000_000_000_000_000_000),
    (earlier: Int(Int64.max) - 1, later: Int(Int64.max)),
  ])
  func `桁数が変わってもキーはイベント番号の順に並ぶ`(earlier: Int, later: Int) {
    let sut = KeyResolver<AID>()

    let actual = [later, earlier].map(sut.resolveSortKey).sorted()

    #expect(actual == [sut.resolveSortKey(earlier), sut.resolveSortKey(later)])
  }
}
