public import Foundation

/// A protocol representing an Event in a CQRS/Event Sourcing system.
///
/// This protocol requires each event to specify a unique Event ID (`Id`), a reference to its Aggregate ID (`aid`),
/// a sequential number (`seqNr`), a timestamp for when it occurred (`occurredAt`), and whether it's a creation event (`isCreated`).
///
/// # Japanese
/// CQRS/Event Sourcing システムにおいてイベントを表すためのプロトコル。
/// 各イベントは固有のイベントID（`Id`）、関連付けられた集約ID（`aid`）、連番（`seqNr`）、
/// 発生した日時（`occurredAt`）、および集約の生成イベントであるかどうか（`isCreated`）を必ず持ちます。
public protocol Event: Sendable, Hashable, Codable {
  /// The type representing the Aggregate ID associated with this event.
  ///
  /// # Japanese
  /// このイベントが紐づく集約IDの型。
  associatedtype AID: EventStoreAdapter.AggregateId

  /// The type representing the event’s unique identifier.
  ///
  /// # Japanese
  /// イベント固有の識別子を表す型。
  associatedtype Id: LosslessStringConvertible

  /// The unique identifier for this event.
  ///
  /// # Japanese
  /// このイベントのユニークな識別子。
  var id: Id { get }

  /// The aggregate ID to which this event is associated.
  ///
  /// # Japanese
  /// このイベントが紐づく集約のID。
  var aid: AID { get }

  /// A sequential number representing how many events have occurred before this one for the associated aggregate.
  ///
  /// In typical usage, the aggregate’s `seqNr` is incremented whenever a new event is generated,
  /// and that incremented value is assigned as the event’s `seqNr`.
  ///
  /// # Japanese
  /// このイベント以前に、関連する集約上で何回イベントが発生したかを示す連番。
  /// 通常は、集約の `seqNr` をイベント生成時にインクリメントし、それがイベントの `seqNr` として割り当てられます。
  var seqNr: Int { get }

  /// The date and time when this event occurred.
  ///
  /// # Japanese
  /// このイベントが発生した日時。
  var occurredAt: Date { get }

  /// A Boolean value indicating whether this event is the creation event for the aggregate.
  ///
  /// # Japanese
  /// このイベントが集約の生成イベントであるかどうかを示すフラグ。
  var isCreated: Bool { get }
}
