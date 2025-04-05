# event-store-adapter-swift

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Testing Status](https://github.com/lemo-nade-room/event-store-adapter-swift/actions/workflows/ci.yaml/badge.svg)](https://github.com/lemo-nade-room/event-store-adapter-swift/actions/workflows/ci.yaml)

This library provides **CQRS** and **Event Sourcing** capabilities for Swift, allowing you to manage events and
snapshots in a scalable and safe manner. It’s designed to work seamlessly with AWS DynamoDB or other data stores, and
also comes with an in-memory version for simpler or testing scenarios.

For other language implementations (Rust, Scala, etc.), please
see [this repository](https://github.com/j5ik2o/event-store-adapter).

[日本語ドキュメント](./README.ja.md)

## Features

- **Easy CQRS/Event Sourcing Implementation**: Offers straightforward read and write of aggregates and events.
- **DynamoDB Support**: Leverages AWS DynamoDB to store events and snapshots efficiently.
- **In-Memory Implementation**: Offers a lightweight, in-memory event store (useful for testing).
- **Optimistic Concurrency**: Manages aggregate versioning to ensure safe concurrent updates.
- **Snapshot Management**: Supports automatic snapshot cleanup, including TTL expiration.
- **Simple Interface**: A single `EventStore` protocol that outlines how to store and retrieve events and snapshots.

## Installation

Add the following to your `Package.swift` using SwiftPM:

```swift
dependencies: [
    .package(url: "https://github.com/lemo-nade-room/event-store-adapter-swift.git", from: "1.0.0"),
]
```

## Usage

### Basic Example

Define your own `Aggregate` and `Event` types that conform to the provided protocols.  
Below is a simplified example:

```swift
import EventStoreAdapter
import Foundation

struct UserAccount: Aggregate {
    struct AID: AggregateId {
        static let name = "UserAccount"
        var value: UUID
        
        init(value: UUID) {
            self.value = value
        }
        init?(_ description: String) {
            guard let uuid = UUID(uuidString: description) else { return nil }
            self.value = uuid
        }
        var description: String { value.uuidString }
    }
    
    var aid: AID
    var seqNr: Int
    var version: Int
    var lastUpdatedAt: Date
    var name: String
}

extension UserAccount {
    enum Event: EventStoreAdapter.Event {
        case created(Created)
        case renamed(Renamed)
        
        struct Created: Codable, Sendable, Hashable {
            let id: UUID
            let aggregateAID: AID
            let seqNr: Int
            let occurredAt: Date
            let name: String
        }
        
        struct Renamed: Codable, Sendable, Hashable {
            let id: UUID
            let aggregateAID: AID
            let seqNr: Int
            let occurredAt: Date
            let name: String
        }

        // MARK: - Conformance to `Event` protocol
        var id: UUID {
            switch self {
            case .created(let e): return e.id
            case .renamed(let e): return e.id
            }
        }
        
        var aid: AID {
            switch self {
            case .created(let e): return e.aggregateAID
            case .renamed(let e): return e.aggregateAID
            }
        }
        
        var seqNr: Int {
            switch self {
            case .created(let e): return e.seqNr
            case .renamed(let e): return e.seqNr
            }
        }
        
        var occurredAt: Date {
            switch self {
            case .created(let e): return e.occurredAt
            case .renamed(let e): return e.occurredAt
            }
        }
        
        var isCreated: Bool {
            switch self {
            case .created: return true
            case .renamed: return false
            }
        }
    }
}
```

### Selecting an Event Store Implementation

- **DynamoDB Version**: Use `EventStoreAdapterDynamoDB` to persist events and snapshots to AWS DynamoDB.
- **In-Memory Version**: Use `EventStoreAdapterForMemory` to keep data only in memory for lightweight usage.

#### Example with DynamoDB

```swift
import EventStoreAdapterDynamoDB
import AWSDynamoDB

let client = try await DynamoDBClient(
    config: .init(
        region: "ap-northeast-1",
        endpoint: "http://localhost:8000" // Local DynamoDB
    )
)

let eventStore = EventStoreForDynamoDB<UserAccount, UserAccount.Event>(
    client: client,
    journalTableName: "journal",
    journalAidIndexName: "journal-aid-index",
    snapshotTableName: "snapshot",
    snapshotAidIndexName: "snapshot-aid-index",
    shardCount: 64
)
```

#### Example with an In-Memory Store

```swift
import EventStoreAdapterForMemory

let eventStore = EventStoreForMemory<UserAccount, UserAccount.Event>()
```

### Repository Example

You can build a repository layer that uses the event store for persistence:

```swift
struct UserAccountRepository<Store: EventStore>
where
    Store.Aggregate == UserAccount,
    Store.Event == UserAccount.Event,
    Store.AID == UserAccount.AID
{
    let eventStore: Store
    
    // Create a new user account and store both event + snapshot
    func createUserAccount(name: String) async throws -> UserAccount {
        let aid = UserAccount.AID(value: UUID())
        let now = Date()
        let createdEvent = UserAccount.Event.created(
            .init(
                id: UUID(),
                aggregateAID: aid,
                seqNr: 1,
                occurredAt: now,
                name: name
            )
        )
        let userAccount = UserAccount(
            aid: aid,
            seqNr: 1,
            version: 1,
            lastUpdatedAt: now,
            name: name
        )
        
        try await eventStore.persistEventAndSnapshot(event: createdEvent, aggregate: userAccount)
        return userAccount
    }
    
    // Rename existing user account (store only the event)
    func renameUserAccount(_ user: inout UserAccount, newName: String) async throws {
        let now = Date()
        let renameEvent = UserAccount.Event.renamed(
            .init(
                id: UUID(),
                aggregateAID: user.aid,
                seqNr: user.seqNr + 1,
                occurredAt: now,
                name: newName
            )
        )
        // Optimistic concurrency check (user.version)
        try await eventStore.persistEvent(event: renameEvent, version: user.version)
        
        user.seqNr += 1
        user.version += 1
        user.lastUpdatedAt = now
        user.name = newName
    }
    
    // Fetch snapshot, replay events, and reconstruct the latest state
    func findByAID(_ aid: UserAccount.AID) async throws -> UserAccount? {
        // Latest snapshot
        guard let snapshot = try await eventStore.getLatestSnapshotByAID(aid: aid) else {
            return nil
        }
        // Events after snapshot
        let events = try await eventStore.getEventsByAIDSinceSequenceNumber(aid: aid, seqNr: snapshot.seqNr + 1)
        
        // Replay events
        return events.reduce(snapshot) { (acc, e) in
            switch e {
            case .renamed(let r):
                var updated = acc
                updated.seqNr = r.seqNr
                updated.version += 1
                updated.lastUpdatedAt = r.occurredAt
                updated.name = r.name
                return updated
            case .created: 
                // If there's already a snapshot, no changes required for creation event
                return acc
            }
        }
    }
}
```

## DynamoDB Table Schema

For DynamoDB, you’ll need two tables:

- **Journal Table (`journal`)**  
  Stores events.
    - Partition key: `pkey`
    - Sort key: `skey`
    - GSI: `journal-aid-index` (keys: `aid`, `seq_nr`)

- **Snapshot Table (`snapshot`)**  
  Stores snapshots.
    - Partition key: `pkey`
    - Sort key: `skey`
    - GSI: `snapshot-aid-index` (keys: `aid`, `seq_nr`)

See [docs/DATABASE_SCHEMA.md](https://github.com/j5ik2o/event-store-adapter-rs/blob/main/docs/DATABASE_SCHEMA.md)
for more details.

## License

This library is released under the [MIT License](LICENSE). You are free to use it in your projects as long as you follow
the terms of the license.

## Other Language Versions

For Rust, Scala, and other implementations, please
visit [this repository](https://github.com/j5ik2o/event-store-adapter).

## Support Tool for This Library

A tool that makes it more convenient to use this
library, [event-store-adapter-support](https://github.com/lemo-nade-room/event-store-adapter-swift-support), is also
available. Please check it out if you want to streamline your workflow.

## Contributing & Questions

If you find a bug, have questions, or want to suggest a feature, feel free to open an Issue or submit a Pull Request. We
appreciate all contributions.
