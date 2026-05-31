# Remote Wispr Architecture

## Purpose

Remote Wispr helps a local Mac running Wispr Flow place dictated text into a text box on a remote Mac controlled through Apple Screen Sharing.

The project should be treated as a local Mac integration. It is not a Wispr remote-desktop integration and it does not require Wispr to run on the remote Mac.

## Current Findings

The two hard problems have working proof points:

1. Wispr transcript retrieval works.
   - Wispr Flow stores usable transcript rows in local SQLite.
   - The known database path is:
     `$HOME/Library/Application Support/Wispr Flow/flow.sqlite`
   - The useful table is `History`.
   - Usable transcript columns include `editedText`, `formattedText`, `defaultFormattedText`, `fallbackFormattedText`, `asrText`, `defaultAsrText`, and `fallbackAsrText`.

2. Shared clipboard sync works if focus briefly leaves Screen Sharing.
   - `pbcopy` and `hs.pasteboard.setContents()` update the local clipboard.
   - Apple Screen Sharing does not always sync those programmatic writes while Screen Sharing remains frontmost.
   - A temporary focus donor app makes the shared clipboard bridge observe the new local pasteboard.

The remaining failures are orchestration problems:

- Wispr writes rows asynchronously.
- Screen Sharing syncs clipboard asynchronously.
- Automatic `Ctrl+Option` release detection can miss or wedge.
- Synthetic auto-paste can fire before Screen Sharing has accepted the updated clipboard.

## Design Principle

Timing should delay progress, not define correctness.

The final system should be a state machine that observes facts:

- a new Wispr row exists,
- a row has not been processed before,
- the local pasteboard contains the expected text,
- focus moved out of Screen Sharing and returned,
- the system is ready for manual or automatic paste.

Avoid building correctness around fixed sleeps alone.

## Implementation Readiness Gate

Before accepting an OS-level, permission, external-app, clipboard, hotkey, or Screen Sharing design, name the risky assumption and classify proof.

Proof levels:

- External proof: vendor docs, official manuals, or credible operational examples show this class of setup works.
- Local proof: the setup works on an actual local Mac with Wispr Flow, Apple Screen Sharing, permissions, accounts, and network path.
- Production proof: it survives reboot/relaunch, has correct app/account ownership, has required permissions documented, logs failures, recovers without restarting the whole workflow, and has rollback/uninstall instructions.

If external proof is weak or generic, run a small spike before designing around it. Timebox unclear experiments and stop when the proof does not land.

Current proof classification:

| Area | Current proof | Accepted? | Notes |
| --- | --- | --- | --- |
| Wispr transcript retrieval from SQLite | Local proof from actual Wispr Flow database | Accepted for prototype, spike required for app | Relies on private app storage, so schema/access checks must be automated. |
| Shared clipboard sync via persistent copy donor | Local proof from actual Screen Sharing workflow | Accepted prototype baseline | Donor launches, copies by normal app copy behavior, reports ready, then closes itself. Hidden donor mode is the current default; visible donor remains a fallback. |
| Manual paste after ready | Local proof in windowed and full-screen Screen Sharing | Accepted baseline | Manual `Cmd+V` is the stable user-facing paste path. Full screen requires manual return to the Screen Sharing Space before paste. |
| Control+Option release trigger | Local proof from actual Wispr Flow and Screen Sharing workflow | Accepted local app baseline | Records the max row on key down, waits for the next row on key release, then uses the same donor/manual-paste path. |
| Full-screen programmatic return | Negative local proof | Not accepted | App activation by PID did not return to the full-screen Space and disturbed clipboard state. Keep separate from baseline. |
| Synthetic auto-paste | Weak/negative local proof | Not accepted | It can fire before Screen Sharing has synced the clipboard. Make it feature-flagged only. |
| Leaked-`v` cleanup | Partial local proof | Not accepted as default | It is remote-field dependent and should be optional. |
| Menu bar app architecture | Local proof from actual Wispr Flow and Screen Sharing workflow | Accepted local baseline | Settings, logging, manual trigger, Control+Option trigger, and donor copy have local proof. |

## Accepted Baseline Boundary

The accepted local app baseline is Control+Option trigger plus manual paste:

1. User holds Control+Option and dictates with Wispr.
2. Remote Wispr records the current max Wispr row on key down.
3. User releases Control+Option.
4. Remote Wispr waits for the next usable Wispr transcript row using read-only SQLite access.
5. Launch the persistent copy donor app.
6. Copy the transcript through the donor app.
7. Verify the local clipboard contains the transcript.
8. Let the donor app close itself.
9. Report ready.
10. User presses `Cmd+V` in the remote text box.

The menu item `Copy Next Wispr Transcript` remains the manual fallback trigger. The CLI command `make local-sync-next` remains the component smoke test for transcript read, donor copy, clipboard verification, and manual paste.

This baseline intentionally does not:

