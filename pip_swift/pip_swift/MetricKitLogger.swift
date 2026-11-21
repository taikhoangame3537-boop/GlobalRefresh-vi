//
//  MetricKitLogger.swift
//  pip_swift
//

import UIKit
import Darwin
import MetricKit

final class MetricKitLogger: NSObject, MXMetricManagerSubscriber {
    static let shared = MetricKitLogger()

    private let storageKey = "pip.metricKit.payloads"
    private let storageFingerprintsKey = "pip.metricKit.payloadFingerprints"
    private let historyStatusKey = "pip.metricKit.beta5HistoryStatus"
    private let modernStatusKey = "pip.metricKit.iOS27Status"
    private let modernEventsKey = "pip.metricKit.iOS27Events"
    private let modernEventFingerprintsKey = "pip.metricKit.iOS27EventFingerprints"
    private let maximumPayloads = 5
    private let maximumPayloadBytes = 256 * 1024
    private let maximumModernEvents = 10
    private let storageLock = NSLock()
    private var isStarted = false
    private var hasImportedPastPayloads = false
    private var modernBridge: AnyObject?

    private override init() {
        super.init()
    }

    func start() {
        guard !isStarted else { return }
        guard AppDebugLogger.isDebugModeEnabled else { return }
        isStarted = true
        MXMetricManager.shared.add(self)
        importPastPayloads()
        #if IOS27_METRICKIT
        if #available(iOS 27.0, *) {
            let bridge = IOS27MetricKitBridge(
                onMetricReport: { [weak self] report in
                    self?.handleModernMetricReport(report)
                },
                onDiagnosticReport: { [weak self] report in
                    self?.handleModernDiagnosticReport(report)
                }
            )
            bridge.start()
            modernBridge = bridge
            AppDebugLogger.log("MetricKit Đã khởi động đăng ký: kênh tương thích cũ + kênh mới của iOS27")
        } else {
            AppDebugLogger.log("MetricKit Đã khởi động đăng ký: kênh tương thích cũ")
        }
        #else
        AppDebugLogger.log("MetricKit Đã khởi động đăng ký: kênh tương thích cũ")
        #endif
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        MXMetricManager.shared.remove(self)
        #if IOS27_METRICKIT
        if #available(iOS 27.0, *) {
            (modernBridge as? IOS27MetricKitBridge)?.stop()
        }
        #endif
        modernBridge = nil
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        guard AppDebugLogger.isDebugModeEnabled else { return }
        appendPayloads(payloads.map { $0.jsonRepresentation() }, source: "Chỉ số callback mới của hệ thống")
        let summary = historicalExitSummary(from: payloads)
        UserDefaults.standard.set(
            "Callback mới của hệ thống: chỉ số=\(payloads.count), \(summary)",
            forKey: historyStatusKey
        )
        AppDebugLogger.logCritical("MetricKit Nhận chỉ số: \(payloads.count) mục; \(summary)")
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        guard AppDebugLogger.isDebugModeEnabled else { return }
        appendPayloads(payloads.map { $0.jsonRepresentation() }, source: "Chẩn đoán callback mới của hệ thống")
        AppDebugLogger.logCritical("MetricKit Nhận gói chẩn đoán: \(payloads.count) mục")
    }

    func copyToPasteboard() {
        UIPasteboard.general.string = exportText()
    }

    func resetLogs() {
        storageLock.lock()
        defer { storageLock.unlock() }
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: storageKey)
        defaults.removeObject(forKey: storageFingerprintsKey)
        defaults.removeObject(forKey: historyStatusKey)
        defaults.removeObject(forKey: modernStatusKey)
        defaults.removeObject(forKey: modernEventsKey)
        defaults.removeObject(forKey: modernEventFingerprintsKey)
        hasImportedPastPayloads = false
    }

    func exportText() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let device = UIDevice.current
        storageLock.lock()
        let payloads = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
        let modernStatus = UserDefaults.standard.string(forKey: modernStatusKey)
        let modernEvents = UserDefaults.standard.stringArray(forKey: modernEventsKey) ?? []
        storageLock.unlock()

        return """
        Nhật ký chỉ số hệ thống Global Refresh (MetricKit)
        App Phiên bản: \(version) (\(build))
        Bundle ID: \(bundleID)
        Phiên bản hệ thống: iOS \(device.systemVersion)
        Mẫu thiết bị: \(deviceModelIdentifier)
        Thời điểm tạo: \(beijingFormatter.string(from: Date())) giờ Bắc Kinh
        Chế độ giữ nền hiện tại: \(KeepAliveModeText.current)

        Nguồn chỉ số: Apple MetricKit, do hệ thống trên máy tổng hợp ở nền, không dùng mạng.
        Giải thích dữ liệu: MetricKit thường cần khoảng 24 giờ mới gọi lại chỉ số hệ thống hằng ngày; có thể trống nếu mới cài hoặc dùng quá ngắn.

        Đọc chỉ số thoát lịch sử của kênh tương thích cũ:
        \(UserDefaults.standard.string(forKey: historyStatusKey) ?? "Chưa đọc; hãy xác nhận đã bật chế độ gỡ lỗi và vào lại ứng dụng.")

        iOS27 Chỉ số chấm dứt nền mới:
        \(modernStatus ?? "Hệ thống hiện tại không cung cấp chỉ số mới của iOS27, hoặc chưa nhận được báo cáo hằng ngày.")

        iOS27 Sự kiện gần đây của kênh mới:
        \(modernEvents.joined(separator: "\n\n").isEmpty
            ? "Chưa có"
            : modernEvents.joined(separator: "\n\n"))

        Chỉ số hệ thống gần đây:
        \(payloads.isEmpty ? "Chưa có chỉ số hệ thống, hãy dùng một thời gian rồi sao chép vào ngày hôm sau." : payloads.joined(separator: "\n\n----- MetricKit Payload -----\n\n"))
        """
    }

    private func importPastPayloads() {
        guard !hasImportedPastPayloads else { return }
        hasImportedPastPayloads = true

        let metricPayloads = MXMetricManager.shared.pastPayloads
        let diagnosticPayloads = MXMetricManager.shared.pastDiagnosticPayloads
        appendPayloads(
            metricPayloads.map { $0.jsonRepresentation() },
            source: "Chỉ số lịch sử đọc khi khởi động"
        )
        appendPayloads(
            diagnosticPayloads.map { $0.jsonRepresentation() },
            source: "Chẩn đoán lịch sử đọc khi khởi động"
        )

        let exitSummary = historicalExitSummary(from: metricPayloads)
        let status = "Chỉ số lịch sử=\(metricPayloads.count) mục, chẩn đoán lịch sử=\(diagnosticPayloads.count) mục; \(exitSummary)"
        UserDefaults.standard.set(status, forKey: historyStatusKey)
        AppDebugLogger.logCritical("MetricKit Đã đọc xong lịch sử: \(status)")
    }

    private func appendPayloads(_ payloadData: [Data], source: String) {
        guard !payloadData.isEmpty else { return }
        storageLock.lock()
        defer { storageLock.unlock() }
        let defaults = UserDefaults.standard
        var payloads = defaults.stringArray(forKey: storageKey) ?? []
        var fingerprints = defaults.stringArray(forKey: storageFingerprintsKey) ?? []
        let knownFingerprints = Set(fingerprints)
        let newEntries = payloadData.compactMap { data -> (fingerprint: String, text: String)? in
            let fingerprint = payloadFingerprint(for: data)
            guard !knownFingerprints.contains(fingerprint) else { return nil }
            let limitedData = data.count > maximumPayloadBytes
                ? data.prefix(maximumPayloadBytes)
                : data[...]
            let text = String(decoding: limitedData, as: UTF8.self)
            let summary = exitMetricSummary(from: data)
            let rawText = data.count > maximumPayloadBytes
                ? text + "\n[MetricKit Dữ liệu quá dài, đã bị cắt bớt]"
                : text
            let formattedText = summary.isEmpty
                ? "Nguồn: \(source)\n\(rawText)"
                : "Nguồn: \(source)\nApp Tóm tắt chỉ số liên quan đến thoát: \n\(summary)\n\n Dữ liệu MetricKit gốc: \n\(rawText)"
            return (fingerprint, formattedText)
        }
        payloads.append(contentsOf: newEntries.map { $0.text })
        fingerprints.append(contentsOf: newEntries.map { $0.fingerprint })
        if payloads.count > maximumPayloads {
            payloads.removeFirst(payloads.count - maximumPayloads)
        }
        if fingerprints.count > maximumPayloads {
            fingerprints.removeFirst(fingerprints.count - maximumPayloads)
        }
        defaults.set(payloads, forKey: storageKey)
        defaults.set(fingerprints, forKey: storageFingerprintsKey)
    }

    #if IOS27_METRICKIT
    @available(iOS 27.0, *)
    private func handleModernMetricReport(_ report: MetricReport) {
        guard AppDebugLogger.isDebugModeEnabled else { return }
        let data = try? JSONEncoder().encode(report)
        let summary = modernMetricSummary(report)
        let range = formatDateRange(report.timeRange)
        let environment = report.environment.map {
            "Hệ thống=\($0.osVersion),Thiết bị=\($0.deviceType),Phiên bản=\($0.latestApplicationVersion)(\($0.applicationBuildVersion)),Chế độ pin yếu=\($0.lowPowerModeEnabled)"
        } ?? "Thông tin môi trường không khả dụng"
        let event = "[iOS27 MetricManager Chỉ số] Thời gian=\(range); \(environment); \(summary)"
        appendModernEvent(event, fingerprintData: data)
        storageLock.lock()
        UserDefaults.standard.set(
            "Thời gian chỉ số gần nhất=\(range); \(summary)",
            forKey: modernStatusKey
        )
        storageLock.unlock()
        if let data {
            appendPayloads([data], source: "iOS27 MetricManager Chỉ số")
        }
        AppDebugLogger.logCritical("iOS27 MetricManager Nhận chỉ số: \(summary)")
    }

    @available(iOS 27.0, *)
    private func handleModernDiagnosticReport(_ report: DiagnosticReport) {
        guard AppDebugLogger.isDebugModeEnabled else { return }
        let data = try? JSONEncoder().encode(report)
        let kind: String
        switch report.result {
        case .crash: kind = "Sập"
        case .hang: kind = "Giật"
        case .cpuException: kind = "CPU Bất thường"
        case .diskWriteException: kind = "Bất thường ghi đĩa"
        case .appLaunch: kind = "Chẩn đoán khởi động"
        case .memoryException: kind = "Bất thường bộ nhớ"
        @unknown default: kind = "Chẩn đoán không rõ"
        }
        let range = formatDateRange(report.timeRange)
        let environment = "Hệ thống=\(report.environment.osVersion),Thiết bị=\(report.environment.deviceType),Phiên bản=\(report.environment.applicationVersion)(\(report.environment.applicationBuildVersion)),Chế độ pin yếu=\(report.environment.lowPowerModeEnabled)"
        let event = "[iOS27 MetricManager Chẩn đoán] Loại=\(kind); thời gian=\(range); \(environment)"
        appendModernEvent(event, fingerprintData: data)
        if let data {
            appendPayloads([data], source: "iOS27 MetricManager Chẩn đoán: \(kind)")
        }
        AppDebugLogger.logCritical("iOS27 MetricManager Nhận chẩn đoán: loại=\(kind), thời gian=\(range)")
    }

    @available(iOS 27.0, *)
    private func modernMetricSummary(_ report: MetricReport) -> String {
        var counts: [String: Int] = [:]

        func add(_ name: String, _ value: Int) {
            guard value > 0 else { return }
            counts[name, default: 0] += value
        }

        let values = report.stateEntries.flatMap { $0.values } + report.intervalEntries.flatMap { $0.values }
        for value in values {
            switch value {
            case .backgroundTermination(let metric):
                add("Chấm dứt nền bình thường", metric.normalTerminationCount)
                add("Giới hạn bộ nhớ ở nền", metric.memoryLimitTerminationCount)
                add("CPU nền quá cao", metric.highCPUTerminationCount)
                add("Áp lực hệ thống ở nền", metric.systemPressureTerminationCount)
                add("Truy cập bộ nhớ bất hợp pháp ở nền", metric.badAccessTerminationCount)
                add("Chấm dứt nền bất thường", metric.abnormalTerminationCount)
                add("Lệnh bất hợp pháp ở nền", metric.illegalInstructionTerminationCount)
                add("Nền Watchdog", metric.watchdogTerminationCount)
                add("Khóa tệp ở nền", metric.fileLockTerminationCount)
                add("Tác vụ nền hết thời gian", metric.taskTimeoutTerminationCount)
            case .foregroundTermination(let metric):
                add("Chấm dứt nền trước bình thường", metric.normalTerminationCount)
                add("Giới hạn bộ nhớ ở nền trước", metric.memoryLimitTerminationCount)
                add("Truy cập bộ nhớ bất hợp pháp ở nền trước", metric.badAccessTerminationCount)
                add("Chấm dứt nền trước bất thường", metric.abnormalTerminationCount)
                add("Lệnh bất hợp pháp ở nền trước", metric.illegalInstructionTerminationCount)
                add("Nền trước Watchdog", metric.watchdogTerminationCount)
            default:
                continue
            }
        }

        guard !counts.isEmpty else {
            return "Không phát hiện bộ đếm chấm dứt ở nền/nền trước"
        }
        return counts.keys.sorted().map { "\($0)=\(counts[$0] ?? 0)" }.joined(separator: ",")
    }
    #endif

    private func appendModernEvent(_ event: String, fingerprintData: Data?) {
        storageLock.lock()
        defer { storageLock.unlock() }
        let defaults = UserDefaults.standard
        var events = defaults.stringArray(forKey: modernEventsKey) ?? []
        var fingerprints = defaults.stringArray(forKey: modernEventFingerprintsKey) ?? []
        let fingerprint = fingerprintData.map(payloadFingerprint) ?? payloadFingerprint(for: Data(event.utf8))
        guard !fingerprints.contains(fingerprint) else { return }
        events.append(event)
        fingerprints.append(fingerprint)
        if events.count > maximumModernEvents {
            events.removeFirst(events.count - maximumModernEvents)
        }
        if fingerprints.count > maximumModernEvents {
            fingerprints.removeFirst(fingerprints.count - maximumModernEvents)
        }
        defaults.set(events, forKey: modernEventsKey)
        defaults.set(fingerprints, forKey: modernEventFingerprintsKey)
    }

    private func formatDateRange(_ range: DateInterval) -> String {
        "\(beijingFormatter.string(from: range.start))~\(beijingFormatter.string(from: range.end))"
    }

    private func historicalExitSummary(from payloads: [MXMetricPayload]) -> String {
        var backgroundNormal = 0
        var backgroundMemoryLimit = 0
        var backgroundCPULimit = 0
        var backgroundMemoryPressure = 0
        var backgroundBadAccess = 0
        var backgroundAbnormal = 0
        var backgroundIllegalInstruction = 0
        var backgroundWatchdog = 0
        var backgroundLockedFile = 0
        var backgroundTaskTimeout = 0
        var foregroundMemoryLimit = 0
        var foregroundBadAccess = 0
        var foregroundAbnormal = 0
        var foregroundIllegalInstruction = 0
        var foregroundWatchdog = 0
        var exitMetricCount = 0

        for payload in payloads {
            guard let metric = payload.applicationExitMetrics else { continue }
            exitMetricCount += 1
            let background = metric.backgroundExitData
            backgroundNormal += Int(background.cumulativeNormalAppExitCount)
            backgroundMemoryLimit += Int(background.cumulativeMemoryResourceLimitExitCount)
            backgroundCPULimit += Int(background.cumulativeCPUResourceLimitExitCount)
            backgroundMemoryPressure += Int(background.cumulativeMemoryPressureExitCount)
            backgroundBadAccess += Int(background.cumulativeBadAccessExitCount)
            backgroundAbnormal += Int(background.cumulativeAbnormalExitCount)
            backgroundIllegalInstruction += Int(background.cumulativeIllegalInstructionExitCount)
            backgroundWatchdog += Int(background.cumulativeAppWatchdogExitCount)
            backgroundLockedFile += Int(background.cumulativeSuspendedWithLockedFileExitCount)
            backgroundTaskTimeout += Int(background.cumulativeBackgroundTaskAssertionTimeoutExitCount)

            let foreground = metric.foregroundExitData
            foregroundMemoryLimit += Int(foreground.cumulativeMemoryResourceLimitExitCount)
            foregroundBadAccess += Int(foreground.cumulativeBadAccessExitCount)
            foregroundAbnormal += Int(foreground.cumulativeAbnormalExitCount)
            foregroundIllegalInstruction += Int(foreground.cumulativeIllegalInstructionExitCount)
            foregroundWatchdog += Int(foreground.cumulativeAppWatchdogExitCount)
        }

        guard exitMetricCount > 0 else {
            return "Không phát hiện chỉ số thoát của App"
        }

        let values: [(String, Int)] = [
            ("Thoát nền bình thường", backgroundNormal),
            ("Mức trần bộ nhớ ở nền", backgroundMemoryLimit),
            ("Mức trần CPU ở nền", backgroundCPULimit),
            ("Áp lực bộ nhớ hệ thống ở nền", backgroundMemoryPressure),
            ("Truy cập bộ nhớ bất hợp pháp ở nền", backgroundBadAccess),
            ("Thoát nền bất thường", backgroundAbnormal),
            ("Lệnh bất hợp pháp ở nền", backgroundIllegalInstruction),
            ("Nền Watchdog", backgroundWatchdog),
            ("Giữ tệp khóa khi bị treo ở nền", backgroundLockedFile),
            ("Tác vụ nền hết thời gian", backgroundTaskTimeout),
            ("Mức trần bộ nhớ ở nền trước", foregroundMemoryLimit),
            ("Truy cập bộ nhớ bất hợp pháp ở nền trước", foregroundBadAccess),
            ("Thoát nền trước bất thường", foregroundAbnormal),
            ("Lệnh bất hợp pháp ở nền trước", foregroundIllegalInstruction),
            ("Nền trước Watchdog", foregroundWatchdog)
        ]
        let nonZeroValues = values.filter { $0.1 > 0 }
        guard !nonZeroValues.isEmpty else {
            return "Gói chỉ số thoát=\(exitMetricCount) mục, chưa ghi nhận các bộ đếm thoát nêu trên"
        }
        let details = nonZeroValues.map { "\($0.0)=\($0.1)" }.joined(separator: ",")
        return "Gói chỉ số thoát=\(exitMetricCount) mục; \(details)"
    }

    private func payloadFingerprint(for data: Data) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private func exitMetricSummary(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return "" }
        var lines: [String] = []

        func collect(_ value: Any, path: [String]) {
            if let dictionary = value as? [String: Any] {
                for key in dictionary.keys.sorted() {
                    if let child = dictionary[key] {
                        collect(child, path: path + [key])
                    }
                }
                return
            }
            if let array = value as? [Any] {
                for (index, child) in array.enumerated() {
                    collect(child, path: path + ["[\(index)]"])
                }
                return
            }

            let normalizedPath = path.joined(separator: ".").lowercased()
            guard normalizedPath.contains("exit")
                    || normalizedPath.contains("termination")
                    || normalizedPath.contains("jetsam")
                    || normalizedPath.contains("watchdog")
            else {
                return
            }
            guard let number = value as? NSNumber else { return }
            lines.append("\(path.joined(separator: ".")) = \(number)")
        }

        collect(object, path: [])
        return lines.prefix(120).joined(separator: "\n")
    }

    private var beijingFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }

    private var deviceModelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            identifier.append(String(UnicodeScalar(UInt8(value))))
        }
    }
}

#if IOS27_METRICKIT
@available(iOS 27.0, *)
private final class IOS27MetricKitBridge {
    private let manager = MetricManager()
    private let onMetricReport: (MetricReport) -> Void
    private let onDiagnosticReport: (DiagnosticReport) -> Void
    private var metricTask: Task<Void, Never>?
    private var diagnosticTask: Task<Void, Never>?

    init(
        onMetricReport: @escaping (MetricReport) -> Void,
        onDiagnosticReport: @escaping (DiagnosticReport) -> Void
    ) {
        self.onMetricReport = onMetricReport
        self.onDiagnosticReport = onDiagnosticReport
    }

    func start() {
        guard metricTask == nil, diagnosticTask == nil else { return }
        let manager = self.manager
        metricTask = Task { [weak self] in
            for await report in manager.metricReports {
                guard !Task.isCancelled else { break }
                self?.onMetricReport(report)
            }
        }
        diagnosticTask = Task { [weak self] in
            for await report in manager.diagnosticReports {
                guard !Task.isCancelled else { break }
                self?.onDiagnosticReport(report)
            }
        }
    }

    func stop() {
        metricTask?.cancel()
        diagnosticTask?.cancel()
        metricTask = nil
        diagnosticTask = nil
    }
}
#endif
