import Foundation

public enum TranscriptWatcherError: Error, Equatable {
    case timeout(afterRowID: Int64)
}

public final class TranscriptWatcher {
    private let store: TranscriptStore
    private let pollIntervalNanoseconds: UInt64
    private let stabilizationSeconds: TimeInterval

    public init(
        store: TranscriptStore,
        pollIntervalSeconds: TimeInterval = 0.25,
        stabilizationSeconds: TimeInterval = 3.0
    ) {
        self.store = store
        self.pollIntervalNanoseconds = UInt64(max(0.05, pollIntervalSeconds) * 1_000_000_000)
        self.stabilizationSeconds = max(0, stabilizationSeconds)
    }

    public func waitForNext(after rowID: Int64, timeoutSeconds: TimeInterval) async throws -> TranscriptRow {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var candidate: TranscriptRow?
        var candidateFirstSeenAt: Date?

        while Date() <= deadline {
            if let row = try store.oldestUsableRow(after: rowID) {
                let now = Date()
                if row == candidate {
                    if let candidateFirstSeenAt,
                       now.timeIntervalSince(candidateFirstSeenAt) >= stabilizationSeconds {
                        return row
                    }
                } else {
                    candidate = row
                    candidateFirstSeenAt = now
                }
            }

            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }

        throw TranscriptWatcherError.timeout(afterRowID: rowID)
    }
}
