# Remote Wispr Test Plan

## Goal

Make each part of Remote Wispr independently testable so failures point to one module instead of a pile of timing guesses.

The tests should answer:

- Did Wispr produce a row?
- Did we choose the right row?
- Did the local pasteboard contain the right text?
- Did Screen Sharing receive the updated clipboard?
- Did cleanup or paste run too early?
- Did the system recover without reload?

## Readiness Gate

Every module that depends on macOS, Wispr, Screen Sharing, permissions, global hotkeys, or another external system must state its proof level before it is considered accepted.

Use these labels:

- External proof: credible docs or examples show the class of setup works.
- Local proof: the setup works on an actual local Mac and remote Screen Sharing path.
- Production proof: it survives relaunch/reboot where relevant, permissions are documented, logs are available, reset/rollback works, and ownership/account expectations are clear.

Tests should explicitly say which proof level they provide. A plausible design with only generic external proof is a spike candidate, not an accepted design.

## Test Levels

## Environment Split

Most development should be testable on the repo machine, even if that machine is not the local Mac that runs Wispr and Screen Sharing. Each test should be labeled by the least-powerful environment that can run it.

### Remote/Repo Tests

These can run in this repository without the user's local Mac setup:

- pure state machine tests,
- transcript row-selection tests against SQLite fixtures,
- transcript column fallback tests,
- queue and timeout tests,
- shell syntax checks,
- log formatting tests,
- mocked clipboard/focus/paste module tests,
- documentation checks.

These tests should become the default automated suite.

### Local Mac Tests

These require the user's local Mac because they depend on real macOS state:

- reading the live Wispr Flow database,
- global hotkeys,
- microphone-driven Wispr dictation,
- local NSPasteboard behavior,
- Focus Donor activation,
- Apple Screen Sharing focus return,
- Accessibility permissions,
- cleanup keystrokes,
- physical or synthetic `Cmd+V`.

These should be packaged as a local smoke test script/app command rather than mixed into normal repo tests.

### Local/Remote Integration Tests

These require both the local Mac and an active remote Mac text box:

- verifying that Screen Sharing receives updated shared clipboard text,
- verifying physical `Cmd+V` into the remote app,
- verifying leaked-`v` cleanup,
- validating optional auto-paste.

These tests should be few, explicit, and run only after the remote/repo and local-only suites pass.

### Automation Strategy

Use three commands or test groups:

```text
test:fixtures       # repo-only tests with fixture DBs and mocked modules
local-db-check      # local Mac read-only Wispr DB diagnostics
test:local-smoke    # local Mac tests against live Wispr/macOS components
test:e2e-manual     # guided local/remote Screen Sharing checklist
```

### Regression Boundary

The accepted local app baseline is:

- Remote Wispr menu bar app is running on the local Mac,
- Wispr shortcut trigger is enabled in Settings,
- Wispr shortcut modifiers match Wispr Flow's configured push-to-talk shortcut,
- user holds the configured Wispr shortcut and dictates with Wispr,
- release starts the wait-for-next-row workflow,
- persistent donor reports `clipboardMatches=yes`,
- menu bar status changes to `RW Ready`,
- manual `Cmd+V` pastes the current transcript in the remote text box.

The component smoke test for the same transcript and donor path is:

```sh
make local-sync-next
```

Baseline pass criteria:

- live Wispr DB read-only access succeeds,
- Wispr history storage is set to at least 24 hours or all-local storage,
- a new Wispr row is found after the trigger marker,
- the persistent donor reports `clipboardMatches=yes`,
- donor app closes itself,
- menu bar status shows ready,
- Diagnostics shows the last marker row, last copied row, donor clipboard match, and no last error,
- manual `Cmd+V` pastes the current transcript in windowed and full-screen Screen Sharing,
- no full-screen focus-return work is needed unless a new local failure appears.

Reboot/login pass criteria:

- installed app launches from `$HOME/Applications/Remote Wispr.app`,
- settings persist after login,
- Accessibility permission still applies to the installed app,
- Diagnostics can read the Wispr DB max row,
- `Run Baseline Health Check` reports `Baseline health: ok`,
- the configured Wispr shortcut trigger still produces `RW Ready`,
- manual `Cmd+V` pastes the current transcript.

Baseline health check pass criteria:

- runs without requiring dictation, Screen Sharing, donor launch, clipboard writes, paste, or permission changes,
- reports app version/build,
- confirms the settings file is present and readable,
- confirms the configured Wispr DB can answer the normal read-only max-row query,
- warns when the configured Wispr DB has max row `0`, because Wispr may be set to store no local history,
- confirms the configured copy donor app exists,
- confirms Wispr shortcut trigger is enabled,
- reports remote cleanup mode,
- confirms timing settings are valid,
- records the result in Diagnostics and the app log.

