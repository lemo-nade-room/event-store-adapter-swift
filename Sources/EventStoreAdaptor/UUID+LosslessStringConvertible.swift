import Foundation

extension UUID: @retroactive LosslessStringConvertible {
    /// ``LosslessStringConvertible``に準拠させるためのイニシャライザ
    /// - Parameter description: UUID文字列
    public init?(_ description: String) {
        self.init(uuidString: description)
    }
    /// ``LosslessStringConvertible``に準拠させるためのdescription
    /// 情報を失うことなく文字列に変換するUUID文字列
    public var description: String { uuidString }
}
