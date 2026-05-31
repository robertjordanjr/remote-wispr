import Foundation

public enum ClipboardSyncMode: String, Codable, Equatable, Sendable {
    case localOnly
    case focusDonor
}

public enum RemoteCleanupMode: String, Codable, Equatable, Sendable, CaseIterable {
    case disabled
    case backspace
    case backspaceThenSpace

    public var displayName: String {
        switch self {
        case .disabled:
            "Disabled"
        case .backspace:
            "Enabled"
        case .backspaceThenSpace:
            "Enabled (legacy backspace then space)"
        }
    }
}

public enum HotkeyModifier: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case control
    case option
    case shift
    case command

    public static let defaultShortcut: [HotkeyModifier] = [.control, .option]

    public var displayName: String {
        switch self {
        case .control:
            "Control"
        case .option:
            "Option"
        case .shift:
            "Shift"
        case .command:
            "Command"
        }
    }

    public static func displayName(for modifiers: [HotkeyModifier]) -> String {
        ordered(modifiers).map(\.displayName).joined(separator: "+")
    }

    public static func ordered(_ modifiers: [HotkeyModifier]) -> [HotkeyModifier] {
        Self.allCases.filter { modifiers.contains($0) }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2
    public static let defaultDonorAppPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Applications/Remote Wispr Copy Donor.app")
        .path

    public var settingsSchemaVersion: Int
    public var wisprDatabasePath: String
    public var donorAppPath: String
    public var hiddenDonorEnabled: Bool
    public var clipboardSyncMode: ClipboardSyncMode
    public var focusDonorBundleIdentifier: String
    public var remoteCleanupMode: RemoteCleanupMode
    public var automaticPasteEnabled: Bool
    public var autoPasteDelaySeconds: Double
    public var automaticTriggerEnabled: Bool
    public var hotkeyModifiers: [HotkeyModifier]
    public var hotkeyMinimumHoldSeconds: Double
    public var waitTimeoutSeconds: Double
    public var pollIntervalSeconds: Double

    private enum CodingKeys: String, CodingKey {
        case settingsSchemaVersion
        case wisprDatabasePath
        case donorAppPath
        case hiddenDonorEnabled
        case clipboardSyncMode
        case focusDonorBundleIdentifier
        case remoteCleanupMode
        case automaticPasteEnabled
        case autoPasteDelaySeconds
        case automaticTriggerEnabled
        case hotkeyModifiers
        case hotkeyMinimumHoldSeconds
        case waitTimeoutSeconds
        case pollIntervalSeconds
    }

    public init(
        settingsSchemaVersion: Int = AppSettings.currentSchemaVersion,
        wisprDatabasePath: String = WisprSQLiteTranscriptStore.defaultDatabasePath,
        donorAppPath: String = AppSettings.defaultDonorAppPath,
        hiddenDonorEnabled: Bool = true,
        clipboardSyncMode: ClipboardSyncMode = .localOnly,
        focusDonorBundleIdentifier: String = "com.remote-wispr.FocusDonor",
        remoteCleanupMode: RemoteCleanupMode = .disabled,
        automaticPasteEnabled: Bool = false,
        autoPasteDelaySeconds: Double = 0.2,
        automaticTriggerEnabled: Bool = false,
        hotkeyModifiers: [HotkeyModifier] = HotkeyModifier.defaultShortcut,
        hotkeyMinimumHoldSeconds: Double = 0.2,
        waitTimeoutSeconds: Double = 60,
        pollIntervalSeconds: Double = 0.25
    ) {
        self.settingsSchemaVersion = settingsSchemaVersion
        self.wisprDatabasePath = wisprDatabasePath
        self.donorAppPath = donorAppPath
        self.hiddenDonorEnabled = hiddenDonorEnabled
        self.clipboardSyncMode = clipboardSyncMode
        self.focusDonorBundleIdentifier = focusDonorBundleIdentifier
        self.remoteCleanupMode = remoteCleanupMode
        self.automaticPasteEnabled = automaticPasteEnabled
        self.autoPasteDelaySeconds = autoPasteDelaySeconds
        self.automaticTriggerEnabled = automaticTriggerEnabled
        self.hotkeyModifiers = HotkeyModifier.ordered(hotkeyModifiers)
        self.hotkeyMinimumHoldSeconds = hotkeyMinimumHoldSeconds
        self.waitTimeoutSeconds = waitTimeoutSeconds
        self.pollIntervalSeconds = pollIntervalSeconds
    }

    public init(from decoder: Decoder) throws {
        let defaults = AppSettings()
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.settingsSchemaVersion = try container.decodeIfPresent(Int.self, forKey: .settingsSchemaVersion)
            ?? defaults.settingsSchemaVersion
        self.wisprDatabasePath = try container.decodeIfPresent(String.self, forKey: .wisprDatabasePath)
            ?? defaults.wisprDatabasePath
        self.donorAppPath = try container.decodeIfPresent(String.self, forKey: .donorAppPath)
            ?? defaults.donorAppPath
        self.hiddenDonorEnabled = try container.decodeIfPresent(Bool.self, forKey: .hiddenDonorEnabled)
            ?? defaults.hiddenDonorEnabled
        self.clipboardSyncMode = try container.decodeIfPresent(ClipboardSyncMode.self, forKey: .clipboardSyncMode)
            ?? defaults.clipboardSyncMode
        self.focusDonorBundleIdentifier = try container.decodeIfPresent(String.self, forKey: .focusDonorBundleIdentifier)
            ?? defaults.focusDonorBundleIdentifier
        self.remoteCleanupMode = try container.decodeIfPresent(RemoteCleanupMode.self, forKey: .remoteCleanupMode)
            ?? defaults.remoteCleanupMode
        self.automaticPasteEnabled = try container.decodeIfPresent(Bool.self, forKey: .automaticPasteEnabled)
            ?? defaults.automaticPasteEnabled
        self.autoPasteDelaySeconds = try container.decodeIfPresent(Double.self, forKey: .autoPasteDelaySeconds)
            ?? defaults.autoPasteDelaySeconds
        self.automaticTriggerEnabled = try container.decodeIfPresent(Bool.self, forKey: .automaticTriggerEnabled)
            ?? defaults.automaticTriggerEnabled
        self.hotkeyModifiers = try container.decodeIfPresent([HotkeyModifier].self, forKey: .hotkeyModifiers)
            ?? defaults.hotkeyModifiers
        self.hotkeyMinimumHoldSeconds = try container.decodeIfPresent(Double.self, forKey: .hotkeyMinimumHoldSeconds)
            ?? defaults.hotkeyMinimumHoldSeconds
        self.waitTimeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .waitTimeoutSeconds)
            ?? defaults.waitTimeoutSeconds
        self.pollIntervalSeconds = try container.decodeIfPresent(Double.self, forKey: .pollIntervalSeconds)
            ?? defaults.pollIntervalSeconds
    }

    public func normalizedForCurrentVersion(defaultSettings: AppSettings = AppSettings()) -> AppSettings {
        var settings = self
        settings.settingsSchemaVersion = Self.currentSchemaVersion

        if settings.donorAppPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            settings.donorAppPath = defaultSettings.donorAppPath
        }
        settings.hotkeyModifiers = HotkeyModifier.ordered(settings.hotkeyModifiers)
        if settings.hotkeyModifiers.isEmpty {
            settings.hotkeyModifiers = defaultSettings.hotkeyModifiers
        }

        return settings
    }
}

public final class SettingsStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    public func load() throws -> AppSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return AppSettings()
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(AppSettings.self, from: data)
    }

    public func loadOrCreate(defaultSettings: AppSettings = AppSettings()) throws -> AppSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let settings = defaultSettings.normalizedForCurrentVersion(defaultSettings: defaultSettings)
            try save(settings)
            return settings
        }

        let data = try Data(contentsOf: fileURL)
        let loaded = try decoder.decode(AppSettings.self, from: data)
        let normalized = loaded.normalizedForCurrentVersion(defaultSettings: defaultSettings)
        try save(normalized)
        return normalized
    }

    public func save(_ settings: AppSettings) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(settings)
        try data.write(to: fileURL, options: .atomic)
    }
}
