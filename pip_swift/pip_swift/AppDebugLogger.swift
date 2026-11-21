//
//  AppDebugLogger.swift
//  pip_swift
//

import UIKit
import AVFoundation
import Darwin
import OSLog

enum AppDebugLogger {
    private static let storageKey = "pip.debug.recentLogs"
    private static let debugModeKey = "pip.debug.modeEnabled"
    private static let maximumEntries = 600
    private static let maximumEntryBytes = 8 * 1024
    private static let maximumBufferBytes = 1_500_000
    private static let logger = Logger(subsystem: "com.yoroin.globalrefresh", category: "diagnostics")
    private static let logQueueKey = DispatchSpecificKey<Void>()
    private static let logQueue: DispatchQueue = {
        let queue = DispatchQueue(label: "com.yoroin.globalrefresh.appDebugLog", qos: .utility)
        queue.setSpecific(key: logQueueKey, value: ())
        return queue
    }()
    private static let registrationLock = NSLock()
    private static var didRegisterBackgroundFlush = false
    private static var didTrimOnLaunch = false
    // Bộ đệm vòng trong bộ nhớ: nhật ký chỉ ghi vào bộ nhớ, không ghi xuống đĩa theo thời gian thực UserDefaults
    private static var memoryBuffer: [String] = []
    private static var memoryBufferBytes = 0

