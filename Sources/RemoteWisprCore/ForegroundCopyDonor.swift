import AppKit
import Foundation

public enum ForegroundCopyDonorError: Error, Equatable, CustomStringConvertible {
    case copyFailed(expected: String, actual: String?)

    public var description: String {
        switch self {
        case let .copyFailed(expected, actual):
            let preview = actual?
                .replacingOccurrences(of: "\n", with: "\\n")
                .prefix(80) ?? ""
            return "Foreground copy failed. Expected \(expected.count) characters, got \(actual?.count ?? 0). Actual preview: \"\(preview)\""
        }
    }
}

@MainActor
public final class ForegroundCopyDonor {
    private static var retainedWindows: [NSWindow] = []

    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public func copyText(_ text: String, holdSeconds: TimeInterval = 1.0, keepWindowOpen: Bool = false) throws -> String {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 160),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Remote Wispr Copy Donor"
        window.center()

        let textView = NSTextView(frame: NSRect(x: 16, y: 16, width: 488, height: 112))
        textView.string = text
        textView.isEditable = true
        textView.isSelectable = true
        window.contentView = textView

        app.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        runLoopBriefly(seconds: 0.2)

        pasteboard.clearContents()
        textView.setSelectedRange(NSRange(location: 0, length: (text as NSString).length))
        runLoopBriefly(seconds: 0.1)

        textView.copy(nil)

        let actual = waitForExpectedPasteboardValue(text, timeoutSeconds: holdSeconds)
        runLoopBriefly(seconds: holdSeconds)

        if keepWindowOpen {
            Self.retainedWindows.append(window)
        } else {
            window.orderOut(nil)
        }

        guard actual == text else {
            throw ForegroundCopyDonorError.copyFailed(expected: text, actual: actual)
        }

        return actual ?? ""
    }

    public static func closeRetainedWindows() {
        retainedWindows.forEach { $0.orderOut(nil) }
        retainedWindows.removeAll()
    }

    private func waitForExpectedPasteboardValue(_ expected: String, timeoutSeconds: TimeInterval) -> String? {
        let end = Date().addingTimeInterval(max(0.2, timeoutSeconds))
        var actual = pasteboard.string(forType: .string)

        while Date() < end {
            actual = pasteboard.string(forType: .string)
            if actual == expected {
                return actual
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        return actual
    }

    private func runLoopBriefly(seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            RunLoop.current.run(mode: .default, before: end)
        }
    }
}