- clean up the leaked remote `v`,
- return to a full-screen Space,
- send `Cmd+V`,
- modify, repair, copy, checkpoint, or write to the Wispr database.

Changes to cleanup, full-screen focus return, alternate hotkeys, or auto-paste must be developed as separate optional modules. A failure in one of those modules does not invalidate the accepted trigger, transcript-read, and donor-copy baseline unless it changes the baseline code path.

The component smoke command is:

```sh
make local-sync-next
```

The baseline proof should be re-run only when one of these areas changes:

- `TranscriptStore`,
- `TranscriptWatcher`,
- persistent copy donor app behavior,
- `PersistentDonorApp`,
- the baseline `local-sync-next` command.

Experimental modules must have their own command or feature flag and their own pass/fail notes before being folded into the default workflow.

The donor app has two visibility modes:

- hidden donor: default baseline path,
- visible donor: diagnostic fallback via `make local-sync-next-visible-donor`.

Changing donor visibility should not change `TranscriptStore` or `TranscriptWatcher` behavior.

## Proposed Product Shape

Build a small local macOS menu bar app.

The menu bar app owns the workflow end to end:

1. Wait for a trigger.
2. Wait for Wispr to write a transcript row.
3. Select the oldest unprocessed transcript row.
4. Write the transcript to the local pasteboard.
5. Briefly activate a focus donor.
6. Return focus to Screen Sharing.
7. Mark the transcript ready to paste.
8. Optionally clean up the leaked `v`.
9. Optionally send `Cmd+V`.

The existing Focus Donor app can either be absorbed into the menu bar app or remain a tiny helper process if macOS requires a separate frontmost app to trigger Screen Sharing clipboard sync.

## Modules

### Settings

Responsibility:

- Store user-configurable paths and feature flags.
- Keep risky behaviors disabled by default.
- Make the current configuration visible from the menu bar app.

Initial settings:

- Wispr SQLite database path.
- Clipboard sync mode: local-only or focus-donor.
- Focus donor bundle identifier.
- Remote cleanup mode: disabled, Backspace, or Backspace then Space.
- Automatic paste: disabled by default.
- Automatic trigger: disabled by default.
- Wispr wait timeout.
- Wispr polling interval.

Menu requirements:

- Settings/Preferences.
- Choose Wispr database file.
- Reset Wispr database path to default.
- Toggle clipboard sync mode.
- Set focus donor bundle identifier.
- Toggle optional cleanup.
- Toggle optional automatic paste.
- Toggle optional automatic trigger only after it has proof.
- Reset state.
- Open log.

Rules:

- Defaults must preserve the manual paste baseline.
- Experimental features must be explicit toggles, never implicit behavior.
- Settings changes should be logged.
- Invalid database paths should fail visibly and recoverably.

### TranscriptStore

Responsibility:

- Open the Wispr SQLite database read-only.
- Read transcript rows from `History`.
- Hide column fallback logic from the rest of the app.

Inputs:

- database path,
- `afterRowId`.

Outputs:

- transcript row ID,
- transcript text,
- timestamp/status metadata when available.

Rules:

- never return empty text,
- prefer Wispr transcript fields in this order: `formattedText`, `defaultFormattedText`, `fallbackFormattedText`, `asrText`, `defaultAsrText`, `fallbackAsrText`, then `editedText`,
- trim leading and trailing whitespace from the selected transcript,
- avoid `pastedText` because it may include remote paste artifacts,
- open and query the Wispr database read-only,
- do not fall back to read/write access,
- do not repair, checkpoint, vacuum, migrate, write pragmas, or manipulate SQLite sidecar files,
- if read-only access fails, stop and report the failure,
- tolerate Wispr being open while SQLite has WAL files.

### TranscriptWatcher

Responsibility:

- Wait for Wispr to produce a row after a trigger.
- Poll asynchronously.
- Never block UI or hotkey processing.

Inputs:

- `afterRowId`,
- timeout,
- poll interval.

Outputs:

- `rowFound(row)`,
- `timeout(afterRowId)`.

Rules:

- polling stops once a row is found,
- timeout returns to idle/recoverable state,
- late rows are not lost if they appear after timeout; they can be handled by explicit manual fetch or skipped intentionally.

### TranscriptQueue

Responsibility:

- Process rows once, oldest first.
- Track the last processed row.

Rules:

- do not reuse a row,
- do not skip intermediate rows unless the user explicitly resets or skips,
- keep the state visible in diagnostics.

Question for implementation:

- Store `lastProcessedRowId` in memory only, or persist it across app restarts?

The safer default is to initialize `lastProcessedRowId` to the current max row at app launch, then process only future rows.

### ClipboardBroker

Responsibility:

- Set local macOS pasteboard text.
- Verify local pasteboard contents.

Inputs:

- transcript text.

Outputs:

- success/failure,
- actual pasteboard value for diagnostics if verification fails.

### FocusBroker

