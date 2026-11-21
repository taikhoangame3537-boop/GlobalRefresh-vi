//
//  PowerUsageLogger.swift
//  pip_swift
//

import UIKit
import Darwin

enum PowerUsageLogger {
    private static let maximumStatisticsAge: TimeInterval = 24 * 60 * 60
    private static let launchDateKey = "pip.power.launchDate"
    private static let foregroundStartKey = "pip.power.foregroundStart"
    private static let foregroundTotalKey = "pip.power.foregroundTotal"
    private static let backgroundStartKey = "pip.power.backgroundStart"
    private static let backgroundTotalKey = "pip.power.backgroundTotal"
    private static let pipStartKey = "pip.power.pipStart"
    private static let pipTotalKey = "pip.power.pipTotal"
    private static let keepAliveStartKey = "pip.power.keepAliveStart"
    private static let keepAliveTotalKey = "pip.power.keepAliveTotal"
    private static let pipStartCountKey = "pip.power.pipStartCount"
    private static let pipStopCountKey = "pip.power.pipStopCount"
    private static let keepAliveStartCountKey = "pip.power.keepAliveStartCount"
    private static let keepAliveStopCountKey = "pip.power.keepAliveStopCount"
    private static let backgroundEntryCountKey = "pip.power.backgroundEntryCount"
    private static let foregroundEntryCountKey = "pip.power.foregroundEntryCount"

    static func markLaunch() {
        guard shouldTrackState else { return }
        UIDevice.current.isBatteryMonitoringEnabled = true
        let defaults = UserDefaults.standard
        if defaults.object(forKey: launchDateKey) == nil {
            defaults.set(Date().timeIntervalSince1970, forKey: launchDateKey)
        }
        rotateStatisticsIfNeeded()
        markForegroundStart()
    }

    static func markForegroundStart() {
        guard shouldTrackState else { return }
        stopTimer(startKey: backgroundStartKey, totalKey: backgroundTotalKey)
        startTimerIfNeeded(foregroundStartKey)
        increment(foregroundEntryCountKey)
    }

    static func markBackgroundStart() {
        guard shouldTrackState else { return }
        stopTimer(startKey: foregroundStartKey, totalKey: foregroundTotalKey)
        startTimerIfNeeded(backgroundStartKey)
        increment(backgroundEntryCountKey)
    }

    static func markPiPStart() {
        guard shouldTrackState else { return }
        if startTimerIfNeeded(pipStartKey) {
            increment(pipStartCountKey)
        }
    }

    static func markPiPStop() {
        guard shouldTrackState else { return }
        if stopTimer(startKey: pipStartKey, totalKey: pipTotalKey) {
            increment(pipStopCountKey)
        }
    }

    static func markKeepAliveStart() {
        guard shouldTrackState else { return }
        if startTimerIfNeeded(keepAliveStartKey) {
            increment(keepAliveStartCountKey)
        }
    }

    static func markKeepAliveStop() {
        guard shouldTrackState else { return }
        if stopTimer(startKey: keepAliveStartKey, totalKey: keepAliveTotalKey) {
            increment(keepAliveStopCountKey)
        }
    }

    static func exportText() -> String {
        UIDevice.current.isBatteryMonitoringEnabled = true
        if !shouldTrackState {
            resetStatistics()
        }
        rotateStatisticsIfNeeded()
        let defaults = UserDefaults.standard
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let device = UIDevice.current
        let launchTimestamp = defaults.double(forKey: launchDateKey)
        let launchText = launchTimestamp > 0 ? beijingFormatter.string(from: Date(timeIntervalSince1970: launchTimestamp)) : "unknown"

        return """
        Nhật ký hỗ trợ theo dõi hao pin Global Refresh
        App Phiên bản: \(version) (\(build))
        Bundle ID: \(bundleID)
        Phiên bản hệ thống: iOS \(device.systemVersion)
        Mẫu thiết bị: \(deviceModelIdentifier)
        Thời điểm tạo: \(beijingFormatter.string(from: Date())) giờ Bắc Kinh
        Chế độ giữ nền hiện tại: \(KeepAliveModeText.current)
        Thời điểm bắt đầu vòng thống kê này: \(launchText) giờ Bắc Kinh

        Pin hiện tại: \(batteryLevelText)
        Trạng thái sạc: \(batteryStateText)

        Tích lũy ở nền trước: \(durationText(total(for: foregroundTotalKey, startKey: foregroundStartKey)))
        Tích lũy ở nền: \(durationText(total(for: backgroundTotalKey, startKey: backgroundStartKey)))
        Tích lũy thời gian bật cửa sổ nổi: \(durationText(total(for: pipTotalKey, startKey: pipStartKey)))
        Tích lũy âm thanh giữ nền ở nền: \(durationText(total(for: keepAliveTotalKey, startKey: keepAliveStartKey)))

        Số lần vào nền trước: \(defaults.integer(forKey: foregroundEntryCountKey))
        Số lần vào nền: \(defaults.integer(forKey: backgroundEntryCountKey))
        Số lần bật cửa sổ nổi: \(defaults.integer(forKey: pipStartCountKey))
        Số lần tắt cửa sổ nổi: \(defaults.integer(forKey: pipStopCountKey))
        Số lần khởi động âm thanh giữ nền: \(defaults.integer(forKey: keepAliveStartCountKey))
        Số lần dừng âm thanh giữ nền: \(defaults.integer(forKey: keepAliveStopCountKey))

        Giải thích chế độ: Giữ nền bằng PiP-tiết kiệm điện không khởi động âm thanh im lặng; Tăng cường âm thanh khi khóa màn hình chỉ khởi động âm thanh im lặng sau khi hệ thống báo thiết bị bị khóa; Giữ nền bằng âm thanh sẽ liên tục cộng dồn thời lượng âm thanh giữ nền.
        Lưu ý: iOS không cho phép ứng dụng thông thường đọc phần trăm mức dùng pin của hệ thống; nhật ký này dùng để hỗ trợ đánh giá thời gian chạy của cửa sổ nổi, giữ nền và phiên âm thanh; chu kỳ thống kê giữ tối đa 24 giờ, quá hạn sẽ tự thống kê lại.
        """
    }

