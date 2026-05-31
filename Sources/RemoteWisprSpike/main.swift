import Foundation
import RemoteWisprCore
import CoreGraphics
import SQLite3

struct Options {
    var command: String = "help"
    var dbPath: String = WisprSQLiteTranscriptStore.defaultDatabasePath
    var afterRowID: Int64?
    var timeoutSeconds: TimeInterval = 12
    var captureDelaySeconds: TimeInterval = 0
    var donorHoldSeconds: TimeInterval = 1.0
    var postReturnDelaySeconds: TimeInterval = 0.25
    var donorBundleIdentifier: String = "com.remote-wispr.FocusDonor"
    var donorAppPath: String = "\(FileManager.default.currentDirectoryPath)/.build/apps/Remote Wispr Copy Donor.app"
    var copyMethod: CopyMethod = .pasteboardDonor
    var skipReturnFocus: Bool = false
    var keepDonorOpen: Bool = false
    var replaceLeakedVWithSpace: Bool = false
    var visibleDonorWindow: Bool = false
}

enum CopyMethod: String {
    case pasteboardDonor = "pasteboard-donor"
    case foregroundCopy = "foreground-copy"
    case persistentDonorApp = "persistent-donor-app"
}

@main
struct RemoteWisprSpike {
    static func main() async {
        do {
            let options = try parseOptions(CommandLine.arguments.dropFirst())
            try await run(options)
        } catch {
            fputs("error: \(error)\n", stderr)
            printUsage()
            exit(1)
        }
    }

    private static func run(_ options: Options) async throws {
        let store = WisprSQLiteTranscriptStore(databasePath: options.dbPath)
        let clipboard = SystemClipboardBroker()

        switch options.command {
        case "prime":
            let maxRowID = try store.maxRowID()
            print("Current max row: \(maxRowID)")

        case "latest":
            let maxRowID = try store.maxRowID()
            guard maxRowID > 0 else {
                print("No Wispr rows found.")
                return
            }
            let workflow = SpikeWorkflow(transcriptStore: store, clipboardBroker: clipboard)
            let result = try workflow.copyNextTranscript(after: maxRowID - 1)
            printReady(result)

        case "wait":
            guard let afterRowID = options.afterRowID else {
                throw CLIError.missingRequiredOption("--after")
            }
            let watcher = TranscriptWatcher(store: store)
            let row = try await watcher.waitForNext(after: afterRowID, timeoutSeconds: options.timeoutSeconds)
            try clipboard.setText(row.text)
            printReady(CopyResult(row: row, clipboardText: clipboard.currentText() ?? ""))

        case "wait-sync", "wait-sync-next":
            let afterRowID: Int64
            if options.command == "wait-sync-next" {
                afterRowID = try store.maxRowID()
                print("Waiting after current max row: \(afterRowID)")
            } else if let optionAfterRowID = options.afterRowID {
                afterRowID = optionAfterRowID
            } else {
                throw CLIError.missingRequiredOption("--after")
            }
            if options.captureDelaySeconds > 0 {
                print("Capturing return focus in \(options.captureDelaySeconds) seconds...")
                try await Task.sleep(nanoseconds: UInt64(options.captureDelaySeconds * 1_000_000_000))
            }
            let focus = SystemFocusBroker()
            let returnTarget = try focus.captureFrontmostApplication()
            print("Captured return app: \(displayName(returnTarget))")

            let watcher = TranscriptWatcher(store: store)
            let row = try await watcher.waitForNext(after: afterRowID, timeoutSeconds: options.timeoutSeconds)
            let sync = SharedClipboardSync(
                clipboardBroker: clipboard,
                focusBroker: focus,
                donorBundleIdentifier: options.donorBundleIdentifier
            )

            let syncResult: SharedClipboardSyncResult
            switch options.copyMethod {
            case .pasteboardDonor:
                syncResult = try sync.syncText(
                    row.text,
                    returnTarget: returnTarget,
                    donorHoldSeconds: options.donorHoldSeconds,
                    postReturnDelaySeconds: options.postReturnDelaySeconds
                )
            case .foregroundCopy:
                let copiedText = try await ForegroundCopyDonor().copyText(
                    row.text,
                    holdSeconds: options.donorHoldSeconds,
                    keepWindowOpen: options.keepDonorOpen
                )
                if options.skipReturnFocus {
                    print("Skipped programmatic focus return.")
                } else {
                    try focus.returnFocus(to: returnTarget)
                    if options.postReturnDelaySeconds > 0 {
                        try await Task.sleep(nanoseconds: UInt64(options.postReturnDelaySeconds * 1_000_000_000))
                    }
                }
                syncResult = SharedClipboardSyncResult(
                    returnTarget: returnTarget,
                    donorTarget: FocusTarget(
                        processIdentifier: ProcessInfo.processInfo.processIdentifier,
                        bundleIdentifier: Bundle.main.bundleIdentifier,
                        localizedName: "Remote Wispr Copy Donor"
                    ),
                    expectedText: row.text,
                    clipboardAfterSet: copiedText,
                    clipboardAfterReturn: clipboard.currentText() ?? ""
                )
            case .persistentDonorApp:
                let donorApp = PersistentDonorApp(
                    appPath: options.donorAppPath,
                    hiddenWindow: !options.visibleDonorWindow
                )
                let donorResult = try donorApp.copyText(row.text)
                print("Persistent donor ready file: \(donorResult.readyFile)")
                print("Persistent donor result:")
                print(donorResult.readyContents)
                if options.replaceLeakedVWithSpace {
                    try focus.returnFocus(to: returnTarget)
                    if options.postReturnDelaySeconds > 0 {
                        try await Task.sleep(nanoseconds: UInt64(options.postReturnDelaySeconds * 1_000_000_000))
                    }
                    replaceLeakedVWithSpace()
                    print("Replaced leaked v with space.")
                }
                if options.skipReturnFocus {
                    print("Skipped programmatic focus return.")
                } else {
                    try focus.returnFocus(to: returnTarget)
                    if options.postReturnDelaySeconds > 0 {
                        try await Task.sleep(nanoseconds: UInt64(options.postReturnDelaySeconds * 1_000_000_000))
                    }
                }
                syncResult = SharedClipboardSyncResult(
                    returnTarget: returnTarget,
                    donorTarget: FocusTarget(
                        processIdentifier: -1,
                        bundleIdentifier: "com.remote-wispr.CopyDonor",
                        localizedName: "Remote Wispr Copy Donor"
                    ),
                    expectedText: row.text,
                    clipboardAfterSet: row.text,
                    clipboardAfterReturn: clipboard.currentText() ?? ""
                )
            }

            printReady(CopyResult(row: row, clipboardText: syncResult.clipboardAfterReturn))
            print("Donor app: \(displayName(syncResult.donorTarget))")
            print("Returned focus to: \(displayName(syncResult.returnTarget))")
            print("Clipboard after set: \(describeClipboard(syncResult.clipboardAfterSet))")
            print("Clipboard after return: \(describeClipboard(syncResult.clipboardAfterReturn))")
            print("Clipboard survived return: \(syncResult.clipboardSurvivedReturn ? "yes" : "no")")
            if options.keepDonorOpen {
                print("Donor window kept open. Paste into Screen Sharing now, then return here and press Return to close.")
                _ = readLine()
                await ForegroundCopyDonor.closeRetainedWindows()
            }

        case "focus-info":
            let focus = SystemFocusBroker()
            let target = try focus.captureFrontmostApplication()
            print("Frontmost app: \(displayName(target))")

        case "db-check":
            runDatabaseCheck(path: options.dbPath)

        case "help":
            printUsage()

        default:
            throw CLIError.unknownCommand(options.command)
        }
    }

