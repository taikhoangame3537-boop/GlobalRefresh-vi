//
//  KeepAliveLogger.swift
//  pip_swift
//

import UIKit
import Darwin
import UserNotifications

enum KeepAliveNotificationProbeFrequency: String, CaseIterable {
    case low
    case high
    case ultra

    var title: String {
        switch self {
        case .low: return "Phát hiện tần suất thấp"
        case .high: return "Phát hiện tần suất cao"
        case .ultra: return "Phát hiện tần suất rất cao"
        }
    }

    var detail: String {
        switch self {
        case .low: return "30 phút kiểm tra một lần, thông báo được hoãn kích hoạt, ít can thiệp nền nhất"
        case .high: return "1 phút kiểm tra một lần, có bộ đệm ngắn, phát hiện bất thường nhanh hơn"
        case .ultra: return "20 giây kiểm tra một lần, chủ yếu để thử nghiệm, nguy cơ báo nhầm cao hơn"
        }
    }

    var localizedTitle: String {
        switch self {
        case .low: return L10n.text("低频检测", "Low", vi: "Thấp")
        case .high: return L10n.text("高频检测", "High", vi: "Cao")
        case .ultra: return L10n.text("超高频检测", "Ultra", vi: "Cực cao")
        }
    }

    var localizedDetail: String {
        switch self {
        case .low:
            return L10n.text("30分钟检测一次，通知延后触发，后台干扰最低", "Checks every 30 minutes. Lowest background interference.", vi: "Kiểm tra mỗi 30 phút. Ít can thiệp nền nhất.")
        case .high:
            return L10n.text("1分钟检测一次，带短缓冲，更快发现异常", "Checks every minute with a short buffer for faster detection.", vi: "Kiểm tra mỗi phút kèm bộ đệm ngắn để phát hiện nhanh hơn.")
        case .ultra:
            return L10n.text("20秒检测一次，主要用于测试，误报风险更高", "Checks every 20 seconds for testing. Higher false-positive risk.", vi: "Kiểm tra mỗi 20 giây để thử nghiệm. Nguy cơ báo nhầm cao hơn.")
        }
    }

    var interval: TimeInterval {
        switch self {
        case .low: return 30 * 60
        case .high: return 60
        case .ultra: return 20
        }
    }

    var intervalText: String {
        switch self {
        case .low: return "30 phút"
        case .high: return "1 phút"
        case .ultra: return "20 giây"
        }
    }

    var notificationDelay: TimeInterval {
        switch self {
        case .low: return 45 * 60
        case .high: return 90
        case .ultra: return 30
        }
    }

    var notificationDelayText: String {
        switch self {
        case .low: return "45 phút"
        case .high: return "1 phút 30 giây"
        case .ultra: return "30 giây"
        }
    }

    var refreshInterval: TimeInterval {
        switch self {
        case .low: return 29 * 60
        case .high: return 55
        case .ultra: return 20
        }
    }

}

struct KeepAliveInterruptionNotice {
    let interruptedAtText: String
    let runtimeText: String

    var message: String {
        L10n.text(
            """
            上次后台在\(interruptedAtText)左右中断
            持续运行了\(runtimeText)
            """,
            """
            The last background session may have stopped around \(interruptedAtText).
            Runtime: \(runtimeText)
            """, vi: """
            Phiên chạy nền gần nhất có thể đã dừng vào khoảng \(interruptedAtText).
            Thời gian chạy: \(runtimeText)
            """
        )
    }
}

struct KeepAliveLocalNotificationNotice {
    let interruptedAtText: String
    let runtimeText: String
    let reason: String

    var message: String {
        L10n.text(
            """
            上次后台在\(interruptedAtText)左右中断
            持续运行了\(runtimeText)
            原因：\(reason)
            """,
            """
            The last background session may have stopped around \(interruptedAtText).
            Runtime: \(runtimeText)
            Reason: \(localizedReason)
            """, vi: """
            Phiên chạy nền gần nhất có thể đã dừng vào khoảng \(interruptedAtText).
            Thời gian chạy: \(runtimeText)
            Lý do: \(localizedReason)
            """
        )
    }

    private var localizedReason: String {
        switch reason {
        case "Có thể bị ứng dụng Hình trong hình khác đẩy đi hoặc bị hệ thống dừng":
            return L10n.text(reason, "Another PiP app or the system may have stopped it", vi: reason)
        default:
            return reason
        }
    }
}

enum KeepAliveLogger {
    private static let eventsKey = "pip.keepAlive.events"
    private static let sessionActiveKey = "pip.keepAlive.sessionActive"
    private static let sessionStartKey = "pip.keepAlive.sessionStart"
    private static let backgroundStartKey = "pip.keepAlive.backgroundStart"
    private static let lastHeartbeatKey = "pip.keepAlive.lastHeartbeat"
    private static let lastHeartbeatSnapshotKey = "pip.keepAlive.lastHeartbeatSnapshot"
    private static let lastModeKey = "pip.keepAlive.lastMode"
    private static let lastInterruptionSummaryKey = "pip.keepAlive.lastInterruptionSummary"
    private static let maximumEvents = 200
    private static let maximumStoredTextBytes = 8 * 1024

    @discardableResult
    static func markAppLaunch() -> KeepAliveInterruptionNotice? {
        guard shouldTrackState else { return nil }
        if UserDefaults.standard.bool(forKey: sessionActiveKey),
           UserDefaults.standard.double(forKey: backgroundStartKey) > 0 {
            let sessionStart = storedTimestamp(sessionStartKey)
            let lastHeartbeat = storedTimestamp(lastHeartbeatKey)
            let heartbeatText = compactDateText(lastHeartbeat)
            let runtimeText = runtimeText(start: sessionStart, end: lastHeartbeat)
            let lastSnapshot = UserDefaults.standard.string(forKey: lastHeartbeatSnapshotKey) ?? "Không có hiện trường"
            let summary = "Giữ nền lần trước có thể bị gián đoạn bất thường, nhịp cuối=\(storedDateText(lastHeartbeatKey)), chạy liên tục=\(runtimeText), chế độ=\(UserDefaults.standard.string(forKey: lastModeKey) ?? "Không rõ"), hiện trường{\(lastSnapshot)}"
            UserDefaults.standard.set(summary, forKey: lastInterruptionSummaryKey)
            appendIfDebug("App Khởi động lại: \(summary), lần khởi động này=\(nowText)")
            AppDebugLogger.logCritical("Suy luận gián đoạn giữ nền bất thường: \(summary)")
            UserDefaults.standard.set(false, forKey: sessionActiveKey)
            UserDefaults.standard.removeObject(forKey: backgroundStartKey)
            return KeepAliveInterruptionNotice(interruptedAtText: heartbeatText, runtimeText: runtimeText)
        } else {
            appendIfDebug("App Khởi động")
            return nil
        }
    }

    static func markPiPStarted(mode: String) {
        guard shouldTrackState else { return }
        UserDefaults.standard.set(true, forKey: sessionActiveKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: sessionStartKey)
        UserDefaults.standard.set(mode, forKey: lastModeKey)
        heartbeat()
        appendIfDebug("Cửa sổ nổi bắt đầu giữ nền, chế độ=\(mode)")
    }

    static func markPiPStopped(reason: String) {
        guard shouldTrackState else { return }
        appendIfDebug("Cửa sổ nổi dừng giữ nền, lý do=\(reason), bắt đầu=\(storedDateText(sessionStartKey)), nhịp cuối=\(storedDateText(lastHeartbeatKey))")
        UserDefaults.standard.set(false, forKey: sessionActiveKey)
        UserDefaults.standard.removeObject(forKey: backgroundStartKey)
        KeepAliveNotificationTester.cancelBackgroundInterruptionProbe(reason: "Cửa sổ nổi dừng: \(reason)")
    }

