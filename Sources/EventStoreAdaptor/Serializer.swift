import Foundation

public struct EventSerializer<Event: EventStoreAdaptor.Event>: Sendable {
    public var serialize: @Sendable (Event) throws -> Data
    public var deserialize: @Sendable (Data) throws -> Event
    public init(
        serialize: @escaping @Sendable (Event) throws -> Data = { try defaultJSONSerialize($0) },
        deserialize: @escaping @Sendable (Data) throws -> Event = { try defaultJSONDeserialize($0) }
    ) {
        self.serialize = serialize
        self.deserialize = deserialize
    }
}

public struct SnapshotSerializer<Aggregate: EventStoreAdaptor.Aggregate>: Sendable {
    public var serialize: @Sendable (Aggregate) throws -> Data
    public var deserialize: @Sendable (Data) throws -> Aggregate
    public init(
        serialize: @escaping @Sendable (Aggregate) throws -> Data = {
            try defaultJSONSerialize($0)
        },
        deserialize: @escaping @Sendable (Data) throws -> Aggregate = {
            try defaultJSONDeserialize($0)
        }
    ) {
        self.serialize = serialize
        self.deserialize = deserialize
    }
}

public func defaultJSONSerialize(_ content: some Codable) throws -> Data {
    try EventStoreSetting.jsonEncoder.encode(content)
}
public func defaultJSONDeserialize<T: Codable>(_ data: Data) throws -> T {
    try EventStoreSetting.jsonDecoder.decode(T.self, from: data)
}
public enum JSONDeserializeError: Error, Sendable {
    case notBase64Encoded
}
