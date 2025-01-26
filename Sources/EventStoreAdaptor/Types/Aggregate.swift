import Foundation

/// 集約を表すProtocol
public protocol Aggregate: Sendable, Hashable, Codable {
    associatedtype Id: AggregateId

    var id: Id { get }

    /// シーケンス番号
    var sequenceNumber: Int { get }

    /// バージョン
    var version: Int { get set }
    
    var lastUpdatedAt: Date { get }
}

extension Aggregate {
    /// バージョンを設定する
    /// - Parameter version: バージョン
    /// - Returns: ``Self``
    public func withVersion(_ version: Int) -> Self {
        var copy = self
        copy.version = version
        return copy
    }
}
