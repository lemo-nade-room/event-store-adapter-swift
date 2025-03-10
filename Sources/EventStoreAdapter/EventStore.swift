/// イベントストアを表すプロトコル
public protocol EventStore: Sendable {
    /// イベント型
    associatedtype Event: EventStoreAdapter.Event
    /// 集約型
    associatedtype Aggregate: EventStoreAdapter.Aggregate
    /// 集約ID型
    associatedtype AID: EventStoreAdapter.AggregateId

    /// イベントを永続化する
    /// - Parameters:
    ///   - event: 永続化対象のためのイベント
    ///   - version: 楽観的バージョンロック
    /// - Throws: 書き込みエラー: ``EventStoreWriteError``
    ///
    ///  すでに存在している集約から発生したイベントの保存に使用する
    ///
    ///  イベントを生成した集約のversionをそのまま引数に入れること
    func persistEvent(event: Event, version: Int) async throws

    /// イベントと集約のスナップショットを永続化する
    /// - Parameters:
    ///   - event: イベント
    ///   - aggregate: 集約
    /// - Throws: 書き込みエラー: ``EventStoreWriteError``
    ///
    ///  集約生成時には必ずこのメソッドによってイベントを集約のスナップショットごと保存する必要がある
    func persistEventAndSnapshot(event: Event, aggregate: Aggregate) async throws

    /// 集約IDによって最新のスナップショットを取得する
    /// - Parameter aid: 集約ID
    /// - Throws: 読み込みエラー: ``EventStoreReadError``
    /// - Returns: 最新のスナップショット
    func getLatestSnapshotByAID(aid: AID) async throws -> Aggregate?

    /// 指定したシーケンシャル番号以降の集約のイベント全てを発生順に取得する
    /// - Parameters:
    ///   - aid: 集約ID
    ///   - seqNr: シーケンシャル番号（連番）
    /// - Throws: 読み込みエラー: ``EventStoreReadError``
    /// - Returns: シーケンシャル番号以降の集約のイベント全てを発生順に
    ///
    /// 指定したシーケンシャル番号のイベントは含むため、スナップショット以降のイベントを取得するには、
    /// スナップショットのseqNrに1加算した値を引数に入れると良い
    func getEventsByAIDSinceSequenceNumber(aid: AID, seqNr: Int) async throws -> [Event]
}

public enum EventStoreWriteError: Swift.Error {
    case serializationError(any Error)
    case optimisticLockError((any Error)?)
    case IOError(any Error)
    case otherError(String)
}

public enum EventStoreReadError: Swift.Error {
    case deserializationError(any Swift.Error)
    case IOError(any Swift.Error)
    case otherError(String)
}
