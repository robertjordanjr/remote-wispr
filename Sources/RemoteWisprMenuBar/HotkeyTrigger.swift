import AppKit
import Foundation
import RemoteWisprCore

@MainActor
final class HotkeyTrigger {
    private let minimumHoldSeconds: TimeInterval
    private let requiredModifiers: [HotkeyModifier]
    private let onKeyDown: () -> Void
    private let onKeyUp: () -> Void
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isShortcutDown = false
    private var downAt: Date?

    init(
        minimumHoldSeconds: TimeInterval,
        requiredModifiers: [HotkeyModifier],
        onKeyDown: @escaping () -> Void,
        onKeyUp: @escaping () -> Void
    ) {
        self.minimumHoldSeconds = minimumHoldSeconds
        self.requiredModifiers = HotkeyModifier.ordered(requiredModifiers)
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
    }

    func start() {
        stop()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }

        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        isShortcutDown = false
        downAt = nil
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let shortcutDown = isRequiredShortcutDown(flags)

        if shortcutDown && !isShortcutDown {
            isShortcutDown = true
            downAt = Date()
            onKeyDown()
            return
        }

        if !shortcutDown && isShortcutDown {
            let heldSeconds = Date().timeIntervalSince(downAt ?? Date())
            isShortcutDown = false
            downAt = nil

            guard heldSeconds >= minimumHoldSeconds else {
                return
            }

            onKeyUp()
        }
    }

    private func isRequiredShortcutDown(_ flags: NSEvent.ModifierFlags) -> Bool {
        let actual = Set(HotkeyModifier.allCases.filter { flags.contains($0.eventFlag) })
        let required = Set(requiredModifiers)
        return actual == required
    }
}

private extension HotkeyModifier {
    var eventFlag: NSEvent.ModifierFlags {
        switch self {
        case .control:
            .control
        case .option:
            .option
        case .shift:
            .shift
        case .command:
            .command
        }
    }
}
