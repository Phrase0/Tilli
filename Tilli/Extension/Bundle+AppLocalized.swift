import Foundation

extension Bundle {
    /// 根據 App 語言設定回傳對應的 .lproj Bundle
    static var appLocalized: Bundle {
        let lang = UserDefaults.standard.string(forKey: "selectedLanguage") ?? "zh-Hant"
        guard let path = Bundle.main.path(forResource: lang, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }
}

extension String {
    /// 使用 App 語言設定載入 localized 字串（取代 String(localized:)）
    static func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .appLocalized)
    }
}
