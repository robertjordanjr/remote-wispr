import Foundation

public struct CopyResult: Equatable {
    public let row: TranscriptRow
    public let clipboardText: String

    public init(row: TranscriptRow, clipboardText: String) {
        self.row = row
        self.clipboardText = clipboardText
    }
}

public enum SpikeWorkflowError: Error, Equatable {
    case noTranscript(afterRowID: Int64)
}

public final class SpikeWorkflow {
    private let transcriptStore: TranscriptStore
    private let clipboardBroker: ClipboardBroker

    public init(transcriptStore: TranscriptStore, clipboardBroker: ClipboardBroker) {
        self.transcriptStore = transcriptStore
        self.clipboardBroker = clipboardBroker
    }

    public func copyNextTranscript(after afterRowID: Int64) throws -> CopyResult {
        guard let row = try transcriptStore.oldestUsableRow(after: afterRowID) else {
            throw SpikeWorkflowError.noTranscript(afterRowID: afterRowID)
        }

        try clipboardBroker.setText(row.text)
        return CopyResult(row: row, clipboardText: clipboardBroker.currentText() ?? "")
    }
}
