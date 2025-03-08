import Foundation

/// 集約を表すProtocol
public protocol Aggregate: Sendable, Hashable, Codable {
    associatedtype AID: AggregateId

    var aid: AID { get }

    /// シーケンス番号
    var seqNr: Int { get }

    /// バージョン
    var version: Int { get set }

    var lastUpdatedAt: Date { get }
}
