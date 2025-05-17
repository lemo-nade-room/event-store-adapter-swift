# event-store-adapter-swift

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Testing Status](https://github.com/lemo-nade-room/event-store-adapter-swift/actions/workflows/swift-test.yaml/badge.svg)](https://github.com/lemo-nade-room/event-store-adapter-swift/actions/workflows/swift-test.yaml)

このライブラリは、**CQRS**および**Event Sourcing**
をSwiftで実現するためのイベントストア機能を提供します。AWSのDynamoDBなどのデータストアを利用してイベントやスナップショットを安全かつスケーラブルに管理できるよう設計されています。

Rust実装をはじめとする他の言語版に興味がある方は、[こちらのリポジトリ](https://github.com/j5ik2o/event-store-adapter)
もご覧ください。

## 特長

- **CQRS/Event Sourcingの実装を支援**: 集約・イベントモデルに沿った読み書きを容易に行えます。
- **DynamoDB対応**: DynamoDBを利用した高速・スケーラブルなイベントストアを提供。
- **メモリ実装（In-Memory Store）**: テストや軽量な利用向けにメモリ上のイベントストアもサポート。
- **楽観的ロック対応**: 集約のバージョン管理による安全な並行更新をサポート。
- **スナップショット管理**: パフォーマンス向上やデータ肥大化を抑制するためのスナップショット自動削除・TTL設定が可能。
- **シンプルなインターフェイス**: `EventStore`プロトコルを介して、イベントやスナップショットの保存・取得方法を簡潔に定義。

## インストール

SwiftPMを利用して`Package.swift`に依存を追加します:

```swift
dependencies: [
    .package(url: "https://github.com/lemo-nade-room/event-store-adapter-swift.git", from: "1.0.0"),
]
```

## 使い方

### 基本的な利用例

まず、独自の`Aggregate`型と`Event`型を用意します。  
（以下は簡略化のためのサンプルです。）

```swift
import EventStoreAdapter

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

        // MARK: - Event プロトコル要件
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

#### イベントストアの実装を選択

- **DynamoDBバージョン**: `EventStoreAdapterDynamoDB`を使用して、AWS DynamoDBにイベントやスナップショットを保存。
- **メモリバージョン**: `EventStoreAdapterForMemory`を使用して、アプリケーションのメモリ上でのみデータを管理。

##### DynamoDBで利用する例

```swift
import EventStoreAdapterDynamoDB

let client = try await DynamoDBClient(
    config: .init(
        region: "ap-northeast-1",
        endpoint: "http://localhost:8000" // ローカルDynamoDBの場合
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

##### メモリストアで利用する例

```swift
import EventStoreAdapterForMemory

let eventStore = EventStoreForMemory<UserAccount, UserAccount.Event>()
```

#### リポジトリの実装例

`EventStore`を使って、イベントの永続化やスナップショット管理などを行うリポジトリを構築できます。

```swift
struct UserAccountRepository<Store: EventStore> 
where 
    Store.Aggregate == UserAccount, 
    Store.Event == UserAccount.Event, 
    Store.AID == UserAccount.AID
{
    let eventStore: Store
    
    // 新しいユーザーアカウントの作成とスナップショット保存
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
        
        // イベントとスナップショットを同時に保存
        try await eventStore.persistEventAndSnapshot(event: createdEvent, aggregate: userAccount)
        return userAccount
    }
    
    // 既存ユーザーアカウントの名称変更（イベントのみ保存する例）
    func renameUserAccount(_ user: inout UserAccount, newName: String) async throws {
        let now = Date()
        let event = UserAccount.Event.renamed(
            .init(
                id: UUID(),
                aggregateAID: user.aid,
                seqNr: user.seqNr + 1,
                occurredAt: now,
                name: newName
            )
        )
        // 楽観ロックバージョン（user.version）を指定
        try await eventStore.persistEvent(event: event, version: user.version)
        
        // 更新後の集約オブジェクトをローカルに反映
        user.seqNr += 1
        user.version += 1
        user.lastUpdatedAt = now
        user.name = newName
    }
    
    // スナップショットを取得し、そこからイベントを適用して最新状態に再構築する例
    func findByAID(_ aid: UserAccount.AID) async throws -> UserAccount? {
        // 最新スナップショット取得
        guard let snapshot = try await eventStore.getLatestSnapshotByAID(aid: aid) else {
            return nil
        }
        // スナップショット以降のイベントを取得
        let events = try await eventStore.getEventsByAIDSinceSequenceNumber(aid: aid, seqNr: snapshot.seqNr + 1)
        
        // 取得したイベントを再適用して最新状態に合成（replay）
        return events.reduce(snapshot) { (acc, e) in
            switch e {
            case .renamed(let r):
                var result = acc
                result.seqNr = r.seqNr
                result.version += 1
                result.lastUpdatedAt = r.occurredAt
                result.name = r.name
                return result
            case .created: 
                // すでにsnapshotが存在している場合は、特に処理不要
                return acc
            }
        }
    }
}
```

## テーブル仕様

DynamoDBを利用する場合は、以下のテーブルが必要です。

- **ジャーナルテーブル（`journal`）**  
  イベントを格納するテーブルです。
    - パーティションキー: `pkey`
    - ソートキー: `skey`
    - GSI: `journal-aid-index` (キー: `aid`, `seq_nr`)
- **スナップショットテーブル（`snapshot`）**  
  スナップショットを格納するテーブルです。
    - パーティションキー: `pkey`
    - ソートキー: `skey`
    - GSI: `snapshot-aid-index` (キー: `aid`, `seq_nr`)

詳しくは [docs/DATABASE_SCHEMA.ja.md](https://github.com/j5ik2o/event-store-adapter-rs/blob/main/docs/DATABASE_SCHEMA.ja.md)
をご覧ください。

## ライセンス

このライブラリは[MIT License](LICENSE)の下で提供されています。自由にご利用いただけますが、必ずライセンス条文に従ってください。

## 他言語版

- RustやScalaなど、その他の言語実装については[こちらのリポジトリ](https://github.com/j5ik2o/event-store-adapter)をご確認ください。

## ライブラリ使用サポートツール

本ライブラリの使用を便利化するツールである[event-store-adapter-support](https://github.com/lemo-nade-room/event-store-adapter-swift-support)が存在しています。こちらもご確認ください。

## コントリビュートや質問

バグ報告や機能要望などがあれば、IssuesやPull Requestなどを通じてご連絡ください。