    static var isDebugModeEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: debugModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: debugModeKey) }
    }

    // Khi khởi động, dọn dữ liệu tồn đọng cũ và nạp nhật ký lịch sử vào bộ nhớ
    static func trimOnLaunch() {
        registrationLock.lock()
        guard !didTrimOnLaunch else {
            registrationLock.unlock()
            return
        }
        didTrimOnLaunch = true
        registrationLock.unlock()
        logQueue.async {
            guard isDebugModeEnabled else {
                memoryBuffer.removeAll(keepingCapacity: false)
                memoryBufferBytes = 0
                UserDefaults.standard.removeObject(forKey: storageKey)
                return
            }
            let stored = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
            memoryBuffer = stored.suffix(maximumEntries).map(limitEntry)
            memoryBufferBytes = memoryBuffer.reduce(into: 0) { $0 += $1.utf8.count }
            trimMemoryBuffer()
            if stored != memoryBuffer {
                UserDefaults.standard.set(memoryBuffer, forKey: storageKey)
            }
        }
    }

    // Đăng ký ghi xuống đĩa khi vào nền/bị chấm dứt, chỉ cần gọi một lần trong viewDidLoad
    static func registerBackgroundFlush() {
        registrationLock.lock()
        guard !didRegisterBackgroundFlush else {
            registrationLock.unlock()
            return
        }
        didRegisterBackgroundFlush = true
        registrationLock.unlock()
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { _ in
            flush()
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: nil) { _ in
            flush()
        }
    }

    // Chỉ ghi vào bộ nhớ, không chạm vào UserDefaults
    static func log(_ message: String, file: StaticString = #fileID, line: UInt = #line) {
        append(message, persistImmediately: false, file: file, line: line)
    }

    // Vòng đời, cảnh báo bộ nhớ và chuyển đổi giữ nền dùng lối vào này để tránh trạng thái cuối cùng chỉ nằm trong bộ nhớ khi hệ thống chấm dứt trực tiếp.
    static func logCritical(_ message: String, file: StaticString = #fileID, line: UInt = #line) {
        append(message, persistImmediately: true, file: file, line: line)
    }

    private static func append(
        _ message: String,
        persistImmediately: Bool,
        file: StaticString,
        line: UInt
    ) {
        guard isDebugModeEnabled else { return }
        let limitedMessage = limitEntry(message)
        DiagnosticsRuntimeState.updateLastEvent(limitedMessage)
        logger.info("\(limitedMessage, privacy: .public)")
        let device = UIDevice.current
        let entry = limitEntry([
            beijingFormatter.string(from: Date()),
            "iOS \(device.systemVersion)",
            deviceModelIdentifier,
            "\(file):\(line)",
            limitedMessage
        ].joined(separator: " | "))

        logQueue.async {
            memoryBuffer.append(entry)
            memoryBufferBytes += entry.utf8.count
            trimMemoryBuffer()
            if persistImmediately {
                UserDefaults.standard.set(memoryBuffer, forKey: storageKey)
                UserDefaults.standard.synchronize()
            }
        }
    }

    // Chỉ ghi xuống đĩa khi sao chép nhật ký/vào nền/bị chấm dứt
    static func flush() {
        logQueue.async {
            guard isDebugModeEnabled else {
                memoryBuffer.removeAll(keepingCapacity: false)
                memoryBufferBytes = 0
                UserDefaults.standard.removeObject(forKey: storageKey)
                return
            }
            guard !memoryBuffer.isEmpty else { return }
            UserDefaults.standard.set(memoryBuffer, forKey: storageKey)
        }
    }

    static func exportText() -> String {
        var entries: [String] = []
        logQueue.sync { entries = memoryBuffer }
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let device = UIDevice.current
        let diagnosticsSection = DebugDiagnosticsMonitor.isEnabled
            ? """
        Ghi nhật ký luồng và hiệu năng: bật
        Hiện trường hiện tại: \(DiagnosticsRuntimeState.snapshotText())
        Hiệu năng thời gian thực: \(PerformanceDiagnosticsLogger.currentSnapshotText())
        \(ProcessTerminationDiagnostics.exportText())
        """
            : ""

        return """
        Nhật ký gỡ lỗi Global Refresh
        App Phiên bản: \(version) (\(build))
        Bundle ID: \(bundleID)
        Phiên bản hệ thống: iOS \(device.systemVersion)
        Mẫu thiết bị: \(deviceModelIdentifier)
        Thời điểm tạo: \(beijingFormatter.string(from: Date())) giờ Bắc Kinh
        Chế độ giữ nền hiện tại: \(KeepAliveModeText.current)
        \(diagnosticsSection)

        Nhật ký gần đây:
        \(entries.isEmpty ? "Chưa có nhật ký" : entries.joined(separator: "\n"))
        """
    }

    static func copyToPasteboard() {
        UIPasteboard.general.string = exportText()
    }

    static func resetLogs() {
        let clearBuffer = {
            memoryBuffer.removeAll(keepingCapacity: false)
            memoryBufferBytes = 0
            UserDefaults.standard.removeObject(forKey: storageKey)
        }
        if DispatchQueue.getSpecific(key: logQueueKey) != nil {
            clearBuffer()
        } else {
            logQueue.sync(execute: clearBuffer)
        }
        DiagnosticsRuntimeState.reset()
        ProcessTerminationDiagnostics.reset()
    }

    static func trimForMemoryPressure() {
        logQueue.async {
            let retained = memoryBuffer.suffix(100)
            memoryBuffer = Array(retained)
            memoryBufferBytes = memoryBuffer.reduce(into: 0) { $0 += $1.utf8.count }
            UserDefaults.standard.set(memoryBuffer, forKey: storageKey)
        }
    }

    private static func limitEntry(_ text: String) -> String {
        guard text.utf8.count > maximumEntryBytes else { return text }
        let marker = "\n[Nhật ký quá dài, đã bị cắt bớt]"
        let prefixByteCount = max(0, maximumEntryBytes - marker.utf8.count)
        return String(decoding: text.utf8.prefix(prefixByteCount), as: UTF8.self) + marker
    }

    private static func trimMemoryBuffer() {
        while memoryBuffer.count > maximumEntries || memoryBufferBytes > maximumBufferBytes {
            guard !memoryBuffer.isEmpty else {
                memoryBufferBytes = 0
                return
            }
            memoryBufferBytes -= memoryBuffer.removeFirst().utf8.count
        }
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

private struct LightweightRuntimeSample: Codable {
    let timestamp: TimeInterval
    let reason: String
    let physicalFootprintMB: Double
    let threadCount: Int
    let appState: String
    let pipActive: Bool?
    let engineRoute: String?
    let keepAlivePolicy: String
    let height: Double?
    let audioPlaying: Bool
    let lowPowerModeEnabled: Bool
    let thermalState: Int
    let appVersion: String
    let buildNumber: String
}

enum LightweightRuntimeDiagnostics {
    private static let storageKey = "pip.lightweightRuntime.samples.beta2"
    private static let lastPeriodicSampleKey = "pip.lightweightRuntime.lastPeriodicSample.beta2"
    private static let minimumPeriodicInterval: TimeInterval = 10 * 60
    private static let maximumSamples = 320
    private static let queue = DispatchQueue(label: "com.yoroin.globalrefresh.lightweight-runtime", qos: .utility)
    private static let observerLock = NSLock()
    private static var observerTokens: [NSObjectProtocol] = []

    static func start() {
        installObserversIfNeeded()
        record(reason: "App Khởi động", force: true)
    }

    static func recordPiPCheckpoint(
        reason: String,
        isActive: Bool,
        engineRoute: String,
        keepAlivePolicy: String,
        height: CGFloat,
        audioPlaying: Bool,
        force: Bool = false
    ) {
        record(
            reason: reason,
            force: force,
            pipActive: isActive,
            engineRoute: engineRoute,
            keepAlivePolicy: keepAlivePolicy,
            height: Double(height),
            audioPlaying: audioPlaying
        )
    }

    static func exportText() -> String {
        let samples = loadSamplesSynchronously()
        guard !samples.isEmpty else {
            return "Bản ghi bộ nhớ thường trực nhẹ (vẫn ghi khi tắt chế độ gỡ lỗi) \n Chưa có bản ghi"
        }

        let lines = samples.map { sample in
            let date = Date(timeIntervalSince1970: sample.timestamp)
            let pipText = sample.pipActive.map { $0 ? "active" : "inactive" } ?? "unknown"
            let routeText = sample.engineRoute ?? "unknown"
            let heightText = sample.height.map { String(format: "%.1fpt", $0) } ?? "unknown"
            return String(
                format: "%@ | %@ | footprint=%.1fMB | threads=%d | App=%@ | PiP=%@ | route=%@ | policy=%@ | height=%@ | audio=%@ | lowPower=%@ | thermal=%d | version=%@(%@)",
                formatter.string(from: date),
                sample.reason,
                sample.physicalFootprintMB,
                sample.threadCount,
                sample.appState,
                pipText,
                routeText,
                sample.keepAlivePolicy,
                heightText,
                sample.audioPlaying ? "on" : "off",
                sample.lowPowerModeEnabled ? "on" : "off",
                sample.thermalState,
                sample.appVersion,
                sample.buildNumber
            )
        }

        return """
        Bản ghi bộ nhớ thường trực nhẹ (vẫn ghi khi tắt chế độ gỡ lỗi)
        Quy tắc lấy mẫu: mỗi 10 phút một lần khi PiP đang chạy, đồng thời ghi lúc khởi động, chuyển nền trước/nền sau và cảnh báo bộ nhớ; giữ tối đa 320 bản ghi.
        Lưu ý: ghi nhận xu hướng bộ nhớ vật lý, không đồng nghĩa với nguyên nhân Jetsam do hệ thống xác nhận.

        \(lines.joined(separator: "\n"))
        """
    }

    static func reset() {
        queue.sync {
            let defaults = UserDefaults.standard
            defaults.removeObject(forKey: storageKey)
            defaults.removeObject(forKey: lastPeriodicSampleKey)
        }
    }

    private static func record(
        reason: String,
        force: Bool,
        pipActive: Bool? = nil,
        engineRoute: String? = nil,
        keepAlivePolicy: String = KeepAlivePolicy.current.rawValue,
        height: Double? = nil,
        audioPlaying: Bool = false
    ) {
        let now = Date()
        let appState = applicationStateText(UIApplication.shared.applicationState)
        let lowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        let thermalState = ProcessInfo.processInfo.thermalState.rawValue
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"

        queue.async {
            let defaults = UserDefaults.standard
            let previous = defaults.double(forKey: lastPeriodicSampleKey)
            guard force || previous <= 0 || now.timeIntervalSince1970 - previous >= minimumPeriodicInterval else {
                return
            }

            let process = PerformanceDiagnosticsLogger.lightweightProcessSnapshot()
            let sample = LightweightRuntimeSample(
                timestamp: now.timeIntervalSince1970,
                reason: String(reason.prefix(80)),
                physicalFootprintMB: (process.physicalFootprintMB * 10).rounded() / 10,
                threadCount: process.threadCount,
                appState: appState,
                pipActive: pipActive,
                engineRoute: engineRoute,
                keepAlivePolicy: keepAlivePolicy,
                height: height,
                audioPlaying: audioPlaying,
                lowPowerModeEnabled: lowPowerModeEnabled,
                thermalState: thermalState,
                appVersion: version,
                buildNumber: build
            )
            var samples = loadSamples(defaults: defaults)
            samples.append(sample)
            if samples.count > maximumSamples {
                samples.removeFirst(samples.count - maximumSamples)
            }
            if let data = try? JSONEncoder().encode(samples) {
                defaults.set(data, forKey: storageKey)
                defaults.set(now.timeIntervalSince1970, forKey: lastPeriodicSampleKey)
            }
        }
    }

    private static func installObserversIfNeeded() {
        observerLock.lock()
        let alreadyInstalled = !observerTokens.isEmpty
        observerLock.unlock()
        guard !alreadyInstalled else { return }

        let center = NotificationCenter.default
        let tokens = [
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
                record(reason: "App Vào nền", force: true)
            },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
                record(reason: "App Sắp quay lại nền trước", force: true)
            },
            center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
                record(reason: "Nhận cảnh báo bộ nhớ", force: true)
                AppDebugLogger.trimForMemoryPressure()
                BackgroundTaskManager.shared.releasePreparedAudioIfInactive()
                URLCache.shared.removeAllCachedResponses()
            }
        ]

        observerLock.lock()
        if observerTokens.isEmpty {
            observerTokens = tokens
        } else {
            tokens.forEach(center.removeObserver)
        }
        observerLock.unlock()
    }

    private static func loadSamplesSynchronously() -> [LightweightRuntimeSample] {
        queue.sync { loadSamples(defaults: .standard) }
    }

    private static func loadSamples(defaults: UserDefaults) -> [LightweightRuntimeSample] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([LightweightRuntimeSample].self, from: data)) ?? []
    }

    private static func applicationStateText(_ state: UIApplication.State) -> String {
        switch state {
        case .active: return "active"
        case .inactive: return "inactive"
        case .background: return "background"
        @unknown default: return "unknown"
        }
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

enum DiagnosticsRuntimeState {
    private static let lock = NSLock()
    private static var observerTokens: [NSObjectProtocol] = []
    private static var appState = "Chưa ghi"
    private static var currentPage = "Chưa ghi"
    private static var pipState = "Chưa ghi"
    private static var displaySleepState = "Chưa ghi"
    private static var pipSurfaceState = "Chưa ghi"
    private static var lastUserAction = "Không"
    private static var lastEvent = "Không"

    static func startAppStateTracking() {
        lock.lock()
        let hasStarted = !observerTokens.isEmpty
        lock.unlock()
        guard !hasStarted else { return }

        updateAppState("Khởi động")
        let center = NotificationCenter.default
        let tokens = [
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { _ in
                updateAppState("Nền trước đang hoạt động")
            },
            center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: nil) { _ in
                updateAppState("Sắp không hoạt động")
            },
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { _ in
                updateAppState("Nền")
            },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil) { _ in
                updateAppState("Sắp quay lại nền trước")
            },
            center.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: nil) { _ in
                updateAppState("Sắp bị chấm dứt")
            }
        ]

        lock.lock()
        if observerTokens.isEmpty {
            observerTokens = tokens
        } else {
            tokens.forEach { center.removeObserver($0) }
        }
        lock.unlock()
    }

    static func stopAppStateTracking() {
        lock.lock()
        let tokens = observerTokens
        observerTokens.removeAll()
        lock.unlock()

        let center = NotificationCenter.default
        tokens.forEach { center.removeObserver($0) }
    }

    static func reset() {
        lock.lock()
        appState = "Chưa ghi"
        currentPage = "Chưa ghi"
        pipState = "Chưa ghi"
        displaySleepState = "Chưa ghi"
        pipSurfaceState = "Chưa ghi"
        lastUserAction = "Không"
        lastEvent = "Không"
        lock.unlock()
    }

    static func refreshAppState() {
        switch UIApplication.shared.applicationState {
        case .active:
            updateAppState("Nền trước đang hoạt động")
        case .inactive:
            updateAppState("Không hoạt động")
        case .background:
            updateAppState("Nền")
        @unknown default:
            updateAppState("Không rõ")
        }
    }

    static func updateAppState(_ state: String) {
        update { appState = state }
    }

    static func updateCurrentPage(_ page: String) {
        update { currentPage = page }
    }

    static func updatePiPState(_ state: String) {
        update { pipState = state }
    }

    static func updateDisplaySleepState(_ state: String) {
        update { displaySleepState = state }
    }

    static func updatePiPSurfaceState(_ state: String) {
        update { pipSurfaceState = state }
    }

    static func recordUserAction(_ action: String) {
        update { lastUserAction = action }
        AppDebugLogger.log("Thao tác người dùng: \(action)")
    }

    static func updateLastEvent(_ event: String) {
        update { lastEvent = event }
    }

    static func snapshotText(includeAudio: Bool = true) -> String {
        let base: String = lockedValue {
            "App=\(appState), Trang=\(currentPage), Cửa sổ nổi=\(pipState), Lớp hiển thị cửa sổ nổi=\(pipSurfaceState), Tắt màn hình=\(displaySleepState), Thao tác cuối=\(lastUserAction), Sự kiện cuối=\(lastEvent)"
        }
        guard includeAudio else { return base }
        return "\(base), Âm thanh=\(audioSessionSnapshotText)"
    }

    static var isForegroundActive: Bool {
        lock.lock()
        let value = appState == "Nền trước đang hoạt động"
        lock.unlock()
        return value
    }

    private static func update(_ block: () -> Void) {
        lock.lock()
        block()
        lock.unlock()
    }

    private static func lockedValue(_ block: () -> String) -> String {
        lock.lock()
        let value = block()
        lock.unlock()
        return value
    }

    private static var audioSessionSnapshotText: String {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs
            .map { output in
                "\(output.portType.rawValue):\(output.portName)"
            }
            .joined(separator: ",")
        let routeText = outputs.isEmpty ? "Không có đầu ra" : outputs
        return String(
            format: "category=%@, mode=%@, route=%@, volume=%.2f, otherAudio=%@",
            session.category.rawValue,
            session.mode.rawValue,
            routeText,
            session.outputVolume,
            session.isOtherAudioPlaying ? "Có" : "Không"
        )
    }
}

