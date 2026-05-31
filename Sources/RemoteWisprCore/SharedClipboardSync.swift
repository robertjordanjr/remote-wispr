import Foundation

public struct SharedClipboardSyncResult: Equatable {
    public let returnTarget: FocusTarget
    public let donorTarget: FocusTarget
    public let expectedText: String
    public let clipboardAfterSet: String
    public let clipboardAfterReturn: String

    public var clipboardSurvivedReturn: Bool {
        clipboardAfterReturn == expectedText
    }

    public init(
        returnTarget: FocusTarget,
        donorTarget: FocusTarget,
        expectedText: String,
        clipboardAfterSet: String,
        clipboardAfterReturn: String
    ) {
        self.returnTarget = returnTarget
        self.donorTarget = donorTarget
        self.expectedText = expectedText
        self.clipboardAfterSet = clipboardAfterSet
        self.clipboardAfterReturn = clipboardAfterReturn
    }
}

public final class SharedClipboardSync {
    private let clipboardBroker: ClipboardBroker
    private let focusBroker: FocusBroker
    private let donorBundleIdentifier: String

    public init(
        clipboardBroker: ClipboardBroker,
        focusBroker: FocusBroker,
        donorBundleIdentifier: String = "com.remote-wispr.FocusDonor"
    ) {
        self.clipboardBroker = clipboardBroker
        self.focusBroker = focusBroker
        self.donorBundleIdentifier = donorBundleIdentifier
    }

    public func syncText(
        _ text: String,
        returnTarget: FocusTarget? = nil,
        donorHoldSeconds: TimeInterval = 1.0,
        postReturnDelaySeconds: TimeInterval = 0.25
    ) throws -> SharedClipboardSyncResult {
        let target = try returnTarget ?? focusBroker.captureFrontmostApplication()
        let donor = try focusBroker.activateDonor(bundleIdentifier: donorBundleIdentifier)
        try clipboardBroker.setText(text)
        let clipboardAfterSet = clipboardBroker.currentText() ?? ""
        if donorHoldSeconds > 0 {
            Thread.sleep(forTimeInterval: donorHoldSeconds)
        }
        try focusBroker.returnFocus(to: target)
        if postReturnDelaySeconds > 0 {
            Thread.sleep(forTimeInterval: postReturnDelaySeconds)
        }
        let clipboardAfterReturn = clipboardBroker.currentText() ?? ""

        return SharedClipboardSyncResult(
            returnTarget: target,
            donorTarget: donor,
            expectedText: text,
            clipboardAfterSet: clipboardAfterSet,
            clipboardAfterReturn: clipboardAfterReturn
        )
    }
}
