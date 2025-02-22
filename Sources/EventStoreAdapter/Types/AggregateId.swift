/// 集約IDを表すためのProtocol
public protocol AggregateId: Sendable, Hashable, Codable, LosslessStringConvertible {
    /// 集約の種別名を返す
    static var name: String { get }
}
