import Foundation

/// イベントストア設定
public enum EventStoreSetting: Sendable {
    /// JSONエンコーダー
    @TaskLocal public static var jsonEncoder: JSONEncoder = .init()
    /// JSONデコーダー
    @TaskLocal public static var jsonDecoder: JSONDecoder = .init()
}
