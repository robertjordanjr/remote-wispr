import Foundation

public enum TranscriptWatcherError: Error, Equatable {
    case timeout(afterRowID: Int64)
}

public final class TranscriptWatcher {
    private let store: TranscriptStore
    private let pollIntervalNanoseconds: UInt64

    public init(store: TranscriptStore, pollIntervalSeconds: TimeInterval = 0.25) {
        self.store = store
        self.pollIntervalNanoseconds = UInt64(max(0.05, pollIntervalSeconds) * 1_000_000_000)
    }

    public func waitForNext(after rowID: Int64, timeoutSeconds: TimeInterval) async throws -> TranscriptRow {
        let deadline = Date().addingTimeInterval(timeoutSeconds)

        while Date() <= deadline {
            if let row = try store.oldestUsableRow(after: rowID) {
                return row
            }

            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }

        throw TranscriptWatcherError.timeout(afterRowID: rowID)
    }
}
