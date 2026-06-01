import Foundation
import RemoteWisprCore
import SQLite3

@main
struct RemoteWisprFixtureTests {
    static func main() async {
        do {
            try await runAll()
            print("fixture tests passed")
        } catch {
            fputs("fixture tests failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func runAll() async throws {
        try testWorkflowCopiesOldestNewTranscript()
        try testWorkflowReportsNoTranscriptAfterMarker()
        try await testWatcherReturnsExistingNewRow()
        try await testWatcherWaitsForStableTranscriptRow()
        try await testWatcherTimesOutWithoutNewRow()
        try testSQLiteStoreReturnsMaxRowID()
        try testSQLiteStoreReturnsOldestUsableRowAfterMarker()
        try testSQLiteStoreUsesColumnFallback()
        try testSQLiteStorePrefersFormattedTextOverPartialEditedText()
        try testSQLiteStoreSkipsEmptyNoAudioAndArchivedRows()
        try testDefaultSettingsKeepRiskyFeaturesOff()
        try testSettingsRoundTrip()
        try testSettingsStoreCreatesAndUpgradesSettings()
        try testClipboardTextFormatterAppendsTrailingSpace()
        try testSharedClipboardSyncActivatesDonorAndReturnsFocus()
    }

    private static func testWorkflowCopiesOldestNewTranscript() throws {
        let store = MemoryTranscriptStore(rows: [
            TranscriptRow(rowID: 10, text: "old"),
            TranscriptRow(rowID: 11, text: "current"),
            TranscriptRow(rowID: 12, text: "next")
        ])
        let clipboard = MemoryClipboardBroker()
        let workflow = SpikeWorkflow(transcriptStore: store, clipboardBroker: clipboard)

        let result = try workflow.copyNextTranscript(after: 10)

        try expectEqual(result.row, TranscriptRow(rowID: 11, text: "current"))
        try expectEqual(clipboard.currentText(), "current")
    }

    private static func testWorkflowReportsNoTranscriptAfterMarker() throws {
        let store = MemoryTranscriptStore(rows: [
            TranscriptRow(rowID: 10, text: "old")
        ])
        let workflow = SpikeWorkflow(transcriptStore: store, clipboardBroker: MemoryClipboardBroker())

        do {
            _ = try workflow.copyNextTranscript(after: 10)
            throw TestFailure("Expected no transcript error")
        } catch let error as SpikeWorkflowError {
            try expectEqual(error, .noTranscript(afterRowID: 10))
        }
    }

    private static func testWatcherReturnsExistingNewRow() async throws {
        let store = MemoryTranscriptStore(rows: [
            TranscriptRow(rowID: 20, text: "before"),
            TranscriptRow(rowID: 21, text: "after")
        ])
        let watcher = TranscriptWatcher(store: store, pollIntervalSeconds: 0.05, stabilizationSeconds: 0)

        let row = try await watcher.waitForNext(after: 20, timeoutSeconds: 1)

        try expectEqual(row, TranscriptRow(rowID: 21, text: "after"))
    }

    private static func testWatcherWaitsForStableTranscriptRow() async throws {
        let finalRow = TranscriptRow(rowID: 21, text: "complete transcript", status: "raw_transcript")
        let store = SequencedTranscriptStore(rowsByCall: [
            TranscriptRow(rowID: 21, text: "com", status: "raw_transcript"),
            TranscriptRow(rowID: 21, text: "com", status: "raw_transcript"),
            finalRow,
            finalRow,
            finalRow
        ])
        let watcher = TranscriptWatcher(store: store, pollIntervalSeconds: 0.05, stabilizationSeconds: 0.08)

        let row = try await watcher.waitForNext(after: 20, timeoutSeconds: 1)

        try expectEqual(row, finalRow)
    }

    private static func testWatcherTimesOutWithoutNewRow() async throws {
        let store = MemoryTranscriptStore(rows: [
            TranscriptRow(rowID: 20, text: "before")
        ])
        let watcher = TranscriptWatcher(store: store, pollIntervalSeconds: 0.05, stabilizationSeconds: 0)

        do {
            _ = try await watcher.waitForNext(after: 20, timeoutSeconds: 0.1)
            throw TestFailure("Expected timeout")
        } catch let error as TranscriptWatcherError {
            try expectEqual(error, .timeout(afterRowID: 20))
        }
    }

    private static func testSQLiteStoreReturnsMaxRowID() throws {
        let fixture = try SQLiteFixture(rows: [
            FixtureRow(rowID: 10, formattedText: "ten"),
            FixtureRow(rowID: 12, formattedText: "twelve")
        ])
        let store = WisprSQLiteTranscriptStore(databasePath: fixture.path)

        try expectEqual(try store.maxRowID(), 12)
    }

    private static func testSQLiteStoreReturnsOldestUsableRowAfterMarker() throws {
        let fixture = try SQLiteFixture(rows: [
            FixtureRow(rowID: 10, formattedText: "ten"),
            FixtureRow(rowID: 11, formattedText: "eleven"),
            FixtureRow(rowID: 12, formattedText: "twelve")
        ])
        let store = WisprSQLiteTranscriptStore(databasePath: fixture.path)

        try expectEqual(
            try store.oldestUsableRow(after: 10),
            TranscriptRow(
                rowID: 11,
                text: "eleven",
                timestamp: "2026-05-29 00:00:11 +00:00",
                status: "raw_transcript"
            )
        )
    }

    private static func testSQLiteStoreUsesColumnFallback() throws {
        let fixture = try SQLiteFixture(rows: [
            FixtureRow(rowID: 20, asrText: "asr fallback")
        ])
        let store = WisprSQLiteTranscriptStore(databasePath: fixture.path)

        try expectEqual(try store.oldestUsableRow(after: 19)?.text, "asr fallback")
    }

    private static func testSQLiteStorePrefersFormattedTextOverPartialEditedText() throws {
        let fixture = try SQLiteFixture(rows: [
            FixtureRow(rowID: 25, editedText: " Alph       ", formattedText: "Alpha test ")
        ])
        let store = WisprSQLiteTranscriptStore(databasePath: fixture.path)

        try expectEqual(try store.oldestUsableRow(after: 24)?.text, "Alpha test")
    }

    private static func testSQLiteStoreSkipsEmptyNoAudioAndArchivedRows() throws {
        let fixture = try SQLiteFixture(rows: [
            FixtureRow(rowID: 30, formattedText: ""),
            FixtureRow(rowID: 31, formattedText: "ignored", status: "no_audio"),
            FixtureRow(rowID: 32, formattedText: "archived", isArchived: true),
            FixtureRow(rowID: 33, formattedText: "usable")
        ])
        let store = WisprSQLiteTranscriptStore(databasePath: fixture.path)

        try expectEqual(try store.oldestUsableRow(after: 29)?.rowID, 33)
    }

    private static func testDefaultSettingsKeepRiskyFeaturesOff() throws {
        let settings = AppSettings()

        try expectEqual(settings.settingsSchemaVersion, AppSettings.currentSchemaVersion)
        try expectEqual(settings.clipboardSyncMode, .localOnly)
        try expectEqual(settings.donorAppPath, AppSettings.defaultDonorAppPath)
        try expectEqual(settings.hiddenDonorEnabled, true)
        try expectEqual(settings.remoteCleanupMode, .disabled)
        try expectEqual(settings.automaticPasteEnabled, false)
        try expectEqual(settings.autoPasteDelaySeconds, 0.2)
        try expectEqual(settings.automaticTriggerEnabled, false)
        try expectEqual(settings.hotkeyModifiers, [.control, .option])
        try expectEqual(settings.hotkeyMinimumHoldSeconds, 0.2)
        try expectEqual(settings.waitTimeoutSeconds, 60)
    }

    private static func testSettingsRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("remote-wispr-settings-\(UUID().uuidString)", isDirectory: true)
        let store = SettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
        let settings = AppSettings(
            settingsSchemaVersion: AppSettings.currentSchemaVersion,
            wisprDatabasePath: "/tmp/flow.sqlite",
            donorAppPath: "/tmp/Remote Wispr Copy Donor.app",
            hiddenDonorEnabled: false,
            clipboardSyncMode: .focusDonor,
            remoteCleanupMode: .backspace,
            automaticPasteEnabled: true,
            autoPasteDelaySeconds: 1.5,
            automaticTriggerEnabled: false,
            hotkeyModifiers: [.control, .option, .shift],
            hotkeyMinimumHoldSeconds: 0.4,
            waitTimeoutSeconds: 30,
            pollIntervalSeconds: 0.5
        )

        try store.save(settings)

        try expectEqual(try store.load(), settings)
    }

    private static func testSettingsStoreCreatesAndUpgradesSettings() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("remote-wispr-settings-\(UUID().uuidString)", isDirectory: true)
        let settingsURL = directory.appendingPathComponent("settings.json")
        let store = SettingsStore(fileURL: settingsURL)
        let defaultSettings = AppSettings(donorAppPath: "/tmp/Remote Wispr Copy Donor.app")

        let created = try store.loadOrCreate(defaultSettings: defaultSettings)
        try expectEqual(created, defaultSettings)
        try expectTrue(
            FileManager.default.fileExists(atPath: settingsURL.path),
            "settings file should be created"
        )

        let oldSettingsJSON = """
        {
          "donorAppPath": "",
          "waitTimeoutSeconds": 30
        }
        """
        guard let oldSettingsData = oldSettingsJSON.data(using: .utf8) else {
            throw TestFailure("could not encode old settings fixture")
        }
        try oldSettingsData.write(to: settingsURL, options: .atomic)

        let upgraded = try store.loadOrCreate(defaultSettings: defaultSettings)
        try expectEqual(upgraded.settingsSchemaVersion, AppSettings.currentSchemaVersion)
        try expectEqual(upgraded.donorAppPath, "/tmp/Remote Wispr Copy Donor.app")
        try expectEqual(upgraded.hotkeyModifiers, [.control, .option])
        try expectEqual(upgraded.waitTimeoutSeconds, 30)
    }