    static func markEnterBackground(mode: String) {
        guard shouldTrackState else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: backgroundStartKey)
        UserDefaults.standard.set(mode, forKey: lastModeKey)
        heartbeat()
        appendIfDebug("Vào nền để giữ nền, chế độ=\(mode)")
        KeepAliveNotificationTester.notifyDidEnterBackground(mode: mode)
    }

    static func markEnterForeground() {
        guard shouldTrackState else { return }
        appendIfDebug("Quay lại nền trước, bắt đầu ở nền=\(storedDateText(backgroundStartKey)), nhịp cuối=\(storedDateText(lastHeartbeatKey))")
        UserDefaults.standard.removeObject(forKey: backgroundStartKey)
        heartbeat()
        KeepAliveNotificationTester.cancelBackgroundInterruptionProbe(reason: "Quay lại nền trước")
    }

    static func heartbeat(snapshot: String? = nil, persistImmediately: Bool = true) {
        guard shouldTrackState else { return }
        let defaults = UserDefaults.standard
        defaults.set(Date().timeIntervalSince1970, forKey: lastHeartbeatKey)
        if let snapshot {
            defaults.set(limitStoredText(snapshot), forKey: lastHeartbeatSnapshotKey)
        }
        if persistImmediately {
            defaults.synchronize()
        }
    }

    static var lastHeartbeatDate: Date? {
        let timestamp = UserDefaults.standard.double(forKey: lastHeartbeatKey)
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    static func backgroundInterruptionProbeDecision(staleAfter: TimeInterval) -> (shouldNotify: Bool, reason: String) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: sessionActiveKey) else {
            return (false, "Phiên giữ nền chưa bật")
        }
        guard defaults.double(forKey: backgroundStartKey) > 0 else {
            return (false, "Chưa ghi nhận giữ nền ở nền")
        }
        let lastHeartbeat = defaults.double(forKey: lastHeartbeatKey)
        guard lastHeartbeat > 0 else {
            return (true, "Không có bản ghi nhịp")
        }
        let age = Date().timeIntervalSince1970 - lastHeartbeat
        if age >= staleAfter {
            return (true, "Nhịp cuối đã quá \(durationText(age))")
        }
        return (false, "Nhịp bình thường, cách nhịp trước \(durationText(age))")
    }

    static func markNotificationScheduled(reason: String, fireAt: Date) {
        guard shouldTrackState else { return }
        append("Thông báo đã xếp hàng, lý do=\(reason), dự kiến hiện lúc=\(compactFormatter.string(from: fireAt))")
    }

    static func markNotificationCancelled(reason: String) {
        guard shouldTrackState else { return }
        append("Thông báo đã hủy, lý do=\(reason)")
    }

    static func markNotificationPaused(reason: String) {
        guard shouldTrackState else { return }
        append("Thông báo đã tạm dừng, lý do=\(reason)")
    }

    static func markNotificationLockProtectionBypassed(reason: String) {
        guard shouldTrackState else { return }
        append("BETA5 Đã bỏ qua bảo vệ khóa màn hình cho thông báo, lý do=\(reason)")
    }

    static func copyToPasteboard() {
        UIPasteboard.general.string = exportText()
    }

    static func resetLogs() {
        let defaults = UserDefaults.standard
        for key in [eventsKey, sessionActiveKey, sessionStartKey, backgroundStartKey, lastHeartbeatKey, lastHeartbeatSnapshotKey, lastModeKey, lastInterruptionSummaryKey] {
            defaults.removeObject(forKey: key)
        }
        KeepAliveNotificationTester.cancelAllTestingNotifications(reason: "Đã xóa nhật ký giữ nền")
    }

    static func exportText() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let device = UIDevice.current
        let events = UserDefaults.standard.stringArray(forKey: eventsKey) ?? []
        let isActive = UserDefaults.standard.bool(forKey: sessionActiveKey)

        return """
        Nhật ký giữ nền Global Refresh
        App Phiên bản: \(version) (\(build))
        Bundle ID: \(bundleID)
        Phiên bản hệ thống: iOS \(device.systemVersion)
        Mẫu thiết bị: \(deviceModelIdentifier)
        Thời điểm tạo: \(nowText) giờ Bắc Kinh
        Chế độ giữ nền hiện tại: \(KeepAliveModeText.current)

        Trạng thái giữ nền hiện tại: \(isActive ? "Có thể đang giữ nền" : "Không ở trạng thái giữ nền")
        Bản ghi chế độ chạy hiện tại: \(UserDefaults.standard.string(forKey: lastModeKey) ?? "Không rõ")
        Thời điểm bắt đầu giữ nền: \(storedDateText(sessionStartKey))
        Thời điểm bắt đầu ở nền: \(storedDateText(backgroundStartKey))
        Thời điểm nhịp cuối: \(storedDateText(lastHeartbeatKey))
        Hiện trường nhịp cuối: \(UserDefaults.standard.string(forKey: lastHeartbeatSnapshotKey) ?? "Không")
        Tóm tắt gián đoạn bất thường lần trước: \(UserDefaults.standard.string(forKey: lastInterruptionSummaryKey) ?? "Không")

        Lưu ý: iOS không thông báo cho ứng dụng thông thường vào khoảnh khắc ứng dụng bị tắt; nếu lần khởi động sau phát hiện giữ nền lần trước không dừng bình thường, sẽ dùng“thời điểm nhịp cuối”đến“thời điểm khởi động lần này”để suy ra khoảng thời gian có thể bị gián đoạn.

        Sự kiện giữ nền gần đây:
        \(events.isEmpty ? "Chưa có sự kiện giữ nền" : events.joined(separator: "\n"))
        """
    }

    private static func append(_ message: String) {
        var events = UserDefaults.standard.stringArray(forKey: eventsKey) ?? []
        events.append(limitStoredText("\(nowText) | \(message)"))
        if events.count > maximumEvents {
            events.removeFirst(events.count - maximumEvents)
        }
        UserDefaults.standard.set(events, forKey: eventsKey)
        UserDefaults.standard.synchronize()
    }

    private static func limitStoredText(_ text: String) -> String {
        guard text.utf8.count > maximumStoredTextBytes else { return text }
        let marker = "\n[Bản ghi quá dài, đã bị cắt bớt]"
        let prefixByteCount = max(0, maximumStoredTextBytes - marker.utf8.count)
        return String(decoding: text.utf8.prefix(prefixByteCount), as: UTF8.self) + marker
    }

    fileprivate static func appendIfDebug(_ message: String) {
        guard AppDebugLogger.isDebugModeEnabled else { return }
        append(message)
    }

    private static var shouldTrackState: Bool {
        AppDebugLogger.isDebugModeEnabled || KeepAliveNotificationTester.isAnyNotificationEnabled
    }

    private static func storedDateText(_ key: String) -> String {
        let timestamp = storedTimestamp(key)
        guard timestamp > 0 else { return "Không" }
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    private static func storedTimestamp(_ key: String) -> TimeInterval {
        UserDefaults.standard.double(forKey: key)
    }

    private static func compactDateText(_ timestamp: TimeInterval) -> String {
        guard timestamp > 0 else { return "Không rõ thời gian" }
        return compactFormatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    private static func runtimeText(start: TimeInterval, end: TimeInterval) -> String {
        guard start > 0, end > 0, end >= start else { return "00:00:00" }
        let totalSeconds = max(0, Int((end - start).rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d giờ %d phút %d giây", hours, minutes, seconds)
        }
        if minutes > 0 {
            return String(format: "%d phút %d giây", minutes, seconds)
        }
        return "\(seconds) giây"
    }

    fileprivate static var nowText: String {
        formatter.string(from: Date())
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private static let compactFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "M/d HH:mm:ss"
        return formatter
    }()

    private static var deviceModelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            identifier.append(String(UnicodeScalar(UInt8(value))))
        }
    }
}

// TEST ANCHOR: Kiểm thử cảnh báo gián đoạn nền/dừng cửa sổ nổi. Khi rút lại hãy xóa enum này và gỡ các lệnh gọi trong KeepAliveLogger/ViewController/VersionViewController.
enum KeepAliveNotificationTester {
    private static let legacyEnabledKey = "pip.keepAlive.notificationTesterEnabled"
	    private static let backgroundProbeEnabledKey = "pip.keepAlive.backgroundProbeNotificationEnabled"
	    private static let pipStoppedEnabledKey = "pip.keepAlive.pipStoppedNotificationEnabled"
	    private static let splitNotificationMigrationKey = "pip.keepAlive.notificationSplit.v1"
	    private static let pipStoppedDefaultMigrationKey = "pip.keepAlive.pipStoppedNotificationDefault.v1"
    private static let frequencyKey = "pip.keepAlive.notificationProbeFrequency"
    private static let frequencyMigrationKey = "pip.keepAlive.notificationProbeFrequency.v6"
    private static let defaultProbeFrequency = KeepAliveNotificationProbeFrequency.low
    private static let backgroundProbeIdentifier = "pip.keepAlive.backgroundInterruptionProbe"
    private static let pipStoppedIdentifier = "pip.keepAlive.pipStopped"
    private static let pendingLocalNotificationNoticeKey = "pip.keepAlive.pendingLocalNotificationNotice"
    private static let immediateDelay: TimeInterval = 1
    private static let backgroundProbeSafetyWindow: TimeInterval = 60
    private static let heartbeatStaleGrace: TimeInterval = 90
    private static let foregroundTakeoverGrace: TimeInterval = 5 * 60
    private static let foregroundTakeoverBounceWindow: TimeInterval = 8
    private static let foregroundTakeoverEndRecoveryWindow: TimeInterval = 12
    private static let systemOverlayProtectionThreshold: TimeInterval = 0.6
    private static let cameraInterruptionWindow: TimeInterval = 2
    private static let pipStartBackgroundGrace: TimeInterval = 6
    private static let backgroundProbeQueue = DispatchQueue(label: "pip.keepAlive.backgroundProbeRefresh")
    private static var backgroundProbeRefreshTimer: DispatchSourceTimer?
    private static let backgroundProbeGenerationLock = NSLock()
    private static var backgroundProbeGeneration = 0
    private static var pendingBackgroundProbeStartWorkItem: DispatchWorkItem?
    private static var pendingUnlockResumeWorkItem: DispatchWorkItem?
    private static var activeBackgroundProbeMode: String?
    private static var didInstallLockStateObserver = false
    private static var lastActiveResignAt: Date?
    private static var foregroundLockStartedAt: Date?
    private static var foregroundSystemOverlayStartedAt: Date?
    private static var foregroundTakeoverSuppressedUntil: Date?
    private static var foregroundTakeoverBounceSuppressedUntil: Date?
    private static var foregroundTakeoverRecentlyEndedUntil: Date?
    private static var foregroundTakeoverSessionActive = false
    private static var lastPiPStartedAt: Date?
    private static var lastAudioInterruptionBeganAt: Date?
    private static var audioInterruptionSessionActive = false
    private static var suppressBackgroundProbeUntilUnlock = false

