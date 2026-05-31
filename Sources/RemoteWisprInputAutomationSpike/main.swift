import AppKit
import Darwin
import Foundation
import RemoteWisprCore

private enum SpikeError: Error, CustomStringConvertible {
    case missingArgument(String)
    case unknownCommand(String)
    case unknownMethod(String)
    case unknownKey(String)
    case screenSharingNotFrontmost(String)
    case noFrontmostApplication
    case eventCreationFailed(String)
    case appleScriptFailed(String)

    var description: String {
        switch self {
        case .missingArgument(let name):
            "missing argument \(name)"
        case .unknownCommand(let command):
            "unknown command \(command)"
        case .unknownMethod(let method):
            "unknown method \(method)"
        case .unknownKey(let key):
            "unknown key \(key)"
        case .screenSharingNotFrontmost(let actual):
            "Screen Sharing is not frontmost; frontmost is \(actual)"
        case .noFrontmostApplication:
            "no frontmost application"
        case .eventCreationFailed(let detail):
            "could not create keyboard event: \(detail)"
        case .appleScriptFailed(let detail):
            "AppleScript failed: \(detail)"
        }
    }
}

private enum InputMethod: String {
    case hid
    case hidModifiers = "hid-modifiers"
    case pid
    case commandV = "command-v"
    case commandVKeys = "command-v-keys"
    case menuPaste = "menu-paste"
    case systemEvents = "system-events"
    case unicode
}

private enum ClipboardSource: String {
    case local
    case donor
}

private enum CleanupSequence: String {
    case none
    case backspace
    case backspaceSpace = "backspace-space"
}

private enum SpikeKey: String {
    case v
    case x
    case space
    case delete
    case forwardDelete = "forward-delete"
    case left
    case right
    case `return`

    var virtualKey: CGKeyCode {
        switch self {
        case .v:
            9
        case .x:
            7
        case .space:
            49
        case .delete:
            51
        case .forwardDelete:
            117
        case .left:
            123
        case .right:
            124
        case .return:
            36
        }
    }
}

@main
struct RemoteWisprInputAutomationSpike {
    private static let screenSharingBundleIdentifier = "com.apple.ScreenSharing"

    static func main() {
        do {
            try run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            fputs("error: \(error)\n\n", stderr)
            printUsage()
            Darwin.exit(1)
        }
    }

