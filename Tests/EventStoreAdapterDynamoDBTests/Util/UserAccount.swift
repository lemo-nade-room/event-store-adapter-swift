import EventStoreAdapter
import Foundation

actor UserAccount {
  nonisolated let id: ID
  private var state: State

  private enum State: Sendable, Hashable {
    case active, inactive
  }

  init(id: ID) {
    self.id = id
    self.state = .active
  }

  init(snapshot: Snapshot) {
    self.id = snapshot.id
    self.state =
      switch snapshot.state {
      case .active: .active
      case .inactive: .inactive
      }
  }

  static func create(id: ID, name: String) -> (aggregate: UserAccount, event: Event) {
    (
      aggregate: .init(id: id),
      event: .created(name: name),
    )
  }

  func rename(to name: String) throws -> Event {
    guard case .active = state else {
      throw RenameError.inactive
    }
    return .renamed(name: name)
  }
  enum RenameError: Error, Sendable, Hashable {
    case inactive
  }

  func deactivate() throws -> Event {
    guard case .active = state else {
      throw DeactivateError.inactive
    }
    self.state = .inactive
    return .deactivated
  }
  enum DeactivateError: Error, Sendable, Hashable {
    case inactive
  }

  var snapshot: Snapshot {
    let state: Snapshot.State =
      switch state {
      case .active: .active
      case .inactive: .inactive
      }
    return .init(id: id, state: state)
  }

  struct ID: EventStoreAdapter.AggregateId, Codable {
    static let name = "UserAccount"
    let value: UUID

    init(value: UUID) {
      self.value = value
    }

    init?(_ description: String) {
      guard let value = UUID(uuidString: description) else { return nil }
      self.value = value
    }

    var description: String { value.uuidString }
  }

  enum Event: Sendable, Hashable, Codable {
    case created(name: String)
    case renamed(name: String)
    case deactivated
  }

  struct Snapshot: Sendable, Hashable, Codable, Identifiable {
    let id: ID
    let state: State

    enum State: String, Sendable, Hashable, Codable {
      case active, inactive
    }
  }
}
