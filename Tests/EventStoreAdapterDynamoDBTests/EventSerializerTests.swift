import EventStoreAdapterDynamoDB
import Foundation
import Testing

@Suite struct EventSerializerTests {
  @Suite struct JSON {
    @Test func `Serializing with a custom encoder preserves its formatting`() async throws {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [
        .prettyPrinted,
        .sortedKeys,
      ]
      let aid = UserAccount.ID(
        value: try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
      )
      let (_, created) = UserAccount.create(id: aid, name: "Alice")
      let event = try EventEnvelope(
        id: try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002")),
        aggregate: UserAccount.ID.name,
        aid: aid,
        seqNr: 1,
        occurredAt: Date(timeIntervalSince1970: 1),
        event: created,
        metadata: ["source": "event-store-test"],
      )
      let sut = EventSerializer<EventEnvelope<UserAccount.Event, UserAccount.ID>>.json(encoder: encoder)

      let data = try await sut.serialize(event)

      #expect(
        String(data: data, encoding: .utf8) == """
          {
            "aggregate" : "UserAccount",
            "aid" : {
              "value" : "00000000-0000-0000-0000-000000000001"
            },
            "id" : "00000000-0000-0000-0000-000000000002",
            "metadata" : {
              "source" : "event-store-test"
            },
            "occurredAt" : -978307199,
            "payload" : "eyJjcmVhdGVkIjp7Im5hbWUiOiJBbGljZSJ9fQ==",
            "seqNr" : 1
          }
          """
      )
    }

    @Test func `JSON data can be deserialized into an event`() async throws {
      let serializer = EventSerializer<EventEnvelope<UserAccount.Event, UserAccount.ID>>.json()
      let aid = UserAccount.ID(
        value: try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
      )
      let (_, created) = UserAccount.create(id: aid, name: "Alice")
      let expected = try EventEnvelope(
        id: try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002")),
        aggregate: UserAccount.ID.name,
        aid: aid,
        seqNr: 1,
        occurredAt: Date(timeIntervalSince1970: 1),
        event: created,
        metadata: ["source": "event-store-test"],
      )
      let data = Data(
        """
        {
          "aggregate": "UserAccount",
          "aid": {
            "value": "00000000-0000-0000-0000-000000000001"
          },
          "id": "00000000-0000-0000-0000-000000000002",
          "metadata": {
            "source": "event-store-test"
          },
          "occurredAt": -978307199,
          "payload": "eyJjcmVhdGVkIjp7Im5hbWUiOiJBbGljZSJ9fQ==",
          "seqNr": 1
        }
        """
        .utf8
      )

      let event = try await serializer.deserialize(data)

      #expect(event == expected)
    }

    @Test func `The default JSON serializer writes event object keys in sorted order`() async throws {
      let aid = UserAccount.ID(
        value: try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
      )
      let (_, created) = UserAccount.create(id: aid, name: "Alice")
      let event = try EventEnvelope(
        id: try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002")),
        aggregate: UserAccount.ID.name,
        aid: aid,
        seqNr: 1,
        occurredAt: Date(timeIntervalSince1970: 1),
        event: created,
        metadata: ["z": "last", "a": "first"],
      )
      let sut = EventSerializer<EventEnvelope<UserAccount.Event, UserAccount.ID>>.json()

      let data = try await sut.serialize(event)

      #expect(
        String(decoding: data, as: UTF8.self)
          == #"{"aggregate":"UserAccount","aid":{"value":"00000000-0000-0000-0000-000000000001"},"id":"00000000-0000-0000-0000-000000000002","metadata":{"a":"first","z":"last"},"occurredAt":-978307199,"payload":"eyJjcmVhdGVkIjp7Im5hbWUiOiJBbGljZSJ9fQ==","seqNr":1}"#
      )
    }
  }
}