Reset Running State pass criteria:

- clears only Remote Wispr in-memory running state, hotkey marker, and last error,
- re-enables the manual copy menu item,
- logs `running state reset`,
- does not modify Wispr files, database sidecars, Accessibility permissions, donor processes, Screen Sharing, or clipboard contents.

Manual launch at login pass criteria:

- Remote Wispr has no in-app launch-at-login checkbox,
- Settings saves do not add, remove, or duplicate macOS Login Items,
- user manually removes stale or duplicate `Remote Wispr.app` entries from System Settings > General > Login Items & Extensions,
- user manually adds `$HOME/Applications/Remote Wispr.app` under Open at Login if desired,
- after reboot/login, `Remote Wispr.app` starts automatically,
- the configured Wispr shortcut trigger still produces `RW Ready`,
- manual `Cmd+V` pastes the current transcript.

Optional paste path:

- manual `Cmd+V` remains the fallback when Auto paste is disabled,
- when Auto paste and cleanup are enabled, Diagnostics should show donor clipboard match, donor handoff, `focusReady=true`, cleanup sent, and paste sent,
- if Screen Sharing is not frontmost after donor handoff, Remote Wispr must not send cleanup or paste keystrokes.

Wispr shortcut context gate:

- with Screen Sharing frontmost, the configured Wispr shortcut arms Remote Wispr and can produce `RW Ready`,
- with any local app frontmost, the configured Wispr shortcut is skipped and must not launch donor copy, alter clipboard, reactivate Screen Sharing, or start a running task,
- Diagnostics records the skip reason.

Manual disable:

- menu item toggles between disabled and enabled,
- Option-clicking the `RW` menu bar item toggles disabled/enabled without opening the menu,
- Remote Wispr does not use a global utility keystroke for manual disable,
- when disabled, the configured Wispr shortcut is skipped even if Screen Sharing is frontmost,
- menu bar title shows `RW Off`.

These limitations belong to separate optional modules:

- `RemoteCleanup`,
- `AutoPaste`,
- alternate trigger modes.

Testing one of those optional modules must not require re-proving transcript selection, Wispr shortcut trigger detection, or donor copy unless its implementation touches the baseline modules. If an optional module fails, revert or disable that module and keep the baseline accepted.

Remote cleanup status:

- the earlier CGEvent Backspace path failed local proof,
- the System Events input spike removed the leaked `v` and pasted donor clipboard text,
- app integration uses the System Events path,
- keep Remote Cleanup disabled by default, but it can be enabled with Auto paste after input permissions are confirmed.

Auto-paste status:

- local spike proof passed for donor clipboard sync followed by System Events Command+V,
- app integration has local proof with donor focus handoff and remains disabled by default,
- app integration requires Accessibility permission for `$HOME/Applications/Remote Wispr.app` and Automation permission for Remote Wispr to control System Events,
- auto-paste failures must not prevent the manual `Cmd+V` fallback.

Input permissions:

- choose `Check Input Permissions` from the Remote Wispr menu,
- if Accessibility is missing, enable `$HOME/Applications/Remote Wispr.app` in System Settings > Privacy & Security > Accessibility,
- if macOS prompts, allow Remote Wispr to control System Events,
- Diagnostics should report `ok - Accessibility enabled and Remote Wispr can control System Events`,
- if Diagnostics reports not authorized, enable System Events under Remote Wispr in System Settings > Privacy & Security > Automation.

The cleanup experiment command is intentionally separate:

```sh
make local-sync-next-cleanup-experimental
```

Do not replace `make local-sync-next` with an experimental command until that module has its own local proof.

The final app can expose the local tests through a diagnostics menu:

- Check Wispr DB path,
- Read latest row,
- Set local clipboard test value,
- Run focus donor test,
- Show current state,
- Export logs.

### Level 1: Unit Tests

These should not require Wispr, Screen Sharing, or a remote Mac.

Targets:

- transcript column fallback,
- row ordering,
- queue behavior,
- state machine transitions,
- timeout handling.

Recommended fixtures:

- SQLite fixture with empty rows,
- SQLite fixture with rows 1 through 5,
- SQLite fixture where rows appear after a delay,
- rows with text in different transcript columns.

### Level 2: Local Integration Tests

These run on the local Mac but do not require Screen Sharing.

Start with:

```sh
make local-db-check
```

