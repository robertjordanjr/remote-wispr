import AppKit
import Foundation
import RemoteWisprCore

@MainActor
final class SettingsWindowController: NSWindowController {
    private static let windowWidth: CGFloat = 660
    private static let labelX: CGFloat = 8
    private static let labelWidth: CGFloat = 154
    private static let controlX: CGFloat = 178
    private static let rightMargin: CGFloat = 14

    var settings: AppSettings {
        didSet {
            loadSettingsIntoFields()
        }
    }

    private let onSave: (AppSettings) -> Void
    private let wisprPathField = NSTextField()
    private let donorPathField = NSTextField()
    private let timeoutField = NSTextField()
    private let autoPasteDelayField = NSTextField()
    private let hotkeyMinimumHoldField = NSTextField()
    private let remoteCleanupButton = NSButton(checkboxWithTitle: "Clean up leaked v", target: nil, action: nil)
    private let hiddenDonorButton = NSButton(checkboxWithTitle: "Hide donor window", target: nil, action: nil)
    private let automaticPasteButton = NSButton(checkboxWithTitle: "Auto paste", target: nil, action: nil)
    private let controlModifierButton = NSButton(checkboxWithTitle: "Ctrl", target: nil, action: nil)
    private let optionModifierButton = NSButton(checkboxWithTitle: "Opt", target: nil, action: nil)
    private let shiftModifierButton = NSButton(checkboxWithTitle: "Shift", target: nil, action: nil)
    private let commandModifierButton = NSButton(checkboxWithTitle: "Cmd", target: nil, action: nil)
    private let automaticTriggerButton = NSButton(
        checkboxWithTitle: "Enable Wispr shortcut trigger",
        target: nil,
        action: nil
    )

    init(
        settings: AppSettings,
        onSave: @escaping (AppSettings) -> Void
    ) {
        self.settings = settings
        self.onSave = onSave

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.windowWidth, height: 510),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Remote Wispr Settings"
        window.center()

        super.init(window: window)
        buildContent()
        loadSettingsIntoFields()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func buildContent() {
        guard let window else {
            return
        }

        let contentView = NSView(frame: window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: Self.windowWidth, height: 450))
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView

        addLabel("Wispr DB Path", y: 456, to: contentView)
        configurePathField(wisprPathField, y: 450, in: contentView)

        addLabel("Donor App Path", y: 406, to: contentView)
        configurePathField(donorPathField, y: 400, in: contentView)

        addLabel("Timeout Seconds", y: 356, to: contentView)
        timeoutField.frame = NSRect(x: Self.controlX, y: 350, width: 90, height: 24)
        timeoutField.placeholderString = "20"
        contentView.addSubview(timeoutField)

        addLabel("Hide donor window", y: 314, to: contentView)
        configureCheckbox(hiddenDonorButton, label: "Hide donor window", y: 314, in: contentView)

        addLabel("Wispr shortcut trigger", y: 278, to: contentView)
        configureCheckbox(automaticTriggerButton, label: "Wispr shortcut trigger", y: 278, in: contentView)

        addLabel("Wispr Shortcut", y: 242, to: contentView)
        configureModifierButtons(y: 242, in: contentView)

        addLabel("Auto paste", y: 206, to: contentView)
        configureCheckbox(automaticPasteButton, label: "Auto paste", y: 206, in: contentView)

        addLabel("Paste Focus Wait", y: 170, to: contentView)
        autoPasteDelayField.frame = NSRect(x: Self.controlX, y: 164, width: 90, height: 24)
        autoPasteDelayField.placeholderString = "0.2"
        contentView.addSubview(autoPasteDelayField)

        addLabel("Clean up leaked v", y: 134, to: contentView)
        configureCheckbox(remoteCleanupButton, label: "Clean up leaked v", y: 134, in: contentView)

        addLabel("Min Hold Seconds", y: 98, to: contentView)
        hotkeyMinimumHoldField.frame = NSRect(x: Self.controlX, y: 92, width: 90, height: 24)
        hotkeyMinimumHoldField.placeholderString = "0.2"
        contentView.addSubview(hotkeyMinimumHoldField)

        let resetButton = NSButton(title: "Reset Defaults", target: self, action: #selector(resetDefaults))
        resetButton.frame = NSRect(x: 350, y: 18, width: 120, height: 32)
        contentView.addSubview(resetButton)

        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"
        saveButton.frame = NSRect(x: 490, y: 18, width: 80, height: 32)
        contentView.addSubview(saveButton)

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.frame = NSRect(x: 572, y: 18, width: 74, height: 32)
        contentView.addSubview(cancelButton)
    }

