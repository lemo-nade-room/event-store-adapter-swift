public import EventStoreAdapter
public import Foundation

/// A serializer and deserializer for events in a CQRS/Event Sourcing system.
///
/// # English
/// **EventSerializer** allows you to define custom or default functions for:
/// - Converting an event (`Event`) into binary data (`Data`), and
/// - Converting binary data back into an event.
///
/// By default, it uses JSON encoding/decoding via `serializeForJSON` and `deserializeFromJSON`.
/// However, you can replace these functions with alternative formats if needed (e.g., Protobuf).
///
/// # Japanese
/// CQRS/Event Sourcing システムで利用するイベントのシリアライズおよびデシリアライズを行うための構造体です。
///
/// - イベント (`Event`) をバイナリデータ (`Data`) に変換する処理
/// - バイナリデータをイベントに復元する処理
///
/// の2つをカスタマイズ可能です。
/// デフォルトでは、`serializeForJSON` と `deserializeFromJSON` を使用して JSON エンコード/デコードを行いますが、
/// プロトコルバッファなど異なる形式を利用したい場合は、独自のクロージャを渡して置き換えることができます。
public struct EventSerializer<Event: EventStoreAdapter.Event>: Sendable {
  /// A closure that serializes an event into raw data.
  ///
  /// # English
  /// Provide a function that takes an `Event` and returns `Data`.
  /// By default, this calls ``serializeForJSON(_:jsonEncoder:)``.
  ///
  /// # Japanese
  /// イベントをバイナリデータへ変換するクロージャ。
  /// デフォルトでは ``serializeForJSON(_:jsonEncoder:)`` を用いて JSON に変換します。
  public var serialize: @Sendable (Event) throws -> Data

  /// A closure that deserializes raw data back into an event.
  ///
  /// # English
  /// Provide a function that takes `Data` and returns an `Event`.
  /// By default, this calls ``deserializeFromJSON(_:jsonDecoder:)``.
  ///
  /// # Japanese
  /// バイナリデータを受け取り、イベントに復元するためのクロージャ。
  /// デフォルトでは ``deserializeFromJSON(_:jsonDecoder:)`` を使って JSON デコードを行います。
  public var deserialize: @Sendable (Data) throws -> Event

  /// Initializes an `EventSerializer` with optional custom serialization/deserialization closures.
  ///
  /// # English
  /// - Parameters:
  /// - serialize: A function to convert `Event` to `Data`.
  /// - deserialize: A function to convert `Data` to `Event`.
  ///
  /// If not provided, both use JSON-based defaults:
  /// `serializeForJSON` and `deserializeFromJSON`.
  ///
  /// # Japanese
  /// - Parameters:
  /// - serialize: `Event` を `Data` に変換する処理を指定できます。
  /// - deserialize: `Data` を `Event` に復元する処理を指定できます。
  ///
  /// 未指定の場合、どちらも JSON を使用するデフォルト処理（
  /// `serializeForJSON` と `deserializeFromJSON`）が利用されます。
  public init(
    serialize: @escaping @Sendable (Event) throws -> Data = {
      try serializeForJSON($0, jsonEncoder: .init())
    },
    deserialize: @escaping @Sendable (Data) throws -> Event = {
      try deserializeFromJSON($0, jsonDecoder: .init())
    }
  ) {
    self.serialize = serialize
    self.deserialize = deserialize
  }
}

/// A serializer and deserializer for aggregate snapshots.
///
/// # English
/// **SnapshotSerializer** works similarly to `EventSerializer`, but is intended for
/// snapshot objects conforming to `Aggregate`. It provides flexible ways to:
/// - Convert an aggregate (snapshot) into `Data`
/// - Convert `Data` back into an aggregate
///
/// By default, it uses JSON, but you may supply your own encoding/decoding if desired.
///
/// # Japanese
/// 集約 (`Aggregate`) のスナップショットをシリアライズおよびデシリアライズするための構造体です。
/// デフォルトでは JSON 形式を使用し、
/// - スナップショットを `Data` に変換、
/// - `Data` からスナップショットを復元
///
/// という処理を自由にカスタマイズできます。
public struct SnapshotSerializer<Aggregate: EventStoreAdapter.Aggregate>: Sendable {
  /// A closure that serializes an aggregate snapshot to raw data.
  ///
  /// # English
  /// By default, this calls ``serializeForJSON(_:jsonEncoder:)``.
  ///
  /// # Japanese
  /// デフォルトでは ``serializeForJSON(_:jsonEncoder:)`` によって JSON 変換を行います。
  public var serialize: @Sendable (Aggregate) throws -> Data

