public import EventStoreAdapter
import Foundation

/// Resolves aggregate IDs and sequence numbers to DynamoDB key strings.
///
/// The event store calls `resolvePartitionKey` and `resolveSortKey` when it
/// writes an item's primary key and when it reads events or the current snapshot.
/// Event reads query the resolved partition and an inclusive range of sort keys.
/// Changing the resolver after data has been persisted can make records
/// unreadable, make updates target a different snapshot row, or create
/// base-table items that do not belong to the existing key scheme.
///
/// The default resolver gives each aggregate its own partition key, derived
/// from its type name and ID, and uses the zero-padded sequence number as
/// the sort key.
/// Custom resolvers must preserve this isolation and deterministic ordering.
public struct KeyResolver<AID: AggregateId>: Sendable {
  /// Produces a partition key that uniquely identifies an aggregate.
  ///
  /// The default closure calls ``KeyResolver/defaultResolvePartitionKey(aid:)``.
  /// The same aggregate must always resolve to the same key, including across
  /// process restarts. Different aggregate IDs or aggregate type names must
  /// produce different keys in each table. Records sharing a partition key
  /// must belong to only one aggregate: reads rely on this contract without
  /// filtering `aid`.
  public var resolvePartitionKey: @Sendable (AID) -> String

  /// Produces the sort key for a sequence number.
  ///
  /// The default closure calls ``KeyResolver/defaultResolveSortKey(seqNr:)``.
  /// The same sequence number must always produce the same key.
  /// Distinct persisted records that share a partition key must have
  /// distinct sort keys.
  ///
  /// It must accept every value in `0...Int.max` and
  /// produce strictly increasing keys in UTF-8 byte order as sequence numbers
  /// increase. For example, the key for sequence `9` must sort before the key
  /// for sequence `10`, even across separate invocations or process restarts.
  /// Event queries use the requested sequence number as an inclusive lower
  /// bound. Unpadded decimal keys do not satisfy this ordering requirement.
  public var resolveSortKey: @Sendable (Int) -> String

  /// Creates a key resolver from custom closures or the default key scheme.
  ///
  /// - Parameters:
  ///   - resolvePartitionKey: Produces a unique partition key from an aggregate
  ///     ID and its type name.
  ///   - resolveSortKey: Produces a sort key from a sequence number.
  ///     Defaults to the sequence number padded to 19 digits.
  ///
  /// The closures are captured without modification and may be invoked
  /// concurrently by event-store operations.
  public init(
    resolvePartitionKey: @escaping @Sendable (AID) -> String = Self.defaultResolvePartitionKey,
    resolveSortKey: @escaping @Sendable (Int) -> String = Self.defaultResolveSortKey,
  ) {
    self.resolvePartitionKey = resolvePartitionKey
    self.resolveSortKey = resolveSortKey
  }
}

extension KeyResolver {
  /// Resolves a partition key from an aggregate's type name and ID.
  ///
  /// - Parameter aid: The aggregate ID, with a canonical, stable description.
  /// - Returns: `"<AID.name>-<aid.description>"`.
  ///
  /// Type names and ID descriptions must be canonical and stable, and their
  /// hyphen-joined keys must be unambiguous across all aggregate types sharing
  /// a table. Neither component is escaped.
  ///
  /// Existing keys with a different format must be migrated before switching
  /// to this resolver. DynamoDB manages physical partition placement itself.
  public static func defaultResolvePartitionKey(aid: AID) -> String {
    "\(AID.name)-\(aid.description)"
  }

  /// Resolves a sort key from a sequence number.
  ///
  /// - Parameter seqNr: The nonnegative event sequence number, or `0` for the snapshot record.
  /// - Returns: The sequence number padded to 19 decimal digits.
  ///
  /// Nineteen decimal digits cover `0...Int64.max`. Leading zeros make string
  /// ordering match numeric ordering within an aggregate, including across
  /// digit boundaries. Aggregate identity is already encoded in the partition
  /// key, so different aggregates may use the same sort key.
  ///
  /// Earlier versions included aggregate identity in the sort key and used
  /// unpadded sequence numbers. Existing journal and snapshot keys must be
  /// migrated before using this default with that data.
  /// Custom resolvers must match stored keys and satisfy the ordering contract
  /// of ``KeyResolver/resolveSortKey`` for journal reads.
  public static func defaultResolveSortKey(seqNr: Int) -> String {
    String(format: "%019lld", Int64(seqNr))
  }
}
