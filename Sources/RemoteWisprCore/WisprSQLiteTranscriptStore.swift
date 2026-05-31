import Foundation
import SQLite3

public enum WisprSQLiteError: Error, Equatable, CustomStringConvertible {
    case openFailed(path: String, message: String)
    case prepareFailed(sql: String, message: String)
    case stepFailed(message: String)

    public var description: String {
        switch self {
        case let .openFailed(path, message):
            "Could not open SQLite database at \(path): \(message)"
        case let .prepareFailed(_, message):
            "Could not prepare SQLite query: \(message)"
        case let .stepFailed(message):
            "SQLite query failed: \(message)"
        }
    }
}

public final class WisprSQLiteTranscriptStore: TranscriptStore {
    public static let defaultDatabasePath =
        "\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Application Support/Wispr Flow/flow.sqlite"

    private let databasePath: String

    public init(databasePath: String = WisprSQLiteTranscriptStore.defaultDatabasePath) {
        self.databasePath = databasePath
    }

    public func maxRowID() throws -> Int64 {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = "SELECT COALESCE(MAX(rowid), 0) FROM History;"
        let statement = try prepare(sql: sql, db: db)
        defer { sqlite3_finalize(statement) }

        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW else {
            throw WisprSQLiteError.stepFailed(message: errorMessage(db))
        }

        return sqlite3_column_int64(statement, 0)
    }

    public func oldestUsableRow(after rowID: Int64) throws -> TranscriptRow? {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        SELECT
            rowid,
            formattedText,
            defaultFormattedText,
            fallbackFormattedText,
            asrText,
            defaultAsrText,
            fallbackAsrText,
            editedText,
            timestamp,
            status
        FROM History
        WHERE rowid > ?
          AND COALESCE(isArchived, 0) = 0
          AND COALESCE(status, '') <> 'no_audio'
        ORDER BY rowid ASC
        LIMIT 25;
        """

        let statement = try prepare(sql: sql, db: db)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, rowID)

        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return nil
            }
            guard result == SQLITE_ROW else {
                throw WisprSQLiteError.stepFailed(message: errorMessage(db))
            }

            guard let text = bestTranscriptText(from: statement) else {
                continue
            }

            return TranscriptRow(
                rowID: sqlite3_column_int64(statement, 0),
                text: text,
                timestamp: stringColumn(statement, 8),
                status: stringColumn(statement, 9)
            )
        }
    }

    private func openDatabase() throws -> OpaquePointer {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX

        guard sqlite3_open_v2(databasePath, &db, flags, nil) == SQLITE_OK, let opened = db else {
            let message = db.map(errorMessage) ?? "unknown error"
            if let db {
                sqlite3_close(db)
            }
            throw WisprSQLiteError.openFailed(path: databasePath, message: message)
        }

        return opened
    }

    private func prepare(sql: String, db: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let prepared = statement else {
            throw WisprSQLiteError.prepareFailed(sql: sql, message: errorMessage(db))
        }

        return prepared
    }

    private func stringColumn(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let cString = sqlite3_column_text(statement, index)
        else {
            return nil
        }

        return String(cString: cString)
    }

    private func bestTranscriptText(from statement: OpaquePointer) -> String? {
        // Prefer Wispr's generated transcript fields. editedText can contain partial
        // padded values while Wispr is still extracting user edits.
        for index in 1...7 {
            guard let value = stringColumn(statement, Int32(index)) else {
                continue
            }

            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return nil
    }

    private func errorMessage(_ db: OpaquePointer) -> String {
        if let cString = sqlite3_errmsg(db) {
            return String(cString: cString)
        }
        return "unknown error"
    }
}