enum MainThreadWatchdog {
    private static let enabledKey = "pip.debug.mainThreadWatchdogEnabled"
    private static let queue = DispatchQueue(label: "pip.debug.main-thread-watchdog")
    private static let pingInterval: TimeInterval = 0.5
    private static let threshold: TimeInterval = 1.2
    private static let reportInterval: TimeInterval = 3

    private static var timer: DispatchSourceTimer?
    private static var lastBeat = Date()
    private static var lastReport = Date.distantPast
    private static var isHanging = false
    private static var currentHangIsForeground = true
    private static var hasPendingPing = false

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static func setEnabled(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: enabledKey)
        isEnabled ? startIfNeeded() : stop()
        AppDebugLogger.log("Main thread watchdog \(isEnabled ? "enabled" : "disabled")")
    }

    static func startIfNeeded() {
        guard isEnabled else { return }
        DiagnosticsRuntimeState.startAppStateTracking()
        DiagnosticsRuntimeState.refreshAppState()
        queue.async {
            guard timer == nil else { return }
            lastBeat = Date()
            lastReport = .distantPast
            isHanging = false
            hasPendingPing = false

            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now() + pingInterval, repeating: pingInterval)
            source.setEventHandler {
                let now = Date()
                let gap = now.timeIntervalSince(lastBeat)
                if gap > threshold {
                    let isForegroundActive = DiagnosticsRuntimeState.isForegroundActive
                    if !isHanging {
                        isHanging = true
                        currentHangIsForeground = isForegroundActive
                        lastReport = now
                        AppDebugLogger.log(
                            String(
                                format: "%@: %.2f giây không phản hồi | %@ | %@",
                                isForegroundActive ? "Luồng chính bắt đầu bị giật" : "Ghi nhận luồng chính bị treo ở nền",
                                gap,
                                PerformanceDiagnosticsLogger.currentSnapshotText(),
                                DiagnosticsRuntimeState.snapshotText()
                            )
                        )
                    } else if now.timeIntervalSince(lastReport) > reportInterval {
                        lastReport = now
                        AppDebugLogger.log(
                            String(
                                format: "%@: %.2f giây không phản hồi | %@",
                                currentHangIsForeground ? "Luồng chính tiếp tục bị giật" : "Luồng chính ở nền vẫn đang bị treo",
                                gap,
                                DiagnosticsRuntimeState.snapshotText()
                            )
                        )
                    }
                }

                guard !hasPendingPing else { return }
                hasPendingPing = true
                DispatchQueue.main.async {
                    let acknowledgedAt = Date()
                    queue.async {
                        let blockedDuration = acknowledgedAt.timeIntervalSince(lastBeat)
                        let shouldLogRecovery = isHanging
                        lastBeat = acknowledgedAt
                        hasPendingPing = false
                        if shouldLogRecovery {
                            isHanging = false
                            AppDebugLogger.log(
                                String(
                                    format: "%@: kéo dài khoảng %.2f giây | %@",
                                    currentHangIsForeground ? "Luồng chính hết giật" : "Luồng chính ở nền hết treo",
                                    blockedDuration,
                                    DiagnosticsRuntimeState.snapshotText()
                                )
                            )
                        }
                    }
                }
            }
            timer = source
            source.resume()
            AppDebugLogger.log("Main thread watchdog started")
        }
    }

    static func stop() {
        queue.async {
            timer?.cancel()
            timer = nil
            isHanging = false
            currentHangIsForeground = true
            hasPendingPing = false
        }
    }
}

