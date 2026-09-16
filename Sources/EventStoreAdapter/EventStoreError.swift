/// An error raised while writing an event or snapshot.
public enum EventStoreWriteError: Swift.Error {
  /// The event or snapshot could not be serialized.
  ///
  /// The associated value contains the underlying serialization error.
  case serializationError(any Swift.Error)

  /// The write conflicted with data already stored for the aggregate.
  ///
  /// This can indicate a stale aggregate version or a duplicate event or
  /// snapshot key. The associated value contains the underlying storage error
  /// when one is available.
  case optimisticLockError((any Swift.Error)?)

  /// The backing store could not complete the write.
  ///
  /// The associated value contains the underlying I/O error.
  case IOError(any Swift.Error)

  /// The write failed for another reason.
  ///
  /// The associated value is a diagnostic message describing the failure. The
  /// message is intended for logging and should not be parsed as a stable API.
  case otherError(Swift.String)
}

/// An error raised while reading an event or snapshot.
public enum EventStoreReadError: Swift.Error {
  /// A stored event or snapshot could not be decoded.
  ///
  /// The associated value contains the underlying deserialization error.
  case deserializationError(any Swift.Error)

  /// The backing store could not complete the read.
  ///
  /// The associated value contains the underlying I/O error.
  case IOError(any Swift.Error)

  /// The stored data was invalid or the read failed for another reason.
  ///
  /// The associated value is a diagnostic message describing the failure. The
  /// message is intended for logging and should not be parsed as a stable API.
  case otherError(Swift.String)
}
