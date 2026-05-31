# Spike 1: App-Managed Clipboard Baseline

## Question

Can a small local macOS helper reliably move the newest Wispr Flow transcript into the clipboard path used by Apple Screen Sharing, then report that the text is ready for a manual paste?

## Proof Target

Required proof level: local proof.

This spike is not accepted until it works on the user's local Mac with:

- Wispr Flow installed and producing rows,
- Apple Screen Sharing connected to the remote Mac,
- the remote text box focused,
- the shared clipboard path enabled,
- the helper able to set and verify the local pasteboard.

## In Scope

- Read the Wispr Flow SQLite database read-only.
- Find the oldest usable row after a marker.
- Set and verify the local macOS pasteboard.
- Accept a configurable Wispr SQLite path.
- Provide a tiny command-line runner for local smoke testing.
- Keep fixture tests runnable in this repo without Wispr or Screen Sharing.

## Out Of Scope

- Automatic paste.
- Automatic dictation-release detection.
- Remote text cleanup.
- Packaging polish.
- Long-running menu bar behavior.

## Repo Tests

Run from the repo:

```sh
make test-fixtures
make build-spike
```

These tests prove:

- default settings preserve the manual baseline,
- settings can be saved and reloaded,
- row selection is deterministic,
- transcript column fallback works,
- partial `editedText` does not outrank complete formatted transcript fields,
- empty, archived, and `no_audio` rows are ignored,
- the workflow copies exactly one row into a clipboard abstraction,
- the async watcher times out instead of wedging.

Tool note:

- The repo currently uses a tiny Swift self-test executable instead of `swift test`.
- On this remote machine, the command-line Swift install did not expose the usual Swift test modules.
- The self-test runner is acceptable for this spike because it keeps fixture checks automated without adding a dependency.
- If the local Mac has a fuller Xcode test environment, we can compare and decide whether to move these checks to the standard test runner.

## Local Smoke Test

Run this on the local Mac that has Wispr Flow and the remote Screen Sharing session.

1. Build the spike runner:

   ```sh
   make build-spike
   ```

2. Capture the current Wispr row marker:

   ```sh
   .build/debug/remote-wispr-spike prime
   ```

3. Dictate once with Wispr Flow.

4. Wait for that newer row and copy it to the local pasteboard:

   ```sh
   .build/debug/remote-wispr-spike wait --after ROW_FROM_STEP_2 --timeout 20
   ```

5. When the command prints `Ready: row ####`, return to the remote text box and press physical `Cmd+V`.

Pass criteria:

- The command prints the correct new row.
- The printed transcript matches what should be pasted.
- Manual `Cmd+V` in the remote text box pastes the current transcript, not older clipboard text.

## Five-Run Test

Repeat the local smoke test for five controlled dictations:

```text
Alpha.
Bravo.
Charlie.
Delta.
Echo.
```

Pass criteria:

- Each run uses a newer row ID.
- Each run updates the local pasteboard to the current transcript.
- Each manual paste into the remote text box inserts the matching text.
- Failure does not require restarting the helper; rerunning `prime` and `wait` is enough to recover.

## Decision

This has passed on the local Mac for five controlled dictations. The clipboard baseline has local proof.

The next spike is `docs/spike-2-focus-sync.md`.

If this fails, stop and classify the failure before adding automation:

- transcript read failure,
- stale local pasteboard,
- shared clipboard sync failure,
- focus/Space issue,
- remote text box issue.
