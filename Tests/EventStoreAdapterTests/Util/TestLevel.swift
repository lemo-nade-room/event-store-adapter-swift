import Foundation

var small: Bool {
    ProcessInfo.processInfo.environment["SMALL"] == "true"
}
var medium: Bool {
    ProcessInfo.processInfo.environment["MEDIUM"] == "true"
}
var large: Bool {
    ProcessInfo.processInfo.environment["LARGE"] == "true"
}
