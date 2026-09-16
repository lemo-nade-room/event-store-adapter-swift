import EventStoreAdapterDynamoDB
import Foundation
import Testing

@Suite struct SnapshotSerializerTests {
  @Test func `A snapshot can be serialized to JSON and restored`() async throws {
    let aid = UserAccount.ID(
      value: try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    )
    let snapshot = try SnapshotEnvelope<UserAccount.Snapshot>(
      snapshot: .init(id: aid, state: .active),
      seqNr: 1,
      version: 1,
      lastUpdatedAt: Date(timeIntervalSince1970: 1),
    )
    let serializer = SnapshotSerializer<SnapshotEnvelope<UserAccount.Snapshot>>.json()

    let data = try await serializer.serialize(snapshot)
    let deserialized = try await serializer.deserialize(data)

    #expect(deserialized == snapshot)
  }

  @Test func `JSON data can be deserialized into a snapshot`() async throws {
    let serializer = SnapshotSerializer<SnapshotEnvelope<UserAccount.Snapshot>>.json()
    let aid = UserAccount.ID(
      value: try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    )
    let expected = try SnapshotEnvelope<UserAccount.Snapshot>(
      snapshot: .init(id: aid, state: .active),
      seqNr: 1,
      version: 1,
      lastUpdatedAt: Date(timeIntervalSince1970: 1),
    )
    let data = Data(
      """
      {
        "aggregate": "UserAccount",
        "aid": {
          "value": "00000000-0000-0000-0000-000000000001"
        },
        "lastUpdatedAt": -978307199,
        "payload": "eyJpZCI6eyJ2YWx1ZSI6IjAwMDAwMDAwLTAwMDAtMDAwMC0wMDAwLTAwMDAwMDAwMDAwMSJ9LCJzdGF0ZSI6ImFjdGl2ZSJ9",
        "seqNr": 1,
        "version": 1
      }
      """
      .utf8
    )

    let snapshot = try await serializer.deserialize(data)

    #expect(snapshot == expected)
  }

  @Test func `The default JSON serializer writes snapshot object keys in sorted order`() async throws {
    let aid = UserAccount.ID(
      value: try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    )
    let snapshot = try SnapshotEnvelope<UserAccount.Snapshot>(
      snapshot: .init(id: aid, state: .active),
      seqNr: 1,
      version: 1,
      lastUpdatedAt: Date(timeIntervalSince1970: 1),
    )
    let serializer = SnapshotSerializer<SnapshotEnvelope<UserAccount.Snapshot>>.json()

    let data = try await serializer.serialize(snapshot)

    #expect(
      String(decoding: data, as: UTF8.self)
        == #"{"aggregate":"UserAccount","aid":{"value":"00000000-0000-0000-0000-000000000001"},"lastUpdatedAt":-978307199,"payload":"eyJpZCI6eyJ2YWx1ZSI6IjAwMDAwMDAwLTAwMDAtMDAwMC0wMDAwLTAwMDAwMDAwMDAwMSJ9LCJzdGF0ZSI6ImFjdGl2ZSJ9","seqNr":1,"version":1}"#
    )
  }
}