    private func addLabel(_ title: String, y: CGFloat, to contentView: NSView) {
        let label = NSTextField(labelWithString: title)
        label.frame = NSRect(x: Self.labelX, y: y, width: Self.labelWidth, height: 20)
        label.alignment = .right
        contentView.addSubview(label)
    }

    private func configurePathField(_ field: NSTextField, y: CGFloat, in contentView: NSView) {
        field.frame = NSRect(
            x: Self.controlX,
            y: y,
            width: Self.windowWidth - Self.controlX - Self.rightMargin,
            height: 24
        )
        field.lineBreakMode = .byTruncatingMiddle
        contentView.addSubview(field)
    }

    private func configureCheckbox(_ button: NSButton, label: String, y: CGFloat, in contentView: NSView) {
        button.title = ""
        button.setAccessibilityLabel(label)
        button.frame = NSRect(x: Self.controlX, y: y, width: 24, height: 24)
        contentView.addSubview(button)
    }

    private func configureModifierButtons(y: CGFloat, in contentView: NSView) {
        let buttons = [
            controlModifierButton,
            optionModifierButton,
            shiftModifierButton,
            commandModifierButton
        ]
        let widths: [CGFloat] = [58, 52, 64, 60]
        var x: CGFloat = Self.controlX
        for (button, width) in zip(buttons, widths) {
            button.frame = NSRect(x: x, y: y, width: width, height: 24)
            contentView.addSubview(button)
            x += width + 10
        }
    }

    private func loadSettingsIntoFields() {
        guard isWindowLoaded else {
            return
        }

        wisprPathField.stringValue = settings.wisprDatabasePath
        donorPathField.stringValue = settings.donorAppPath
        timeoutField.stringValue = String(settings.waitTimeoutSeconds)
        autoPasteDelayField.stringValue = String(settings.autoPasteDelaySeconds)
        hiddenDonorButton.state = settings.hiddenDonorEnabled ? .on : .off
        automaticTriggerButton.state = settings.automaticTriggerEnabled ? .on : .off
        automaticPasteButton.state = settings.automaticPasteEnabled ? .on : .off
        controlModifierButton.state = settings.hotkeyModifiers.contains(.control) ? .on : .off
        optionModifierButton.state = settings.hotkeyModifiers.contains(.option) ? .on : .off
        shiftModifierButton.state = settings.hotkeyModifiers.contains(.shift) ? .on : .off
        commandModifierButton.state = settings.hotkeyModifiers.contains(.command) ? .on : .off
        remoteCleanupButton.state = settings.remoteCleanupMode == .disabled ? .off : .on
        hotkeyMinimumHoldField.stringValue = String(settings.hotkeyMinimumHoldSeconds)
    }

    @objc private func resetDefaults() {
        settings = AppSettings()
        loadSettingsIntoFields()
    }

    @objc private func save() {
        var newSettings = settings
        newSettings.wisprDatabasePath = wisprPathField.stringValue
        newSettings.donorAppPath = donorPathField.stringValue
        newSettings.waitTimeoutSeconds = Double(timeoutField.stringValue) ?? settings.waitTimeoutSeconds
        newSettings.hiddenDonorEnabled = hiddenDonorButton.state == .on
        newSettings.automaticTriggerEnabled = automaticTriggerButton.state == .on
        newSettings.hotkeyModifiers = selectedHotkeyModifiers()
        newSettings.automaticPasteEnabled = automaticPasteButton.state == .on
        let autoPasteDelay = Double(autoPasteDelayField.stringValue) ?? settings.autoPasteDelaySeconds
        newSettings.autoPasteDelaySeconds = Swift.max(0, autoPasteDelay)
        newSettings.remoteCleanupMode = remoteCleanupButton.state == .on ? .backspace : .disabled
        let minimumHold = Double(hotkeyMinimumHoldField.stringValue) ?? settings.hotkeyMinimumHoldSeconds
        newSettings.hotkeyMinimumHoldSeconds = Swift.max(0, minimumHold)
        onSave(newSettings)
        close()
    }

    private func selectedHotkeyModifiers() -> [HotkeyModifier] {
        var modifiers: [HotkeyModifier] = []
        if controlModifierButton.state == .on {
            modifiers.append(.control)
        }
        if optionModifierButton.state == .on {
            modifiers.append(.option)
        }
        if shiftModifierButton.state == .on {
            modifiers.append(.shift)
        }
        if commandModifierButton.state == .on {
            modifiers.append(.command)
        }
        return modifiers.isEmpty ? HotkeyModifier.defaultShortcut : modifiers
    }

    @objc private func cancel() {
        close()
    }
}
