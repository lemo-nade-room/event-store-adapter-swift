import Foundation

/// イベントを表すためのProtocol
public protocol Event: Sendable, Hashable, Codable {
    associatedtype AID: EventStoreAdapter.AggregateId
    associatedtype Id: LosslessStringConvertible
    /// イベントID
    var id: Id { get }

    /// 集約ID
    var aid: AID { get }

    /// シーケンス番号
    var seqNr: Int { get }

    /// 発生日時
    var occurredAt: Date { get }

    var isCreated: Bool { get }
}