    private static func testClipboardTextFormatterAppendsTrailingSpace() throws {
        try expectEqual(
            ClipboardTextFormatter.appendTrailingSpace("Hello world."),
            "Hello world. "
        )
    }

    private static func testSharedClipboardSyncActivatesDonorAndReturnsFocus() throws {
        let clipboard = MemoryClipboardBroker()
        let focus = MemoryFocusBroker()
        let sync = SharedClipboardSync(
            clipboardBroker: clipboard,
            focusBroker: focus,
            donorBundleIdentifier: "com.remote-wispr.FocusDonor"
        )

        let result = try sync.syncText("Bravo.")

        try expectEqual(clipboard.currentText(), "Bravo.")
        try expectEqual(focus.activatedDonorBundleIdentifier, "com.remote-wispr.FocusDonor")
        try expectEqual(focus.returnedTarget, FocusTarget(processIdentifier: 100, bundleIdentifier: "com.apple.ScreenSharing", localizedName: "Screen Sharing"))
        try expectEqual(result.clipboardAfterSet, "Bravo.")
        try expectEqual(result.clipboardAfterReturn, "Bravo.")
        try expectEqual(result.clipboardSurvivedReturn, true)
    }

    private static func expectEqual<T: Equatable>(_ actual: T, _ expected: T) throws {
        if actual != expected {
            throw TestFailure("Expected \(expected), got \(actual)")
        }
    }

