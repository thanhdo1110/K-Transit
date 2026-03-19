import Foundation

/// Localized string that respects in-app language setting (instant switch)
func L(_ key: String.LocalizationValue) -> String {
    let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? "ko"
    let keyStr = "\(key)"

    // Korean is source language — no ko.lproj exists, use main bundle directly
    if lang == "ko" {
        // Return the key itself (which IS the Korean string in our xcstrings)
        return keyStr
    }

    // For en/vi — load from the language-specific .lproj bundle
    if let path = Bundle.main.path(forResource: lang, ofType: "lproj"),
       let bundle = Bundle(path: path) {
        let result = bundle.localizedString(forKey: keyStr, value: keyStr, table: nil)
        return result
    }

    // Final fallback
    return String(localized: key, locale: Locale(identifier: lang))
}
