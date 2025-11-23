public import Foundation

/// Represents an aggregate in a CQRS/Event Sourcing system.
///
/// This protocol defines essential elements for an aggregate, including a unique Aggregate ID (`AID`),
/// a sequential number (`seqNr`) to track the number of applied events, a version number (`version`) for
/// optimistic locking, and a timestamp (`lastUpdatedAt`) for the last update time.
///
/// # Japanese
/// CQRS/Event Sourcing システムにおいて、集約を表すためのプロトコルです。
/// このプロトコルは、集約固有の ID (`AID`)、適用されたイベントの数を管理するシーケンシャル番号 (`seqNr`)、
/// 楽観的ロックのためのバージョン (`version`)、そして最終更新日時 (`lastUpdatedAt`) を定義します。
///
/// Conforming to this protocol ensures compatibility with `event-store-adapter-swift` and any related
/// infrastructure that expects a standardized Aggregate model.
public protocol Aggregate: Sendable, Hashable, Codable {
  /// The type representing the Aggregate's unique identifier (`AID`).
  ///
  /// # Japanese
  /// 集約 ID (`AID`) を表す型。
  associatedtype AID: AggregateId

  /// The unique identifier of this aggregate.
  ///
  /// # Japanese
  /// 集約のユニークな識別子。
  var aid: AID { get }

  /// A sequential number indicating how many events have been applied to this aggregate.
  ///
  /// This value should start at 1 upon the creation of the aggregate and increment by 1
  /// every time a new event is generated and applied to this aggregate.
  ///
  /// # Japanese
  /// この集約に適用されたイベントの通し番号（連番）。
  /// 集約の生成時に `1` から開始し、新しいイベントが生成されるたびに `1` ずつ増加させます。
  var seqNr: Int { get }

  /// The version number used for optimistic locking.
  ///
  /// This version is managed internally by the `event-store-adapter-swift` library.
  /// Users of the library typically only need to define this property, without directly modifying it.
  ///
  /// # Japanese
  /// 楽観的ロックのためのバージョン番号。
  /// `event-store-adapter-swift` ライブラリによって内部的に管理されるため、
  /// 利用者はこのプロパティを定義するだけで、手動で変更する必要はありません。
  var version: Int { get set }

  /// The timestamp representing the last time this aggregate was updated.
  ///
  /// # Japanese
  /// この集約が最後に更新された日時。
  var lastUpdatedAt: Date { get }
}