enum FrameStutterMonitor {
    private static let enabledKey = "pip.debug.frameStutterEnabled"
    private static let threshold: CFTimeInterval = 0.18
    private static let reportInterval: TimeInterval = 3
    private static var displayLink: CADisplayLink?
    private static var lastTimestamp: CFTimeInterval = 0
    private static var lastReport = Date.distantPast

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static func setEnabled(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: enabledKey)
        isEnabled ? startIfNeeded() : stop()
        AppDebugLogger.log("Frame stutter monitor \(isEnabled ? "enabled" : "disabled")")
    }

    static func startIfNeeded() {
        guard isEnabled else { return }
        DiagnosticsRuntimeState.startAppStateTracking()
        DiagnosticsRuntimeState.refreshAppState()
        DispatchQueue.main.async {
            guard displayLink == nil else { return }
            lastTimestamp = 0
            lastReport = .distantPast

            let link = CADisplayLink(target: FrameStutterTarget.shared, selector: #selector(FrameStutterTarget.step(_:)))
            // BETA2 ANCHOR: Giám sát khung hình khi gỡ lỗi tránh tracking mode để việc giám sát không ảnh hưởng cảm giác vuốt.
            link.add(to: .main, forMode: .default)
            displayLink = link
            AppDebugLogger.log("Frame stutter monitor started")
        }
    }

    static func stop() {
        DispatchQueue.main.async {
            displayLink?.invalidate()
            displayLink = nil
            lastTimestamp = 0
        }
    }

    fileprivate static func handleStep(_ displayLink: CADisplayLink) {
        guard lastTimestamp > 0 else {
            lastTimestamp = displayLink.timestamp
            return
        }

        let interval = displayLink.timestamp - lastTimestamp
        lastTimestamp = displayLink.timestamp

        guard interval > threshold else { return }
        let now = Date()
        guard now.timeIntervalSince(lastReport) > reportInterval else { return }
        lastReport = now

        let expectedFrame = displayLink.targetTimestamp - displayLink.timestamp
        let label = DiagnosticsRuntimeState.isForegroundActive ? "UI Khoảng cách khung hình bất thường" : "Ghi nhận khoảng cách khung hình UI ở nền"
        AppDebugLogger.log(
            String(
                format: "%@: %.0fms, khoảng cách khung hình dự kiến khoảng %.1fms | %@ | %@",
                label,
                interval * 1000,
                max(expectedFrame, 0) * 1000,
                PerformanceDiagnosticsLogger.currentSnapshotText(),
                DiagnosticsRuntimeState.snapshotText()
            )
        )
    }
}