  /// A closure that deserializes raw data back into an aggregate snapshot.
  ///
  /// # English
  /// By default, this calls ``deserializeFromJSON(_:jsonDecoder:)``.
  ///
  /// # Japanese
  /// デフォルトでは ``deserializeFromJSON(_:jsonDecoder:)`` によって JSON からの復元を行います。
  public var deserialize: @Sendable (Data) throws -> Aggregate

  /// Initializes a `SnapshotSerializer` with optional custom serialization/deserialization closures.
  ///
  /// # English
  /// - Parameters:
  /// - serialize: A function to convert `Aggregate` to `Data`.
  /// - deserialize: A function to convert `Data` to `Aggregate`.
  ///
  /// Defaults to JSON-based serialization with `serializeForJSON` and `deserializeFromJSON`.
  ///
  /// # Japanese
  /// - Parameters:
  /// - serialize: `Aggregate` を `Data` に変換する処理。
  /// - deserialize: `Data` を `Aggregate` に変換する処理。
  ///
  /// 未指定の場合は JSON を用いたデフォルト処理が使用されます (`serializeForJSON` と `deserializeFromJSON`)。
  public init(
    serialize: @escaping @Sendable (Aggregate) throws -> Data = {
      try serializeForJSON($0, jsonEncoder: .init())
    },
    deserialize: @escaping @Sendable (Data) throws -> Aggregate = {
      try deserializeFromJSON($0, jsonDecoder: .init())
    }
  ) {
    self.serialize = serialize
    self.deserialize = deserialize
  }
}

/// Serializes a `Codable` object to JSON data.
///
/// # English
/// - Parameters:
///   - content: A `Codable` object to serialize.
///   - jsonEncoder: A `JSONEncoder` instance for encoding.
/// - Throws: An error if encoding fails.
/// - Returns: The resulting JSON data.
///
/// This function is used by default in `EventSerializer` and `SnapshotSerializer`.
///
/// # Japanese
/// - Parameters:
///   - content: `Codable` を実装したシリアライズ対象のオブジェクト。
///   - jsonEncoder: エンコードに使用する `JSONEncoder`。
/// - Throws: エンコードエラーが発生した場合にスローされます。
/// - Returns: シリアライズ後の JSON データ。
///
/// `EventSerializer` や `SnapshotSerializer` でデフォルトとして使用される関数です。
public func serializeForJSON(_ content: some Codable, jsonEncoder: JSONEncoder) throws -> Data {
  try jsonEncoder.encode(content)
}

/// Deserializes JSON data into a `Codable` object.
///
/// # English
/// - Parameters:
///   - data: The JSON `Data` to decode.
///   - jsonDecoder: A `JSONDecoder` instance for decoding.
/// - Throws: An error if decoding fails.
/// - Returns: The decoded object of type `T`.
///
/// This function is also used by default in `EventSerializer` and `SnapshotSerializer`.
///
/// # Japanese
/// - Parameters:
///   - data: デコード対象となる JSON データ。
///   - jsonDecoder: デコードに使用する `JSONDecoder`。
/// - Throws: デコードエラーが発生した場合にスローされます。
/// - Returns: デコードされたオブジェクト。
///
/// `EventSerializer` や `SnapshotSerializer` でデフォルトとして利用される関数です。
public func deserializeFromJSON<T: Codable>(_ data: Data, jsonDecoder: JSONDecoder) throws -> T {
  try jsonDecoder.decode(T.self, from: data)
}

/// An enumeration representing potential errors during JSON deserialization.
///
/// # English
/// - `notBase64Encoded`: Indicates the data was expected to be Base64-encoded but was not.
///
/// # Japanese
/// JSON デシリアライズ時に発生する可能性があるエラーを表す列挙型です。
/// - `notBase64Encoded`: データが Base64 形式でエンコードされているはずなのに、そうではなかったことを示します。
public enum JSONDeserializeError: Error, Sendable {
  case notBase64Encoded
}
