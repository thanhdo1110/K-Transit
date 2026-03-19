import Foundation

/// Localized string using plain String key — respects in-app language setting
func L(_ key: String) -> String {
    let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? "ko"

    // Load from the language-specific .lproj bundle
    if let path = Bundle.main.path(forResource: lang, ofType: "lproj"),
       let bundle = Bundle(path: path) {
        let result = bundle.localizedString(forKey: key, value: key, table: nil)
        return result
    }

    // Fallback: return key itself (works for Korean since keys ARE Korean text)
    return key
}
