import Foundation

package var small: Bool {
    Environment.enableSmall
}
package var medium: Bool {
    Environment.enableMedium
}
package var large: Bool {
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
