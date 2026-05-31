import AppKit
import Foundation

public struct FocusTarget: Equatable, Sendable {
    public let processIdentifier: pid_t
    public let bundleIdentifier: String?
    public let localizedName: String?

    public init(processIdentifier: pid_t, bundleIdentifier: String?, localizedName: String?) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
    }
}

public protocol FocusBroker {
    func captureFrontmostApplication() throws -> FocusTarget
    func activateDonor(bundleIdentifier: String) throws -> FocusTarget
    func returnFocus(to target: FocusTarget) throws
}

public enum FocusBrokerError: Error, Equatable, CustomStringConvertible {
    case noFrontmostApplication
    case donorApplicationNotFound(bundleIdentifier: String)
    case donorLaunchFailed(bundleIdentifier: String, message: String)
    case activationFailed(target: FocusTarget)
    case returnTargetNotFound(processIdentifier: pid_t)

    public var description: String {
        switch self {
        case .noFrontmostApplication:
            "No frontmost application was available to capture."
        case let .donorApplicationNotFound(bundleIdentifier):
            "Could not find donor application with bundle identifier \(bundleIdentifier)."
        case let .donorLaunchFailed(bundleIdentifier, message):
            "Could not launch donor application \(bundleIdentifier): \(message)"
        case let .activationFailed(target):
            "Could not activate \(target.localizedName ?? target.bundleIdentifier ?? String(target.processIdentifier))."
        case let .returnTargetNotFound(processIdentifier):
            "Could not find captured application with process ID \(processIdentifier)."
        }
    }
}

public final class SystemFocusBroker: FocusBroker {
    private let workspace: NSWorkspace
    private let settleDelaySeconds: TimeInterval

    public init(workspace: NSWorkspace = .shared, settleDelaySeconds: TimeInterval = 0.25) {
        self.workspace = workspace
        self.settleDelaySeconds = settleDelaySeconds
    }

    public func captureFrontmostApplication() throws -> FocusTarget {
        guard let app = workspace.frontmostApplication else {
            throw FocusBrokerError.noFrontmostApplication
        }

        return FocusTarget(app)
    }

    public func activateDonor(bundleIdentifier: String) throws -> FocusTarget {
        let app = try runningOrLaunchableApplication(bundleIdentifier: bundleIdentifier)
        try activate(app)
        return FocusTarget(app)
    }

    public func returnFocus(to target: FocusTarget) throws {
        guard let app = NSRunningApplication(processIdentifier: target.processIdentifier) else {
            throw FocusBrokerError.returnTargetNotFound(processIdentifier: target.processIdentifier)
        }

        try activate(app)
    }

    private func runningOrLaunchableApplication(bundleIdentifier: String) throws -> NSRunningApplication {
        if let running = workspace.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            return running
        }

        guard let appURL = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            throw FocusBrokerError.donorApplicationNotFound(bundleIdentifier: bundleIdentifier)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        let semaphore = DispatchSemaphore(value: 0)
        let result = LaunchResultBox()

        workspace.openApplication(at: appURL, configuration: configuration) { app, error in
            result.application = app
            result.error = error
            semaphore.signal()
        }

        let waitResult = semaphore.wait(timeout: .now() + 5)
        guard waitResult == .success, let launchedApplication = result.application else {
            let message = result.error.map { String(describing: $0) } ?? "launch timed out"
            throw FocusBrokerError.donorLaunchFailed(bundleIdentifier: bundleIdentifier, message: message)
        }

        return launchedApplication
    }

    private func activate(_ app: NSRunningApplication) throws {
        guard app.activate(options: [.activateIgnoringOtherApps]) else {
            throw FocusBrokerError.activationFailed(target: FocusTarget(app))
        }

        Thread.sleep(forTimeInterval: settleDelaySeconds)
    }
}

public final class MemoryFocusBroker: FocusBroker {
    public private(set) var capturedTarget: FocusTarget
    public private(set) var activatedDonorBundleIdentifier: String?
    public private(set) var returnedTarget: FocusTarget?

    private let donorTarget: FocusTarget

    public init(
        capturedTarget: FocusTarget = FocusTarget(processIdentifier: 100, bundleIdentifier: "com.apple.ScreenSharing", localizedName: "Screen Sharing"),
        donorTarget: FocusTarget = FocusTarget(processIdentifier: 200, bundleIdentifier: "com.remote-wispr.FocusDonor", localizedName: "Remote Wispr Focus Donor")
    ) {
        self.capturedTarget = capturedTarget
        self.donorTarget = donorTarget
    }

    public func captureFrontmostApplication() throws -> FocusTarget {
        capturedTarget
    }

    public func activateDonor(bundleIdentifier: String) throws -> FocusTarget {
        activatedDonorBundleIdentifier = bundleIdentifier
        return donorTarget
    }

    public func returnFocus(to target: FocusTarget) throws {
        returnedTarget = target
    }
}

private extension FocusTarget {
    init(_ app: NSRunningApplication) {
        self.init(
            processIdentifier: app.processIdentifier,
            bundleIdentifier: app.bundleIdentifier,
            localizedName: app.localizedName
        )
    }
}

private final class LaunchResultBox: @unchecked Sendable {
    var application: NSRunningApplication?
    var error: Error?
}