private final class FrameStutterTarget: NSObject {
    static let shared = FrameStutterTarget()

    @objc func step(_ displayLink: CADisplayLink) {
        FrameStutterMonitor.handleStep(displayLink)
    }
}

struct LightweightProcessSnapshot {
    let physicalFootprintMB: Double
    let threadCount: Int
}

enum PerformanceDiagnosticsLogger {
    private static let enabledKey = "pip.debug.performanceDiagnosticsEnabled"
    private static let queue = DispatchQueue(label: "pip.debug.performance-diagnostics")
    private static var timer: DispatchSourceTimer?
    private static var isRuntimeSamplingSuppressed = false

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static func setEnabled(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: enabledKey)
        isEnabled ? startIfNeeded() : stop()
        AppDebugLogger.log("Performance diagnostics \(isEnabled ? "enabled" : "disabled")")
    }

    static func startIfNeeded() {
        guard isEnabled else { return }
        DiagnosticsRuntimeState.startAppStateTracking()
        DiagnosticsRuntimeState.refreshAppState()
        queue.async {
            guard timer == nil else { return }
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now() + 2, repeating: 60, leeway: .seconds(3))
            source.setEventHandler {
                guard !isRuntimeSamplingSuppressed else { return }
                let snapshot = makeSnapshot()
                AppDebugLogger.log(snapshot)
                DispatchQueue.main.async {
                    let runtime = DiagnosticsRuntimeState.snapshotText(includeAudio: false)
                    ProcessTerminationDiagnostics.recordCheckpoint(
                        reason: "60 giây - nhịp hiệu năng",
                        pipSnapshot: "\(runtime), Hiệu năng{\(snapshot)}"
                    )
                }
            }
            timer = source
            source.resume()
            AppDebugLogger.log("Performance diagnostics started")
        }
    }

    static func stop() {
        queue.async {
            timer?.cancel()
            timer = nil
            isRuntimeSamplingSuppressed = false
        }
    }

    static func setRuntimeSamplingSuppressed(_ isSuppressed: Bool, reason: String) {
        queue.async {
            guard isRuntimeSamplingSuppressed != isSuppressed else { return }
            isRuntimeSamplingSuppressed = isSuppressed
            AppDebugLogger.log(
                "Performance diagnostics runtime sampling \(isSuppressed ? "suppressed" : "resumed"): \(reason)"
            )
        }
    }

    static func currentSnapshotText() -> String {
        makeSnapshot()
    }

    static func lightweightProcessSnapshot() -> LightweightProcessSnapshot {
        let threadSnapshot = threadUsageSnapshot()
        return LightweightProcessSnapshot(
            physicalFootprintMB: physicalFootprintMB(),
            threadCount: threadSnapshot.threadCount
        )
    }

    private static func makeSnapshot() -> String {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let batteryLevel = UIDevice.current.batteryLevel >= 0
            ? "\(Int(UIDevice.current.batteryLevel * 100))%"
            : "Không rõ"
        let processSnapshot = makeProcessSnapshot()
        return String(
            format: "Lấy mẫu hiệu năng: CPU=%.1f%%, Luồng cao nhất=%.1f%%, Bộ nhớ=%.1fMB, Chiếm dụng vật lý=%.1fMB, Luồng=%d(Đang chạy=%d,Đang chờ=%d,Đã dừng=%d,Không thể ngắt=%d,Treo=%d), Trạng thái nhiệt=%@, Pin=%@, Sạc=%@",
            processSnapshot.cpuUsage,
            processSnapshot.maxThreadCPUUsage,
            processSnapshot.residentMemoryMB,
            processSnapshot.physicalFootprintMB,
            processSnapshot.threadCount,
            processSnapshot.runningThreadCount,
            processSnapshot.waitingThreadCount,
            processSnapshot.stoppedThreadCount,
            processSnapshot.uninterruptibleThreadCount,
            processSnapshot.haltedThreadCount,
            thermalStateText,
            batteryLevel,
            batteryStateText
        )
    }

    private static var thermalStateText: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            return "Bình thường"
        case .fair:
            return "Hơi nóng lên"
        case .serious:
            return "Nóng rõ rệt"
        case .critical:
            return "Nghiêm trọng"
        @unknown default:
            return "Không rõ"
        }
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

    private struct ProcessSnapshot {
        let cpuUsage: Double
        let maxThreadCPUUsage: Double
        let residentMemoryMB: Double
        let physicalFootprintMB: Double
        let threadCount: Int
        let runningThreadCount: Int
        let waitingThreadCount: Int
        let stoppedThreadCount: Int
        let uninterruptibleThreadCount: Int
        let haltedThreadCount: Int
    }

    private static func makeProcessSnapshot() -> ProcessSnapshot {
        let threadSnapshot = threadUsageSnapshot()
        return ProcessSnapshot(
            cpuUsage: threadSnapshot.totalCPUUsage,
            maxThreadCPUUsage: threadSnapshot.maxThreadCPUUsage,
            residentMemoryMB: residentMemoryMB(),
            physicalFootprintMB: physicalFootprintMB(),
            threadCount: threadSnapshot.threadCount,
            runningThreadCount: threadSnapshot.runningThreadCount,
            waitingThreadCount: threadSnapshot.waitingThreadCount,
            stoppedThreadCount: threadSnapshot.stoppedThreadCount,
            uninterruptibleThreadCount: threadSnapshot.uninterruptibleThreadCount,
            haltedThreadCount: threadSnapshot.haltedThreadCount
        )
    }

    private static func residentMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / 1024.0 / 1024.0
    }

    private static func physicalFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1024.0 / 1024.0
    }

    private struct ThreadUsageSnapshot {
        let totalCPUUsage: Double
        let maxThreadCPUUsage: Double
        let threadCount: Int
        let runningThreadCount: Int
        let waitingThreadCount: Int
        let stoppedThreadCount: Int
        let uninterruptibleThreadCount: Int
        let haltedThreadCount: Int
    }

    private static func threadUsageSnapshot() -> ThreadUsageSnapshot {
        var threadList: thread_act_array_t?
        var threadCount = mach_msg_type_number_t(0)
        let result = task_threads(mach_task_self_, &threadList, &threadCount)
        guard result == KERN_SUCCESS, let threadList else {
            return ThreadUsageSnapshot(
                totalCPUUsage: 0,
                maxThreadCPUUsage: 0,
                threadCount: 0,
                runningThreadCount: 0,
                waitingThreadCount: 0,
                stoppedThreadCount: 0,
                uninterruptibleThreadCount: 0,
                haltedThreadCount: 0
            )
        }

        defer {
            let size = vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threadList)), size)
        }

        var totalUsage: Double = 0
        var maxUsage: Double = 0
        var runningCount = 0
        var waitingCount = 0
        var stoppedCount = 0
        var uninterruptibleCount = 0
        var haltedCount = 0

        for index in 0..<Int(threadCount) {
            var threadInfo = thread_basic_info()
            var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
            let infoResult = withUnsafeMutablePointer(to: &threadInfo) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(threadInfoCount)) {
                    thread_info(threadList[index], thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
                }
            }

            if infoResult == KERN_SUCCESS, (threadInfo.flags & TH_FLAGS_IDLE) == 0 {
                let usage = Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
                totalUsage += usage
                maxUsage = max(maxUsage, usage)

                switch Int32(threadInfo.run_state) {
                case TH_STATE_RUNNING:
                    runningCount += 1
                case TH_STATE_WAITING:
                    waitingCount += 1
                case TH_STATE_STOPPED:
                    stoppedCount += 1
                case TH_STATE_UNINTERRUPTIBLE:
                    uninterruptibleCount += 1
                case TH_STATE_HALTED:
                    haltedCount += 1
                default:
                    break
                }
            }
        }

        return ThreadUsageSnapshot(
            totalCPUUsage: totalUsage,
            maxThreadCPUUsage: maxUsage,
            threadCount: Int(threadCount),
            runningThreadCount: runningCount,
            waitingThreadCount: waitingCount,
            stoppedThreadCount: stoppedCount,
            uninterruptibleThreadCount: uninterruptibleCount,
            haltedThreadCount: haltedCount
        )
    }
}

