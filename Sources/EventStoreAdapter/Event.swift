public import Foundation

/// A value that records a change to an aggregate.
///
/// An event carries the event payload together with the aggregate identity, its
/// position in that aggregate's history, and the time at which the change
/// occurred. The inherited `Identifiable.id` property identifies the event
/// itself; `aid` identifies the aggregate whose history contains the event.
/// The event's `ID` type must be `Sendable` and
/// `LosslessStringConvertible`.
///
/// Event payloads are required to be `Sendable` and `Hashable`, but they are not
/// required to conform to `Codable`. Serialization is selected by the event store
/// implementation, which allows binary and other custom formats.
public protocol Event<Payload, AID, ID>: Swift.Sendable, Swift.Hashable, Swift.Identifiable
where ID: Swift.Sendable & Swift.LosslessStringConvertible {
  /// The type of the domain value carried by the event.
  associatedtype Payload: Swift.Sendable, Swift.Hashable

  /// The type of aggregate ID associated with the event.
  associatedtype AID: EventStoreAdapter.AggregateId

  /// The domain value carried by the event.
  var payload: Payload { get }

  /// The ID of the aggregate whose history contains this event.
  var aid: AID { get }

  /// The event's position in the aggregate history.
  ///
  /// Event-sourced aggregates conventionally start at `1` and increase this value
  /// by one for each successive event. Concrete stores define whether and how
  /// they validate that convention.
  var seqNr: Swift.Int { get }

  /// The date and time at which the event occurred.
  var occurredAt: Foundation.Date { get }
}
