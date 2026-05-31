import AppKit
import Foundation

public protocol ClipboardBroker {
    func setText(_ text: String) throws
    func currentText() -> String?
}

public enum ClipboardError: Error, Equatable {
    case writeFailed
    case verificationFailed(expected: String, actual: String?)
}

public final class SystemClipboardBroker: ClipboardBroker {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public func setText(_ text: String) throws {
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw ClipboardError.writeFailed
        }

        let actual = currentText()
        guard actual == text else {
            throw ClipboardError.verificationFailed(expected: text, actual: actual)
        }
    }

    public func currentText() -> String? {
        pasteboard.string(forType: .string)
    }
}

public final class MemoryClipboardBroker: ClipboardBroker {
    private var text: String?

    public init(text: String? = nil) {
        self.text = text
    }

    public func setText(_ text: String) throws {
        self.text = text
    }

    public func currentText() -> String? {
        text
    }
}
