import Foundation
import RemoteWisprCore

enum BaselineHealthState {
    case ok
    case warning
    case failure

    var blocksBaseline: Bool {
        self == .failure
    }

    var statusText: String {
        switch self {
        case .ok:
            "ok"
        case .warning:
            "warning"
        case .failure:
            "needs attention"
        }
    }
}

struct BaselineHealthItem {
    let name: String
    let state: BaselineHealthState
    let detail: String

    var statusText: String {
        state.statusText
    }
}

struct BaselineHealthReport {
    let checkedAt: Date
    let items: [BaselineHealthItem]

    var passed: Bool {
        items.allSatisfy { !$0.state.blocksBaseline }
    }

    var statusText: String {
        if items.contains(where: { $0.state == .failure }) {
            return "needs attention"
        }
        if items.contains(where: { $0.state == .warning }) {
            return "ok with notes"
        }
        return "ok"
    }

    func summaryLines() -> [String] {
        var lines = [
            "Baseline health: \(statusText)",
            "Last baseline health check: \(format(checkedAt))"
        ]

        for item in items {
            lines.append("- \(item.name): \(item.statusText) - \(item.detail)")
        }

        return lines
    }

    private func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

final class BaselineHealthChecker {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func run(
        settings: AppSettings,
        resolvedDonorAppPath: String,
        settingsPath: String,
        appVersion: String,
        appBuild: String
    ) -> BaselineHealthReport {
        var items: [BaselineHealthItem] = []

        items.append(checkAppVersion(version: appVersion, build: appBuild))
        items.append(checkSettingsFile(path: settingsPath))
        items.append(checkSettingsSchema(settings.settingsSchemaVersion))
        items.append(checkWisprDatabase(path: settings.wisprDatabasePath))
        items.append(checkDonorApp(path: resolvedDonorAppPath))
        items.append(checkCodeSigning())
        items.append(checkWisprShortcutTrigger(settings))
        items.append(checkAccessibilityPermission())
        items.append(checkRemoteCleanup(settings.remoteCleanupMode))
        items.append(checkAutoPaste(settings))
        items.append(checkTimingSettings(settings))

        return BaselineHealthReport(checkedAt: Date(), items: items)
    }

    private func checkAppVersion(version: String, build: String) -> BaselineHealthItem {
        let hasVersion = !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasBuild = !build.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return BaselineHealthItem(
            name: "App version",
            state: hasVersion && hasBuild ? .ok : .failure,
            detail: "\(version) (\(build))"
        )
    }

    private func checkSettingsFile(path: String) -> BaselineHealthItem {
        let exists = fileManager.fileExists(atPath: path)
        let readable = fileManager.isReadableFile(atPath: path)
        let detail = exists ? path : "not found at \(path)"

        return BaselineHealthItem(
            name: "Settings file",
            state: exists && readable ? .ok : .failure,
            detail: readable ? detail : "\(detail), not readable"
        )
    }

    private func checkSettingsSchema(_ version: Int) -> BaselineHealthItem {
        BaselineHealthItem(
            name: "Settings schema",
            state: version == AppSettings.currentSchemaVersion ? .ok : .failure,
            detail: "\(version)"
        )
    }

    private func checkWisprDatabase(path: String) -> BaselineHealthItem {
        guard fileManager.fileExists(atPath: path) else {
            return BaselineHealthItem(
                name: "Wispr DB read-only query",
                state: .failure,
                detail: "not found at \(path)"
            )
        }

        guard fileManager.isReadableFile(atPath: path) else {
            return BaselineHealthItem(
                name: "Wispr DB read-only query",
                state: .failure,
                detail: "not readable at \(path)"
            )
        }

        do {
            let maxRowID = try WisprSQLiteTranscriptStore(databasePath: path).maxRowID()
            return BaselineHealthItem(
                name: "Wispr DB read-only query",
                state: maxRowID > 0 ? .ok : .warning,
                detail: maxRowID > 0
                    ? "max row \(maxRowID)"
                    : "max row 0; confirm Wispr history storage is set to at least 24 hours and dictate once"
            )
        } catch {
            return BaselineHealthItem(
                name: "Wispr DB read-only query",
                state: .failure,
                detail: String(describing: error)
            )
        }
    }

    private func checkDonorApp(path: String) -> BaselineHealthItem {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: path, isDirectory: &isDirectory)

        return BaselineHealthItem(
            name: "Copy donor app",
            state: exists && isDirectory.boolValue ? .ok : .failure,
            detail: exists ? path : "not found at \(path)"
        )
    }

    private func checkCodeSigning() -> BaselineHealthItem {
        let status = CodeSigningDiagnostics.currentAppStatus()
        let stableSignature = status.signature != "adhoc"
        let matchingIdentifier = status.identifier == "com.remote-wispr.MenuBar"
        let passed = status.verified && stableSignature && matchingIdentifier

        return BaselineHealthItem(
            name: "Code signing",
            state: passed ? .ok : .warning,
            detail: passed
                ? status.summary
                : "\(status.summary); run make setup-local-signing then make install-local"
        )
    }

    private func checkWisprShortcutTrigger(_ settings: AppSettings) -> BaselineHealthItem {
        BaselineHealthItem(
            name: "Wispr shortcut trigger",
            state: settings.automaticTriggerEnabled ? .ok : .failure,
            detail: settings.automaticTriggerEnabled
                ? "enabled, \(HotkeyModifier.displayName(for: settings.hotkeyModifiers))"
                : "disabled"
        )
    }

    private func checkRemoteCleanup(_ mode: RemoteCleanupMode) -> BaselineHealthItem {
        BaselineHealthItem(
            name: "Remote cleanup",
            state: .ok,
            detail: mode.displayName
        )
    }

    private func checkAccessibilityPermission() -> BaselineHealthItem {
        let trusted = AccessibilityPermission.isTrusted(prompt: false)
        return BaselineHealthItem(
            name: "Accessibility permission",
            state: trusted ? .ok : .warning,
            detail: trusted ? "enabled" : "not enabled for Remote Wispr; cleanup and auto-paste cannot send keystrokes"
        )
    }

    private func checkAutoPaste(_ settings: AppSettings) -> BaselineHealthItem {
        let validDelay = settings.autoPasteDelaySeconds >= 0
        let enabledDetail = settings.automaticPasteEnabled ? "enabled" : "disabled"
        return BaselineHealthItem(
            name: "Auto paste",
            state: validDelay ? .ok : .failure,
            detail: "\(enabledDetail), delay \(settings.autoPasteDelaySeconds)"
        )
    }

    private func checkTimingSettings(_ settings: AppSettings) -> BaselineHealthItem {
        let passed = settings.waitTimeoutSeconds > 0
            && settings.pollIntervalSeconds > 0
            && settings.hotkeyMinimumHoldSeconds >= 0
            && settings.autoPasteDelaySeconds >= 0

        return BaselineHealthItem(
            name: "Timing settings",
            state: passed ? .ok : .failure,
            detail: "timeout \(settings.waitTimeoutSeconds), poll \(settings.pollIntervalSeconds), min hold \(settings.hotkeyMinimumHoldSeconds), paste delay \(settings.autoPasteDelaySeconds)"
        )
    }
}