    private static func expectTrue(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw TestFailure(message)
        }
    }
}

private struct FixtureRow {
    let rowID: Int64
    var editedText: String? = nil
    var formattedText: String? = nil
    var defaultFormattedText: String? = nil
    var fallbackFormattedText: String? = nil
    var asrText: String? = nil
    var defaultAsrText: String? = nil
    var fallbackAsrText: String? = nil
    var status: String = "raw_transcript"
    var isArchived: Bool = false

    var timestamp: String {
        "2026-05-29 00:00:\(String(format: "%02d", rowID % 60)) +00:00"
    }
}

private final class SequencedTranscriptStore: TranscriptStore {
    private let rowsByCall: [TranscriptRow?]
    private var callCount = 0

    init(rowsByCall: [TranscriptRow?]) {
        self.rowsByCall = rowsByCall
    }

    func maxRowID() throws -> Int64 {
        rowsByCall.compactMap(\.?.rowID).max() ?? 0
    }

    func oldestUsableRow(after rowID: Int64) throws -> TranscriptRow? {
        defer { callCount += 1 }

        let row = rowsByCall[min(callCount, rowsByCall.count - 1)]
        guard let row,
              row.rowID > rowID,
              !row.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        return row
    }
}

private final class SQLiteFixture {
    let path: String

    init(rows: [FixtureRow]) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("remote-wispr-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        path = directory.appendingPathComponent("flow.sqlite").path

        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK, let db else {
            throw TestFailure("Could not open fixture DB")
        }
        defer { sqlite3_close(db) }

        try execute(
            db,
            """
            CREATE TABLE History (
                editedText TEXT,
                formattedText TEXT,
                defaultFormattedText TEXT,
                fallbackFormattedText TEXT,
                asrText TEXT,
                defaultAsrText TEXT,
                fallbackAsrText TEXT,
                timestamp DATETIME,
                status VARCHAR(255),
                isArchived TINYINT(1) NOT NULL DEFAULT 0
            );
            """
        )

        for row in rows {
            try insert(row, db: db)
        }
    }

    private func insert(_ row: FixtureRow, db: OpaquePointer) throws {
        let sql = """
        INSERT INTO History (
            rowid,
            editedText,
            formattedText,
            defaultFormattedText,
            fallbackFormattedText,
            asrText,
            defaultAsrText,
            fallbackAsrText,
            timestamp,
            status,
            isArchived
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw TestFailure("Could not prepare fixture insert")
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, row.rowID)
        bindText(row.editedText, to: statement, index: 2)
        bindText(row.formattedText, to: statement, index: 3)
        bindText(row.defaultFormattedText, to: statement, index: 4)
        bindText(row.fallbackFormattedText, to: statement, index: 5)
        bindText(row.asrText, to: statement, index: 6)
        bindText(row.defaultAsrText, to: statement, index: 7)
        bindText(row.fallbackAsrText, to: statement, index: 8)
        bindText(row.timestamp, to: statement, index: 9)
        bindText(row.status, to: statement, index: 10)
        sqlite3_bind_int(statement, 11, row.isArchived ? 1 : 0)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw TestFailure("Could not insert fixture row \(row.rowID)")
        }
    }

    private func bindText(_ text: String?, to statement: OpaquePointer, index: Int32) {
        guard let text else {
            sqlite3_bind_null(statement, index)
            return
        }

        sqlite3_bind_text(statement, index, text, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    private func execute(_ db: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw TestFailure("Could not execute fixture SQL")
        }
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