enum DebugDiagnosticsMonitor {
    static var isEnabled: Bool {
        MainThreadWatchdog.isEnabled || PerformanceDiagnosticsLogger.isEnabled || FrameStutterMonitor.isEnabled
    }

    static func setEnabled(_ isEnabled: Bool) {
        if isEnabled {
            DiagnosticsRuntimeState.startAppStateTracking()
            DiagnosticsRuntimeState.refreshAppState()
        }
        MainThreadWatchdog.setEnabled(isEnabled)
        FrameStutterMonitor.setEnabled(isEnabled)
        PerformanceDiagnosticsLogger.setEnabled(isEnabled)
        if !isEnabled {
            DiagnosticsRuntimeState.stopAppStateTracking()
        }
    }

    static func startIfNeeded() {
        MainThreadWatchdog.startIfNeeded()
        FrameStutterMonitor.startIfNeeded()
        PerformanceDiagnosticsLogger.startIfNeeded()
    }

    static func stop() {
        MainThreadWatchdog.stop()
        FrameStutterMonitor.stop()
        PerformanceDiagnosticsLogger.stop()
    }
}
struct ProcessTerminationEvidenceSnapshot: Codable, Equatable {
    let capturedAt: Date
    let lastCheckpointAt: Date?
    let memoryWarningCount: Int
    let lastMemoryWarningAt: Date?
    let checkpointText: String
    let inferenceText: String
    let systemRestartDetected: Bool
    let metricKitStatus: String?
}

enum ProcessTerminationDiagnostics {
    private static let prefix = "pip.debug.processExit."
    private static let runActiveKey = prefix + "runActive"
    private static let launchKey = prefix + "launch"
    private static let legacyBootKey = prefix + "boot"
    private static let lastUptimeKey = prefix + "lastUptime"
    private static let lastCheckpointKey = prefix + "lastCheckpoint"
    private static let lastCheckpointDateKey = prefix + "lastCheckpointDate"
    private static let memoryWarningCountKey = prefix + "memoryWarningCount"
    private static let lastMemoryWarningKey = prefix + "lastMemoryWarning"
    private static let previousRunSummaryKey = prefix + "previousRunSummary"
    private static let previousRunEvidenceKey = prefix + "previousRunEvidence.v1"
    private static let observerLock = NSLock()
    private static var observerTokens: [NSObjectProtocol] = []

