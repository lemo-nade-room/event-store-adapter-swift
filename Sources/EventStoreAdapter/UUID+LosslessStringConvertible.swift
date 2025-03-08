import Foundation

extension UUID: @retroactive LosslessStringConvertible {
    /// - Parameter description: UUID文字列
    public init?(_ description: String) {
        self.init(uuidString: description)
    }
    /// 情報を失うことなく文字列に変換するUUID文字列
    public var description: String { uuidString }
}
