# event-store-adapter-swift

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
<a href="https://github.com/lemo-nade-room/event-store-adapter-swift/actions/workflows/ci.yaml">
    <img src="https://github.com/lemo-nade-room/event-store-adapter-swift/actions/workflows/ci.yaml/badge.svg" alt="Testing Status">
</a>

このライブラリは、DynamoDBなどのデータストアを利用し、CQRS/Event Sourcingのためのイベントストア機能をSwiftで提供するためのライブラリです。  
Rust版の[Event Store Adapter (event-store-adapter-rs)](https://github.com/j5ik2o/event-store-adapter-rs)を参考に実装されています。

## 使い方

EventStoreを使えば、Event Sourcing対応リポジトリを簡単に実装できます。

```swift
import EventStoreAdapter

struct UserAccountRepository<EventStore: EventStoreAdapter.EventStore>
where
    EventStore.Aggregate == UserAccount,
    EventStore.Event == UserAccount.Event,
    EventStore.AID == UserAccount.Id
{
    var eventStore: EventStore
    
    func storeEvent(event: UserAccount.Event, version: Int) async throws {
        try await eventStore.persistEvent(event: event, version: version)
    }
    
    func storeEventAndSnapshot(event: UserAccount.Event, snapshot: UserAccount) async throws {
        try await eventStore.persistEventAndSnapshot(event: event, aggregate: snapshot)
    }
    
    func find(aid: UserAccount.AID) async throws -> UserAccount? {
        guard let snapshot = try await eventStore.getLatestSnapshotById(aid: aid) else {
            return nil
        }
        let events = eventStore.getEventsByIdSinceSequenceNumber(aid: aid, seqNr: snapshot.seqNr + 1)
        return UserAccount.replay(events, snapshot)
    }
}
```

以下はリポジトリの使用例です。

```swift
let eventStore = EventStoreForDynamoDB<UserAccount, UserAccount.Event>(
    client: try await DynamoDBClient(),
    journalTableName: journalTableName,
    journalAidIndexName: journalAidIndexName,
    snapshotTableName: snapshotTableName,
    snapshotAidIndexName: snapshotAidIndexName,
    shardCount: 64
)

let repository = UserAccountRepository(eventStore: eventStore)

guard var userAccount = try await repository.find(aid: userAccountAID) else {
    fatalError()
}

let userAccountEvent = try userAccount.rename(name: "foo")

// Store the new event without a snapshot
try await repository.storeEvent(event: userAccountEvent, version: userAccount.version)

// Store the new event with a snapshot
// try await repository.storeEventAndSnapshot(event: userAccountEvent, snapshot: userAccount)
```

## テーブル仕様

[docs/DATABASE_SCHEMA.ja.md](https://github.com/j5ik2o/event-store-adapter-rs/blob/main/docs/DATABASE_SCHEMA.ja.md)を参照してください。