    static func prepareForLaunch() {
        guard AppDebugLogger.isDebugModeEnabled else { return }

        let defaults = UserDefaults.standard
        let previousRunWasActive = defaults.bool(forKey: runActiveKey)
        let previousLaunch = defaults.double(forKey: launchKey)
        let previousUptime = defaults.double(forKey: lastUptimeKey)
        let previousCheckpoint = defaults.string(forKey: lastCheckpointKey) ?? "Không"
        let previousCheckpointDate = defaults.double(forKey: lastCheckpointDateKey)
        let previousMemoryWarnings = defaults.integer(forKey: memoryWarningCountKey)
        let previousLastMemoryWarning = defaults.double(forKey: lastMemoryWarningKey)
        let currentUptime = ProcessInfo.processInfo.systemUptime

        if previousRunWasActive {
            // A reboot resets monotonic uptime. Deriving a boot date from wall-clock time
            // drifts during deep sleep on some iOS versions and causes false reboot reports.
            let bootChanged = previousUptime > 0 && currentUptime + 90 < previousUptime
            let warningWasRecent = previousLastMemoryWarning > 0
                && previousCheckpointDate > 0
                && previousCheckpointDate - previousLastMemoryWarning < 30 * 60
            let inference: String
            if bootChanged {
                inference = "Thiết bị đã khởi động lại hoặc cập nhật hệ thống giữa hai lần chạy, không thể kết luận chỉ đơn thuần là bị tắt nền"
            } else if warningWasRecent || previousMemoryWarnings > 0 {
                inference = "Đã có cảnh báo bộ nhớ trước khi bị chấm dứt, có thể liên quan đến áp lực bộ nhớ/Jetsam; cần đối chiếu với MetricKit để xác nhận"
            } else if previousCheckpoint.contains("Pin yếu=Có") && previousCheckpoint.contains("PiP") {
                inference = "Ở chế độ pin yếu, có thể do không đủ điều kiện chạy media nền, hệ thống dọn dẹp ban đêm hoặc Jetsam; ứng dụng thông thường không nhận được callback chấm dứt chính xác"
            } else {
                inference = "Có thể do chính sách nền của hệ thống, Jetsam, người dùng vuốt tắt ứng dụng hoặc kiểu chấm dứt khác không có callback; cần đối chiếu với MetricKit để xác nhận"
            }
            let previousLaunchText = dateText(previousLaunch)
            let checkpointText = dateText(previousCheckpointDate)
            let summary = "Tiến trình lần trước không ghi nhận chấm dứt bình thường | Khởi động=\(previousLaunchText) | Hiện trường cuối=\(checkpointText) | Cảnh báo bộ nhớ=\(previousMemoryWarnings) lần | Suy luận=\(inference) | Hiện trường{\(previousCheckpoint)}"
            defaults.set(summary, forKey: previousRunSummaryKey)
            let evidence = ProcessTerminationEvidenceSnapshot(
                capturedAt: Date(),
                lastCheckpointAt: previousCheckpointDate > 0 ? Date(timeIntervalSince1970: previousCheckpointDate) : nil,
                memoryWarningCount: previousMemoryWarnings,
                lastMemoryWarningAt: previousLastMemoryWarning > 0 ? Date(timeIntervalSince1970: previousLastMemoryWarning) : nil,
                checkpointText: previousCheckpoint,
                inferenceText: inference,
                systemRestartDetected: bootChanged,
                metricKitStatus: defaults.string(forKey: "pip.metricKit.beta5HistoryStatus")
            )
            if let data = try? JSONEncoder().encode(evidence) {
                defaults.set(data, forKey: previousRunEvidenceKey)
            }
        } else {
            defaults.removeObject(forKey: previousRunEvidenceKey)
        }

        defaults.set(true, forKey: runActiveKey)
        defaults.set(Date().timeIntervalSince1970, forKey: launchKey)
        defaults.set(0, forKey: memoryWarningCountKey)
        defaults.removeObject(forKey: lastMemoryWarningKey)
        installObserversIfNeeded()
        recordCheckpoint(reason: "Khởi động tiến trình")
        AppDebugLogger.logCritical("Đã khởi động chẩn đoán chấm dứt tiến trình; \(defaults.string(forKey: previousRunSummaryKey) ?? "Không có bản ghi chấm dứt bất thường lần trước")")
    }

    static func recordCheckpoint(
        reason: String,
        pipSnapshot: String? = nil,
        persistImmediately: Bool = true
    ) {
        guard AppDebugLogger.isDebugModeEnabled else { return }
        let defaults = UserDefaults.standard
        let snapshot = runtimeSnapshot(reason: reason, pipSnapshot: pipSnapshot)
        defaults.set(snapshot, forKey: lastCheckpointKey)
        defaults.set(Date().timeIntervalSince1970, forKey: lastCheckpointDateKey)
        defaults.set(ProcessInfo.processInfo.systemUptime, forKey: lastUptimeKey)
        if persistImmediately {
            defaults.synchronize()
        }
    }

    static func recordMemoryWarning() {
        guard AppDebugLogger.isDebugModeEnabled else { return }
        let defaults = UserDefaults.standard
        let count = defaults.integer(forKey: memoryWarningCountKey) + 1
        defaults.set(count, forKey: memoryWarningCountKey)
        defaults.set(Date().timeIntervalSince1970, forKey: lastMemoryWarningKey)
        recordCheckpoint(reason: "Nhận cảnh báo bộ nhớ#\(count)")
        AppDebugLogger.logCritical("Nhận cảnh báo bộ nhớ của hệ thống#\(count) | \(PerformanceDiagnosticsLogger.currentSnapshotText())")
    }