This command is read-only. It reports the configured Wispr DB path, SQLite header journal mode, sidecar file state, SQLite open result, and prepare/step results for the exact query class used by the helper.

Targets:

- read real Wispr database read-only,
- get latest row ID,
- wait for row after trigger,
- set and verify local pasteboard,
- write diagnostics.

### Level 3: Screen Sharing Clipboard Tests

These require Apple Screen Sharing connected to a remote Mac text box.

Targets:

- focus donor activation,
- shared clipboard sync,
- focus return,
- manual paste.

### Level 4: End-To-End Workflow Tests

These test the user workflow.

Targets:

- one dictation,
- three controlled dictations,
- five controlled dictations,
- longer dictation,
- timeout/recovery,
- optional cleanup,
- optional auto-paste.

## Module Tests

### TranscriptStore

Purpose:

Verify that transcript reading is correct independent of UI automation.

Test cases:

1. Get max row ID.
   - Given a fixture DB with rows 10, 11, 12.
   - Expect max row ID 12.

2. Get oldest row after marker.
   - Given rows 10, 11, 12.
   - Query after 10.
   - Expect row 11.

3. Do not reuse processed rows.
   - Given last processed row 12.
   - Query after 12.
   - Expect no row.

4. Column fallback.
   - Given a row with `formattedText`, use it.
   - Given no `formattedText` but `asrText`, use `asrText`.
   - Avoid `pastedText` unless explicitly allowed.

5. Ignore unusable rows.
   - Skip empty transcripts.
   - Skip `no_audio` rows.
   - Skip archived rows.

Pass criteria:

- returned row IDs and text match fixtures exactly.
- no write access is taken on the Wispr database.

### TranscriptWatcher

Purpose:

Verify async Wispr row readiness.

Test cases:

1. Row already exists.
   - Watch after row 20.
   - Row 21 exists immediately.
   - Expect success without timeout.

2. Row appears later.
   - Watch after row 20.
   - Insert row 21 after 3 seconds.
   - Expect success.

3. Timeout.
   - Watch after row 20.
   - No new row appears.
   - Expect timeout and recoverable state.

4. Burst rows.
   - Rows 21, 22, 23 appear before first delivery completes.
   - Expect oldest-first processing.

Pass criteria:

- watcher never blocks trigger handling or UI.
- timeouts do not require app restart.

### TranscriptQueue

Purpose:

Verify row ordering and exactly-once processing.

Test cases:

1. Three pending triggers, three rows.
   - Expect rows delivered once each, in order.

2. Five pending triggers, five rows.
   - Expect rows delivered once each, in order.

3. Extra rows without triggers.
   - Decide behavior by mode:
     - manual-trigger mode should not drain extra rows,
     - drain mode should process new rows until inactive.

4. Reset.
   - Reset clears pending triggers and returns to idle.

Pass criteria:

- no duplicate row deliveries.
- no wedge state.

### ClipboardBroker

Purpose:

Verify local clipboard correctness.

Test cases:

1. Set simple text.
   - Set `Hello`.
   - Read local pasteboard.
   - Expect `Hello`.

2. Set punctuation/newline text.
   - Expect exact local pasteboard value.

3. Replace previous clipboard.
   - Start with old clipboard.
   - Set new text.
   - Expect new text.

Pass criteria:

- local pasteboard verification succeeds before shared sync begins.

### FocusBroker

Purpose:

Verify the donor behavior without Wispr.

Test cases:

1. Screen Sharing frontmost.
   - Activate donor.
   - Return to Screen Sharing.
   - Expect no Space jump and focus returns.

2. Other app frontmost.
   - Activate donor.
   - Return to previous app.

3. Donor unavailable.
   - Expect visible error and recovery.

Pass criteria:

- no modal dialogs,
- no document windows,
- no permanent focus loss.

### SharedClipboardSync

Purpose:

Verify that the local clipboard update reaches the remote Mac.

Manual test:

1. Open Screen Sharing to a remote text box.
2. Run sync with text `Sync one`.
3. Wait for ready indicator.
4. Press physical `Cmd+V`.

Expected:

```text
Sync one
```

Repeat with:

```text
Sync two
Sync three
```

Pass criteria:

- physical `Cmd+V` pastes the current synced text,
- not stale prior text.

### RemoteCleanup

Purpose:

Verify leaked-`v` handling separately from paste.

Test cases:

1. Cleanup disabled.
   - Expect leaked `v` remains.

2. Backspace mode.
   - Given a single leaked `v`.
   - Expect it removed.

3. Backspace then Space mode.
   - Given a single leaked `v`.
   - Expect one space remains.

