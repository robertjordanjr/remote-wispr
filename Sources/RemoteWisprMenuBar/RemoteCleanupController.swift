import AppKit
import Foundation
import RemoteWisprCore

struct RemoteCleanupResult {
    let didRun: Bool
    let detail: String
}

final class RemoteCleanupController {
    private static let screenSharingBundleIdentifier = "com.apple.ScreenSharing"

    func cleanup(mode: RemoteCleanupMode, targetApplication: NSRunningApplication?) -> RemoteCleanupResult {
        guard mode != .disabled else {
            return RemoteCleanupResult(didRun: false, detail: "disabled")
        }

        guard targetApplication?.bundleIdentifier == Self.screenSharingBundleIdentifier else {
            let name = targetApplication?.localizedName ?? "unknown"
            let bundleIdentifier = targetApplication?.bundleIdentifier ?? "unknown"
            return RemoteCleanupResult(
                didRun: false,
                detail: "skipped target=\(name) bundle=\(bundleIdentifier)"
            )
        }

        let activated = targetApplication?.activate(options: [.activateIgnoringOtherApps]) ?? false
        Thread.sleep(forTimeInterval: 0.15)

        do {
            switch mode {
            case .disabled:
                return RemoteCleanupResult(didRun: false, detail: "disabled")
            case .backspace:
                try SystemEventsAutomation.sendKeyCode(CleanupKey.delete.virtualKey)
                return RemoteCleanupResult(didRun: true, detail: "activated=\(activated), method=system-events, sent backspace to Screen Sharing pid=\(targetApplication?.processIdentifier ?? -1)")
            case .backspaceThenSpace:
                try SystemEventsAutomation.sendKeyCode(CleanupKey.delete.virtualKey)
                Thread.sleep(forTimeInterval: 0.15)
                try SystemEventsAutomation.sendKeyCode(CleanupKey.space.virtualKey)
                return RemoteCleanupResult(didRun: true, detail: "activated=\(activated), method=system-events, sent backspace then space to Screen Sharing pid=\(targetApplication?.processIdentifier ?? -1)")
            }
        } catch {
            return RemoteCleanupResult(didRun: false, detail: "activated=\(activated), method=system-events, error=\(error)")
        }
    }
}

private enum CleanupKey {
    case delete
    case space

    var virtualKey: CGKeyCode {
        switch self {
        case .delete:
            51
        case .space:
            49
        }
    }
}