    static func markGracefulTermination(reason: String) {
        guard AppDebugLogger.isDebugModeEnabled else { return }
        recordCheckpoint(reason: reason)
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: runActiveKey)
        defaults.synchronize()
        AppDebugLogger.logCritical("Tiến trình ghi nhận kết thúc bình thường: \(reason)")
    }

    static func exportText() -> String {
        let defaults = UserDefaults.standard
        return """
        Suy luận chấm dứt tiến trình:
        Lần chạy trước: \(defaults.string(forKey: previousRunSummaryKey) ?? "Không có bản ghi chấm dứt bất thường")
        Lần khởi động này: \(dateText(defaults.double(forKey: launchKey)))
        Cảnh báo bộ nhớ lần này: \(defaults.integer(forKey: memoryWarningCountKey)) lần
        Hiện trường chẩn đoán cuối: \(defaults.string(forKey: lastCheckpointKey) ?? "Không")
        Lưu ý: iOS không cung cấp callback tức thời của Jetsam cho ứng dụng thông thường; đây là suy luận dựa trên hiện trường được lưu cuối cùng, việc khởi động lại thiết bị, cảnh báo bộ nhớ và MetricKit, không đồng nghĩa với nguyên nhân hệ thống tắt tiến trình một cách chính xác.
        """
    }

    static func previousRunEvidenceSnapshot() -> ProcessTerminationEvidenceSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: previousRunEvidenceKey) else { return nil }
        return try? JSONDecoder().decode(ProcessTerminationEvidenceSnapshot.self, from: data)
    }

    static func reset() {
        observerLock.lock()
        let tokens = observerTokens
        observerTokens.removeAll(keepingCapacity: false)
        observerLock.unlock()
        tokens.forEach(NotificationCenter.default.removeObserver)

        let defaults = UserDefaults.standard
        [
            runActiveKey,
            launchKey,
            legacyBootKey,
            lastUptimeKey,
            lastCheckpointKey,
            lastCheckpointDateKey,
            memoryWarningCountKey,
            lastMemoryWarningKey,
            previousRunSummaryKey,
            previousRunEvidenceKey
        ].forEach(defaults.removeObject(forKey:))
    }

    private static func installObserversIfNeeded() {
        observerLock.lock()
        let hasObservers = !observerTokens.isEmpty
        observerLock.unlock()
        guard !hasObservers else { return }

        let center = NotificationCenter.default
        let tokens = [
            center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
                recordAndLogCritical("App Sắp không hoạt động")
            },
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
                recordAndLogCritical("App Vào nền")
            },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
                recordAndLogCritical("App Sắp quay lại nền trước")
            },
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                recordAndLogCritical("App Nền trước đang hoạt động")
            },
            center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
                recordMemoryWarning()
            },
            center.addObserver(forName: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil, queue: .main) { _ in
                recordAndLogCritical("Thiết bị sắp khóa")
            },
            center.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main) { _ in
                recordAndLogCritical("Thiết bị đã mở khóa")
            },
            center.addObserver(forName: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { _ in
                recordAndLogCritical("Chế độ pin yếu của hệ thống thay đổi")
            },
            center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { _ in
                recordAndLogCritical("Trạng thái nhiệt của hệ thống thay đổi")
            },
            center.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { _ in
                markGracefulTermination(reason: "Nhận willTerminate")
            }
        ]

        observerLock.lock()
        if observerTokens.isEmpty {
            observerTokens = tokens
        } else {
            tokens.forEach(center.removeObserver)
        }
        observerLock.unlock()
    }

    private static func recordAndLogCritical(_ reason: String) {
        recordCheckpoint(reason: reason)
        AppDebugLogger.logCritical("Chẩn đoán vòng đời: \(runtimeSnapshot(reason: reason, pipSnapshot: nil))")
    }

    private static func runtimeSnapshot(reason: String, pipSnapshot: String?) -> String {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let app = UIApplication.shared
        let state: String
        switch app.applicationState {
        case .active: state = "active"
        case .inactive: state = "inactive"
        case .background: state = "background"
        @unknown default: state = "unknown"
        }
        let remainingBackgroundTime = app.backgroundTimeRemaining
        let backgroundTime: String
        if app.applicationState != .background {
            backgroundTime = "Không áp dụng"
        } else if !remainingBackgroundTime.isFinite || remainingBackgroundTime > 24 * 60 * 60 {
            backgroundTime = "Hệ thống không giới hạn"
        } else {
            backgroundTime = String(format: "%.1fs", remainingBackgroundTime)
        }
        let battery = UIDevice.current.batteryLevel >= 0
            ? "\(Int(UIDevice.current.batteryLevel * 100))%"
            : "Không rõ"
        let pipText = pipSnapshot ?? DiagnosticsRuntimeState.snapshotText(includeAudio: false)
        return [
            "Lý do=\(reason)",
            "App=\(state)",
            "Còn lại ở nền=\(backgroundTime)",
            "Dữ liệu được bảo vệ=\(app.isProtectedDataAvailable ? "Khả dụng" : "Không khả dụng/đã khóa")",
            "Pin yếu=\(ProcessInfo.processInfo.isLowPowerModeEnabled ? "Có" : "Không")",
            "Trạng thái nhiệt=\(thermalStateText)",
            "Pin=\(battery)",
            "Bộ nhớ vật lý=\(String(format: "%.1fGB", Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824))",
            "Thời gian chạy=\(String(format: "%.0fs", ProcessInfo.processInfo.systemUptime))",
            "Chính sách giữ nền=\(KeepAlivePolicy.current.diagnosticsName)",
            "Âm thanh{\(BackgroundTaskManager.shared.diagnosticsText)}",
            "Hiện trường{\(pipText)}"
        ].joined(separator: ", ")
    }

    private static var thermalStateText: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "Bình thường"
        case .fair: return "Hơi nóng lên"
        case .serious: return "Nóng rõ rệt"
        case .critical: return "Nghiêm trọng"
        @unknown default: return "Không rõ"
        }
    }

    private static func dateText(_ timestamp: TimeInterval) -> String {
        guard timestamp > 0 else { return "Không" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }
}