Responsibility:

- Move focus out of Screen Sharing briefly.
- Return focus to the prior app.

Candidate implementations:

- menu bar app activates itself,
- separate Focus Donor app activates,
- fallback to Finder only for diagnostics.

Rules:

- no documents,
- no windows unless required,
- no Space jump,
- repeated attempts to return focus,
- explicit failure if focus does not return.

### SharedClipboardSync

Responsibility:

- Combine `FocusBroker` and `ClipboardBroker` into one operation:
  `sync text to shared clipboard`.

Flow:

1. Capture frontmost app.
2. Activate focus donor.
3. Set local pasteboard.
4. Verify local pasteboard.
5. Return to previous app.
6. Emit `readyToPaste(rowId)`.

This module should not paste. It only makes the text available.

### RemoteCleanup

Responsibility:

- Optionally clean up Wispr's leaked `v` in Screen Sharing.

Modes:

- disabled,
- Backspace,
- Backspace then Space.

Rules:

- only run if returning to Screen Sharing,
- run after focus returns,
- log the action,
- be optional because cleanup is remote-text-field dependent.

### PasteController

Responsibility:

- Optionally send `Cmd+V` after `readyToPaste`.

Default:

- manual paste remains the stable supported path.

Auto-paste should be feature-flagged because it is a symptom layer. If shared clipboard sync is reliable and readiness is real, auto-paste is simple. If auto-paste fails, the failure usually belongs to clipboard-sync readiness, focus, or remote app timing.

### TriggerController

Responsibility:

- Decide when a new transcript should be fetched.

Possible triggers:

- manual global hotkey,
- menu bar item,
- automatic Wispr `Ctrl+Option` release detection,
- hybrid automatic trigger plus manual retry.

Recommended baseline:

- Control+Option release trigger plus manual paste,
- menu bar item as the manual fallback trigger.

Reason:

- trigger reliability should not block validation of transcript retrieval and shared clipboard sync.

Current app behavior:

- the Control+Option trigger is the accepted local app trigger,
- the menu item remains the fallback trigger,
- Control+Option down records the current max Wispr row,
- Control+Option release waits for the next usable row after that marker,
- the trigger does not paste, clean up the leaked `v`, or move Spaces.

### Diagnostics

Responsibility:

- Make failures explainable.

Required diagnostics:

- current state,
- last processed row ID,
- pending row wait,
- latest row in Wispr DB,
- last transcript preview,
- last error,
- focus return status,
- clipboard verification status,
- reset action.

Log file should include:

- timestamps,
- state transitions,
- row IDs,
- transcript preview,
- trigger source,
- timeout events,
- focus donor activity,
- paste/cleanup activity.

## State Machine

```text
Idle
  -> Triggered
  -> WaitingForWisprRow
  -> RowFound
  -> LocalClipboardSet
  -> FocusDonorActive
  -> FocusReturned
  -> ReadyToPaste
  -> Done
  -> Idle
```

Error states:

```text
TimeoutWaitingForRow
ClipboardVerifyFailed
FocusReturnFailed
PasteFailed
Reset
```

Every error must return to `Idle` or a visible recoverable state. No path should require restarting the helper or relaunching the app.

## Supported Workflow

The stable workflow to design around:

1. User dictates with Wispr Flow.
2. User triggers Remote Wispr when done, or automatic trigger fires.
3. Remote Wispr waits for the next Wispr row.
4. Remote Wispr syncs that text to the shared clipboard.
5. User sees `Ready to paste`.
6. User presses physical `Cmd+V`.

Auto-paste is an optional layer after step 5.

## Non-Goals

- Do not run Wispr on the remote Mac unless remote microphone input is proven.
- Do not depend on a special Wispr remote-desktop integration.
- Do not type long transcripts as keystrokes except as a fallback.
- Do not make Screen Sharing clipboard timing assumptions invisible.

## Implementation Phases

### Phase 1: Stabilize The Prototype Boundary

- Keep the source-build app path as the supported implementation.
- Keep manual paste as the supported path.
- Document known working settings and failure cases.

### Phase 2: Build Menu Bar App Skeleton

- App lifecycle,
- menu/status item,
- global hotkey,
- log view or log file,
- reset action.

### Phase 3: Port Transcript Modules

- Read Wispr SQLite directly.
- Unit test row selection.
- Add async row watcher.

### Phase 4: Port Clipboard And Focus Modules

- Implement pasteboard write/verify.
- Implement focus donor behavior.
- Test whether the menu bar app can be its own donor.
- Keep separate donor helper only if needed.

### Phase 5: Integrate State Machine

- Wire trigger -> row wait -> clipboard sync -> ready state.
- Manual paste remains primary.

### Phase 6: Optional Cleanup And Auto-Paste

- Add leaked-`v` cleanup as a feature flag.
- Add auto-paste as a feature flag.
- Require module-level evidence before making auto-paste default.
