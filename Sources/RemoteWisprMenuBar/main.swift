import AppKit
import Foundation
import RemoteWisprCore

@MainActor
final class RemoteWisprMenuBarApp: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let statusMenuItem = NSMenuItem(title: "Idle", action: nil, keyEquivalent: "")
    private let copyMenuItem = NSMenuItem(title: "Copy Next Wispr Transcript", action: #selector(copyNextTranscript), keyEquivalent: "")
    private let checkMenuItem = NSMenuItem(title: "Check Wispr DB", action: #selector(checkWisprDatabase), keyEquivalent: "")
    private let baselineHealthMenuItem = NSMenuItem(title: "Run Baseline Health Check", action: #selector(runBaselineHealthCheck), keyEquivalent: "")
    private let inputPermissionMenuItem = NSMenuItem(title: "Check Input Permissions", action: #selector(checkInputPermissions), keyEquivalent: "")
    private let diagnosticsMenuItem = NSMenuItem(title: "Diagnostics...", action: #selector(openDiagnostics), keyEquivalent: "")
    private let settingsMenuItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
    private let manualDisableMenuItem = NSMenuItem(title: "Disable Remote Wispr", action: #selector(toggleManualDisable), keyEquivalent: "")
    private let resetMenuItem = NSMenuItem(title: "Reset Running State", action: #selector(resetRunningState), keyEquivalent: "")
    private let openLogMenuItem = NSMenuItem(title: "Open Log", action: #selector(openLog), keyEquivalent: "")
    private let logURL = RemoteWisprMenuBarApp.defaultLogURL()
    private let settingsStore = SettingsStore(fileURL: RemoteWisprMenuBarApp.defaultSettingsURL())
    private let baselineHealthChecker = BaselineHealthChecker()
    private let remoteCleanupController = RemoteCleanupController()
    private let remoteInputAutomationController = RemoteInputAutomationController()
    private var settings = AppSettings()
    private var runningTask: Task<Void, Never>?
    private var lastStatus = "Idle"
    private var settingsWindowController: SettingsWindowController?
    private var diagnosticsWindowController: DiagnosticsWindowController?
    private var hotkeyTrigger: HotkeyTrigger?
    private var isManuallyDisabled = false
    private var hotkeyMarkerRowID: Int64?
    private var hotkeyTargetApplication: NSRunningApplication?
    private var readyTitleClearTimer: Timer?
    private var diagnostics = AppDiagnostics()

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadSettings()
        configureMenu()
        configureHotkeyTrigger()
        setStatus("Idle")
    }

    func applicationWillTerminate(_ notification: Notification) {
        runningTask?.cancel()
        hotkeyTrigger?.stop()
        readyTitleClearTimer?.invalidate()
    }

    private func configureMenu() {
        if let button = statusItem.button {
            button.title = "RW"
            button.toolTip = "Remote Wispr"
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(NSMenuItem.separator())

        copyMenuItem.target = self
        menu.addItem(copyMenuItem)

        checkMenuItem.target = self
        menu.addItem(checkMenuItem)

        baselineHealthMenuItem.target = self
        menu.addItem(baselineHealthMenuItem)

        inputPermissionMenuItem.target = self
        menu.addItem(inputPermissionMenuItem)

        diagnosticsMenuItem.target = self
        menu.addItem(diagnosticsMenuItem)

        settingsMenuItem.target = self
        menu.addItem(settingsMenuItem)

        manualDisableMenuItem.target = self
        menu.addItem(manualDisableMenuItem)

        resetMenuItem.target = self
        menu.addItem(resetMenuItem)

        openLogMenuItem.target = self
        menu.addItem(openLogMenuItem)

        menu.addItem(NSMenuItem.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        appendLog("app launched")
    }

    @objc private func statusItemClicked() {
        let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
        if flags.contains(.option) {
            toggleManualDisable()
            appendLog("manual disable toggled by option-click")
            return
        }

        if let button = statusItem.button {
            menu.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: button.bounds.height),
                in: button
            )
        }
    }

    @objc private func copyNextTranscript() {
        guard runningTask == nil else {
            setStatus("Already running")
            return
        }

        copyMenuItem.isEnabled = false
        runningTask = Task { [weak self] in
            await self?.runCopyNextTranscript()
        }
    }

    @objc private func checkWisprDatabase() {
        guard runningTask == nil else {
            setStatus("Already running")
            return
        }

        runningTask = Task { [weak self] in
            await self?.runDatabaseCheck()
        }
    }

    @objc private func runBaselineHealthCheck() {
        guard runningTask == nil else {
            setStatus("Already running")
            return
        }

        let report = baselineHealthChecker.run(
            settings: settings,
            resolvedDonorAppPath: resolvedDonorAppPath(settings),
            settingsPath: Self.defaultSettingsURL().path,
            appVersion: Self.bundleValue("CFBundleShortVersionString", defaultValue: "development"),
            appBuild: Self.bundleValue("CFBundleVersion", defaultValue: "development")
        )

        diagnostics.lastBaselineHealthReport = report
        diagnostics.lastError = report.passed ? nil : "Baseline health needs attention"
        setStatus(report.statusText == "ok with notes" ? "Health OK with notes" : report.passed ? "Health OK" : "Health needs attention")
        appendLog("baseline health \(report.statusText)")
        for item in report.items {
            appendLog("baseline health item name=\"\(item.name)\" status=\(item.statusText) detail=\"\(item.detail)\"")
        }
    }

    @objc private func checkInputPermissions() {
        diagnostics.lastInputPermissionCheckAt = Date()
        let codeSigningStatus = CodeSigningDiagnostics.currentAppStatus()
        diagnostics.lastCodeSigningStatus = codeSigningStatus
        appendLog("input permission code signing \(codeSigningStatus.summary)")
        let accessibilityTrusted = AccessibilityPermission.isTrusted(prompt: true)
        guard accessibilityTrusted else {
            let installPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/Remote Wispr.app")
                .path
            let message = "Accessibility is not enabled for this signed Remote Wispr app. \(codeSigningStatus.summary). Open System Settings > Privacy & Security > Accessibility, remove stale Remote Wispr entries, then add \(installPath)."
            diagnostics.lastInputPermissionResult = message
            diagnostics.lastError = message
            setStatus("Input permission needed")
            appendLog("input permission accessibility error=\(message)")
            diagnosticsWindowController?.refresh()
            return
        }

        do {
            try SystemEventsAutomation.checkPermission()
            diagnostics.lastInputPermissionResult = "ok - Accessibility enabled and Remote Wispr can control System Events"
            diagnostics.lastError = nil
            setStatus("Input permissions OK")
            appendLog("input permissions ok")
        } catch {
            let message = String(describing: error)
            diagnostics.lastInputPermissionResult = message
            diagnostics.lastError = message
            setStatus("Input permission needed")
            appendLog("input permission automation error=\(message)")
        }
        diagnosticsWindowController?.refresh()
    }

    @objc private func quit() {
        appendLog("quit")
        NSApplication.shared.terminate(nil)
    }

    @objc private func openLog() {
        ensureLogDirectory()
        if !FileManager.default.fileExists(atPath: logURL.path) {
            appendLog("log created")
        }
        NSWorkspace.shared.open(logURL)
    }

    @objc private func openDiagnostics() {
        if diagnosticsWindowController == nil {
            diagnosticsWindowController = DiagnosticsWindowController(
                snapshotProvider: { [weak self] in
                    self?.makeDiagnosticsSnapshot() ?? Self.emptyDiagnosticsSnapshot()
                },
                onOpenLog: { [weak self] in
                    self?.openLog()
                }
            )
        }

        diagnosticsWindowController?.refresh()
        diagnosticsWindowController?.showWindow(nil)
        diagnosticsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                settings: settings
            ) { [weak self] newSettings in
                self?.saveSettings(newSettings)
            }
        }

        settingsWindowController?.settings = settings
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func toggleManualDisable() {
        isManuallyDisabled.toggle()
        diagnostics.isManuallyDisabled = isManuallyDisabled
        updateManualDisableMenuItem()
        hotkeyMarkerRowID = nil
        hotkeyTargetApplication = nil
        diagnostics.hotkeyMarkerRowID = nil
        let message = isManuallyDisabled ? "Disabled" : "Enabled"
        setStatus(message)
        appendLog("manual disable toggled disabled=\(isManuallyDisabled)")
    }

    @objc private func resetRunningState() {
        runningTask?.cancel()
        runningTask = nil
        hotkeyMarkerRowID = nil
        hotkeyTargetApplication = nil
        diagnostics.lastSkippedReason = nil
        diagnostics.isRunning = false
        diagnostics.hotkeyMarkerRowID = nil
        diagnostics.lastError = nil
        diagnostics.lastResetAt = Date()
        copyMenuItem.isEnabled = true
        setStatus("Reset")
        appendLog("running state reset")
    }

    private func runCopyNextTranscript() async {
        do {
            let store = WisprSQLiteTranscriptStore(databasePath: settings.wisprDatabasePath)
            let afterRowID = try store.maxRowID()
            diagnostics.lastMarkerRowID = afterRowID
            await runCopyNextTranscript(afterRowID: afterRowID, source: "menu", cleanupTargetApplication: nil)
        } catch {
            if Task.isCancelled {
                appendLog("copy next marker cancelled")
                return
            }
            runningTask = nil
            copyMenuItem.isEnabled = true
            diagnostics.isRunning = false
            diagnostics.lastError = String(describing: error)
            setStatus("Error: \(error)")
            appendLog("copy next marker error=\(error)")
        }
    }

    private func runCopyNextTranscript(
        afterRowID: Int64,
        source: String,
        cleanupTargetApplication: NSRunningApplication?
    ) async {
        defer {
            runningTask = nil
            copyMenuItem.isEnabled = true
            diagnostics.isRunning = false
            diagnosticsWindowController?.refresh()
        }

        do {
            let currentSettings = settings
            let store = WisprSQLiteTranscriptStore(databasePath: currentSettings.wisprDatabasePath)
            diagnostics.isRunning = true
            diagnostics.lastTriggerSource = source
            diagnostics.lastOperationStartedAt = Date()
            diagnostics.lastMarkerRowID = afterRowID
            diagnostics.lastError = nil
            diagnostics.lastDonorClipboardMatches = nil
            diagnostics.lastAutoPasteEnabled = nil
            diagnostics.lastAutoPasteResult = nil
            setStatus("Waiting after row \(afterRowID)")
            appendLog("copy next started source=\(source) afterRowID=\(afterRowID)")

            let watcher = TranscriptWatcher(store: store, pollIntervalSeconds: currentSettings.pollIntervalSeconds)
            let row = try await watcher.waitForNext(after: afterRowID, timeoutSeconds: currentSettings.waitTimeoutSeconds)
            diagnostics.lastRowSeen = row
            setStatus("Copying row \(row.rowID)")
            appendLog("row found rowID=\(row.rowID) length=\(row.text.count)")
            let cleanupTargetApplication = cleanupTargetApplication ?? NSWorkspace.shared.frontmostApplication

            let donor = PersistentDonorApp(
                appPath: resolvedDonorAppPath(currentSettings),
                hiddenWindow: currentSettings.hiddenDonorEnabled
            )
            let clipboardText = ClipboardTextFormatter.appendTrailingSpace(row.text)
            let result = try donor.copyText(
                clipboardText,
                returnProcessIdentifier: cleanupTargetApplication?.processIdentifier
            )
            let clipboardMatches = result.readyContents.contains("clipboardMatches=yes")
            diagnostics.lastCopiedRowID = row.rowID
            diagnostics.lastCopiedLength = clipboardText.count
            diagnostics.lastDonorClipboardMatches = clipboardMatches
            diagnostics.lastDonorReadyAt = Date()
            diagnostics.lastDonorHandoffWaitSeconds = result.handoffWaitSeconds
            diagnostics.lastDonorStillFrontmost = result.donorStillFrontmost
            var autoPasteResult: RemoteInputAutomationResult?
            if clipboardMatches {
                if currentSettings.automaticPasteEnabled {
                    autoPasteResult = runAutoPasteIfEnabled(
                        settings: currentSettings,
                        targetApplication: cleanupTargetApplication
                    )
                } else {
                    runRemoteCleanupIfEnabled(
                        mode: currentSettings.remoteCleanupMode,
                        targetApplication: cleanupTargetApplication
                    )
                    autoPasteResult = runAutoPasteIfEnabled(
                        settings: currentSettings,
                        targetApplication: cleanupTargetApplication
                    )
                }
            }
            if clipboardMatches, currentSettings.automaticPasteEnabled, autoPasteResult?.didRun == true {
                setStatus("Paste sent row \(row.rowID)")
            } else {
                setStatus(clipboardMatches ? "Ready row \(row.rowID)" : "Copy verify failed")
            }
            appendLog("donor ready rowID=\(row.rowID) clipboardMatches=\(clipboardMatches) handoffWait=\(result.handoffWaitSeconds) donorStillFrontmost=\(result.donorStillFrontmost)")
        } catch {
            if Task.isCancelled {
                appendLog("copy next cancelled")
                return
            }
            let message = userFacingCopyError(error)
            diagnostics.lastError = message
            setStatus("Error: \(message)")
            appendLog("copy next error=\(message)")
        }
    }

    private func userFacingCopyError(_ error: Error) -> String {
        if case TranscriptWatcherError.timeout(let afterRowID) = error {
            return "Timed out waiting after row \(afterRowID). Confirm Wispr history storage is set to at least 24 hours."
        }

        return String(describing: error)
    }

    private func runRemoteCleanupIfEnabled(mode: RemoteCleanupMode, targetApplication: NSRunningApplication?) {
        let result = remoteCleanupController.cleanup(mode: mode, targetApplication: targetApplication)
        diagnostics.lastCleanupMode = mode
        diagnostics.lastCleanupResult = result.detail
        diagnostics.lastCleanupAt = Date()
        appendLog("remote cleanup mode=\(mode.rawValue) ran=\(result.didRun) detail=\"\(result.detail)\"")
    }

    private func runAutoPasteIfEnabled(settings: AppSettings, targetApplication: NSRunningApplication?) -> RemoteInputAutomationResult {
        let enabled = settings.automaticPasteEnabled
        diagnostics.lastAutoPasteEnabled = enabled
        diagnostics.lastAutoPasteAt = Date()

        guard enabled else {
            diagnostics.lastAutoPasteResult = "disabled"
            appendLog("auto paste disabled")
            return RemoteInputAutomationResult(didRun: false, detail: "disabled")
        }

        let result = remoteInputAutomationController.pasteIntoScreenSharing(
            targetApplication: targetApplication,
            activationDelaySeconds: settings.autoPasteDelaySeconds,
            cleanupMode: settings.remoteCleanupMode
        )
        diagnostics.lastCleanupMode = settings.remoteCleanupMode
        diagnostics.lastCleanupResult = result.cleanupDetail
        diagnostics.lastCleanupAt = Date()
        appendLog("remote cleanup combined mode=\(settings.remoteCleanupMode.rawValue) ran=\(result.cleanupDidRun) detail=\"\(result.cleanupDetail)\"")
        diagnostics.lastAutoPasteResult = result.detail
        appendLog("auto paste ran=\(result.didRun) detail=\"\(result.detail)\"")
        return result
    }

    private func runDatabaseCheck() async {
        defer {
            runningTask = nil
            diagnostics.isRunning = false
            diagnosticsWindowController?.refresh()
        }

        do {
            diagnostics.isRunning = true
            diagnostics.lastError = nil
            let store = WisprSQLiteTranscriptStore(databasePath: settings.wisprDatabasePath)
            let maxRowID = try store.maxRowID()
            diagnostics.lastDatabaseCheckAt = Date()
            diagnostics.lastDatabaseMaxRowID = maxRowID
            if maxRowID > 0 {
                setStatus("DB OK, max row \(maxRowID)")
                appendLog("db check ok maxRowID=\(maxRowID)")
            } else {
                setStatus("DB warning, max row 0")
                appendLog("db check warning maxRowID=0 reason=wispr-history-storage-may-be-disabled")
            }
        } catch {
            if Task.isCancelled {
                appendLog("db check cancelled")
                return
            }
            diagnostics.lastError = String(describing: error)
            setStatus("DB error: \(error)")
            appendLog("db check error=\(error)")
        }
    }

    private func setStatus(_ message: String) {
        readyTitleClearTimer?.invalidate()
        readyTitleClearTimer = nil
        lastStatus = message
        diagnostics.status = message
        let display = message.count > 64 ? String(message.prefix(61)) + "..." : message
        statusMenuItem.title = display
        statusItem.button?.title = statusTitle(for: message)
        scheduleReadyTitleClearIfNeeded(for: message)
        diagnosticsWindowController?.refresh()
    }

    private func scheduleReadyTitleClearIfNeeded(for message: String) {
        guard message.hasPrefix("Ready") || message.hasPrefix("Paste sent") else {
            return
        }

        readyTitleClearTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.lastStatus == message else {
                    return
                }
                self.statusItem.button?.title = "RW"
                self.readyTitleClearTimer = nil
            }
        }
    }

    private func loadSettings() {
        do {
            settings = try settingsStore.loadOrCreate(defaultSettings: Self.defaultAppSettings())
            appendLog("settings loaded or created schemaVersion=\(settings.settingsSchemaVersion)")
        } catch {
            settings = Self.defaultAppSettings()
            appendLog("settings load failed error=\(error)")
        }
    }

    private func saveSettings(_ newSettings: AppSettings) {
        do {
            try settingsStore.save(newSettings)
            settings = newSettings
            configureHotkeyTrigger()
            appendLog("settings saved")
            setStatus("Settings saved")
        } catch {
            appendLog("settings save error=\(error)")
            setStatus("Settings error: \(error)")
        }
    }

    private func resolvedDonorAppPath(_ settings: AppSettings) -> String {
        settings.donorAppPath.isEmpty ? Self.defaultDonorAppPath() : settings.donorAppPath
    }

    private static func defaultAppSettings() -> AppSettings {
        AppSettings(donorAppPath: defaultDonorAppPath())
    }

    private func configureHotkeyTrigger() {
        hotkeyTrigger?.stop()
        hotkeyTrigger = nil

        guard settings.automaticTriggerEnabled else {
            diagnostics.hotkeyEnabled = false
            appendLog("hotkey trigger disabled")
            return
        }

        diagnostics.hotkeyEnabled = true
        let trigger = HotkeyTrigger(
            minimumHoldSeconds: settings.hotkeyMinimumHoldSeconds,
            requiredModifiers: settings.hotkeyModifiers,
            onKeyDown: { [weak self] in
                self?.handleHotkeyDown()
            },
            onKeyUp: { [weak self] in
                self?.handleHotkeyUp()
            }
        )
        trigger.start()
        hotkeyTrigger = trigger
        appendLog("hotkey trigger enabled shortcut=\(HotkeyModifier.displayName(for: settings.hotkeyModifiers)) minimumHoldSeconds=\(settings.hotkeyMinimumHoldSeconds)")
    }

    private func handleHotkeyDown() {
        guard runningTask == nil else {
            appendLog("hotkey down ignored already running")
            return
        }

        guard !isManuallyDisabled else {
            hotkeyMarkerRowID = nil
            hotkeyTargetApplication = nil
            diagnostics.hotkeyMarkerRowID = nil
            diagnostics.lastSkippedReason = "manual disable is on"
            appendLog("hotkey down skipped reason=manual-disabled")
            return
        }

        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        guard frontmostApplication?.bundleIdentifier == Self.screenSharingBundleIdentifier else {
            let description = Self.describeApplication(frontmostApplication)
            hotkeyMarkerRowID = nil
            hotkeyTargetApplication = nil
            diagnostics.hotkeyMarkerRowID = nil
            diagnostics.lastSkippedReason = "frontmost app is not Screen Sharing: \(description)"
            appendLog("hotkey down skipped reason=not-screen-sharing frontmost=\"\(description)\"")
            return
        }

        do {
            let store = WisprSQLiteTranscriptStore(databasePath: settings.wisprDatabasePath)
            let marker = try store.maxRowID()
            hotkeyMarkerRowID = marker
            hotkeyTargetApplication = frontmostApplication
            diagnostics.hotkeyMarkerRowID = marker
            diagnostics.lastMarkerRowID = marker
            diagnostics.lastSkippedReason = nil
            appendLog("hotkey down markerRowID=\(marker)")
        } catch {
            hotkeyMarkerRowID = nil
            hotkeyTargetApplication = nil
            diagnostics.hotkeyMarkerRowID = nil
            diagnostics.lastError = String(describing: error)
            appendLog("hotkey down error=\(error)")
            setStatus("Hotkey error: \(error)")
        }
    }

    private func handleHotkeyUp() {
        guard runningTask == nil else {
            appendLog("hotkey up ignored already running")
            return
        }

        guard !isManuallyDisabled else {
            hotkeyMarkerRowID = nil
            hotkeyTargetApplication = nil
            diagnostics.hotkeyMarkerRowID = nil
            diagnostics.lastSkippedReason = "manual disable is on"
            appendLog("hotkey up skipped reason=manual-disabled")
            return
        }

        guard let marker = hotkeyMarkerRowID else {
            appendLog("hotkey up ignored no marker")
            return
        }

        hotkeyMarkerRowID = nil
        let cleanupTargetApplication = hotkeyTargetApplication
        hotkeyTargetApplication = nil
        diagnostics.hotkeyMarkerRowID = nil
        copyMenuItem.isEnabled = false
        runningTask = Task { [weak self] in
            await self?.runCopyNextTranscript(
                afterRowID: marker,
                source: "hotkey",
                cleanupTargetApplication: cleanupTargetApplication
            )
        }
    }

    private func makeDiagnosticsSnapshot() -> DiagnosticsSnapshot {
        var currentMaxRowID: Int64?
        var currentMaxRowError: String?

        do {
            let store = WisprSQLiteTranscriptStore(databasePath: settings.wisprDatabasePath)
            currentMaxRowID = try store.maxRowID()
        } catch {
            currentMaxRowError = String(describing: error)
        }

        var currentDiagnostics = diagnostics
        currentDiagnostics.isRunning = runningTask != nil
        currentDiagnostics.isManuallyDisabled = isManuallyDisabled
        currentDiagnostics.hotkeyEnabled = settings.automaticTriggerEnabled
        currentDiagnostics.hotkeyMarkerRowID = hotkeyMarkerRowID

        return DiagnosticsSnapshot(
            settings: settings,
            diagnostics: currentDiagnostics,
            currentMaxRowID: currentMaxRowID,
            currentMaxRowError: currentMaxRowError,
            donorAppPath: resolvedDonorAppPath(settings),
            logPath: logURL.path,
            appVersion: Self.bundleValue("CFBundleShortVersionString", defaultValue: "development"),
            appBuild: Self.bundleValue("CFBundleVersion", defaultValue: "development")
        )
    }

    private static func emptyDiagnosticsSnapshot() -> DiagnosticsSnapshot {
        DiagnosticsSnapshot(
            settings: AppSettings(),
            diagnostics: AppDiagnostics(status: "Diagnostics unavailable"),
            currentMaxRowID: nil,
            currentMaxRowError: "app delegate unavailable",
            donorAppPath: defaultDonorAppPath(),
            logPath: defaultLogURL().path,
            appVersion: bundleValue("CFBundleShortVersionString", defaultValue: "development"),
            appBuild: bundleValue("CFBundleVersion", defaultValue: "development")
        )
    }

    private func appendLog(_ message: String) {
        ensureLogDirectory()
        let line = "\(Self.timestamp()) \(message)\n"
        guard let data = line.data(using: .utf8) else {
            return
        }

        if FileManager.default.fileExists(atPath: logURL.path),
           let handle = try? FileHandle(forWritingTo: logURL) {
            defer {
                try? handle.close()
            }
            _ = try? handle.seekToEnd()
            _ = try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logURL, options: .atomic)
        }
    }

    private func ensureLogDirectory() {
        try? FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private func statusTitle(for message: String) -> String {
        if isManuallyDisabled || message == "Disabled" {
            return "RW Off"
        }
        if message.hasPrefix("Ready") {
            return "RW Ready"
        }
        if message.hasPrefix("Error")
            || message.localizedCaseInsensitiveContains("error")
            || message.localizedCaseInsensitiveContains("needs attention")
            || message.localizedCaseInsensitiveContains("failed") {
            return "RW Error"
        }
        if message == "Idle" || message == "Enabled" {
            return "RW"
        }
        if message.hasPrefix("DB OK")
            || message == "Settings saved"
            || message == "Reset"
            || message == "Health OK"
            || message == "Health OK with notes" {
            return "RW"
        }
        return "RW..."
    }

    private static var screenSharingBundleIdentifier: String {
        "com.apple.ScreenSharing"
    }

    private func updateManualDisableMenuItem() {
        manualDisableMenuItem.title = isManuallyDisabled ? "Enable Remote Wispr" : "Disable Remote Wispr"
    }

    private static func defaultDonorAppPath() -> String {
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            return bundleURL
                .deletingLastPathComponent()
                .appendingPathComponent("Remote Wispr Copy Donor.app")
                .path
        }

        return FileManager.default.currentDirectoryPath + "/.build/apps/Remote Wispr Copy Donor.app"
    }

    private static func describeApplication(_ application: NSRunningApplication?) -> String {
        guard let application else {
            return "none"
        }
        let name = application.localizedName ?? "unknown"
        let bundleIdentifier = application.bundleIdentifier ?? "unknown"
        return "\(name)[\(bundleIdentifier)]"
    }

    private static func defaultLogURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/RemoteWispr/menu-bar.log")
    }

    private static func defaultSettingsURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/RemoteWispr/settings.json")
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private static func bundleValue(_ key: String, defaultValue: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? defaultValue
    }
}

let app = NSApplication.shared
let delegate = RemoteWisprMenuBarApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
