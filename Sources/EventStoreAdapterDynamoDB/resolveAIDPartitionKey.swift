public import EventStoreAdapter

/// Returns the DynamoDB partition key for an aggregate ID.
///
/// The key has the form `<AID.name>-<aid.description>` and is shared by the
/// journal and snapshot tables.
///
/// - Parameters:
///   - type: The aggregate ID type, inferred from `aid` when omitted.
///   - aid: The aggregate ID whose partition key is resolved.
/// - Returns: The aggregate name and ID description joined by a hyphen.
public func resolveAIDPartitionKey<AID: AggregateId>(
  _ type: AID.Type = AID.self,
  aid: AID,
) -> String {
  "\(type.name)-\(aid.description)"
}
