import Foundation

var small: Bool {
    Environment.enableSmall
}
var medium: Bool {
    Environment.enableMedium
}
var large: Bool {
    Environment.enableLarge
}

enum Environment {
    case small, medium, large, all

    static var enableSmall: Bool {
        [.all, .small].contains(detect())
    }

    static var enableMedium: Bool {
        [.all, .medium].contains(detect())
    }

    static var enableLarge: Bool {
        [.all, .large].contains(detect())
    }

    static func detect() -> Self {
        switch ProcessInfo.processInfo.environment["TEST_LEVEL"] {
        case "small": .small
        case "medium": .medium
        case "large": .large
        default: .all
        }
    }
}
