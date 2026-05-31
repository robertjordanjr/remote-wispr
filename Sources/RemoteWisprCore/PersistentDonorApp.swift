import AppKit
import Foundation

public enum PersistentDonorAppError: Error, Equatable, CustomStringConvertible {
    case appNotFound(path: String)
    case donorAlreadyRunning(bundleIdentifier: String, processIDs: [pid_t])
    case launchFailed(status: Int32)
    case readyTimeout(path: String)

    public var description: String {
        switch self {
        case let .appNotFound(path):
            "Persistent donor app not found at \(path)."
        case let .donorAlreadyRunning(bundleIdentifier, processIDs):
            "Persistent donor app \(bundleIdentifier) is already running with process IDs \(processIDs). Close it before retrying."
        case let .launchFailed(status):
            "Persistent donor app launch failed with status \(status)."
        case let .readyTimeout(path):
            "Persistent donor app did not report ready at \(path)."
        }
    }
}

public struct PersistentDonorAppResult: Equatable {
    public let textFile: String
    public let readyFile: String
    public let readyContents: String
    public let handoffWaitSeconds: TimeInterval
    public let donorStillFrontmost: Bool

    public init(
        textFile: String,
        readyFile: String,
        readyContents: String,
        handoffWaitSeconds: TimeInterval = 0,
        donorStillFrontmost: Bool = false
    ) {
        self.textFile = textFile
        self.readyFile = readyFile
        self.readyContents = readyContents
        self.handoffWaitSeconds = handoffWaitSeconds
        self.donorStillFrontmost = donorStillFrontmost
    }
}

public final class PersistentDonorApp {
    public static let bundleIdentifier = "com.remote-wispr.CopyDonor"

    private let appPath: String
    private let fileManager: FileManager
    private let hiddenWindow: Bool

    public init(
        appPath: String = "\(FileManager.default.homeDirectoryForCurrentUser.path)/Applications/Remote Wispr Copy Donor.app",
        fileManager: FileManager = .default,
        hiddenWindow: Bool = true
    ) {
        self.appPath = appPath
        self.fileManager = fileManager
        self.hiddenWindow = hiddenWindow
    }

    public func copyText(
        _ text: String,
        timeoutSeconds: TimeInterval = 5,
        returnProcessIdentifier: pid_t? = nil
    ) throws -> PersistentDonorAppResult {
        guard fileManager.fileExists(atPath: appPath) else {
            throw PersistentDonorAppError.appNotFound(path: appPath)
        }

        try ensureNoRunningDonors()

        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("remote-wispr-donor-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let textURL = directory.appendingPathComponent("transcript.txt")
        let readyURL = directory.appendingPathComponent("ready.txt")
        try text.write(to: textURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [
            "-n",
            appPath,
            "--args",
            "--text-file",
            textURL.path,
            "--ready-file",
            readyURL.path
        ]
        if hiddenWindow {
            process.arguments?.append("--hidden-window")
        }
        if let returnProcessIdentifier {
            process.arguments?.append("--return-pid")
            process.arguments?.append(String(returnProcessIdentifier))
        }
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw PersistentDonorAppError.launchFailed(status: process.terminationStatus)
        }

        let readyContents = try waitForReadyFile(at: readyURL, timeoutSeconds: timeoutSeconds)
        let handoff = waitForDonorHandoff(timeoutSeconds: 2)
        return PersistentDonorAppResult(
            textFile: textURL.path,
            readyFile: readyURL.path,
            readyContents: readyContents,
            handoffWaitSeconds: handoff.elapsedSeconds,
            donorStillFrontmost: handoff.donorStillFrontmost
        )
    }

    private func waitForReadyFile(at url: URL, timeoutSeconds: TimeInterval) throws -> String {
        let deadline = Date().addingTimeInterval(timeoutSeconds)

        while Date() < deadline {
            if fileManager.fileExists(atPath: url.path),
               let contents = try? String(contentsOf: url, encoding: .utf8) {
                return contents
            }

            Thread.sleep(forTimeInterval: 0.05)
        }

        throw PersistentDonorAppError.readyTimeout(path: url.path)
    }

    private func ensureNoRunningDonors() throws {
        let runningDonors = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier)
        if !runningDonors.isEmpty {
            throw PersistentDonorAppError.donorAlreadyRunning(
                bundleIdentifier: Self.bundleIdentifier,
                processIDs: runningDonors.map(\.processIdentifier)
            )
        }
    }

    private func waitForDonorHandoff(timeoutSeconds: TimeInterval) -> (elapsedSeconds: TimeInterval, donorStillFrontmost: Bool) {
        let start = Date()

        repeat {
            let frontmost = NSWorkspace.shared.frontmostApplication
            let donorIsFrontmost = isDonorApplication(frontmost)
            let runningDonors = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier)

            if !donorIsFrontmost && runningDonors.isEmpty {
                return (Date().timeIntervalSince(start), false)
            }

            Thread.sleep(forTimeInterval: 0.02)
        } while Date().timeIntervalSince(start) < timeoutSeconds

        return (
            Date().timeIntervalSince(start),
            isDonorApplication(NSWorkspace.shared.frontmostApplication)
        )
    }

    private func isDonorApplication(_ application: NSRunningApplication?) -> Bool {
        application?.bundleIdentifier == Self.bundleIdentifier
            || application?.localizedName == "Remote Wispr Copy Donor"
    }
}