    private static func run(arguments: [String]) throws {
        guard let command = arguments.first else {
            throw SpikeError.missingArgument("command")
        }

        let options = Options(arguments: Array(arguments.dropFirst()))

        switch command {
        case "target-info":
            waitForCaptureDelay(options)
            printTargetInfo()
        case "send-key":
            let keyName = try options.value(for: "--key")
            guard let key = SpikeKey(rawValue: keyName) else {
                throw SpikeError.unknownKey(keyName)
            }
            let method = try parseMethod(options.valueOrDefault(for: "--method", defaultValue: "hid"))
            waitForCaptureDelay(options)
            let target = try requireScreenSharingFrontmost()
            try sendKey(key, method: method, target: target)
            printResult(action: "send-key", method: method, target: target, detail: "key=\(key.rawValue)")
        case "paste-fixed":
            let method = try parseMethod(options.valueOrDefault(for: "--method", defaultValue: "command-v"))
            let text = options.valueOrDefault(for: "--text", defaultValue: "REMOTE_WISPR_INPUT_TEST")
            waitForCaptureDelay(options)
            let target = try requireScreenSharingFrontmost()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            try paste(method: method, target: target)
            printResult(action: "paste-fixed", method: method, target: target, detail: "textLength=\(text.count)")
        case "cleanup-paste-fixed":
            let cleanupRawValue = options.valueOrDefault(for: "--cleanup", defaultValue: "backspace-space")
            guard let cleanup = CleanupSequence(rawValue: cleanupRawValue) else {
                throw SpikeError.unknownMethod(cleanupRawValue)
            }
            let cleanupMethod = try parseMethod(options.valueOrDefault(for: "--cleanup-method", defaultValue: "system-events"))
            let pasteMethod = try parseMethod(options.valueOrDefault(for: "--paste-method", defaultValue: "system-events"))
            let clipboardRawValue = options.valueOrDefault(for: "--clipboard", defaultValue: "donor")
            guard let clipboard = ClipboardSource(rawValue: clipboardRawValue) else {
                throw SpikeError.unknownMethod(clipboardRawValue)
            }
            let text = options.valueOrDefault(for: "--text", defaultValue: "REMOTE_WISPR_CLEANUP_PASTE_TEST")
            let donorAppPath = options.valueOrDefault(
                for: "--donor-app",
                defaultValue: "\(FileManager.default.homeDirectoryForCurrentUser.path)/Applications/Remote Wispr Copy Donor.app"
            )
            let donorTimeout = Double(options.valueOrDefault(for: "--donor-timeout", defaultValue: "5")) ?? 5
            let postClipboardDelay = Double(options.valueOrDefault(for: "--post-clipboard-delay", defaultValue: "0.2")) ?? 0.2
            let betweenDelay = Double(options.valueOrDefault(for: "--between-delay", defaultValue: "0.15")) ?? 0.15
            waitForCaptureDelay(options)
            let target = try requireScreenSharingFrontmost()
            let clipboardDetail = try setClipboard(
                text,
                source: clipboard,
                donorAppPath: donorAppPath,
                donorTimeout: donorTimeout
            )
            if postClipboardDelay > 0 {
                Thread.sleep(forTimeInterval: postClipboardDelay)
            }
            let cleanupDetail = try runCleanup(cleanup, method: cleanupMethod, target: target, betweenDelay: betweenDelay)
            if betweenDelay > 0 {
                Thread.sleep(forTimeInterval: betweenDelay)
            }
            try paste(method: pasteMethod, target: target)
            printResult(
                action: "cleanup-paste-fixed",
                method: pasteMethod,
                target: target,
                detail: "textLength=\(text.count) clipboard=\(clipboard.rawValue) \(clipboardDetail) cleanup=\(cleanup.rawValue) cleanupMethod=\(cleanupMethod.rawValue) cleanupDetail=\"\(cleanupDetail)\" pasteMethod=\(pasteMethod.rawValue)"
            )
        case "type-fixed":
            let method = try parseMethod(options.valueOrDefault(for: "--method", defaultValue: "hid"))
            let text = options.valueOrDefault(for: "--text", defaultValue: "Remote Wispr type test.")
            let interval = Double(options.valueOrDefault(for: "--interval", defaultValue: "0.02")) ?? 0.02
            waitForCaptureDelay(options)
            let target = try requireScreenSharingFrontmost()
            try typeText(text, method: method, target: target, interval: interval)
            printResult(action: "type-fixed", method: method, target: target, detail: "textLength=\(text.count)")
        case "donor-paste-fixed":
            let text = options.valueOrDefault(for: "--text", defaultValue: "REMOTE_WISPR_DONOR_PASTE_TEST")
            let donorAppPath = options.valueOrDefault(
                for: "--donor-app",
                defaultValue: "\(FileManager.default.homeDirectoryForCurrentUser.path)/Applications/Remote Wispr Copy Donor.app"
            )
            let donorTimeout = Double(options.valueOrDefault(for: "--donor-timeout", defaultValue: "5")) ?? 5
            let postDonorDelay = Double(options.valueOrDefault(for: "--post-donor-delay", defaultValue: "0.2")) ?? 0.2
            waitForCaptureDelay(options)
            let target = try requireScreenSharingFrontmost()
            let donor = PersistentDonorApp(appPath: donorAppPath, hiddenWindow: true)
            let result = try donor.copyText(text, timeoutSeconds: donorTimeout)
            print("Persistent donor result:")
            print(result.readyContents.trimmingCharacters(in: .whitespacesAndNewlines))
            if postDonorDelay > 0 {
                Thread.sleep(forTimeInterval: postDonorDelay)
            }
            try paste(method: .commandVKeys, target: target)
            printResult(
                action: "donor-paste-fixed",
                method: .commandVKeys,
                target: target,
                detail: "textLength=\(text.count) donorApp=\(donorAppPath)"
            )
        default:
            throw SpikeError.unknownCommand(command)
        }
    }

    private static func parseMethod(_ rawValue: String) throws -> InputMethod {
        guard let method = InputMethod(rawValue: rawValue) else {
            throw SpikeError.unknownMethod(rawValue)
        }
        return method
    }

