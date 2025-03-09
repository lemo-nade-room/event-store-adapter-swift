import Crypto
public import EventStoreAdapter
import Foundation

/// 集約IDとシャード数、シーケンス番号からパーティションキーとソートキーを解決する
public struct KeyResolver<AID: AggregateId>: Sendable {
    /// 集約IDとシャード数を受け取り、partition keyを返す
    public var resolvePartitionKey: @Sendable (AID, Int) -> String
    /// 集約IDとシーケンス番号を受け取り、sort keyを返す
    public var resolveSortKey: @Sendable (AID, Int) -> String

    public init(
        resolvePartitionKey: @escaping @Sendable (AID, Int) -> String = {
            defaultResolvePartitionKey(aid: $0, shardCount: $1)
        },
        resolveSortKey: @escaping @Sendable (AID, Int) -> String = {
            defaultResolveSortKey(aid: $0, seqNr: $1)
        }
    ) {
        self.resolvePartitionKey = resolvePartitionKey
        self.resolveSortKey = resolveSortKey
    }
}

/// デフォルトのパーティションキーリゾルバー
/// - Parameters:
///   - aid: 集約ID
///   - shardCount: シャード数
/// - Returns: パーティションキー
public func defaultResolvePartitionKey<AID: AggregateId>(aid: AID, shardCount: Int) -> String {
    let data = Data(aid.description.utf8)
    let hash = SHA256.hash(data: data)
    /*
     [b_0, b_1, ..., b_{k-1}]
     b_n|0〜255

     N = b_0 * 256^{k-1} + b_1 * 256^{k-2} + ... + b_{k-2} * 256 + b_{k-1}

     r_0 = 0, r_{i+1} = (r_i * 256 + b_i) \mod d

     N \mod d = r_k
     */
    let remainder = hash.reduce(0) { ri, bi in
        (ri * 256 + UInt64(bi)) % UInt64(shardCount)
    }
    return "\(AID.name)-\(remainder)"
}

/// デフォルトのソートキーリゾルバー
/// - Parameters:
///   - aid: 集約ID
///   - seqNr: シーケンス番号
/// - Returns: ソートキー
public func defaultResolveSortKey<AID: AggregateId>(aid: AID, seqNr: Int) -> String {
    "\(AID.name)-\(aid.description)-\(seqNr)"
}
