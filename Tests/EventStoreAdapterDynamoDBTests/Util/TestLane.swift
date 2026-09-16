import Foundation

extension Bool {
  static var medium: Bool {
    ProcessInfo.processInfo.environment["MEDIUM_TESTS"] == "true"
  }
}