    private static func printReady(_ result: CopyResult) {
        print("Ready: row \(result.row.rowID)")
        print("Clipboard length: \(result.clipboardText.count)")
        print("Transcript:")
        print(result.row.text)
    }

    private static func displayName(_ target: FocusTarget) -> String {
        let name = target.localizedName ?? "unknown"
        let bundle = target.bundleIdentifier ?? "no-bundle-id"
        return "\(name) [\(bundle)] pid=\(target.processIdentifier)"
    }

    private static func describeClipboard(_ value: String) -> String {
        let normalized = value.replacingOccurrences(of: "\n", with: "\\n")
        let preview = normalized.prefix(80)
        let suffix = normalized.count > 80 ? "..." : ""
        return "length=\(value.count) preview=\"\(preview)\(suffix)\""
    }

    private static func parseOptions(_ args: ArraySlice<String>) throws -> Options {
        var options = Options()
        var iterator = args.makeIterator()

        if let command = iterator.next() {
            options.command = command
        }

        while let arg = iterator.next() {
            switch arg {
            case "--db":
                options.dbPath = try iterator.nextValue(after: arg)
            case "--after":
                let value = try iterator.nextValue(after: arg)
                guard let rowID = Int64(value) else {
                    throw CLIError.invalidValue(option: arg, value: value)
                }
                options.afterRowID = rowID
            case "--timeout":
                let value = try iterator.nextValue(after: arg)
                guard let timeout = TimeInterval(value) else {
                    throw CLIError.invalidValue(option: arg, value: value)
                }
                options.timeoutSeconds = timeout
            case "--capture-delay":
                let value = try iterator.nextValue(after: arg)
                guard let delay = TimeInterval(value) else {
                    throw CLIError.invalidValue(option: arg, value: value)
                }
                options.captureDelaySeconds = delay
            case "--donor-hold":
                let value = try iterator.nextValue(after: arg)
                guard let hold = TimeInterval(value) else {
                    throw CLIError.invalidValue(option: arg, value: value)
                }
                options.donorHoldSeconds = hold
            case "--post-return-delay":
                let value = try iterator.nextValue(after: arg)
                guard let delay = TimeInterval(value) else {
                    throw CLIError.invalidValue(option: arg, value: value)
                }
                options.postReturnDelaySeconds = delay
            case "--donor-bundle":
                options.donorBundleIdentifier = try iterator.nextValue(after: arg)
            case "--donor-app":
                options.donorAppPath = try iterator.nextValue(after: arg)
            case "--copy-method":
                let value = try iterator.nextValue(after: arg)
                guard let method = CopyMethod(rawValue: value) else {
                    throw CLIError.invalidValue(option: arg, value: value)
                }
                options.copyMethod = method
            case "--skip-return":
                options.skipReturnFocus = true
            case "--keep-donor-open":
                options.keepDonorOpen = true
            case "--replace-v-with-space":
                options.replaceLeakedVWithSpace = true
            case "--visible-donor-window":
                options.visibleDonorWindow = true
            default:
                throw CLIError.unknownOption(arg)
            }
        }

        return options
    }