	    private static func migrateSplitNotificationPreferencesIfNeeded() {
	        guard !UserDefaults.standard.bool(forKey: splitNotificationMigrationKey) else { return }
	        UserDefaults.standard.set(true, forKey: splitNotificationMigrationKey)
	        UserDefaults.standard.set(false, forKey: backgroundProbeEnabledKey)
	        if UserDefaults.standard.bool(forKey: legacyEnabledKey) {
	            AppDebugLogger.log("Công tắc thông báo nền đã được tách riêng, công tắc cũ không tự động di chuyển, hai công tắc mới mặc định tắt")
	        }
	    }

	    static func enablePiPStoppedNotificationByDefaultIfNeeded(from controller: UIViewController?, completion: @escaping (Bool) -> Void) {
	        migrateSplitNotificationPreferencesIfNeeded()
	        guard !UserDefaults.standard.bool(forKey: pipStoppedDefaultMigrationKey) else {
	            completion(isPiPStoppedNotificationEnabled)
	            return
	        }
	        UserDefaults.standard.set(true, forKey: pipStoppedDefaultMigrationKey)
	        guard UserDefaults.standard.object(forKey: pipStoppedEnabledKey) == nil else {
	            completion(isPiPStoppedNotificationEnabled)
	            return
	        }
	        prepareForPiPStoppedToggle(from: controller, shouldOpenSettingsOnDenied: false, completion: completion)
	    }

    static var isEnabled: Bool {
        isBackgroundProbeEnabled
    }

    static var isAnyNotificationEnabled: Bool {
        isBackgroundProbeEnabled || isPiPStoppedNotificationEnabled
    }

    static var isBackgroundProbeEnabled: Bool {
        get {
            migrateSplitNotificationPreferencesIfNeeded()
            return UserDefaults.standard.bool(forKey: backgroundProbeEnabledKey)
        }
        set {
            migrateSplitNotificationPreferencesIfNeeded()
            UserDefaults.standard.set(newValue, forKey: backgroundProbeEnabledKey)
            if !newValue {
                cancelBackgroundProbeNotifications(reason: "Tắt cảnh báo gián đoạn nền beta")
            }
        }
    }

    static var isPiPStoppedNotificationEnabled: Bool {
        get {
            migrateSplitNotificationPreferencesIfNeeded()
            return UserDefaults.standard.bool(forKey: pipStoppedEnabledKey)
        }
        set {
            migrateSplitNotificationPreferencesIfNeeded()
            UserDefaults.standard.set(newValue, forKey: pipStoppedEnabledKey)
            if !newValue {
                cancelPiPStoppedNotifications(reason: "Tắt thông báo cửa sổ nổi bị đẩy đi")
            }
        }
    }

    static var probeFrequency: KeepAliveNotificationProbeFrequency {
        get {
            if !UserDefaults.standard.bool(forKey: frequencyMigrationKey) {
                UserDefaults.standard.set(true, forKey: frequencyMigrationKey)
                UserDefaults.standard.set(defaultProbeFrequency.rawValue, forKey: frequencyKey)
                return defaultProbeFrequency
            }
            let rawValue = UserDefaults.standard.string(forKey: frequencyKey) ?? defaultProbeFrequency.rawValue
            return KeepAliveNotificationProbeFrequency(rawValue: rawValue) ?? defaultProbeFrequency
        }
        set {
            let oldValue = probeFrequency
            UserDefaults.standard.set(newValue.rawValue, forKey: frequencyKey)
            guard oldValue != newValue else { return }
            AppDebugLogger.log("Đổi tần suất cảnh báo gián đoạn nền: \(newValue.title), khoảng cách=\(newValue.intervalText)")
            restartActiveBackgroundProbeIfNeeded(reason: "Đổi tần suất")
        }
    }

    static func prepareForBackgroundProbeToggle(from controller: UIViewController?, completion: @escaping (Bool) -> Void) {
        ensureAuthorizationForHomeToggle(from: controller) { granted in
            guard granted else {
                isBackgroundProbeEnabled = false
                completion(false)
                return
            }
            isBackgroundProbeEnabled = true
            sanitizeScheduledNotifications(reason: "Trang chủ bật thông báo gián đoạn nền")
            completion(true)
        }
    }

	    static func prepareForPiPStoppedToggle(
	        from controller: UIViewController?,
	        shouldOpenSettingsOnDenied: Bool = true,
	        completion: @escaping (Bool) -> Void
	    ) {
	        ensureAuthorizationForHomeToggle(
	            from: controller,
	            purpose: .pipStopped,
	            shouldOpenSettingsOnDenied: shouldOpenSettingsOnDenied
	        ) { granted in
	            guard granted else {
	                isPiPStoppedNotificationEnabled = false
                completion(false)
                return
            }
            isPiPStoppedNotificationEnabled = true
            completion(true)
        }
    }

    static func sanitizeOnLaunch() {
        installLockStateObserverIfNeeded()
        sanitizeScheduledNotifications(reason: "Dọn dẹp khi khởi động")
    }

