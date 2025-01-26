import Foundation

/// イベントを表すためのProtocol
public protocol Event: Sendable, Hashable, Codable {
    associatedtype AggregateId: EventStoreAdaptor.AggregateId
    associatedtype Id: LosslessStringConvertible
    /// イベントID
    var id: Id { get }

    /// 集約ID
    var aggregateId: AggregateId { get }

    /// シーケンス番号
    var sequenceNumber: Int { get }

    /// 発生日時
    var occurredAt: Date { get }

    var isCreated: Bool { get }
}
