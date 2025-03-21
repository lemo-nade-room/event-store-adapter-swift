/// Represents a protocol for defining an Aggregate ID, ensuring the type is `Sendable`, `Hashable`, `Codable`,
/// and `LosslessStringConvertible`.
///
/// In most CQRS/Event Sourcing contexts, an `AggregateId` uniquely identifies a specific category or type of aggregate.
///
/// # Japanese
/// 集約IDを定義するためのプロトコルです。
/// このプロトコルは、`Sendable`, `Hashable`, `Codable`, `LosslessStringConvertible` をすべて満たす必要があります。
/// CQRS/Event Sourcing において、`AggregateId` は特定の集約（エンティティ）の種類や識別を一意に行うために使用されます。
public protocol AggregateId: Sendable, Hashable, Codable, LosslessStringConvertible {
    /// Returns the name of this aggregate type.
    ///
    /// This name must be unique for each aggregate type within the system.
    ///
    /// # Japanese
    /// 集約の種別名を返します。
    /// システム内で集約の型ごとに一意となる必要があります。
    static var name: String { get }
}