    static func presentLaunchInterruptionAlert(_ notice: KeepAliveInterruptionNotice, from controller: UIViewController) {
        guard isBackgroundProbeEnabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak controller] in
            guard let controller, controller.presentedViewController == nil else { return }
            let alert = UIAlertController(
                title: L10n.text("后台保活可能已中断", "Background keep-alive may have stopped", vi: "Giữ nền có thể đã bị dừng"),
                message: notice.message,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: L10n.text("知道了", "OK", vi: "OK"), style: .default))
            controller.present(alert, animated: true)
        }
    }

    static func presentPendingLocalNotificationAlertIfNeeded(from controller: UIViewController) {
        guard isPiPStoppedNotificationEnabled, let notice = pendingLocalNotificationNoticeIfReady() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak controller] in
            guard let controller, controller.presentedViewController == nil else { return }
            let alert = UIAlertController(
                title: L10n.text("后台保活可能已中断", "Background keep-alive may have stopped", vi: "Giữ nền có thể đã bị dừng"),
                message: notice.message,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: L10n.text("知道了", "OK", vi: "OK"), style: .default))
            controller.present(alert, animated: true)
            clearPendingLocalNotificationNotice()
        }
    }

    static func startBackgroundInterruptionProbe(mode: String) {
        guard isEnabled else { return }
        DispatchQueue.main.async {
            installLockStateObserverIfNeeded()
            guard isAppInBackground else {
                clearBackgroundProbeStateOnMain(reason: "Không ở nền, bỏ qua thông báo gián đoạn nền khi khởi động")
                return
            }
            guard !isForegroundLockProbeSuppressed else {
                activeBackgroundProbeMode = mode
                pauseBackgroundProbeForDeviceLockOnMain(reason: "Khóa màn hình ở nền trước rồi vào nền, không lên lịch thông báo trước khi mở khóa")
                return
            }
            guard !isDeviceLocked else {
                pauseBackgroundProbeForDeviceLockOnMain(reason: "Thiết bị bị khóa khi vào nền")
                return
            }
            guard !isForegroundSystemOverlayTransition else {
                pauseBackgroundProbeForDeviceLockOnMain(reason: "Giao diện hệ thống phủ lên nền trước, bỏ qua thông báo gián đoạn nền")
                return
            }
            guard !isForegroundLockTransition else {
                clearBackgroundProbeStateOnMain(reason: "Khóa màn hình ở nền trước, bỏ qua thông báo gián đoạn nền")
                return
            }
            pendingUnlockResumeWorkItem?.cancel()
            pendingUnlockResumeWorkItem = nil
            activeBackgroundProbeMode = mode
            requestAuthorizationIfNeeded()
            pendingBackgroundProbeStartWorkItem?.cancel()
            pendingBackgroundProbeStartWorkItem = nil
            if isForegroundTakeoverSuppressed {
                startBackgroundProbeSafetyWindow(
                    mode: mode,
                    reason: "Bảo vệ giao diện hệ thống/camera",
                    detail: "Bảo vệ còn lại=\(notificationDelayText(foregroundTakeoverRemaining))"
                )
            } else {
                scheduleBackgroundProbeNotification(mode: mode, reason: "Vào nền và lên lịch trước ngay")
                startBackgroundProbeRefreshTimer(mode: mode)
            }
        }
    }

    static func markAudioInterruptionBegan() {
        DispatchQueue.main.async {
            lastAudioInterruptionBeganAt = Date()
            audioInterruptionSessionActive = true
            KeepAliveLogger.appendIfDebug("Gián đoạn âm thanh bắt đầu, đã ghi lại để xét bảo vệ camera/giao diện hệ thống")
        }
    }

    static func markAudioInterruptionEnded() {
        DispatchQueue.main.async {
            lastAudioInterruptionBeganAt = nil
            audioInterruptionSessionActive = false
            guard foregroundTakeoverSessionActive || foregroundTakeoverSuppressedUntil != nil else {
                KeepAliveLogger.appendIfDebug("Gián đoạn âm thanh kết thúc, hiện không nằm trong phiên bảo vệ giao diện hệ thống/camera")
                return
            }

            markForegroundTakeoverEndedIfNeeded(reason: "Gián đoạn âm thanh kết thúc")
            guard isEnabled else { return }
            guard activeBackgroundProbeMode != nil else {
                KeepAliveLogger.appendIfDebug("Sau khi gián đoạn âm thanh kết thúc không có thăm dò nền đang hoạt động, bỏ qua khôi phục thông báo")
                return
            }
            guard isAppInBackground else {
                sanitizeScheduledNotifications(reason: "Sau khi gián đoạn âm thanh kết thúc đã quay lại nền trước")
                return
            }

            requestAuthorizationIfNeeded()
            restartActiveBackgroundProbeIfNeeded(reason: "Gián đoạn âm thanh kết thúc: nghi là đã thoát camera")
        }
    }

    static func markPiPStartedForBackgroundProbe() {
        DispatchQueue.main.async {
            lastPiPStartedAt = Date()
        }
    }

    // BETA2 ANCHOR: Máy trạng thái thông báo gián đoạn nền. Các nguồn chiếm dụng của hệ thống như Trung tâm điều khiển, Trung tâm thông báo, camera sẽ vào cửa sổ bảo vệ trước; thoát ra nền thông thường vẫn lên lịch trước bình thường.
    static func notifyDidEnterBackground(mode: String) {
        DispatchQueue.main.async {
            let overlayElapsed = foregroundSystemOverlayElapsed
            let resignElapsed = lastActiveResignElapsed
            let isOverlayLongEnoughToProtect = overlayElapsed.map { $0 >= systemOverlayProtectionThreshold } ?? false
            let shouldTreatAsFreshPiPStartBackground = isFreshPiPStartBackground && !isOverlayLongEnoughToProtect
            let shouldSkipOverlayProtectionAfterEndedTakeover = isForegroundTakeoverRecentlyEnded
            let shouldProtectCameraLikeTakeover = !shouldSkipOverlayProtectionAfterEndedTakeover
                && !shouldTreatAsFreshPiPStartBackground
                && wasRecentlyAudioInterrupted
                && (resignElapsed.map { $0 < cameraInterruptionWindow } ?? false)
            let shouldProtectSystemOverlay = !shouldSkipOverlayProtectionAfterEndedTakeover
                && !shouldTreatAsFreshPiPStartBackground
                && isOverlayLongEnoughToProtect
            foregroundSystemOverlayStartedAt = nil
            if isForegroundLockProbeSuppressed {
                foregroundTakeoverSuppressedUntil = nil
                foregroundTakeoverBounceSuppressedUntil = nil
                foregroundTakeoverRecentlyEndedUntil = nil
                foregroundTakeoverSessionActive = false
                audioInterruptionSessionActive = false
                activeBackgroundProbeMode = mode
                pauseBackgroundProbeForDeviceLockOnMain(reason: "Sau khi khóa màn hình ở nền trước rồi vào nền, không lên lịch thông báo trước khi mở khóa")
                return
            }
            foregroundLockStartedAt = nil
            if shouldProtectCameraLikeTakeover, !isDeviceLocked {
                enableForegroundTakeoverProtection(
                    reason: "Nghi là bảo vệ camera hoặc giao diện hệ thống",
                    detail: resignElapsed.map { String(format: "Sau gián đoạn âm thanh, nền trước không hoạt động %.1f giây rồi vào nền", $0) }
                )
            } else if shouldProtectSystemOverlay, !isDeviceLocked {
                enableForegroundTakeoverProtection(
                    reason: "Bảo vệ giao diện hệ thống/camera",
                    detail: overlayElapsed.map { String(format: "Nền trước không hoạt động %.1f giây rồi vào nền", $0) }
                )
            } else {
                foregroundTakeoverSuppressedUntil = nil
                foregroundTakeoverBounceSuppressedUntil = nil
                foregroundTakeoverRecentlyEndedUntil = nil
                foregroundTakeoverSessionActive = false
                audioInterruptionSessionActive = false
                if let overlayElapsed {
                    let endedText = shouldSkipOverlayProtectionAfterEndedTakeover ? ", vừa kết thúc bảo vệ giao diện hệ thống/camera, lần này khôi phục lên lịch trước bình thường" : ""
                    let pipStartText = shouldTreatAsFreshPiPStartBackground ? ", vừa khởi động cửa sổ nổi, lần này lên lịch như nền thông thường" : ""
                    KeepAliveLogger.appendIfDebug(String(format: "Thoát ra nền thông thường, chưa bật bảo vệ giao diện hệ thống/camera, nền trước không hoạt động %.1f giây %@%@", overlayElapsed, endedText, pipStartText))
                }
            }
            startBackgroundInterruptionProbe(mode: mode)
        }
    }

    static func cancelBackgroundInterruptionProbe(reason: String) {
        DispatchQueue.main.async {
            clearBackgroundProbeStateOnMain(
                reason: reason,
                preserveForegroundTakeoverBounce: reason == "Quay lại nền trước"
            )
        }
    }

    static func cancelAllTestingNotifications(reason: String) {
        DispatchQueue.main.async {
            stopBackgroundProbeRefreshTimer()
            activeBackgroundProbeMode = nil
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: [backgroundProbeIdentifier, pipStoppedIdentifier]
            )
            UNUserNotificationCenter.current().removeDeliveredNotifications(
                withIdentifiers: [backgroundProbeIdentifier, pipStoppedIdentifier]
            )
            clearPendingLocalNotificationNotice()
            AppDebugLogger.log("Đã hủy toàn bộ thông báo kiểm thử nhắc giữ nền, lý do=\(reason)")
        }
    }

    static func cancelBackgroundProbeNotifications(reason: String) {
        DispatchQueue.main.async {
            clearBackgroundProbeStateOnMain(reason: reason)
        }
    }

    static func cancelPiPStoppedNotifications(reason: String) {
        DispatchQueue.main.async {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [pipStoppedIdentifier])
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [pipStoppedIdentifier])
            clearPendingLocalNotificationNotice()
            KeepAliveLogger.markNotificationCancelled(reason: reason)
            AppDebugLogger.log("Đã hủy thông báo cửa sổ nổi dừng, lý do=\(reason)")
        }
    }

    private static func restartActiveBackgroundProbeIfNeeded(reason: String) {
        DispatchQueue.main.async {
            guard isEnabled, let mode = activeBackgroundProbeMode else { return }
            endExpiredForegroundTakeoverIfNeeded(reason: reason)
            guard isAppInBackground else {
                clearBackgroundProbeStateOnMain(reason: "\(reason): hiện không ở nền")
                return
            }
            guard !isForegroundLockProbeSuppressed else {
                pauseBackgroundProbeForDeviceLockOnMain(reason: "\(reason): bảo vệ khóa màn hình ở nền trước")
                return
            }
            guard !isDeviceLocked else {
                pauseBackgroundProbeForDeviceLockOnMain(reason: "\(reason): thiết bị bị khóa")
                return
            }
            guard !isForegroundSystemOverlayTransition else {
                pauseBackgroundProbeForDeviceLockOnMain(reason: "\(reason): giao diện hệ thống phủ lên nền trước")
                return
            }
            guard !isForegroundLockTransition else {
                clearBackgroundProbeStateOnMain(reason: "\(reason): khóa màn hình ở nền trước")
                return
            }
            if isForegroundTakeoverSuppressed {
                KeepAliveLogger.markNotificationPaused(reason: "\(reason): đang trong phiên bảo vệ giao diện hệ thống/camera, tạm không lên lịch trước thông báo hẹn giờ ở nền")
                AppDebugLogger.log("Tạm không lên lịch thông báo cục bộ gián đoạn nền, lý do=\(reason): bảo vệ giao diện hệ thống/camera, còn lại=\(notificationDelayText(foregroundTakeoverRemaining))")
            } else {
                scheduleBackgroundProbeNotification(mode: mode, reason: "\(reason): lên lịch trước")
            }
            startBackgroundProbeRefreshTimer(mode: mode)
        }
    }

    private static func scheduleBackgroundProbeNotification(
        mode: String,
        reason: String,
        delay: TimeInterval? = nil,
        allowDuringForegroundTakeover: Bool = false
    ) {
        let blocksForegroundTakeover = foregroundTakeoverSessionActive && !allowDuringForegroundTakeover
        guard isEnabled, isAppInBackground, !isDeviceLocked, !isForegroundLockProbeSuppressed, !isForegroundSystemOverlayTransition, !isForegroundLockTransition, !blocksForegroundTakeover else {
            clearBackgroundProbeNotifications()
            AppDebugLogger.log("Bỏ qua lên lịch thông báo cục bộ gián đoạn nền, lý do=\(reason), hiện không ở nền, thiết bị bị khóa, bảo vệ khóa màn hình ở nền trước, giao diện hệ thống phủ lên nền trước, khóa màn hình ở nền trước hoặc phiên bảo vệ giao diện hệ thống/camera")
            return
        }
        let frequency = probeFrequency
        let notificationDelay = max(1, delay ?? frequency.notificationDelay)
        let expectedAt = Date().addingTimeInterval(notificationDelay)
        let expectedText = notificationDateText(expectedAt)
        let notificationBody = L10n.text(
            """
            可能中断时间：\(expectedText)
            模式：\(mode)，频率：\(frequency.title)
            """,
            """
            Possible interruption: \(expectedText)
            Mode: \(mode), frequency: \(frequency.localizedTitle)
            """, vi: """
            Có thể bị gián đoạn lúc: \(expectedText)
            Chế độ: \(mode), tần suất: \(frequency.localizedTitle)
            """
        )
        let content = UNMutableNotificationContent()
        content.title = L10n.text("后台定时探测中断通知", "Background Probe Alert", vi: "Cảnh báo thăm dò nền")
        content.body = notificationBody
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: notificationDelay, repeats: false)
        let request = UNNotificationRequest(identifier: backgroundProbeIdentifier, content: content, trigger: trigger)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [backgroundProbeIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [backgroundProbeIdentifier])
        center.add(request) { error in
            if let error {
                AppDebugLogger.log("Lên lịch thông báo cục bộ gián đoạn nền thất bại: \(error.localizedDescription)")
            } else {
                KeepAliveLogger.markNotificationScheduled(reason: reason, fireAt: expectedAt)
                AppDebugLogger.log("Đã lên lịch thông báo cục bộ gián đoạn nền, lý do=\(reason), tần suất=\(frequency.title), khoảng kiểm tra=\(frequency.intervalText), độ trễ thông báo=\(notificationDelayText(notificationDelay)), dự kiến=\(notificationDateText(expectedAt)), chế độ=\(mode)")
            }
        }
    }

    private static func startBackgroundProbeSafetyWindow(mode: String, reason: String, detail: String? = nil) {
        stopBackgroundProbeRefreshTimer()
        let fallbackDelay: TimeInterval
        if foregroundTakeoverSessionActive, !audioInterruptionSessionActive {
            fallbackDelay = backgroundProbeSafetyWindow + probeFrequency.notificationDelay
        } else {
            fallbackDelay = max(backgroundProbeSafetyWindow + probeFrequency.notificationDelay, foregroundTakeoverRemaining + probeFrequency.notificationDelay)
        }
        if foregroundTakeoverSessionActive {
            clearBackgroundProbeNotifications()
            AppDebugLogger.log("Trong phiên bảo vệ giao diện hệ thống/camera của thông báo gián đoạn nền, không lên lịch thông báo dự phòng, độ trễ dự phòng ban đầu=\(notificationDelayText(fallbackDelay)), chế độ=\(mode)")
        } else {
            scheduleBackgroundProbeNotification(
                mode: mode,
                reason: "\(reason): lên lịch trước dự phòng cho cửa sổ an toàn",
                delay: fallbackDelay
            )
        }
        KeepAliveLogger.markNotificationPaused(reason: "\(reason): vào \(Int(backgroundProbeSafetyWindow)) giây cửa sổ an toàn, tạm chưa khởi động làm mới chính thức")
        let detailText = detail.map { ", \($0)" } ?? ""
        let fallbackText = foregroundTakeoverSessionActive
            ? "Không lên lịch thông báo dự phòng"
            : "Độ trễ dự phòng=\(notificationDelayText(fallbackDelay))"
        AppDebugLogger.log("Thông báo gián đoạn nền vào cửa sổ an toàn, lý do=\(reason)\(detailText), cửa sổ an toàn=\(Int(backgroundProbeSafetyWindow)) giây, \(fallbackText), chế độ=\(mode)")

        scheduleBackgroundProbeSafetyWindowResume(mode: mode, reason: reason, delay: backgroundProbeSafetyWindow)
    }

    private static func scheduleBackgroundProbeSafetyWindowResume(mode: String, reason: String, delay: TimeInterval) {
        let workItem = DispatchWorkItem {
            pendingBackgroundProbeStartWorkItem = nil
            guard isEnabled else { return }
            endExpiredForegroundTakeoverIfNeeded(reason: "\(reason): cửa sổ an toàn kết thúc")
            guard isAppInBackground else {
                clearBackgroundProbeStateOnMain(reason: "\(reason): khi cửa sổ an toàn kết thúc đã quay lại nền trước")
                return
            }
            guard !isForegroundLockProbeSuppressed else {
                pauseBackgroundProbeForDeviceLockOnMain(reason: "\(reason): khi cửa sổ an toàn kết thúc vẫn đang được bảo vệ khóa màn hình ở nền trước")
                return
            }
            guard !isDeviceLocked else {
                pauseBackgroundProbeForDeviceLockOnMain(reason: "\(reason): khi cửa sổ an toàn kết thúc thiết bị bị khóa")
                return
            }
            guard !isForegroundSystemOverlayTransition else {
                pauseBackgroundProbeForDeviceLockOnMain(reason: "\(reason): khi cửa sổ an toàn kết thúc vẫn còn giao diện hệ thống phủ lên nền trước")
                return
            }
            guard !isForegroundLockTransition else {
                clearBackgroundProbeStateOnMain(reason: "\(reason): khi cửa sổ an toàn kết thúc vẫn đang khóa màn hình ở nền trước")
                return
            }

            if foregroundTakeoverSessionActive {
                KeepAliveLogger.markNotificationPaused(reason: "\(reason): bảo vệ giao diện hệ thống/camera vẫn còn, tiếp tục tạm dừng kiểm tra chính thức")
                clearBackgroundProbeNotifications()
                AppDebugLogger.log("Cửa sổ an toàn của thông báo gián đoạn nền đã kết thúc nhưng bảo vệ giao diện hệ thống/camera vẫn còn, tiếp tục xóa thông báo đã lên lịch trước, còn lại=\(notificationDelayText(foregroundTakeoverRemaining))")
                scheduleBackgroundProbeSafetyWindowResume(
                    mode: mode,
                    reason: reason,
                    delay: backgroundProbeSafetyWindow
                )
                return
            }

            activeBackgroundProbeMode = mode
            let decision = KeepAliveLogger.backgroundInterruptionProbeDecision(staleAfter: heartbeatStaleGrace)
            guard !decision.shouldNotify else {
                AppDebugLogger.log("Sau cửa sổ an toàn của thông báo gián đoạn nền, tạm chưa làm mới, kiểm tra trước=\(decision.reason)")
                return
            }
            scheduleBackgroundProbeNotification(mode: mode, reason: "\(reason): lên lịch trước chính thức sau cửa sổ an toàn, \(decision.reason)")
            startBackgroundProbeRefreshTimer(mode: mode)
        }
        pendingBackgroundProbeStartWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private static func startBackgroundProbeRefreshTimer(mode: String) {
        stopBackgroundProbeRefreshTimer()
        let frequency = probeFrequency
        let generation = activateBackgroundProbeGeneration()
        let timer = DispatchSource.makeTimerSource(queue: backgroundProbeQueue)
        timer.schedule(
            deadline: .now() + frequency.refreshInterval,
            repeating: frequency.refreshInterval,
            leeway: .seconds(1)
        )
        timer.setEventHandler {
            refreshBackgroundProbeFromTimer(mode: mode, generation: generation)
        }
        backgroundProbeRefreshTimer = timer
        timer.resume()
        AppDebugLogger.log("Đã khởi động bộ hẹn giờ làm mới thông báo gián đoạn nền, tần suất=\(frequency.title), khoảng làm mới=\(frequency.refreshIntervalText), cách thức=hàng đợi nền")
    }

    private static func refreshBackgroundProbeFromTimer(mode: String, generation: Int) {
        guard isBackgroundProbeGenerationActive(generation) else { return }
        guard isEnabled else {
            DispatchQueue.main.async {
                clearBackgroundProbeStateOnMain(reason: "Thông báo đã tắt khi làm mới")
            }
            return
        }
        KeepAliveLogger.heartbeat()
        guard !foregroundTakeoverSessionActive else {
            clearBackgroundProbeNotifications()
            AppDebugLogger.log("Tạm không làm mới thông báo cục bộ gián đoạn nền, lý do=đang trong phiên bảo vệ giao diện hệ thống/camera")
            return
        }
        guard !isForegroundTakeoverSuppressed else {
            AppDebugLogger.log("Tạm không làm mới thông báo cục bộ gián đoạn nền, lý do=bảo vệ khi chuyển từ nền trước sang ứng dụng bên ngoài, còn lại=\(notificationDelayText(foregroundTakeoverRemaining))")
            return
        }
        let decision = KeepAliveLogger.backgroundInterruptionProbeDecision(staleAfter: heartbeatStaleGrace)
        guard isBackgroundProbeGenerationActive(generation) else { return }
        guard !decision.shouldNotify else {
            AppDebugLogger.log("Không làm mới thông báo cục bộ gián đoạn nền, kiểm tra trước=\(decision.reason)")
            return
        }
        scheduleBackgroundProbeNotificationFromTimer(
            mode: mode,
            reason: "Nhịp giữ nền ở nền làm mới bình thường, \(decision.reason)",
            generation: generation
        )
    }

    private static func scheduleBackgroundProbeNotificationFromTimer(mode: String, reason: String, generation: Int) {
        guard isEnabled, isBackgroundProbeGenerationActive(generation) else {
            return
        }
        let frequency = probeFrequency
        let notificationDelay = frequency.notificationDelay
        let expectedAt = Date().addingTimeInterval(notificationDelay)
        let expectedText = notificationDateText(expectedAt)
        let notificationBody = L10n.text(
            """
            可能中断时间：\(expectedText)
            模式：\(mode)，频率：\(frequency.title)
            """,
            """
            Possible interruption: \(expectedText)
            Mode: \(mode), frequency: \(frequency.localizedTitle)
            """, vi: """
            Có thể bị gián đoạn lúc: \(expectedText)
            Chế độ: \(mode), tần suất: \(frequency.localizedTitle)
            """
        )
        let content = UNMutableNotificationContent()
        content.title = L10n.text("后台定时探测中断通知", "Background Probe Alert", vi: "Cảnh báo thăm dò nền")
        content.body = notificationBody
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: notificationDelay, repeats: false)
        let request = UNNotificationRequest(identifier: backgroundProbeIdentifier, content: content, trigger: trigger)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [backgroundProbeIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [backgroundProbeIdentifier])
        center.add(request) { error in
            guard isBackgroundProbeGenerationActive(generation) else { return }
            if let error {
                AppDebugLogger.log("Làm mới thông báo cục bộ gián đoạn nền thất bại: \(error.localizedDescription)")
            } else {
                KeepAliveLogger.markNotificationScheduled(reason: reason, fireAt: expectedAt)
                AppDebugLogger.log("Đã làm mới thông báo cục bộ gián đoạn nền, lý do=\(reason), tần suất=\(frequency.title), khoảng kiểm tra=\(frequency.intervalText), độ trễ thông báo=\(notificationDelayText(notificationDelay)), dự kiến=\(notificationDateText(expectedAt)), chế độ=\(mode)")
            }
        }
    }

    private static func sanitizeScheduledNotifications(reason: String) {
        DispatchQueue.main.async {
            guard isEnabled else {
                cancelBackgroundProbeNotifications(reason: "\(reason): thông báo gián đoạn nền đã tắt")
                return
            }
            endExpiredForegroundTakeoverIfNeeded(reason: reason)
            guard isAppInBackground else {
                clearBackgroundProbeStateOnMain(
                    reason: "\(reason): dọn phần còn sót ở nền trước",
                    preserveForegroundTakeoverBounce: reason.hasPrefix("Quay lại nền trước")
                )
                requestAuthorizationIfNeeded()
                return
            }
            guard !isForegroundLockProbeSuppressed else {
                pauseBackgroundProbeForDeviceLockOnMain(reason: "\(reason): bảo vệ khóa màn hình ở nền trước")
                requestAuthorizationIfNeeded()
                return
            }
            guard !isDeviceLocked else {
                pauseBackgroundProbeForDeviceLockOnMain(reason: "\(reason): thiết bị bị khóa")
                requestAuthorizationIfNeeded()
                return
            }
            guard !isForegroundSystemOverlayTransition else {
                pauseBackgroundProbeForDeviceLockOnMain(reason: "\(reason): giao diện hệ thống phủ lên nền trước")
                requestAuthorizationIfNeeded()
                return
            }
            guard !isForegroundLockTransition else {
                clearBackgroundProbeStateOnMain(reason: "\(reason): khóa màn hình ở nền trước")
                requestAuthorizationIfNeeded()
                return
            }
            if foregroundTakeoverSessionActive {
                requestAuthorizationIfNeeded()
                clearBackgroundProbeNotifications()
                KeepAliveLogger.markNotificationPaused(reason: "\(reason): đang trong phiên bảo vệ giao diện hệ thống/camera, tạm không lên lịch trước thông báo hẹn giờ ở nền")
                AppDebugLogger.log("Tạm không lên lịch thông báo cục bộ gián đoạn nền, lý do=\(reason): đang trong phiên bảo vệ giao diện hệ thống/camera")
                return
            }
            if isForegroundTakeoverSuppressed {
                requestAuthorizationIfNeeded()
                if let mode = activeBackgroundProbeMode {
                    KeepAliveLogger.markNotificationPaused(reason: "\(reason): đang trong phiên bảo vệ giao diện hệ thống/camera, tạm không lên lịch trước thông báo hẹn giờ ở nền")
                    AppDebugLogger.log("Tạm không lên lịch thông báo cục bộ gián đoạn nền, lý do=\(reason): bảo vệ giao diện hệ thống/camera, còn lại=\(notificationDelayText(foregroundTakeoverRemaining))")
                    startBackgroundProbeRefreshTimer(mode: mode)
                }
                return
            }
            requestAuthorizationIfNeeded()
            if let mode = activeBackgroundProbeMode {
                scheduleBackgroundProbeNotification(mode: mode, reason: "\(reason): lên lịch trước")
                startBackgroundProbeRefreshTimer(mode: mode)
            }
        }
    }

    private static var isAppInBackground: Bool {
        UIApplication.shared.applicationState == .background
    }

    private static var isDeviceLocked: Bool {
        !UIApplication.shared.isProtectedDataAvailable
    }

    private static var isForegroundLockTransition: Bool {
        guard let foregroundLockStartedAt else { return false }
        return Date().timeIntervalSince(foregroundLockStartedAt) < 30
    }

    private static var isForegroundLockProbeSuppressed: Bool {
        suppressBackgroundProbeUntilUnlock
    }

    private static var isForegroundSystemOverlayTransition: Bool {
        guard let foregroundSystemOverlayStartedAt else { return false }
        return Date().timeIntervalSince(foregroundSystemOverlayStartedAt) < 120
    }

    private static var foregroundSystemOverlayElapsed: TimeInterval? {
        guard let foregroundSystemOverlayStartedAt else { return nil }
        return Date().timeIntervalSince(foregroundSystemOverlayStartedAt)
    }

    private static var lastActiveResignElapsed: TimeInterval? {
        guard let lastActiveResignAt else { return nil }
        return Date().timeIntervalSince(lastActiveResignAt)
    }

    private static var isFreshPiPStartBackground: Bool {
        guard let lastPiPStartedAt else { return false }
        return Date().timeIntervalSince(lastPiPStartedAt) < pipStartBackgroundGrace
    }

    private static var wasRecentlyAudioInterrupted: Bool {
        guard let lastAudioInterruptionBeganAt else { return false }
        return Date().timeIntervalSince(lastAudioInterruptionBeganAt) < cameraInterruptionWindow
    }

    private static var isForegroundTakeoverSuppressed: Bool {
        guard let foregroundTakeoverSuppressedUntil else { return false }
        if Date() < foregroundTakeoverSuppressedUntil {
            return true
        }
        self.foregroundTakeoverSuppressedUntil = nil
        return false
    }

    private static var isForegroundTakeoverBounceSuppressed: Bool {
        guard let foregroundTakeoverBounceSuppressedUntil else { return false }
        if Date() < foregroundTakeoverBounceSuppressedUntil {
            return true
        }
        self.foregroundTakeoverBounceSuppressedUntil = nil
        return false
    }

    private static var isForegroundTakeoverRecentlyEnded: Bool {
        guard let foregroundTakeoverRecentlyEndedUntil else { return false }
        if Date() < foregroundTakeoverRecentlyEndedUntil {
            return true
        }
        self.foregroundTakeoverRecentlyEndedUntil = nil
        return false
    }

    private static var foregroundTakeoverRemaining: TimeInterval {
        guard let foregroundTakeoverSuppressedUntil else { return 0 }
        return max(0, foregroundTakeoverSuppressedUntil.timeIntervalSinceNow)
    }

    private static func enableForegroundTakeoverProtection(reason: String, detail: String? = nil) {
        let until = Date().addingTimeInterval(foregroundTakeoverGrace)
        if let currentUntil = foregroundTakeoverSuppressedUntil, currentUntil > until {
            return
        }
        foregroundTakeoverSuppressedUntil = until
        foregroundTakeoverBounceSuppressedUntil = nil
        foregroundTakeoverSessionActive = true
        let detailText = detail.map { ", \($0)" } ?? ""
        KeepAliveLogger.appendIfDebug("\(reason) Đã bật \(detailText), \(Int(foregroundTakeoverGrace)) giây trì hoãn thông báo hẹn giờ ở nền")
    }

    private static func rememberForegroundTakeoverBounceIfNeeded(reason: String) {
        guard isForegroundTakeoverSuppressed else { return }
        let until = Date().addingTimeInterval(foregroundTakeoverBounceWindow)
        if let currentUntil = foregroundTakeoverBounceSuppressedUntil, currentUntil > until {
            return
        }
        foregroundTakeoverBounceSuppressedUntil = until
        KeepAliveLogger.appendIfDebug("\(reason): bảo vệ giao diện hệ thống/camera vào bộ đệm ngắn khi quay lại nền trước, \(Int(foregroundTakeoverBounceWindow)) giây nếu vào nền lần nữa vẫn trì hoãn thông báo")
    }

    private static func markForegroundTakeoverEndedIfNeeded(reason: String) {
        guard foregroundTakeoverSessionActive || isForegroundTakeoverSuppressed else { return }
        pendingBackgroundProbeStartWorkItem?.cancel()
        pendingBackgroundProbeStartWorkItem = nil
        foregroundTakeoverSuppressedUntil = nil
        foregroundTakeoverBounceSuppressedUntil = nil
        foregroundTakeoverSessionActive = false
        audioInterruptionSessionActive = false
        foregroundTakeoverRecentlyEndedUntil = Date().addingTimeInterval(foregroundTakeoverEndRecoveryWindow)
        clearBackgroundProbeNotifications()
        KeepAliveLogger.appendIfDebug("\(reason): bảo vệ giao diện hệ thống/camera đã kết thúc, \(Int(foregroundTakeoverEndRecoveryWindow)) giây nếu vào nền lần nữa sẽ khôi phục lên lịch trước bình thường")
    }

    private static func endExpiredForegroundTakeoverIfNeeded(reason: String) {
        guard foregroundTakeoverSessionActive else { return }
        guard !audioInterruptionSessionActive else { return }
        guard !isForegroundTakeoverSuppressed else { return }
        foregroundTakeoverSessionActive = false
        foregroundTakeoverBounceSuppressedUntil = nil
        foregroundTakeoverRecentlyEndedUntil = Date().addingTimeInterval(foregroundTakeoverEndRecoveryWindow)
        clearBackgroundProbeNotifications()
        KeepAliveLogger.appendIfDebug("\(reason): bảo vệ giao diện hệ thống/Trung tâm thông báo hết hạn tự nhiên, khôi phục khả năng lên lịch trước gián đoạn nền")
    }

    private static func installLockStateObserverIfNeeded() {
        guard !didInstallLockStateObserver else { return }
        didInstallLockStateObserver = true
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            lastActiveResignAt = Date()
            if UIApplication.shared.applicationState == .active {
                foregroundSystemOverlayStartedAt = Date()
                KeepAliveLogger.appendIfDebug("App Không hoạt động tạm thời, foregroundSystemOverlayStartedAt=\(KeepAliveLogger.nowText)")
                pauseBackgroundProbeForDeviceLockOnMain(reason: "Nền trước không hoạt động tạm thời, có thể là Trung tâm điều khiển hoặc Trung tâm thông báo")
            }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            markForegroundTakeoverEndedIfNeeded(reason: "App Quay lại nền trước và hoạt động")
            foregroundSystemOverlayStartedAt = nil
            if suppressBackgroundProbeUntilUnlock {
                KeepAliveLogger.appendIfDebug("App Quay lại nền trước và hoạt động, nhưng vẫn đang được bảo vệ khóa màn hình ở nền trước, chờ thiết bị mở khóa")
                clearBackgroundProbeStateOnMain(reason: "Quay lại nền trước và hoạt động: bảo vệ khóa màn hình ở nền trước")
                return
            }
            foregroundLockStartedAt = nil
            KeepAliveLogger.appendIfDebug("App Quay lại nền trước và hoạt động, đã dọn dấu hiệu lớp phủ hệ thống")
            sanitizeScheduledNotifications(reason: "Quay lại nền trước và hoạt động")
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataWillBecomeUnavailableNotification,
            object: nil,
            queue: .main
        ) { _ in
            KeepAliveLogger.appendIfDebug("Thiết bị sắp khóa, foregroundLockStartedAt=\(KeepAliveLogger.nowText), trạng thái App=\(UIApplication.shared.applicationState.rawValue)")
            if didRecentlyLeaveForeground || UIApplication.shared.applicationState != .background {
                foregroundLockStartedAt = Date()
                foregroundTakeoverSuppressedUntil = nil
                foregroundTakeoverBounceSuppressedUntil = nil
                foregroundTakeoverSessionActive = false
                audioInterruptionSessionActive = false
                suppressBackgroundProbeUntilUnlock = true
                clearBackgroundProbeStateOnMain(reason: "Khóa màn hình ở nền trước")
            } else {
                pauseBackgroundProbeForDeviceLockOnMain(reason: "Thiết bị bị khóa")
            }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil,
            queue: .main
        ) { _ in
            foregroundLockStartedAt = nil
            suppressBackgroundProbeUntilUnlock = false
            clearBackgroundProbeNotifications()
            KeepAliveLogger.markNotificationCancelled(reason: "Thiết bị mở khóa: chờ trạng thái nền trước/nền sau ổn định")
            KeepAliveLogger.appendIfDebug("Thiết bị mở khóa, đã dọn dấu khóa màn hình ở nền trước, trì hoãn xác nhận trạng thái nền rồi mới khôi phục thông báo")
            if foregroundTakeoverSessionActive {
                KeepAliveLogger.markNotificationPaused(reason: "Sau khi mở khóa vẫn đang trong phiên bảo vệ giao diện hệ thống/camera")
                AppDebugLogger.log("Sau khi mở khóa vẫn đang trong phiên bảo vệ giao diện hệ thống/camera, tiếp tục không lên lịch thông báo gián đoạn nền")
                return
            }
            foregroundTakeoverSuppressedUntil = nil
            foregroundTakeoverBounceSuppressedUntil = nil
            pendingUnlockResumeWorkItem?.cancel()
            let workItem = DispatchWorkItem {
                guard isEnabled else { return }
                guard let mode = activeBackgroundProbeMode else {
                    KeepAliveLogger.appendIfDebug("Sau khi mở khóa không có thăm dò nền đang hoạt động, bỏ qua khôi phục thông báo")
                    return
                }
                guard isAppInBackground else {
                    clearBackgroundProbeStateOnMain(reason: "Sau khi mở khóa đã quay lại nền trước, bỏ qua khôi phục thông báo")
                    return
                }
                guard !isDeviceLocked else {
                    pauseBackgroundProbeForDeviceLockOnMain(reason: "Sau khi mở khóa vẫn đang bị khóa")
                    return
                }
                guard !isForegroundSystemOverlayTransition else {
                    pauseBackgroundProbeForDeviceLockOnMain(reason: "Sau khi mở khóa vẫn còn giao diện hệ thống phủ lên")
                    return
                }
                requestAuthorizationIfNeeded()
                scheduleBackgroundProbeNotification(mode: mode, reason: "Sau khi mở khóa vẫn ở nền: lên lịch trước")
                startBackgroundProbeRefreshTimer(mode: mode)
            }
            pendingUnlockResumeWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
        }
    }

    private static func clearBackgroundProbeStateOnMain(reason: String, preserveForegroundTakeoverBounce: Bool = false) {
        if preserveForegroundTakeoverBounce {
            markForegroundTakeoverEndedIfNeeded(reason: reason)
        }
        pendingBackgroundProbeStartWorkItem?.cancel()
        pendingBackgroundProbeStartWorkItem = nil
        pendingUnlockResumeWorkItem?.cancel()
        pendingUnlockResumeWorkItem = nil
        stopBackgroundProbeRefreshTimer()
        activeBackgroundProbeMode = nil
        foregroundTakeoverSuppressedUntil = nil
        foregroundTakeoverSessionActive = false
        audioInterruptionSessionActive = false
        if !preserveForegroundTakeoverBounce {
            foregroundTakeoverBounceSuppressedUntil = nil
            foregroundTakeoverRecentlyEndedUntil = nil
        }
        clearBackgroundProbeNotifications()
        KeepAliveLogger.markNotificationCancelled(reason: reason)
        AppDebugLogger.log("Đã hủy kiểm thử thông báo cục bộ gián đoạn nền, lý do=\(reason)")
    }

    private static func pauseBackgroundProbeForDeviceLockOnMain(reason: String) {
        pendingBackgroundProbeStartWorkItem?.cancel()
        pendingBackgroundProbeStartWorkItem = nil
        pendingUnlockResumeWorkItem?.cancel()
        pendingUnlockResumeWorkItem = nil
        stopBackgroundProbeRefreshTimer()
        if !foregroundTakeoverSessionActive {
            foregroundTakeoverSuppressedUntil = nil
            foregroundTakeoverBounceSuppressedUntil = nil
        }
        clearBackgroundProbeNotifications()
        KeepAliveLogger.markNotificationPaused(reason: reason)
        AppDebugLogger.log("Đã tạm dừng thông báo cục bộ gián đoạn nền, lý do=\(reason), nếu sau khi mở khóa vẫn ở nền thì sẽ tiếp tục kiểm tra")
    }

    private static var didRecentlyLeaveForeground: Bool {
        guard let lastActiveResignAt else { return false }
        return Date().timeIntervalSince(lastActiveResignAt) < 5
    }

    private static func stopBackgroundProbeRefreshTimer() {
        deactivateBackgroundProbeGeneration()
        backgroundProbeRefreshTimer?.cancel()
        backgroundProbeRefreshTimer = nil
    }

    private static func activateBackgroundProbeGeneration() -> Int {
        backgroundProbeGenerationLock.lock()
        backgroundProbeGeneration += 1
        let generation = backgroundProbeGeneration
        backgroundProbeGenerationLock.unlock()
        return generation
    }

    private static func deactivateBackgroundProbeGeneration() {
        backgroundProbeGenerationLock.lock()
        backgroundProbeGeneration += 1
        backgroundProbeGenerationLock.unlock()
    }

    private static func isBackgroundProbeGenerationActive(_ generation: Int) -> Bool {
        backgroundProbeGenerationLock.lock()
        let isActive = backgroundProbeGeneration == generation
        backgroundProbeGenerationLock.unlock()
        return isActive
    }

    private static func clearBackgroundProbeNotifications() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [backgroundProbeIdentifier])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [backgroundProbeIdentifier])
    }

    static func schedulePiPStoppedNotification(mode: String, reason: String) {
        guard isPiPStoppedNotificationEnabled else { return }
        DispatchQueue.main.async {
            requestAuthorizationIfNeeded()
            let stoppedAt = Date()
            let stoppedText = notificationDateText(stoppedAt)
            let notificationBody = L10n.text(
                """
                中断时间：\(stoppedText)
                原因：可能被其他画中画应用挤掉或被系统停止
                模式：\(mode)
                """,
                """
                Stopped at: \(stoppedText)
                Reason: another PiP app or the system may have stopped it
                Mode: \(mode)
                """, vi: """
                Dừng lúc: \(stoppedText)
                Lý do: ứng dụng PiP khác hoặc hệ thống có thể đã dừng nó
                Chế độ: \(mode)
                """
            )
            let content = UNMutableNotificationContent()
            content.title = L10n.text("全局高刷悬浮窗已停止", "Global Refresh PiP Stopped", vi: "Global Refresh PiP đã dừng")
            content.body = notificationBody
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: immediateDelay, repeats: false)
            let request = UNNotificationRequest(identifier: pipStoppedIdentifier, content: content, trigger: trigger)
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: [pipStoppedIdentifier])
            center.add(request) { error in
                if let error {
                    AppDebugLogger.log("Lên lịch thông báo cục bộ dừng cửa sổ nổi thất bại: \(error.localizedDescription)")
                } else {
                    storePendingLocalNotificationNotice(
                        identifier: pipStoppedIdentifier,
                        interruptedAt: stoppedAt,
                        reason: "Có thể bị ứng dụng Hình trong hình khác đẩy đi hoặc bị hệ thống dừng",
                        fireAt: stoppedAt.addingTimeInterval(immediateDelay)
                    )
                    KeepAliveLogger.markNotificationScheduled(reason: "Cửa sổ nổi dừng: \(reason), có thể bị gián đoạn=\(stoppedText)", fireAt: stoppedAt.addingTimeInterval(immediateDelay))
                    AppDebugLogger.log("Đã lên lịch thông báo cục bộ dừng cửa sổ nổi, lý do=\(reason), có thể bị gián đoạn=\(stoppedText)")
                }
            }
        }
    }

    static func shouldSuppressPiPStoppedNotification(reason: String, allowWhileLocked: Bool = false) -> Bool {
        guard isPiPStoppedNotificationEnabled else { return false }
        let protectedByLock = isDeviceLocked || isForegroundLockProbeSuppressed || isForegroundLockTransition
        guard protectedByLock else { return false }
        if allowWhileLocked {
            KeepAliveLogger.markNotificationLockProtectionBypassed(reason: "Xác nhận PiP dừng bất thường, vẫn gửi thông báo trong lúc khóa màn hình: \(reason)")
            AppDebugLogger.logCritical("BETA5 Thông báo PiP dừng bất thường không còn bị bảo vệ khóa màn hình chặn, lý do=\(reason)")
            return false
        }
        let protectionReason = "Bảo vệ khóa màn hình"
        KeepAliveLogger.markNotificationPaused(reason: "Thông báo cửa sổ nổi dừng bị \(protectionReason) chặn: \(reason)")
        AppDebugLogger.log("Đã chặn thông báo cửa sổ nổi dừng, bảo vệ=\(protectionReason), lý do=\(reason)")
        return true
    }

    private static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                AppDebugLogger.log("Quyền thông báo cục bộ chưa được quyết định, chờ lối vào cấp quyền ở nền trước kích hoạt")
            case .denied:
                AppDebugLogger.log("Quyền thông báo cục bộ đã bị từ chối, cảnh báo gián đoạn nền không thể hiện lên")
            default:
                break
            }
        }
    }

    private enum NotificationAuthorizationPurpose {
        case backgroundProbe
        case pipStopped
    }

    private static func requestSystemNotificationAuthorization(
        from controller: UIViewController?,
        purpose: NotificationAuthorizationPurpose,
        shouldOpenSettingsOnDenied: Bool,
        completion: @escaping (Bool) -> Void
    ) {
        let performRequest = {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error {
                    AppDebugLogger.log("Yêu cầu quyền thông báo cục bộ thất bại: \(error.localizedDescription)")
                } else {
                    AppDebugLogger.log("Kết quả yêu cầu quyền thông báo cục bộ: \(granted ? "Cho phép" : "Từ chối")")
                }
                DispatchQueue.main.async {
                    if !granted, shouldOpenSettingsOnDenied {
                        openSystemSettings(from: controller, purpose: purpose, reason: "Lần cấp quyền đầu tiên không được cho phép")
                    }
                    completion(granted)
                }
            }
        }

        DispatchQueue.main.async {
            guard let controller, controller.presentedViewController == nil else {
                performRequest()
                return
            }

            let message: String
            switch purpose {
            case .backgroundProbe:
                message = L10n.text(
                    "通知权限用于在后台保活异常中断时提醒你。",
                    "Notifications are used to alert you when background keep-alive may stop unexpectedly.", vi: "Thông báo dùng để cảnh báo bạn khi tính năng giữ nền có thể bị dừng bất ngờ."
                )
            case .pipStopped:
                message = L10n.text(
                    "通知权限用于在悬浮窗被其他画中画应用挤掉或被系统停止时通知。",
                    "Notifications are used to alert you when another Picture in Picture app or the system stops the floating window.", vi: "Thông báo dùng để cảnh báo bạn khi ứng dụng Hình trong hình khác hoặc hệ thống dừng cửa sổ nổi."
                )
            }

            let alert = UIAlertController(
                title: L10n.text("开启通知提醒", "Enable Notifications", vi: "Bật thông báo"),
                message: message,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: L10n.text("暂不开启", "Not Now", vi: "Để sau"), style: .cancel) { _ in
                completion(false)
            })
            alert.addAction(UIAlertAction(title: L10n.text("继续授权", "Continue", vi: "Tiếp tục"), style: .default) { _ in
                performRequest()
            })
            controller.present(alert, animated: true)
        }
    }

    private static func ensureAuthorizationForHomeToggle(
        from controller: UIViewController?,
        purpose: NotificationAuthorizationPurpose = .backgroundProbe,
        shouldOpenSettingsOnDenied: Bool = true,
        completion: @escaping (Bool) -> Void
    ) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                requestSystemNotificationAuthorization(
                    from: controller,
                    purpose: purpose,
                    shouldOpenSettingsOnDenied: shouldOpenSettingsOnDenied,
                    completion: completion
                )
            case .denied:
                AppDebugLogger.log("Quyền thông báo cục bộ chưa bật, chuyển đến Cài đặt hệ thống")
                DispatchQueue.main.async {
                    if shouldOpenSettingsOnDenied {
                        openSystemSettings(from: controller, purpose: purpose, reason: "Quyền bị tắt")
                    }
                    completion(false)
                }
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async {
                    completion(true)
                }
            @unknown default:
                DispatchQueue.main.async {
                    completion(false)
                }
            }
        }
    }

	    private static func openSystemSettings(from controller: UIViewController?, purpose: NotificationAuthorizationPurpose, reason: String) {
	        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
	        let message: String
	        switch purpose {
	        case .backgroundProbe:
	            message = L10n.text(
	                "后台中断通知需要开启系统通知权限，请在设置里允许通知后再打开。",
	                "Background alerts need notification permission. Please allow notifications in Settings, then turn this on again.", vi: "Cảnh báo nền cần quyền thông báo. Hãy cho phép thông báo trong Cài đặt, rồi bật lại tính năng này."
	            )
	        case .pipStopped:
	            message = L10n.text(
	                "悬浮窗被挤通知需要开启系统通知权限，请在设置里允许通知后再打开。",
	                "PiP conflict alerts need notification permission. Please allow notifications in Settings, then turn this on again.", vi: "Cảnh báo xung đột PiP cần quyền thông báo. Hãy cho phép thông báo trong Cài đặt, rồi bật lại tính năng này."
	            )
	        }
        if let controller, controller.presentedViewController == nil {
            let alert = UIAlertController(title: L10n.text("通知权限未开启", "Notifications Disabled", vi: "Thông báo đang tắt"), message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: L10n.cancel, style: .cancel))
            alert.addAction(UIAlertAction(title: L10n.text("去设置", "Open Settings", vi: "Mở Cài đặt"), style: .default) { _ in
                UIApplication.shared.open(url)
            })
            controller.present(alert, animated: true)
        } else {
            UIApplication.shared.open(url)
        }
        AppDebugLogger.log("Mở Cài đặt hệ thống để yêu cầu quyền thông báo, lý do=\(reason)")
    }

    private static let notificationFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "M/d HH:mm:ss"
        return formatter
    }()

    private static func notificationDateText(_ date: Date) -> String {
        notificationFormatter.string(from: date)
    }

    private static func notificationDelayText(_ delay: TimeInterval) -> String {
        let totalSeconds = max(1, Int(delay.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0, seconds > 0 {
            return "\(minutes) phút \(seconds) giây"
        }
        if minutes > 0 {
            return "\(minutes) phút"
        }
        return "\(seconds) giây"
    }

    private static func storePendingLocalNotificationNotice(identifier: String, interruptedAt: Date, reason: String, fireAt: Date) {
        let sessionStart = UserDefaults.standard.double(forKey: "pip.keepAlive.sessionStart")
        let interruptedAtTimestamp = interruptedAt.timeIntervalSince1970
        let payload: [String: Any] = [
            "identifier": identifier,
            "interruptedAt": interruptedAtTimestamp,
            "interruptedAtText": notificationDateText(interruptedAt),
            "runtimeText": runtimeText(start: sessionStart, end: interruptedAtTimestamp),
            "reason": reason,
            "fireAt": fireAt.timeIntervalSince1970
        ]
        UserDefaults.standard.set(payload, forKey: pendingLocalNotificationNoticeKey)
    }

    private static func runtimeText(start: TimeInterval, end: TimeInterval) -> String {
        guard start > 0, end > 0, end >= start else { return "00:00:00" }
        let totalSeconds = max(0, Int((end - start).rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private static func clearPendingLocalNotificationNotice() {
        UserDefaults.standard.removeObject(forKey: pendingLocalNotificationNoticeKey)
    }

    private static func pendingLocalNotificationNoticeIfReady() -> KeepAliveLocalNotificationNotice? {
        guard let payload = UserDefaults.standard.dictionary(forKey: pendingLocalNotificationNoticeKey),
              let interruptedAtText = payload["interruptedAtText"] as? String,
              let runtimeText = payload["runtimeText"] as? String,
              let reason = payload["reason"] as? String,
              let fireAt = payload["fireAt"] as? TimeInterval else {
            return nil
        }
        if reason == "Thăm dò định kỳ bị gián đoạn" {
            clearPendingLocalNotificationNotice()
            return nil
        }
        guard Date().timeIntervalSince1970 >= fireAt else { return nil }
        return KeepAliveLocalNotificationNotice(interruptedAtText: interruptedAtText, runtimeText: runtimeText, reason: reason)
    }

}

private extension KeepAliveNotificationProbeFrequency {
    var refreshIntervalText: String {
        switch self {
        case .low: return "29 phút"
        case .high: return "55 giây"
        case .ultra: return "20 giây"
        }
    }
}
