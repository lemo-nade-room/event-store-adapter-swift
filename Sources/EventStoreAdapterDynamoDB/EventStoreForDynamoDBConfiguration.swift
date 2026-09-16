public import Configuration

/// Names and key-distribution settings required by ``EventStoreForDynamoDB``.
///
/// The adapter uses two DynamoDB tables. Each table must have a string
/// partition key named `pkey` and a string sort key named `skey`. Each table
/// must also provide a global secondary index whose partition key is the
/// string attribute `aid` and whose numeric sort key is `seq_nr`. The journal
/// index is queried for events; the snapshot index is queried for the single
/// snapshot record whose `seq_nr` is `0`.
///
/// This type only carries names and does not create, inspect, or validate the
/// tables. Create the tables and indexes with a schema that matches these
/// requirements before using the event store.
public struct EventStoreForDynamoDBConfiguration: Sendable, Hashable, Codable {
  /// The DynamoDB table that stores journal events.
  public var journalTableName: String

  /// The journal table's GSI used to query events by aggregate ID and sequence number.
  public var journalAidIndexName: String

  /// The DynamoDB table that stores the current snapshot for each aggregate.
  public var snapshotTableName: String

  /// The snapshot table's GSI used to query a snapshot by aggregate ID.
  public var snapshotAidIndexName: String

  /// The number of logical shards used by the default partition-key resolver.
  ///
  /// This value must be in `1...2^56` when the default ``KeyResolver`` is used.
  /// Changing it after data has been written changes the partition key for
  /// many aggregate IDs.
  public var shardCount: Int

  /// Creates a configuration with explicit table and index names.
  ///
  /// - Parameters:
  ///   - journalTableName: The journal table name.
  ///   - journalAidIndexName: The journal table's aggregate-ID GSI name.
  ///   - snapshotTableName: The snapshot table name.
  ///   - snapshotAidIndexName: The snapshot table's aggregate-ID GSI name.
  ///   - shardCount: The number of logical shards for partition-key resolution.
  ///
  /// The values are stored as supplied. The initializer does not validate
  /// names, index schemas, or `shardCount`.
  public init(
    journalTableName: String,
    journalAidIndexName: String,
    snapshotTableName: String,
    snapshotAidIndexName: String,
    shardCount: Int,
  ) {
    self.journalTableName = journalTableName
    self.journalAidIndexName = journalAidIndexName
    self.snapshotTableName = snapshotTableName
    self.snapshotAidIndexName = snapshotAidIndexName
    self.shardCount = shardCount
  }

  /// Creates a configuration by overriding selected default values.
  ///
  /// A `nil` argument uses the corresponding value from ``EventStoreForDynamoDBConfiguration/default``.
  ///
  /// - Parameters:
  ///   - journalTableName: An optional journal table name.
  ///   - journalAidIndexName: An optional journal aggregate-ID GSI name.
  ///   - snapshotTableName: An optional snapshot table name.
  ///   - snapshotAidIndexName: An optional snapshot aggregate-ID GSI name.
  ///   - shardCount: An optional logical shard count.
  ///
  /// The initializer does not validate names, index schemas, or `shardCount`.
  public init(
    journalTableName: String? = nil,
    journalAidIndexName: String? = nil,
    snapshotTableName: String? = nil,
    snapshotAidIndexName: String? = nil,
    shardCount: Int? = nil,
  ) {
    self.journalTableName = journalTableName ?? Self.default.journalTableName
    self.journalAidIndexName = journalAidIndexName ?? Self.default.journalAidIndexName
    self.snapshotTableName = snapshotTableName ?? Self.default.snapshotTableName
    self.snapshotAidIndexName = snapshotAidIndexName ?? Self.default.snapshotAidIndexName
    self.shardCount = shardCount ?? Self.default.shardCount
  }

  /// Creates a configuration from a `ConfigReader`, with explicit values taking precedence.
  ///
  /// The reader is queried with these keys when the corresponding argument is
  /// `nil`:
  ///
  /// - `journal.table.name`
  /// - `journal.aid.index.name`
  /// - `snapshot.table.name`
  /// - `snapshot.aid.index.name`
  /// - `shard.count`
  ///
  /// If a key is absent, the configuration falls back to the default value.
  /// The initializer does not validate names, index schemas, or `shardCount`.
  ///
  /// - Parameters:
  ///   - config: The configuration reader.
  ///   - journalTableName: An optional explicit journal table name.
  ///   - journalAidIndexName: An optional explicit journal aggregate-ID GSI name.
  ///   - snapshotTableName: An optional explicit snapshot table name.
  ///   - snapshotAidIndexName: An optional explicit snapshot aggregate-ID GSI name.
  ///   - shardCount: An optional explicit logical shard count.
  public init(
    config: ConfigReader,
    journalTableName: String? = nil,
    journalAidIndexName: String? = nil,
    snapshotTableName: String? = nil,
    snapshotAidIndexName: String? = nil,
    shardCount: Int? = nil,
  ) {
    self.init(
      journalTableName: journalTableName ?? config.string(forKey: "journal.table.name"),
      journalAidIndexName: journalAidIndexName ?? config.string(forKey: "journal.aid.index.name"),
      snapshotTableName: snapshotTableName ?? config.string(forKey: "snapshot.table.name"),
      snapshotAidIndexName: snapshotAidIndexName ?? config.string(forKey: "snapshot.aid.index.name"),
      shardCount: shardCount ?? config.int(forKey: "shard.count"),
    )
  }

  /// The default DynamoDB names and logical shard count.
  ///
  /// The defaults are `journal`, `aid-index`, `snapshot`, `aid-index`, and
  /// `64`, respectively. The same index name may be used for both tables
  /// because DynamoDB index names are scoped to a table.
  public static var `default`: Self {
    self.init(
      journalTableName: "journal",
      journalAidIndexName: "aid-index",
      snapshotTableName: "snapshot",
      snapshotAidIndexName: "aid-index",
      shardCount: 64,
    )
  }
}
