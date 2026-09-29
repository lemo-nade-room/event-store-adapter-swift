import EventStoreAdapter
import EventStoreAdapterDynamoDB
import Testing

@Suite struct ResolveAIDPartitionKeyTests {
  @Test(arguments: [
    (id: "123", expected: "UserAccount-123"),
    (id: "00042", expected: "UserAccount-00042"),
    (id: "user-123", expected: "UserAccount-user-123"),
    (id: "顧客/東京", expected: "UserAccount-顧客/東京"),
  ])
  func `集約名と識別子をそのままハイフンでつないだ保存キーを生成する`(id: String, expected: String) {
    let aid = AccountID(id)

    let key = resolveAIDPartitionKey(aid: aid)

    #expect(key == expected)
  }

  @Test func `同じ識別子でも集約の種類が異なれば保存キーを区別できる`() {
    let accountID = AccountID("123")
    let orderID = OrderID("123")

    let keys = [resolveAIDPartitionKey(aid: accountID), resolveAIDPartitionKey(OrderID.self, aid: orderID)]

    #expect(keys == ["UserAccount-123", "Order-123"])
  }

  private struct AccountID: AggregateId {
    static let name = "UserAccount"
    let description: String

    init(_ description: String) {
      self.description = description
    }
  }

  private struct OrderID: AggregateId {
    static let name = "Order"
    let description: String

    init(_ description: String) {
      self.description = description
    }
  }
}