    private static func waitForCaptureDelay(_ options: Options) {
        let seconds = Double(options.valueOrDefault(for: "--capture-delay", defaultValue: "0")) ?? 0
        guard seconds > 0 else {
            return
        }

        print("Capturing Screen Sharing target in \(seconds) seconds...")
        fflush(stdout)
        Thread.sleep(forTimeInterval: seconds)
    }

    private static func printTargetInfo() {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            print("Frontmost app: none")
            return
        }

        print("Frontmost app: \(describe(app))")
        print("Screen Sharing frontmost: \(app.bundleIdentifier == screenSharingBundleIdentifier ? "yes" : "no")")
    }

    private static func requireScreenSharingFrontmost() throws -> NSRunningApplication {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            throw SpikeError.noFrontmostApplication
        }

        guard app.bundleIdentifier == screenSharingBundleIdentifier else {
            throw SpikeError.screenSharingNotFrontmost(describe(app))
        }

        return app
    }

    private static func sendKey(_ key: SpikeKey, method: InputMethod, target: NSRunningApplication) throws {
        switch method {
        case .hid:
            try postKey(key.virtualKey, flags: [], target: nil)
        case .hidModifiers:
            try postKeyWithExplicitModifiers(key.virtualKey, flags: [], target: nil)
        case .pid:
            try postKey(key.virtualKey, flags: [], target: target)
        case .systemEvents:
            try sendSystemEventsKeyCode(key.virtualKey)
        case .commandV, .commandVKeys, .menuPaste, .unicode:
            throw SpikeError.unknownMethod(method.rawValue)
        }
    }

    private static func paste(method: InputMethod, target: NSRunningApplication) throws {
        switch method {
        case .commandV:
            try postKey(9, flags: .maskCommand, target: nil)
        case .commandVKeys:
            try postKeyWithExplicitModifiers(9, flags: .maskCommand, target: nil)
        case .pid:
            try postKey(9, flags: .maskCommand, target: target)
        case .menuPaste:
            try clickScreenSharingPasteMenu()
        case .systemEvents:
            try sendSystemEventsPaste()
        case .hid, .hidModifiers, .unicode:
            throw SpikeError.unknownMethod(method.rawValue)
        }
    }

    private static func setClipboard(
        _ text: String,
        source: ClipboardSource,
        donorAppPath: String,
        donorTimeout: TimeInterval
    ) throws -> String {
        switch source {
        case .local:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return "localPasteboardLength=\(text.count)"
        case .donor:
            let donor = PersistentDonorApp(appPath: donorAppPath, hiddenWindow: true)
            let result = try donor.copyText(text, timeoutSeconds: donorTimeout)
            print("Persistent donor result:")
            print(result.readyContents.trimmingCharacters(in: .whitespacesAndNewlines))
            return "donorApp=\(donorAppPath)"
        }
    }

    private static func runCleanup(
        _ cleanup: CleanupSequence,
        method: InputMethod,
        target: NSRunningApplication,
        betweenDelay: TimeInterval
    ) throws -> String {
        switch cleanup {
        case .none:
            return "none"
        case .backspace:
            try sendKey(.delete, method: method, target: target)
            return "delete"
        case .backspaceSpace:
            try sendKey(.delete, method: method, target: target)
            if betweenDelay > 0 {
                Thread.sleep(forTimeInterval: betweenDelay)
            }
            try sendKey(.space, method: method, target: target)
            return "delete,space"
        }
    }

    private static func typeText(
        _ text: String,
        method: InputMethod,
        target: NSRunningApplication,
        interval: TimeInterval
    ) throws {
        switch method {
        case .hid, .hidModifiers, .pid:
            for character in text {
                let stroke = try KeyStroke(character: character)
                if method == .hidModifiers {
                    try postKeyWithExplicitModifiers(stroke.virtualKey, flags: stroke.flags, target: nil)
                } else {
                    try postKey(stroke.virtualKey, flags: stroke.flags, target: method == .pid ? target : nil)
                }
                if interval > 0 {
                    Thread.sleep(forTimeInterval: interval)
                }
            }
        case .unicode:
            for scalar in text.unicodeScalars {
                try postUnicodeScalar(scalar)
                if interval > 0 {
                    Thread.sleep(forTimeInterval: interval)
                }
            }
        case .commandV, .commandVKeys, .menuPaste, .systemEvents:
            throw SpikeError.unknownMethod(method.rawValue)
        }
    }

    private static func postKeyWithExplicitModifiers(
        _ virtualKey: CGKeyCode,
        flags: CGEventFlags,
        target: NSRunningApplication?
    ) throws {
        let modifierKeys = modifierVirtualKeys(for: flags)
        for modifierKey in modifierKeys {
            try postModifierKey(modifierKey, keyDown: true, target: target)
        }
        try postKey(virtualKey, flags: flags, target: target)
        for modifierKey in modifierKeys.reversed() {
            try postModifierKey(modifierKey, keyDown: false, target: target)
        }
    }

    private static func postModifierKey(
        _ virtualKey: CGKeyCode,
        keyDown: Bool,
        target: NSRunningApplication?
    ) throws {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: keyDown) else {
            throw SpikeError.eventCreationFailed("modifierVirtualKey=\(virtualKey)")
        }

        if let processIdentifier = target?.processIdentifier {
            event.postToPid(processIdentifier)
        } else {
            event.post(tap: .cghidEventTap)
        }
    }

    private static func modifierVirtualKeys(for flags: CGEventFlags) -> [CGKeyCode] {
        var keys: [CGKeyCode] = []
        if flags.contains(.maskCommand) {
            keys.append(55)
        }
        if flags.contains(.maskShift) {
            keys.append(56)
        }
        return keys
    }

    private static func postKey(
        _ virtualKey: CGKeyCode,
        flags: CGEventFlags,
        target: NSRunningApplication?
    ) throws {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false) else {
            throw SpikeError.eventCreationFailed("virtualKey=\(virtualKey)")
        }

        keyDown.flags = flags
        keyUp.flags = flags

        if let processIdentifier = target?.processIdentifier {
            keyDown.postToPid(processIdentifier)
            keyUp.postToPid(processIdentifier)
        } else {
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }

    private static func postUnicodeScalar(_ scalar: Unicode.Scalar) throws {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            throw SpikeError.eventCreationFailed("unicodeScalar=\(scalar)")
        }

        var codeUnit = UniChar(scalar.value)
        keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &codeUnit)
        keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &codeUnit)
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private static func clickScreenSharingPasteMenu() throws {
        let script = """
        tell application "System Events"
            tell process "Screen Sharing"
                click menu item "Paste" of menu "Edit" of menu bar 1
            end tell
        end tell
        """

        var errorInfo: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            throw SpikeError.appleScriptFailed("could not compile script")
        }

        appleScript.executeAndReturnError(&errorInfo)
        if let errorInfo {
            throw SpikeError.appleScriptFailed("\(errorInfo)")
        }
    }

    private static func sendSystemEventsKeyCode(_ keyCode: CGKeyCode) throws {
        let script = """
        tell application "Screen Sharing" to activate
        delay 0.15
        tell application "System Events"
            key code \(keyCode)
        end tell
        """
        try runAppleScript(script)
    }

    private static func sendSystemEventsPaste() throws {
        let script = """
        tell application "Screen Sharing" to activate
        delay 0.15
        tell application "System Events"
            keystroke "v" using command down
        end tell
        """
        try runAppleScript(script)
    }

    private static func runAppleScript(_ source: String) throws {
        var errorInfo: NSDictionary?
        guard let appleScript = NSAppleScript(source: source) else {
            throw SpikeError.appleScriptFailed("could not compile script")
        }

        appleScript.executeAndReturnError(&errorInfo)
        if let errorInfo {
            throw SpikeError.appleScriptFailed("\(errorInfo)")
        }
    }

    private static func printResult(
        action: String,
        method: InputMethod,
        target: NSRunningApplication,
        detail: String
    ) {
        print("Remote Wispr input automation spike")
        print("Action: \(action)")
        print("Method: \(method.rawValue)")
        print("Target: \(describe(target))")
        print("Detail: \(detail)")
        print("Posted: yes")
        print("Observe the remote text field and record whether it changed correctly.")
    }

    private static func describe(_ app: NSRunningApplication) -> String {
        let name = app.localizedName ?? "unknown"
        let bundleIdentifier = app.bundleIdentifier ?? "unknown"
        return "\(name) [\(bundleIdentifier)] pid=\(app.processIdentifier)"
    }

    private static func printUsage() {
        print(
            """
            Remote Wispr input automation spike

            Commands:
              target-info [--capture-delay S]
                  Print the current frontmost app. Run this after focusing the remote text box.

              send-key --key v|x|space|delete|forward-delete|left|right|return --method hid|hid-modifiers|pid|system-events [--capture-delay S]
                  Send one fixed key to Screen Sharing. Default method: hid.

              paste-fixed --method command-v|command-v-keys|pid|menu-paste|system-events [--text TEXT] [--capture-delay S]
                  Put fixed text on the local pasteboard, then attempt to paste it into Screen Sharing.

              cleanup-paste-fixed [--clipboard local|donor] [--cleanup none|backspace|backspace-space] [--cleanup-method hid|hid-modifiers|pid|system-events] [--paste-method command-v|command-v-keys|pid|menu-paste|system-events] [--text TEXT] [--capture-delay S]
                  Set fixed clipboard text, optionally clean leaked input, then attempt to paste into Screen Sharing.

              type-fixed --method hid|hid-modifiers|pid|unicode [--text TEXT] [--interval S] [--capture-delay S]
                  Type fixed text into Screen Sharing without using the pasteboard.

              donor-paste-fixed [--text TEXT] [--donor-app PATH] [--donor-timeout S] [--post-donor-delay S] [--capture-delay S]
                  Use the persistent donor app to sync fixed text, then send explicit Command+V keys.

            Notes:
              Screen Sharing must be frontmost.
              The process running this command needs macOS Accessibility permission.
              This spike does not read Wispr or touch Remote Wispr settings.
              Donor commands launch only the configured Remote Wispr Copy Donor app.
            """
        )
    }
}