    private static func printUsage() {
        print(
            """
            Remote Wispr spike runner

            Commands:
              prime                         Print current max Wispr row.
              latest                        Copy latest usable row to the local clipboard.
              wait --after ROW [--timeout S] Wait for a newer row, copy it, and print Ready.
              wait-sync --after ROW          Wait, sync through a donor app, return focus, and print Ready.
              wait-sync-next                 Use current max row, then wait-sync the next row.
              focus-info                    Print the currently frontmost app captured by AppKit.
              db-check                      Print read-only Wispr SQLite diagnostics.

            Options:
              --db PATH      Wispr SQLite path. Defaults to the current user's Wispr Flow DB.
              --after ROW    Row marker for wait.
              --timeout S    Wait timeout in seconds. Default: 12.
              --capture-delay S
                             Delay before capturing the return app. Useful for clicking Screen Sharing.
              --donor-hold S
                             Seconds to keep the donor active after setting clipboard. Default: 1.0.
              --post-return-delay S
                             Seconds to wait before checking clipboard after returning focus. Default: 0.25.
              --donor-bundle BUNDLE_ID
                             Focus donor bundle. Default: com.remote-wispr.FocusDonor.
              --donor-app PATH
                             Persistent copy donor app path. Default: .build/apps/Remote Wispr Copy Donor.app.
              --copy-method METHOD
                             pasteboard-donor, foreground-copy, or persistent-donor-app.
                             Default: pasteboard-donor.
              --skip-return  Do not programmatically return focus after foreground-copy.
              --keep-donor-open
                             Keep foreground-copy donor window open until Return is pressed.
              --replace-v-with-space
                             Send one space after persistent donor copy, before manual paste.
              --visible-donor-window
                             Show the persistent donor window. Hidden by default.
            """
        )
    }

    private static func replaceLeakedVWithSpace() {
        sendKey(virtualKey: 51)
        sendKey(virtualKey: 49)
    }

    private static func sendKey(virtualKey: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false)
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private static func runDatabaseCheck(path: String) {
        let manager = FileManager.default
        let url = URL(fileURLWithPath: path)
        let parent = url.deletingLastPathComponent()
        let sidecars = [path, path + "-wal", path + "-shm"]

        print("Wispr DB diagnostics")
        print("Path: \(path)")
        print("SQLite library: \(String(cString: sqlite3_libversion()))")
        printDatabaseHeaderMode(path: path)
        print("Parent exists: \(manager.fileExists(atPath: parent.path) ? "yes" : "no")")
        print("Parent readable: \(manager.isReadableFile(atPath: parent.path) ? "yes" : "no")")
        print("Parent writable by this process: \(manager.isWritableFile(atPath: parent.path) ? "yes" : "no")")

        for sidecar in sidecars {
            print("")
            print("File: \(sidecar)")
            guard manager.fileExists(atPath: sidecar) else {
                print("  exists: no")
                continue
            }
            print("  exists: yes")
            print("  readable: \(manager.isReadableFile(atPath: sidecar) ? "yes" : "no")")
            print("  writable by this process: \(manager.isWritableFile(atPath: sidecar) ? "yes" : "no")")
            if let attributes = try? manager.attributesOfItem(atPath: sidecar) {
                if let size = attributes[.size] {
                    print("  size: \(size)")
                }
                if let modified = attributes[.modificationDate] {
                    print("  modified: \(modified)")
                }
                if let permissions = attributes[.posixPermissions] as? NSNumber {
                    print("  permissions: \(String(permissions.intValue, radix: 8))")
                }
            }
        }

        print("")
        print("Open mode: SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX")
        var db: OpaquePointer?
        let openResult = sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        print("open result: \(openResult) (\(sqliteResultName(openResult)))")
        guard let db else {
            print("open message: no database handle returned")
            return
        }

        print("open message: \(sqliteErrorMessage(db))")
        guard openResult == SQLITE_OK else {
            let closeResult = sqlite3_close(db)
            print("close result: \(closeResult) (\(sqliteResultName(closeResult)))")
            return
        }

        runDiagnosticSQL("PRAGMA database_list;", db: db)
        runDiagnosticSQL("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'History';", db: db)
        runDiagnosticSQL("SELECT COALESCE(MAX(rowid), 0) FROM History;", db: db)
        let closeResult = sqlite3_close(db)
        print("close result: \(closeResult) (\(sqliteResultName(closeResult)))")
    }

