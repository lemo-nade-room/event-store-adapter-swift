import Foundation

public enum EventStoreSetting: Sendable {
    @TaskLocal public static var jsonEncoder: JSONEncoder = .init()
    @TaskLocal public static var jsonDecoder: JSONDecoder = .init()
}
