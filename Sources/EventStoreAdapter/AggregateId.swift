/// 集約IDを表すためのProtocol
public protocol AggregateId: Sendable, Hashable, Codable, LosslessStringConvertible {
    /// 集約の種別名を返す
    ///
    /// 集約の型ごとに一意である必要がある
    static var name: String { get }
}
