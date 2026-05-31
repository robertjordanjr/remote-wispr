import AppKit
import Foundation
import RemoteWisprCore

struct RemoteInputAutomationResult {
    let didRun: Bool
    let detail: String
    let cleanupDidRun: Bool
    let cleanupDetail: String

    init(didRun: Bool, detail: String, cleanupDidRun: Bool = false, cleanupDetail: String = "disabled") {
        self.didRun = didRun
        self.detail = detail
        self.cleanupDidRun = cleanupDidRun
        self.cleanupDetail = cleanupDetail
    }
}

final class RemoteInputAutomationController {
    private static let screenSharingBundleIdentifier = "com.apple.ScreenSharing"
    private struct FocusWaitResult {
        let isFrontmost: Bool
        let elapsedSeconds: TimeInterval
        let frontmostApplication: NSRunningApplication?
    }

    func pasteIntoScreenSharing(
        targetApplication: NSRunningApplication?,
        activationDelaySeconds: TimeInterval = 0.35,
        cleanupMode: RemoteCleanupMode = .disabled
    ) -> RemoteInputAutomationResult {
        guard targetApplication?.bundleIdentifier == Self.screenSharingBundleIdentifier else {
            let name = targetApplication?.localizedName ?? "unknown"
            let bundleIdentifier = targetApplication?.bundleIdentifier ?? "unknown"
            return RemoteInputAutomationResult(
                didRun: false,
                detail: "skipped target=\(name) bundle=\(bundleIdentifier)",
                cleanupDetail: cleanupMode == .disabled ? "disabled" : "skipped target=\(name) bundle=\(bundleIdentifier)"
            )
        }

        let frontmostBeforeActivation = NSWorkspace.shared.frontmostApplication
        let wasAlreadyFrontmost = frontmostBeforeActivation?.processIdentifier == targetApplication?.processIdentifier
        let activated = wasAlreadyFrontmost ? true : targetApplication?.activate(options: [.activateIgnoringOtherApps]) ?? false
        let focusWaitLimitSeconds = wasAlreadyFrontmost ? 0 : max(activationDelaySeconds, 0.75)
        let focusWait = waitForFrontmost(
            targetApplication: targetApplication,
            timeoutSeconds: focusWaitLimitSeconds
        )
        let frontmostDescription = describe(focusWait.frontmostApplication)
        if !focusWait.isFrontmost {
            let detail = "activated=\(activated), alreadyFrontmost=\(wasAlreadyFrontmost), focusReady=false, frontmost=\(frontmostDescription), configuredDelay=\(activationDelaySeconds), focusWait=\(focusWait.elapsedSeconds), method=system-events-combined, no keys sent"
            return RemoteInputAutomationResult(
                didRun: false,
                detail: detail,
                cleanupDidRun: false,
                cleanupDetail: cleanupMode == .disabled ? "disabled" : detail
            )
        }

        let cleanupKeyCodes = keyCodes(for: cleanupMode)
        let cleanupDetail = cleanupDetail(for: cleanupMode)

        do {
            try SystemEventsAutomation.sendKeyCodesThenPaste(cleanupKeyCodes)
        } catch {
            let detail = String(describing: error)
            return RemoteInputAutomationResult(
                didRun: false,
                detail: detail,
                cleanupDidRun: false,
                cleanupDetail: cleanupMode == .disabled ? "disabled" : "method=system-events-combined, error=\(detail)"
            )
        }

        return RemoteInputAutomationResult(
            didRun: true,
            detail: "activated=\(activated), alreadyFrontmost=\(wasAlreadyFrontmost), focusReady=true, frontmost=\(frontmostDescription), configuredDelay=\(activationDelaySeconds), focusWait=\(focusWait.elapsedSeconds), method=system-events-combined, cleanup=\(cleanupMode.rawValue), sent command-v to Screen Sharing pid=\(targetApplication?.processIdentifier ?? -1)",
            cleanupDidRun: cleanupMode != .disabled,
            cleanupDetail: cleanupDetail
        )
    }

    private func waitForFrontmost(
        targetApplication: NSRunningApplication?,
        timeoutSeconds: TimeInterval
    ) -> FocusWaitResult {
        let start = Date()
        repeat {
            _ = targetApplication?.activate(options: [.activateIgnoringOtherApps])
            let frontmost = NSWorkspace.shared.frontmostApplication
            if frontmost?.processIdentifier == targetApplication?.processIdentifier {
                return FocusWaitResult(
                    isFrontmost: true,
                    elapsedSeconds: Date().timeIntervalSince(start),
                    frontmostApplication: frontmost
                )
            }

            if timeoutSeconds <= 0 {
                return FocusWaitResult(
                    isFrontmost: false,
                    elapsedSeconds: Date().timeIntervalSince(start),
                    frontmostApplication: frontmost
                )
            }

            Thread.sleep(forTimeInterval: 0.02)
        } while Date().timeIntervalSince(start) < timeoutSeconds

        return FocusWaitResult(
            isFrontmost: false,
            elapsedSeconds: Date().timeIntervalSince(start),
            frontmostApplication: NSWorkspace.shared.frontmostApplication
        )
    }

    private func keyCodes(for cleanupMode: RemoteCleanupMode) -> [CGKeyCode] {
        switch cleanupMode {
        case .disabled:
            []
        case .backspace:
            [51]
        case .backspaceThenSpace:
            [51, 49]
        }
    }

    private func cleanupDetail(for cleanupMode: RemoteCleanupMode) -> String {
        switch cleanupMode {
        case .disabled:
            "disabled"
        case .backspace:
            "method=system-events-combined, sent backspace"
        case .backspaceThenSpace:
            "method=system-events-combined, sent backspace then space"
        }
    }

    private func describe(_ application: NSRunningApplication?) -> String {
        guard let application else {
            return "none"
        }
        let name = application.localizedName ?? "unknown"
        let bundleIdentifier = application.bundleIdentifier ?? "unknown"
        return "\(name)[\(bundleIdentifier)]"
    }
}
