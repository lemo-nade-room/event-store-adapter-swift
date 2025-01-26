import Foundation

/// イベントのシリアライズ・デシリアライズを行う
public struct EventSerializer<Event: EventStoreAdaptor.Event>: Sendable {
    /// イベントをシリアライズする関数
    public var serialize: @Sendable (Event) throws -> Data
    /// イベントをデシリアライズする関数
    public var deserialize: @Sendable (Data) throws -> Event
    /// イニシャライザ
    /// - Parameters:
    ///   - serialize: イベントをシリアライズする関数
    ///   - deserialize: イベントをデシリアライズする関数
    public init(
        serialize: @escaping @Sendable (Event) throws -> Data = { try serializeForJSON($0) },
        deserialize: @escaping @Sendable (Data) throws -> Event = { try deserializeFromJSON($0) }
    ) {
        self.serialize = serialize
        self.deserialize = deserialize
    }
}

/// 集約のスナップショットのシリアライズ・デシリアライズを行う
public struct SnapshotSerializer<Aggregate: EventStoreAdaptor.Aggregate>: Sendable {
    /// 集約のスナップショットをシリアライズする関数
    public var serialize: @Sendable (Aggregate) throws -> Data
    /// 集約のスナップショットをデシリアライズする関数
    public var deserialize: @Sendable (Data) throws -> Aggregate
    /// イニシャライザ
    /// - Parameters:
    ///   - serialize: 集約のスナップショットをシリアライズする関数
    ///   - deserialize: 集約のスナップショットをデシリアライズする関数
    public init(
        serialize: @escaping @Sendable (Aggregate) throws -> Data = {
            try serializeForJSON($0)
        },
        deserialize: @escaping @Sendable (Data) throws -> Aggregate = {
            try deserializeFromJSON($0)
        }
    ) {
        self.serialize = serialize
        self.deserialize = deserialize
    }
}

/// JSONデータにシリアライズする関数
/// - Parameter content: オブジェクト
/// - Throws: シリアライズに失敗した場合にスローされる
/// - Returns: シリアライズされたJSONデータ
public func serializeForJSON(_ content: some Codable) throws -> Data {
    try EventStoreSetting.jsonEncoder.encode(content)
}
/// JSONデータからデシリアライズする関数
/// - Parameter data: JSONデータ
/// - Throws: デシリアライズに失敗した場合にスローされる
/// - Returns: デシリアライズされたオブジェクト
public func deserializeFromJSON<T: Codable>(_ data: Data) throws -> T {
    try EventStoreSetting.jsonDecoder.decode(T.self, from: data)
}
public enum JSONDeserializeError: Error, Sendable {
    case notBase64Encoded
}
