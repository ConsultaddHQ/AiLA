import SwiftUI

enum PrompterTheme: String, CaseIterable, Identifiable {
    case dark
    case light

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }
}

enum PrompterHorizontalAlignment: String, CaseIterable, Identifiable {
    case left
    case center
    case right

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .left: return "Left"
        case .center: return "Center"
        case .right: return "Right"
        }
    }
}
