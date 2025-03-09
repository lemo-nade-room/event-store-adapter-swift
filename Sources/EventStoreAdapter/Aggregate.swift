public import Foundation

/// 集約を表すProtocol
public protocol Aggregate: Sendable, Hashable, Codable {
    /// 集約ID型
    associatedtype AID: AggregateId

    /// 集約ID
    var aid: AID { get }

    /// シーケンシャル番号（連番）
    ///
    /// 集約に対して一意なイベントに1から順に割り当てられる番号
    /// この集約が何番目のイベントまでが適用されているのかを示す
    ///
    /// 集約の生成時にはseqNrを1としておき、集約がイベントを生成するたびにこの数値を1増やす必要がある
    var seqNr: Int { get }

    /// 楽観的ロック用のバージョン
    ///
    /// EventStoreAdapterライブラリによってversionの変更は行われるため、
    /// ライブラリ使用者がプロパティを操作する必要はなく定義するだけで良い
    var version: Int { get set }

    /// 最終更新日時
    var lastUpdatedAt: Date { get }
}
