//
//  Localization.swift
//  pip_swift
//

import Foundation

enum L10n {
    enum Language: String {
        case chinese = "zh"
        case english = "en"
        case vietnamese = "vi"

        var usesChinese: Bool {
            self == .chinese
        }

        var usesVietnamese: Bool {
            self == .vietnamese
        }

        /// Vòng chuyển ngôn ngữ: Tiếng Việt → English → 中文 → Tiếng Việt
        var toggled: Language {
            switch self {
            case .vietnamese: return .english
            case .english: return .chinese
            case .chinese: return .vietnamese
            }
        }
    }

    static let languageDidChangeNotification = Notification.Name("L10n.languageDidChangeNotification")

    static let languageOverrideKey = "app.language.override"
    private static let systemLanguageMarkerKey = "app.language.lastSystem"

    static var languageOverride: Language? {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: languageOverrideKey) else {
                return nil
            }
            return Language(rawValue: rawValue)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.rawValue, forKey: languageOverrideKey)
            } else {
                UserDefaults.standard.removeObject(forKey: languageOverrideKey)
            }
        }
    }

    static var systemLanguage: Language {
        guard let preferred = Locale.preferredLanguages.first else { return .english }
        if preferred.hasPrefix("zh") { return .chinese }
        if preferred.hasPrefix("vi") { return .vietnamese }
        return .english
    }

    static var currentLanguage: Language {
        if let languageOverride {
            return languageOverride
        }
        return systemLanguage
    }

    static var usesChinese: Bool {
        currentLanguage.usesChinese
    }

    static var usesVietnamese: Bool {
        currentLanguage.usesVietnamese
    }

    /// Trả về chuỗi theo ngôn ngữ hiện tại. Nếu thiếu bản tiếng Việt thì dùng tiếng Anh.
    static func text(_ chinese: String, _ english: String, vi vietnamese: String? = nil) -> String {
        switch currentLanguage {
        case .chinese: return chinese
        case .vietnamese: return vietnamese ?? english
        case .english: return english
        }
    }

    /// Nhãn nút hiển thị ngôn ngữ sẽ được chuyển sang
    static var languageToggleTitle: String {
        switch currentLanguage {
        case .vietnamese: return "EN"
        case .english: return "中"
        case .chinese: return "VI"
        }
    }

    static func toggleLanguageOverride() {
        languageOverride = currentLanguage.toggled
        NotificationCenter.default.post(name: languageDidChangeNotification, object: nil)
    }

    static func rememberCurrentSystemLanguageIfNeeded() {
        if UserDefaults.standard.string(forKey: systemLanguageMarkerKey) == nil {
            UserDefaults.standard.set(systemLanguage.rawValue, forKey: systemLanguageMarkerKey)
        }
    }

    static func followSystemLanguageIfActuallyChanged() {
        let currentSystemLanguage = systemLanguage.rawValue
        let previousSystemLanguage = UserDefaults.standard.string(forKey: systemLanguageMarkerKey)
        guard previousSystemLanguage != currentSystemLanguage else { return }
        UserDefaults.standard.set(currentSystemLanguage, forKey: systemLanguageMarkerKey)
        followSystemLanguageAndNotify()
    }

    static func followSystemLanguageAndNotify() {
        languageOverride = nil
        UserDefaults.standard.set(systemLanguage.rawValue, forKey: systemLanguageMarkerKey)
        NotificationCenter.default.post(name: languageDidChangeNotification, object: nil)
    }

    static var versionDisplay: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.0fix"
    }

    static var isBetaBuild: Bool {
        let normalizedVersion = versionDisplay.lowercased()
        return normalizedVersion.contains("beta")
            || normalizedVersion.contains("alpha")
            || normalizedVersion.contains("test")
            || normalizedVersion.contains("测试")
            || normalizedVersion.contains("thử nghiệm")
    }

    static var appName: String { text("全局高刷", "Global Refresh", vi: "Global Refresh") }
    static var floatingWindow: String { text("悬浮窗", "Floating", vi: "Cửa sổ nổi") }
    static var frameRateDemo: String { text("帧率演示", "Frame Rate", vi: "Tần số quét") }
    static var version: String { text("版本", "Version", vi: "Phiên bản") }
    static var home: String { text("首页", "Home", vi: "Trang chủ") }
    static var about: String { text("关于", "About", vi: "Giới thiệu") }
    static var changelog: String { text("更新日志", "Changelog", vi: "Nhật ký cập nhật") }
    static var faq: String { text("常见问题", "FAQ", vi: "Câu hỏi thường gặp") }
    static var cacheCleanupTitle: String { text("清理缓存", "Clear Cache", vi: "Xóa bộ nhớ đệm") }
    static var cacheCleanupMessage: String {
        text(
            "将删除 App 缓存和历史临时视频，不会清理设置、内置素材或诊断日志。正在运行的悬浮窗会保留当前媒体缓存。",
            "This removes app caches and old temporary videos. Settings, bundled assets, and diagnostic logs are kept. The active PiP media cache is preserved.", vi: "Thao tác này xóa bộ nhớ đệm ứng dụng và các video tạm cũ. Cài đặt, tài nguyên đi kèm và nhật ký chẩn đoán được giữ lại. Bộ nhớ đệm phương tiện của PiP đang chạy được giữ nguyên."
        )
    }
    static var cacheCleanupConfirm: String { text("清理", "Clear", vi: "Xóa") }
    static var cacheCleanupCompleted: String { text("缓存清理完成", "Cache Cleared", vi: "Đã xóa bộ nhớ đệm") }
    static var ok: String { text("确定", "OK", vi: "OK") }
    static var cancel: String { text("取消", "Cancel", vi: "Hủy") }
}