Pass criteria:

- cleanup does not delete user text,
- cleanup is skipped unless Screen Sharing is the target.
- cleanup result appears in Diagnostics and the app log.

### PasteController

Purpose:

Verify optional auto-paste only after readiness.

Test cases:

1. Manual paste mode.
   - Ready indicator appears.
   - No synthetic paste is sent.

2. Auto-paste after ready.
   - Ready indicator appears.
   - Persistent donor reports `clipboardMatches=yes`.
   - Fresh-source explicit Command+V key events are sent only after donor verification and the configured paste delay.

3. Stale clipboard detection.
   - If remote paste receives old text, auto-paste is not considered reliable.

Pass criteria:

- auto-paste does not run before shared clipboard readiness.
- Diagnostics records last auto-paste enabled/result/timestamp and paste delay.
- failures are logged as paste readiness failures, not transcript failures.

## End-To-End Manual Tests

Use a safe remote text box.

### Test A: One Dictation

Say:

```text
One.
```

Expected:

```text
One.
```

Record:

- row ID,
- transcript preview,
- whether manual paste used current text.

### Test B: Three Controlled Dictations

Rule:

Wait for the ready message to clear before starting the next dictation.

Say:

```text
One.
Two.
Three.
```

Expected:

```text
One. Two. Three.
```

Acceptable recognition variation:

- Wispr may mishear words, for example `Two` as `To`.
- That is not a Remote Wispr failure if the log shows the same transcript text.

### Test C: Five Controlled Dictations

Rule:

Wait for the ready message to clear before starting the next dictation.

Say:

```text
Alpha.
Bravo.
Charlie.
Delta.
Echo.
```

Expected:

```text
Alpha. Bravo. Charlie. Delta. Echo.
```

Pass criteria:

- no duplicate rows,
- no stale clipboard paste,
- no stuck state,
- no app reload needed.

### Test D: Longer Dictation

Say:

```text
This is a longer test with two short sentences. I am checking whether the shared clipboard sync still works.
```

Expected:

- one transcript row,
- one ready state,
- paste matches Wispr transcript.

### Test E: Timeout And Recovery

Trigger Remote Wispr when no new Wispr row is expected.

Expected:

- visible timeout,
- log entry,
- state returns to idle,
- next valid dictation works without restart.

## Failure Classification

Use logs to classify failures.

### Wispr Recognition Failure

Symptoms:

- pasted text is wrong,
- log transcript is also wrong.

Conclusion:

- Wispr recognized wrong text.
- Remote Wispr is not at fault.

### Transcript Selection Failure

Symptoms:

- log shows wrong row ID,
- duplicate row ID,
- skipped row ID.

Conclusion:

- fix `TranscriptStore`, `TranscriptWatcher`, or `TranscriptQueue`.

### Clipboard Sync Failure

Symptoms:

- log shows correct row/text,
- local clipboard verifies,
- remote paste gets old text.

Conclusion:

- shared clipboard readiness was not real yet.
- fix `SharedClipboardSync` or disable auto-paste.

### Trigger Failure

Symptoms:

- Wispr row exists,
- no trigger or pending request logged.

Conclusion:

- trigger layer failed.
- prefer manual trigger or menu bar hotkey over automatic Wispr-key detection.

Wispr shortcut trigger acceptance:

- enabled from Settings,
- press records the current Wispr max row without writing to the Wispr database,
- release starts the same copy-next workflow used by the menu item,
- success means `RW Ready` appears and manual `Cmd+V` pastes the current transcript,
- failure in this module does not invalidate the accepted manual menu item workflow.

### Cleanup Failure

Symptoms:

- transcript is correct,
- leaked `v` remains or cleanup deletes user text.

Conclusion:

- fix or disable `RemoteCleanup`.

### Paste Failure

Symptoms:

- ready state logged,
- manual paste works,
- auto-paste fails or uses old text.

Conclusion:

- auto-paste is premature or target focus is wrong.
- keep manual paste as supported baseline.

## Minimum Acceptance Criteria

Before packaging as a stable tool:

1. One dictation works 5 times in a row.
2. Three controlled dictations work 3 times in a row.
3. Five controlled dictations work once.
4. Timeout recovers without restart.
5. Manual paste after ready uses the current transcript.
6. Logs identify row ID and transcript preview for every attempt.

Auto-paste acceptance is separate:

1. Auto-paste works for one dictation 5 times in a row.
2. Auto-paste works for three controlled dictations 3 times in a row.
3. No stale clipboard paste occurs.

If auto-paste does not meet this bar, ship manual paste mode first.