    private static func printDatabaseHeaderMode(path: String) {
        do {
            let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
            defer {
                try? handle.close()
            }
            try handle.seek(toOffset: 18)
            let data = handle.readData(ofLength: 2)
            guard data.count == 2 else {
                print("Header journal mode: unavailable")
                return
            }

            let writeVersion = data[data.startIndex]
            let readVersion = data[data.index(after: data.startIndex)]
            print("Header write version: \(writeVersion)")
            print("Header read version: \(readVersion)")
            print("Header journal mode: \(headerJournalMode(writeVersion: writeVersion, readVersion: readVersion))")
        } catch {
            print("Header journal mode: unavailable (\(error))")
        }
    }

    private static func headerJournalMode(writeVersion: UInt8, readVersion: UInt8) -> String {
        switch (writeVersion, readVersion) {
        case (1, 1):
            return "rollback"
        case (2, 2):
            return "wal"
        default:
            return "unknown"
        }
    }

    private static func runDiagnosticSQL(_ sql: String, db: OpaquePointer) {
        print("")
        print("SQL: \(sql)")
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        print("prepare result: \(prepareResult) (\(sqliteResultName(prepareResult)))")
        print("prepare message: \(sqliteErrorMessage(db))")
        guard prepareResult == SQLITE_OK, let statement else {
            if let statement {
                sqlite3_finalize(statement)
            }
            return
        }

        let stepResult = sqlite3_step(statement)
        print("step result: \(stepResult) (\(sqliteResultName(stepResult)))")
        print("step message: \(sqliteErrorMessage(db))")
        if stepResult == SQLITE_ROW {
            let columnCount = sqlite3_column_count(statement)
            for index in 0..<columnCount {
                let name = sqlite3_column_name(statement, index).map(String.init(cString:)) ?? "column\(index)"
                let value = sqlite3_column_text(statement, index).map(String.init(cString:)) ?? "NULL"
                print("column \(index) \(name): \(value)")
            }
        }
        sqlite3_finalize(statement)
    }

    private static func sqliteErrorMessage(_ db: OpaquePointer) -> String {
        sqlite3_errmsg(db).map(String.init(cString:)) ?? "unknown error"
    }

    private static func sqliteResultName(_ code: Int32) -> String {
        switch code {
        case SQLITE_OK:
            return "SQLITE_OK"
        case SQLITE_ROW:
            return "SQLITE_ROW"
        case SQLITE_DONE:
            return "SQLITE_DONE"
        case SQLITE_CANTOPEN:
            return "SQLITE_CANTOPEN"
        case SQLITE_READONLY:
            return "SQLITE_READONLY"
        case SQLITE_BUSY:
            return "SQLITE_BUSY"
        case SQLITE_LOCKED:
            return "SQLITE_LOCKED"
        case SQLITE_NOTADB:
            return "SQLITE_NOTADB"
        case SQLITE_IOERR:
            return "SQLITE_IOERR"
        default:
            return "code \(code)"
        }
    }
}

enum CLIError: Error, CustomStringConvertible {
    case missingRequiredOption(String)
    case invalidValue(option: String, value: String)
    case unknownCommand(String)
    case unknownOption(String)

    var description: String {
        switch self {
        case let .missingRequiredOption(option):
            "Missing required option \(option)."
        case let .invalidValue(option, value):
            "Invalid value for \(option): \(value)."
        case let .unknownCommand(command):
            "Unknown command: \(command)."
        case let .unknownOption(option):
            "Unknown option: \(option)."
        }
    }
}

extension IteratorProtocol where Element == String {
    mutating func nextValue(after option: String) throws -> String {
        guard let value = next() else {
            throw CLIError.missingRequiredOption(option)
        }
        return value
    }
}
