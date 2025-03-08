public import Foundation

/// イベントを表すためのProtocol
public protocol Event: Sendable, Hashable, Codable {
    /// 集約ID型
    associatedtype AID: EventStoreAdapter.AggregateId
    /// イベントID型
    associatedtype Id: LosslessStringConvertible
    /// イベントID
    var id: Id { get }

    /// 集約ID
    var aid: AID { get }

    /// シーケンシャル番号（連番）
    ///
    /// 集約に対して一意なイベントに1から順に割り当てられる番号
    ///
    /// 集約がイベントを生成する際に集約のseqNrを1増やし、その後イベントを生成時に集約のseqNrをイベントに割り当てる
    var seqNr: Int { get }

    /// 発生日時
    var occurredAt: Date { get }

    /// このイベントが集約の生成イベントかどうか
    var isCreated: Bool { get }
}
