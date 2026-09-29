# EventStoreAdapter for Swift

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Store domain events and snapshots in DynamoDB from Swift. EventStoreAdapter provides storage protocols and a
[Soto](https://github.com/soto-project/soto) implementation for event-sourced applications. Your application owns the
domain model, applies events, and decides when to persist changes.

This README describes the **v2 API in the current checkout**. Version 2 replaces `aws-sdk-swift` with Soto and
introduces separate event and snapshot types. It is a breaking change from v1; see [Migrating from v1](#migrating-from-v1).

## What's new in v2

### Soto: binary size, build time, and concurrency

The move from `aws-sdk-swift` to Soto aims to reduce binary size and build times while improving reliability under
concurrent use. In the maintainer's project, the migration reduced the application binary size by **39%** and resolved
crashes encountered when creating multiple DynamoDB clients concurrently. Those crashes had made parallel test runs
highly flaky. The measured size reduction applies to that project; results depend on the application, dependency
graph, and build configuration.

### Domain events independent of the adapter

Define domain events and aggregate state as ordinary Swift types, without importing EventStoreAdapter or conforming
to its storage protocols. The Domain and UseCase layers can depend on application-owned repository protocols, while
an infrastructure implementation wraps those values in persistence envelopes and writes them through this library.

Keep `EventEnvelopeProtocol`, `SnapshotEnvelopeProtocol`, and `AggregateId` conformances at that outer boundary,
mapping domain IDs as needed. This lets pure domain events remain independent of storage keys, persistence versions,
and SDK clients, and keeps the adapter dependency out of the Domain and UseCase layers.

### Custom event and aggregate snapshot envelopes

Define your own envelopes conforming to `EventEnvelopeProtocol` and `SnapshotEnvelopeProtocol`, with a domain event
or aggregate state as the `payload`, or encode that payload into bytes. Add application metadata such as an
idempotency key or an observability trace ID when assembling the envelope outside the Domain and UseCase layers.
This context can be supplied by outer layers and persisted alongside the event or aggregate snapshot without adding
infrastructure concerns to the domain model.

The built-in JSON serializers encode the entire envelope, including additional fields represented by its `Codable`
conformance. [Custom serializers](#serialization) let you control the stored format. Idempotency checks and trace
context propagation remain application responsibilities.

## What is included

| Product                     | Purpose                                                                                                       |
| --------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `EventStoreAdapter`         | `AggregateId`, `EventEnvelopeProtocol`, `SnapshotEnvelopeProtocol`, `EventStore`, and read/write error types. |
| `EventStoreAdapterDynamoDB` | The Soto adapter, configuration, and event/snapshot serializers.                              |

The DynamoDB adapter writes an event and its snapshot in one transaction, detects conflicting writes through
conditional expressions, and keeps one current snapshot per aggregate.

### Current limitations

- **Event-only writes are unavailable.** `persistEvent(event:version:)` remains in the protocol, but the DynamoDB
  implementation calls `fatalError`. Use `persistEventAndSnapshot(event:snapshot:)`. Support for `persistEvent` is
  planned for a future release and is outside the scope of `2.0.0-alpha.1`.
- **Event reads return only one page.** `getEventsByAIDSinceSequenceNumber(aid:seqNr:)` returns the first query page,
  subject to DynamoDB's [1 MB limit](https://docs.aws.amazon.com/amazondynamodb/latest/APIReference/API_Query.html).
- There is no in-memory adapter, snapshot history, automatic expiration policy, or table provisioning in v2.

## Requirements

- Swift 6.4 or later.
- macOS 15 or later, or Linux.
- Two DynamoDB tables with the [schema below](#dynamodb-schema). DynamoDB Local can be used for development.

## Installation

The following package manifest uses a local checkout for the renamed envelope protocols. Adjust the path as needed.

```swift
// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "Example",
  platforms: [.macOS(.v15)],
  dependencies: [
    .package(path: "../event-store-adapter-swift"),
    .package(url: "https://github.com/soto-project/soto.git", from: "7.0.0"),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
  ],
  targets: [
    .executableTarget(
      name: "Example",
      dependencies: [
        .product(name: "EventStoreAdapter", package: "event-store-adapter-swift"),
        .product(name: "EventStoreAdapterDynamoDB", package: "event-store-adapter-swift"),
        .product(name: "SotoDynamoDB", package: "soto"),
        .product(name: "Logging", package: "swift-log"),
      ],
    )
  ],
)
```

The example declares Soto and SwiftLog directly because its source imports their modules. If you only need the
storage protocols, depend on the `EventStoreAdapter` product.

## Quick start

First [start DynamoDB Local and create the tables](#local-dynamodb-setup). Then put both Swift blocks in this section
in `Sources/Example/Example.swift` in the consuming package and run `swift run Example`.

### Define the stored values

An event contains a payload, an event ID, an aggregate ID, a sequence number, and an occurrence time. A snapshot
contains the aggregate state, aggregate ID, payload's applied event number,
concurrency version, and last-update time.

The protocols require `Sendable` and `Hashable`, but not `Codable`. These example types also conform to `Codable`
so they can use the built-in JSON serializers.

This example defines payload types inside the envelopes to keep the setup compact. In a layered application, use
your independent domain event and aggregate state types as those payloads.

```swift
import EventStoreAdapter
import EventStoreAdapterDynamoDB
import Foundation
import Logging
import SotoDynamoDB

struct AccountID: AggregateId, Codable {
  static let name = "account"
  let value: UUID

  init(_ value: UUID) {
    self.value = value
  }

  init?(_ description: String) {
    let prefix = "\(Self.name):"
    guard description.hasPrefix(prefix),
      let value = UUID(uuidString: String(description.dropFirst(prefix.count)))
    else {
      return nil
    }
    self.value = value
  }

  var description: String { "\(Self.name):\(value.uuidString)" }
}

struct AccountEvent: EventEnvelopeProtocol, Codable {
  enum Payload: Sendable, Hashable, Codable {
    case created(name: String)
    case renamed(name: String)
  }

  let id: UUID
  let payload: Payload
  let aid: AccountID
  let seqNr: Int
  let occurredAt: Date
}

struct AccountSnapshot: SnapshotEnvelopeProtocol, Codable {
  struct Payload: Sendable, Hashable, Codable {
    let name: String
  }

  let payload: Payload
  let aid: AccountID
  let appliedSeqNr: Int
  var version: Int
  let lastUpdatedAt: Date
}
```

The `AccountID` string in this example includes its aggregate type. The partition key also includes
`AggregateId.name`, so ID strings only need to be unique within their aggregate type. Keep type names and ID strings
stable after storing data, and ensure their hyphen-joined keys are unambiguous across all aggregate types.

### Create, update, and read

This example uses dummy credentials and an explicit endpoint for **DynamoDB Local**.

```swift
@main
struct Example {
  static func main() async throws {
    let client = AWSClient(
      credentialProvider: .static(accessKeyId: "dummy", secretAccessKey: "dummy")
    )

    do {
      let dynamoDB = DynamoDB(
        client: client,
        region: .apnortheast1,
        endpoint: "http://127.0.0.1:8001",
      )
      let store = EventStoreForDynamoDB<AccountEvent, AccountSnapshot>(
        logger: Logger(label: "example.event-store"),
        dynamoDB: dynamoDB,
      )

      let aid = AccountID(UUID())
      let createdAt = Date()
      let created = AccountEvent(
        id: UUID(),
        payload: .created(name: "Alice"),
        aid: aid,
        seqNr: 1,
        occurredAt: createdAt,
      )
      let initialSnapshot = AccountSnapshot(
        payload: .init(name: "Alice"),
        aid: aid,
        appliedSeqNr: 1,
        version: 1,
        lastUpdatedAt: createdAt,
      )
      try await store.persistEventAndSnapshot(event: created, snapshot: initialSnapshot)

      let renamedAt = Date()
      let renamed = AccountEvent(
        id: UUID(),
        payload: .renamed(name: "Alicia"),
        aid: aid,
        seqNr: 2,
        occurredAt: renamedAt,
      )
      let updatedSnapshot = AccountSnapshot(
        payload: .init(name: "Alicia"),
        aid: aid,
        appliedSeqNr: 2,
        version: 1,  // Expected stored version, before this update.
        lastUpdatedAt: renamedAt,
      )
      try await store.persistEventAndSnapshot(event: renamed, snapshot: updatedSnapshot)

      let snapshot = try await store.getLatestSnapshotByAID(aid: aid)
      let events = try await store.getEventsByAIDSinceSequenceNumber(aid: aid, seqNr: 1)
      print("Visible snapshot version:", snapshot?.version as Any)
      print("Visible events:", events.count)

      try await client.shutdown()
    } catch {
      try? await client.shutdown()
      throw error
    }
  }
}
```

For AWS, configure the region and credentials for your environment and omit the local endpoint.
`AWSClient()` uses [Soto's default credential provider](https://soto.codes/user-guides/credential-providers.html).
The caller owns the client and must shut it down after all operations finish, including on failure. Reuse the client
for the lifetime of your application rather than creating one for each write.

## Write and read behavior

`persistEventAndSnapshot` requires matching aggregate IDs and `event.seqNr == snapshot.appliedSeqNr`. It serializes
both envelopes before making a DynamoDB request. The snapshot row's `last_committed_seq_nr` comes from `event.seqNr`;
both snapshot sequence attributes advance to that number in the same transaction.

| Write                     | Snapshot behavior                                                                                                           | Journal behavior                                    |
| ------------------------- | --------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| `event.seqNr == 1`        | Insert only if the snapshot key is unused, storing version `1` regardless of the supplied version.                          | Insert the event only if its primary key is unused. |
| Any other sequence number | Require the stored version to equal `snapshot.version`, then replace the snapshot payload and increment the stored version. | Insert the event only if its primary key is unused. |

Each row describes a single atomic transaction: the event and snapshot writes succeed or fail together.

For an update, pass the version from the snapshot you loaded. **Do not increment it before writing.** The adapter
increments the version in the stored copy. With a struct snapshot, the value you passed is unchanged. After a
successful write, your application can track the incremented version locally or reload the snapshot with a strongly
consistent read.

Your application must assign valid, increasing sequence numbers. The adapter checks that `event.seqNr` and
`snapshot.appliedSeqNr` match, but does not check that an update immediately follows the previous stored sequence number.
It also does not apply an event to the snapshot for you.

`getLatestSnapshotByAID` reads the current snapshot by primary key with a strongly consistent `GetItem`, or returns
`nil` if no row exists. It restores `version` from the stored numeric attribute and takes `appliedSeqNr` from the
deserialized snapshot envelope. To replay events after the stored state, start at
`snapshot.appliedSeqNr + 1`. Reads and writes always derive `aid_pkey` from the aggregate type name and ID.
The caller needs `dynamodb:GetItem` permission on the snapshot table.

`getEventsByAIDSinceSequenceNumber` queries the journal table with strongly consistent reads. It uses
`aid_pkey` and an **inclusive** numeric `seq_nr` lower bound, and returns events in ascending
sequence order from the first query page. The partition key identifies one aggregate, so no `aid` filter is required.
The method returns an empty array when no events match.
The caller needs `dynamodb:Query` permission on the journal table.

### Errors

- `EventStoreWriteError.optimisticLockError`: DynamoDB canceled the transaction with a `ConditionalCheckFailed`
  reason, such as a stale version or a duplicate event key. Reload and reconsider the domain operation before retrying.
- `EventStoreWriteError.serializationError`: an event or snapshot serializer failed before the transaction was sent.
- `EventStoreWriteError.otherError`: aggregate IDs or sequence numbers differ, or the event timestamp cannot be
  represented as an `Int64` millisecond timestamp.
- `EventStoreWriteError.IOError`: another failure from the DynamoDB write request.
- `EventStoreReadError` distinguishes request failures (`IOError`), decoding failures (`deserializationError`), and
  missing or invalid stored attributes (`otherError`).

Retrying an already committed creation or update is not treated as a successful no-op: it can produce an optimistic
lock error. Handle an ambiguous write outcome at the application boundary.

## DynamoDB schema

Create both tables before using the adapter. It does not create or validate them. Neither table requires a GSI.

| Setting                | Default     |
| ---------------------- | ----------- |
| `journalTableName`     | `journal`   |
| `snapshotTableName`    | `snapshot`  |

The `aid_pkey` is always `<AggregateId.name>-<ID string>`. Type names and ID descriptions must be canonical
and stable, and their hyphen-joined keys must be unambiguous across aggregate types sharing a table.
Neither component is escaped. Partition-key generation is fixed and cannot be customized.

### Snapshot table

| Attribute | DynamoDB type | Meaning |
| --- | --- | --- |
| `aid_pkey` | String | Partition key; the snapshot table has no sort key. |
| `aggregate_name` | String | `AggregateId.name`. |
| `aid` | String | The original aggregate ID's `description`. |
| `last_committed_seq_nr` | Number | The latest event sequence number committed to the journal. |
| `applied_seq_nr` | Number | The latest event represented by the stored snapshot payload. |
| `payload` | Binary | The complete serialized snapshot envelope. |
| `version` | Number | `1` on creation; incremented on each successful update. |
| `last_updated_at` | Number | The event's occurrence time in Unix epoch milliseconds, rounded down. |

### Journal table

| Attribute | DynamoDB type | Meaning |
| --- | --- | --- |
| `aid_pkey` | String | Partition key. |
| `seq_nr` | Number | Sort key; the event's sequence number. |
| `aggregate_name` | String | `AggregateId.name`. |
| `aid` | String | The original aggregate ID's `description`. |
| `payload` | Binary | The complete serialized event envelope. |
| `occurred_at` | Number | The event's occurrence time in Unix epoch milliseconds, rounded down. |

The adapter derives `aggregate_name` and `aid` from the same typed aggregate ID used to resolve `aid_pkey`,
so consumers can identify the aggregate without parsing the physical key. Journal events sort numerically;
there is no string padding or configurable sort-key encoding.

`last_committed_seq_nr` and `applied_seq_nr` have different meanings even though the currently supported
`persistEventAndSnapshot` operation advances both together. The former provides a commit position for Snapshot CDC;
the latter identifies where aggregate replay starts. The committed position is table metadata; snapshot envelopes
only need `appliedSeqNr` for their payload's position. Neither is the optimistic-lock revision `version`.
Event-only writes, checkpoint storage, and CDC handlers are not implemented by this change.

The serialized snapshot's `lastUpdatedAt` is retained as supplied. As in earlier versions, the separate
`last_updated_at` attribute comes from `event.occurredAt`, not the wall-clock time of the database write.
No `ttl` attribute is written.

**Schema migration:** the former `pkey` / string `skey` tables are incompatible with this schema. Create new tables
with the keys above and migrate existing records before switching the adapter's configured table names.
For snapshots, remove the fixed sort-key slot, rename the payload's `seqNr` to `appliedSeqNr`, and populate both
sequence attributes. The committed position must reflect the latest
persisted journal event; do not infer it from `version`. For journals, store `seq_nr` as a Number sort key.
Populate `aggregate_name` and the original `aid` for both tables, migrate the binary envelopes with compatible
serializers, and remove obsolete `pkey`, `skey`, snapshot `seq_nr`, and `ttl` attributes.
Keep the old tables until the migrated data and read/write paths have been verified. This adapter does not migrate
data automatically or fall back to the previous schema.

Pass optional `journalTableName:` and `snapshotTableName:` arguments directly to `EventStoreForDynamoDB`.
A `nil` value uses `defaultJournalTableName` or `defaultSnapshotTableName`, respectively.
The store exposes the resolved names as properties.

The separate `config:` initializer accepts a Swift Configuration `ConfigReader` and reads
`journal.table.name` and `snapshot.table.name` with `string()` during initialization. Missing values use the
same defaults. This initializer accepts no table-name arguments and does not throw.

`KeyResolver` and the `keyResolver` initializer arguments have been removed. Partition keys always use the
aggregate type name and ID; journal sort keys are the unmodified numeric sequence numbers.
Changing the type name or ID representation after data has been written can make existing records inaccessible
or cause writes to use different keys.

## Serialization

When both stored types conform to `Codable`, the convenience initializer uses JSON for the **entire event and
snapshot envelopes**, not just their `payload` properties. The JSON bytes are stored in DynamoDB binary attributes.
The defaults use sorted JSON object keys and Foundation's default date and data strategies; this is not a
cross-language canonical serialization format.

`EventEnvelopeSerializer.json(encoder:decoder:)` accepts custom JSON coders and adds `.sortedKeys` to the supplied encoder.
`SnapshotEnvelopeSerializer.json()` uses its own default coders.

For another format or different snapshot coding strategies, pass
[`EventEnvelopeSerializer`](Sources/EventStoreAdapterDynamoDB/EventEnvelopeSerializer.swift) and
[`SnapshotEnvelopeSerializer`](Sources/EventStoreAdapterDynamoDB/SnapshotEnvelopeSerializer.swift) instances to the designated
initializer. Their `serialize` and `deserialize` closures are asynchronous, throwing, and `@Sendable`. They must be
safe for concurrent use and able to decode every stored format your application still supports.

## Migrating from v1

| v1                                                   | v2                                                                                                                          |
| ---------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| `AWSDynamoDB.DynamoDBClient` and `client:`           | `SotoDynamoDB.DynamoDB` and `dynamoDB:`; the caller manages its `AWSClient`.                                                |
| `Event`                                              | `EventEnvelopeProtocol`.                                                                                                    |
| `Aggregate` and `EventStore.Aggregate`               | A separate snapshot type conforming to `SnapshotEnvelopeProtocol`, and `EventStore.SnapshotEnvelope`.                       |
| `EventStoreForDynamoDB<Aggregate, Event>`            | `EventStoreForDynamoDB<EventEnvelope, SnapshotEnvelope>`.                                                                   |
| `persistEventAndSnapshot(event:aggregate:)`          | `persistEventAndSnapshot(event:snapshot:)`.                                                                                 |
| `Event.isCreated`                                    | Creation is selected by `event.seqNr == 1`.                                                                                 |
| `Event.Id`                                           | `EventEnvelopeProtocol.ID` from `Identifiable`, constrained to `Sendable` and `LosslessStringConvertible`.                  |
| No required `payload` property                       | `EventEnvelopeProtocol.payload` and `SnapshotEnvelopeProtocol.payload`, each with a `Sendable` and `Hashable` payload type. |
| `Codable` required by the storage protocols          | Add `Codable` for JSON serialization, or supply custom serializers.                                                         |
| Table/index/shard arguments on the store initializer | Table names remain on `EventStoreForDynamoDB`; index names and shard count are removed.                                     |
| Snapshot retention and TTL options                   | One current snapshot; no retention or expiration policy.                                                                    |
| `EventStoreAdapterForMemory`                         | Removed.                                                                                                                    |

Earlier v2 previews named these protocols `Event` and `Snapshot`. Update those conformances and constraints to
`EventEnvelopeProtocol` and `SnapshotEnvelopeProtocol`, respectively.
The associated types on `EventStore` are now `EventEnvelope` and `SnapshotEnvelope`; update type aliases and generic
constraints that referred to `EventStore.Event` or `EventStore.Snapshot` accordingly.
The serializers are now named `EventEnvelopeSerializer` and `SnapshotEnvelopeSerializer`, replacing `EventSerializer`
and `SnapshotSerializer`.

This release does not migrate existing data. Check your serialized values, ID strings, key scheme, and snapshot
layout before pointing v2 at a v1 table. Source compatibility and stored-data compatibility are separate concerns.
See the [current limitations](#current-limitations), especially the unavailable event-only write method.

## Local DynamoDB setup

Install Docker and the AWS CLI, then start an ephemeral local database:

```sh
docker run --rm -d --name event-store-adapter-dynamodb \
  -p 127.0.0.1:8001:8000 \
  amazon/dynamodb-local:latest \
  -jar DynamoDBLocal.jar -inMemory -sharedDb
```

Once the service is ready, create both tables. The following commands explicitly target the local endpoint and use
dummy credentials:

```sh
export AWS_ACCESS_KEY_ID=dummy
export AWS_SECRET_ACCESS_KEY=dummy
export AWS_DEFAULT_REGION=ap-northeast-1
export AWS_ENDPOINT_URL_DYNAMODB=http://127.0.0.1:8001

aws dynamodb create-table \
  --endpoint-url "$AWS_ENDPOINT_URL_DYNAMODB" \
  --table-name journal \
  --attribute-definitions AttributeName=aid_pkey,AttributeType=S AttributeName=seq_nr,AttributeType=N \
  --key-schema AttributeName=aid_pkey,KeyType=HASH AttributeName=seq_nr,KeyType=RANGE \
  --billing-mode PAY_PER_REQUEST \
  --no-cli-pager

aws dynamodb create-table \
  --endpoint-url "$AWS_ENDPOINT_URL_DYNAMODB" \
  --table-name snapshot \
  --attribute-definitions AttributeName=aid_pkey,AttributeType=S \
  --key-schema AttributeName=aid_pkey,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --no-cli-pager

for table_name in journal snapshot; do
  aws dynamodb wait table-exists \
    --endpoint-url "$AWS_ENDPOINT_URL_DYNAMODB" \
    --table-name "$table_name"
done
```

Run this setup once per fresh local database. Table creation reports `ResourceInUseException` if a table already
exists. To stop the container and discard its in-memory data, run `docker stop event-store-adapter-dynamodb`.

## Development

From this repository:

```sh
swift build
swift test
swift format lint -s --configuration .swift-format -r Sources Tests Package.swift
```

Without `MEDIUM_TESTS=true`, `swift test` skips the DynamoDB integration tests. After completing the local setup,
run the full suite with:

```sh
MEDIUM_TESTS=true \
AWS_ACCESS_KEY_ID=dummy \
AWS_SECRET_ACCESS_KEY=dummy \
AWS_REGION=ap-northeast-1 \
AWS_ENDPOINT_URL_DYNAMODB=http://127.0.0.1:8001 \
swift test
```

The tests expect pre-existing tables; they do not provision them. Test configuration also accepts an
optional `.env.testing` file, with process environment variables taking precedence.

Bug reports and pull requests are welcome. Include your Swift version, platform, a minimal reproduction, and the
relevant error output in [an issue](https://github.com/lemo-nade-room/event-store-adapter-swift/issues). Add tests for
behavior changes and run the checks above before submitting a pull request.

## Related projects

The [event-store-adapter project](https://github.com/j5ik2o/event-store-adapter) lists implementations in other
languages. Their APIs and stored formats may differ from this Swift implementation.

## License

[MIT](LICENSE).