private struct KeyStroke {
    let virtualKey: CGKeyCode
    let flags: CGEventFlags

    init(character: Character) throws {
        guard let value = Self.map[character] else {
            throw SpikeError.unknownKey(String(character))
        }
        self.virtualKey = value.virtualKey
        self.flags = value.flags
    }

    private static let shift: CGEventFlags = .maskShift

    private static let map: [Character: (virtualKey: CGKeyCode, flags: CGEventFlags)] = [
        "a": (0, []), "b": (11, []), "c": (8, []), "d": (2, []), "e": (14, []), "f": (3, []),
        "g": (5, []), "h": (4, []), "i": (34, []), "j": (38, []), "k": (40, []), "l": (37, []),
        "m": (46, []), "n": (45, []), "o": (31, []), "p": (35, []), "q": (12, []), "r": (15, []),
        "s": (1, []), "t": (17, []), "u": (32, []), "v": (9, []), "w": (13, []), "x": (7, []),
        "y": (16, []), "z": (6, []),
        "A": (0, shift), "B": (11, shift), "C": (8, shift), "D": (2, shift), "E": (14, shift), "F": (3, shift),
        "G": (5, shift), "H": (4, shift), "I": (34, shift), "J": (38, shift), "K": (40, shift), "L": (37, shift),
        "M": (46, shift), "N": (45, shift), "O": (31, shift), "P": (35, shift), "Q": (12, shift), "R": (15, shift),
        "S": (1, shift), "T": (17, shift), "U": (32, shift), "V": (9, shift), "W": (13, shift), "X": (7, shift),
        "Y": (16, shift), "Z": (6, shift),
        "0": (29, []), "1": (18, []), "2": (19, []), "3": (20, []), "4": (21, []),
        "5": (23, []), "6": (22, []), "7": (26, []), "8": (28, []), "9": (25, []),
        " ": (49, []),
        ".": (47, []), ",": (43, []), "-": (27, []), "=": (24, []), "'": (39, []), ";": (41, []), "/": (44, []),
        "!": (18, shift), "?": (44, shift), ":": (41, shift), "\"": (39, shift),
        "\n": (36, [])
    ]
}

private struct Options {
    private let arguments: [String]

    init(arguments: [String]) {
        self.arguments = arguments
    }

    func value(for key: String) throws -> String {
        for index in arguments.indices where arguments[index] == key {
            let valueIndex = arguments.index(after: index)
            guard arguments.indices.contains(valueIndex) else {
                throw SpikeError.missingArgument(key)
            }
            return arguments[valueIndex]
        }
        throw SpikeError.missingArgument(key)
    }

    func valueOrDefault(for key: String, defaultValue: String) -> String {
        (try? value(for: key)) ?? defaultValue
    }
}
