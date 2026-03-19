import SwiftUI
import Combine

enum AppLanguage: String, CaseIterable, Codable {
    case korean = "ko"
    case english = "en"
    case vietnamese = "vi"

    var displayName: String {
        switch self {
        case .korean: return "한국어"
        case .english: return "English"
        case .vietnamese: return "Tiếng Việt"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }
}

enum AppTheme: String, CaseIterable, Codable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var displayName: LocalizedStringKey {
        switch self {
        case .system: return "시스템"
        case .light: return "라이트"
        case .dark: return "다크"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

class SettingsStore: ObservableObject {
    @AppStorage("appLanguage") var language: AppLanguage = .korean {
        willSet { objectWillChange.send() }
    }
    @AppStorage("appTheme") var theme: AppTheme = .system {
        willSet { objectWillChange.send() }
    }
    @AppStorage("debugMode") var debugMode: Bool = false {
        willSet { objectWillChange.send() }
    }
}