    static func copyToPasteboard() {
        UIPasteboard.general.string = exportText()
    }

    static func resetStatistics() {
        let defaults = UserDefaults.standard
        for key in [launchDateKey] + totalKeys + countKeys + startKeys {
            defaults.removeObject(forKey: key)
        }
    }

    static func startFreshStatistics() {
        resetStatistics()
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: launchDateKey)
    }

    @discardableResult
    private static func startTimerIfNeeded(_ key: String) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.double(forKey: key) <= 0 else { return false }
        defaults.set(Date().timeIntervalSince1970, forKey: key)
        return true
    }

    @discardableResult
    private static func stopTimer(startKey: String, totalKey: String) -> Bool {
        let defaults = UserDefaults.standard
        let start = defaults.double(forKey: startKey)
        guard start > 0 else { return false }
        let elapsed = max(0, Date().timeIntervalSince1970 - start)
        defaults.set(defaults.double(forKey: totalKey) + elapsed, forKey: totalKey)
        defaults.removeObject(forKey: startKey)
        return true
    }

    private static func total(for totalKey: String, startKey: String) -> TimeInterval {
        let defaults = UserDefaults.standard
        let total = defaults.double(forKey: totalKey)
        let start = defaults.double(forKey: startKey)
        guard start > 0 else { return total }
        return total + max(0, Date().timeIntervalSince1970 - start)
    }

    private static func increment(_ key: String) {
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
    }

    private static func rotateStatisticsIfNeeded() {
        let defaults = UserDefaults.standard
        let now = Date().timeIntervalSince1970
        let launchTimestamp = defaults.double(forKey: launchDateKey)
        guard launchTimestamp > 0 else {
            defaults.set(now, forKey: launchDateKey)
            return
        }
        guard now - launchTimestamp > maximumStatisticsAge else { return }

        let isForegroundActive = defaults.double(forKey: foregroundStartKey) > 0
        let isBackgroundActive = defaults.double(forKey: backgroundStartKey) > 0
        let isPiPActive = defaults.double(forKey: pipStartKey) > 0
        let isKeepAliveAudioActive = defaults.double(forKey: keepAliveStartKey) > 0

        for key in totalKeys + countKeys + startKeys {
            defaults.removeObject(forKey: key)
        }

        defaults.set(now, forKey: launchDateKey)
        if isForegroundActive {
            defaults.set(now, forKey: foregroundStartKey)
            defaults.set(1, forKey: foregroundEntryCountKey)
        }
        if isBackgroundActive {
            defaults.set(now, forKey: backgroundStartKey)
            defaults.set(1, forKey: backgroundEntryCountKey)
        }
        if isPiPActive {
            defaults.set(now, forKey: pipStartKey)
            defaults.set(1, forKey: pipStartCountKey)
        }
        if isKeepAliveAudioActive {
            defaults.set(now, forKey: keepAliveStartKey)
            defaults.set(1, forKey: keepAliveStartCountKey)
        }
    }

    private static var totalKeys: [String] {
        [foregroundTotalKey, backgroundTotalKey, pipTotalKey, keepAliveTotalKey]
    }

    private static var countKeys: [String] {
        [
            pipStartCountKey,
            pipStopCountKey,
            keepAliveStartCountKey,
            keepAliveStopCountKey,
            backgroundEntryCountKey,
            foregroundEntryCountKey
        ]
    }

    private static var startKeys: [String] {
        [foregroundStartKey, backgroundStartKey, pipStartKey, keepAliveStartKey]
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60
        return "\(hours) giờ \(minutes) phút \(remainingSeconds) giây"
    }

    private static var batteryLevelText: String {
        let level = UIDevice.current.batteryLevel
        guard level >= 0 else { return "Không rõ" }
        return "\(Int((level * 100).rounded()))%"
    }

    private static var batteryStateText: String {
        switch UIDevice.current.batteryState {
        case .unknown:
            return "Không rõ"
        case .unplugged:
            return "Không sạc"
        case .charging:
            return "Đang sạc"
        case .full:
            return "Đã sạc đầy"
        @unknown default:
            return "Không rõ"
        }
    }

    private static var shouldTrackState: Bool {
        AppDebugLogger.isDebugModeEnabled || KeepAliveNotificationTester.isAnyNotificationEnabled
    }

    private static let beijingFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
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
