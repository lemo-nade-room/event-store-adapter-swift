import Crypto
public import EventStoreAdapter
import Foundation

/// Resolves aggregate IDs and sequence numbers to DynamoDB key strings.
///
/// The event store calls `resolvePartitionKey` and `resolveSortKey` when it
/// writes an item's primary key. Reads query the configured GSIs by `aid` and
/// `seq_nr` and do not invoke these closures. Changing the resolver after data
/// has been persisted can make updates target a different snapshot row or
/// create base-table items that do not belong to the existing key scheme.
///
/// The default resolver maps each aggregate ID to one of a fixed number of
/// logical shards while retaining the aggregate type in the key. Supply
/// custom closures when an existing table uses a different schema, but
/// preserve determinism and uniqueness for all values that the event store can
/// receive.
public struct KeyResolver<AID: AggregateId>: Sendable {
  /// Produces the partition key for an aggregate and the configured shard count.
  ///
  /// The default closure calls ``KeyResolver/defaultResolvePartitionKey(aid:shardCount:)``.
  /// It must return the same value for the same inputs and should distribute
  /// aggregate IDs across the configured shards.
  public var resolvePartitionKey: @Sendable (AID, Int) -> String

  /// Produces the sort key for an aggregate and sequence number.
  ///
  /// The default closure calls ``KeyResolver/defaultResolveSortKey(aid:seqNr:)``.
  /// It must be deterministic and return distinct keys for distinct persisted
  /// records that share a partition key.
  public var resolveSortKey: @Sendable (AID, Int) -> String

  /// Creates a key resolver from custom closures or the default key scheme.
  ///
  /// - Parameters:
  ///   - resolvePartitionKey: Produces a partition key from an aggregate ID and
  ///     shard count. Defaults to the SHA-256 based resolver.
  ///   - resolveSortKey: Produces a sort key from an aggregate ID and sequence
  ///     number. Defaults to the aggregate name, ID description, and sequence
  ///     number joined by hyphens.
  ///
  /// The closures are captured without modification and may be invoked
  /// concurrently by event-store operations.
  public init(
    resolvePartitionKey: @escaping @Sendable (AID, Int) -> String = {
      defaultResolvePartitionKey(aid: $0, shardCount: $1)
    },
    resolveSortKey: @escaping @Sendable (AID, Int) -> String = {
      defaultResolveSortKey(aid: $0, seqNr: $1)
    },
  ) {
    self.resolvePartitionKey = resolvePartitionKey
    self.resolveSortKey = resolveSortKey
  }
}

extension KeyResolver {
  /// Resolves a partition key with SHA-256 based sharding.
  ///
  /// - Parameters:
  ///   - aid: The aggregate ID. Its `description` is the hash input.
  ///   - shardCount: The number of logical shards. Must be greater than zero
  ///     and no greater than `2^56` for the current implementation.
  /// - Returns: A partition key of the form `"<AID.name>-<remainder>"`, where
  ///   `remainder` is in `0..<shardCount`.
  ///
  /// The SHA-256 digest of `aid.description` is consumed as a base-256 number
  /// and reduced modulo `shardCount`. The result is appended to `AID.name`.
  ///
  /// Increasing or decreasing the shard count changes the remainder for many
  /// aggregate IDs. Do not change it for a table that contains existing data
  /// unless the migration also preserves the old key mapping.
  ///
  /// - Precondition: `0 < shardCount <= 2^56`. A non-positive value cannot
  ///   define a modulo operation, and a larger value can overflow the
  ///   base-256 accumulation used by the current implementation.
  public static func defaultResolvePartitionKey(aid: some AggregateId, shardCount: Int) -> String {
    let data = Data(aid.description.utf8)
    let hash = SHA256.hash(data: data)
    // Explanation of the remainder computation:
    // [b_0, b_1, ..., b_{k-1}] are bytes of the hash.
    // We accumulate them in a 64-bit integer, multiplying the previous result by 256 and adding the new byte,
    // then take modulo shardCount. This final remainder is appended to AID.name.
    let remainder = hash.reduce(0) { ri, bi in
      (ri * 256 + UInt64(bi)) % UInt64(shardCount)
    }
    return "\(AID.name)-\(remainder)"
  }

  /// Resolves a sort key from an aggregate ID and sequence number.
  ///
  /// - Parameters:
  ///   - aid: The aggregate ID.
  ///   - seqNr: The event sequence number, or `0` for the snapshot record.
  /// - Returns: A sort key of the form
  ///   `"<AID.name>-<aid.description>-<seqNr>"`.
  ///
  /// The components are interpolated as strings without escaping or
  /// zero-padding. The resulting key is unique for the same aggregate ID and
  /// sequence number when the component strings do not introduce collisions.
  /// Keep the format stable for all records in a table.
  public static func defaultResolveSortKey(aid: some AggregateId, seqNr: Int) -> String {
    "\(AID.name)-\(aid.description)-\(seqNr)"
  }
}
