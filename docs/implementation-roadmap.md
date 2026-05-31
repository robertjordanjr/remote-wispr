# Implementation Roadmap

## Current Decision

The prototype proved the core mechanics:

- Wispr transcripts can be read from local SQLite.
- Shared clipboard sync can be nudged by briefly moving focus to a donor app.

The prototype also exposed the weak points:

- automatic Wispr-key release detection is fragile,
- Screen Sharing clipboard sync is asynchronous,
- synthetic auto-paste can run before the remote clipboard is ready,
- too many independent apps coordinated by sleeps leads to timing bugs.

The next implementation should be a small local macOS app with explicit modules and a state machine.

Readiness gate:

- The menu bar app is not accepted architecture yet.
- It is the next spike target because earlier experiments produced enough local proof for the core mechanisms and enough negative proof for timing-heavy orchestration.
- Each phase below must name whether it has external, local, or production proof before becoming the default path.

## Target Product

A local macOS menu bar app named Remote Wispr.

Primary supported workflow:

1. User dictates with Wispr Flow.
2. User triggers Remote Wispr with a hotkey or menu item.
3. Remote Wispr waits for the next transcript row.
4. Remote Wispr syncs that transcript to the shared clipboard.
5. Remote Wispr displays `Ready to paste`.
6. User presses physical `Cmd+V`.

Auto-paste is optional and disabled until the shared clipboard readiness signal is proven stable.

Current accepted baseline as of `0.4.4`: Control+Option trigger, read-only Wispr SQLite row detection, persistent donor clipboard sync, `RW Ready`, and manual `Cmd+V`. Full-screen Screen Sharing does not currently need a focus-return module for this baseline.

## Phase 0: Freeze Prototype Evidence

Do this before writing the app:

- Keep a short written record of lessons from early experiments.
- Do not ship prototype scripts or local-machine artifacts in the public source tree.
- Stop adding timing behavior to one-off prototypes unless a specific hypothesis is being tested.

Deliverables:

- `docs/architecture.md`
- `docs/test-plan.md`
- this roadmap

## Phase 1: App Skeleton

Build a minimal Swift/AppKit menu bar app.

Features:

- menu bar item,
- `Copy Next Wispr Transcript` menu action,
- `Check Wispr DB` menu action,
- `Settings...` window for baseline settings,
- `Diagnostics...` window for baseline state,
- `Open Log` menu action,
- Quit,
- status display.

Initial settings:

- Wispr SQLite database path,
- donor app path,
- hidden donor toggle,
- wait timeout,
- Control+Option trigger toggle,
- Control+Option minimum hold seconds,
- poll interval remains internal for now.

The first app shell intentionally includes Wispr integration because it wraps the accepted transcript-read and donor-copy path. It does not include cleanup, full-screen return, or auto-paste behavior. The accepted local app baseline is Control+Option trigger, donor clipboard sync, ready status, and manual `Cmd+V`.

Tests:

- app launches,
- menu works,
- settings save and reload,
- `Check Wispr DB` reports max row,
- `Copy Next Wispr Transcript` waits for a new row,
- donor copies and closes,
- menu bar status changes to ready,
- diagnostics show current DB max row, last marker row, last copied row, donor verification, and last error,
- log file records app launch, DB checks, copy attempts, and errors,
- manual paste uses the current transcript,
- Control+Option trigger records the row marker on key down and waits for the next row on key release.

Environment:

- Build and unit-test app logic on the repo/remote machine where possible.
- Run macOS UI, global hotkey, Accessibility, and Screen Sharing tests only on the user's local Mac.
- Keep local-only tests behind explicit commands or diagnostics menu actions.

Install packaging:

- `make install-local` builds both app bundles,
- closes a running `Remote Wispr.app` if needed,
- installs `Remote Wispr.app` into `$HOME/Applications`,
- installs `Remote Wispr Copy Donor.app` beside it,
- creates or upgrades the Remote Wispr settings file,
- starts `Remote Wispr.app` after install,
- leaves Wispr, Screen Sharing, Accessibility permissions, login items, clipboard contents, and Wispr database files unchanged.

Recovery:

- `Reset Running State` clears only app-owned in-memory state,
- cancels the current app task if one is pending,
- clears the current hotkey marker and last error,
- leaves Wispr, Screen Sharing, clipboard contents, donor processes, permissions, and database files untouched.

Manual launch at login:

- Remote Wispr does not manage macOS Login Items from inside the app,
- local testing showed stale or duplicate Login Items could appear across installed app bundle versions,
- users who want launch-at-login add `$HOME/Applications/Remote Wispr.app` manually in System Settings > General > Login Items & Extensions,
- any future in-app launch-at-login attempt requires a separate spike and proof gate before re-entering the accepted baseline.

Baseline health:

- menu exposes `Run Baseline Health Check`,
- the check is read-only and does not require dictation, Screen Sharing, donor launch, clipboard writes, paste, or permission changes,
- the check reports app version/build, settings file readability, Wispr DB max-row query, donor app path, Control+Option trigger state, remote cleanup mode, and timing settings,
- Diagnostics stores the last health report so install/reboot sanity can be checked before local/remote testing.

## Separate Spike: Input Automation

Cleanup and auto-paste are now treated as one separate input-automation problem, not as timing tweaks on the accepted baseline.

Why:

- the current Backspace cleanup can report success while the remote text box does not change,
- if synthetic Backspace does not reliably affect the remote text field, synthetic auto-paste is unlikely to be reliable through the same mechanism,
- current full-screen testing does not show a focus problem for manual paste, so focus return should not be mixed into this spike unless it fails again.

Spike requirement:

- prove a reliable way to send a simple input action into the remote text box,
- keep transcript selection and donor clipboard sync mocked or reused as fixed prerequisites,
- do not modify the accepted baseline unless the input mechanism earns local proof.

See `docs/input-automation-spike.md`.

## Phase 2: TranscriptStore

Port the SQLite reader.

Features:

- configurable Wispr DB path,
- read-only database connection,
- max row ID,
- oldest usable row after row ID,
- transcript column fallback.

Tests:

- fixture DB tests,
- real local DB read-only smoke test.

Deliverable:

- function returning `{ rowId, text }`.

## Phase 3: TranscriptWatcher And Queue

Add async row waiting and exactly-once row processing.

Features:

- wait for row after marker,
- timeout,
- queue,
- last processed row ID,
- reset.

Tests:

- delayed row appears,
- timeout recovers,
- rows process oldest first,
- app does not wedge.

Decision:

- initialize `lastProcessedRowId` to current max row at app launch.
- do not process historical rows unless user explicitly chooses "copy latest historical row."

## Phase 4: ClipboardBroker

Add local pasteboard writing.

Features:

- write text,
- verify pasteboard contents,
- log preview and length,
- preserve or replace existing clipboard depending on setting.

Tests:

- local pasteboard set/read,
- punctuation/newline text,
- old clipboard replaced.

## Phase 5: FocusBroker

Move focus out of Screen Sharing and back.

Options to test:

1. menu bar app activates itself,
2. separate Focus Donor app activates,
3. Finder fallback for diagnostics only.

Acceptance:

- no document windows,
- no modal dialogs,
- no Space jump,
- focus returns to Screen Sharing.

Decision point:

- If self-activation triggers Screen Sharing clipboard sync, remove the separate donor app.
- If not, keep a bundled helper app.

## Phase 6: SharedClipboardSync

Integrate FocusBroker and ClipboardBroker.

Flow:

```text
capture frontmost app
activate donor
set local pasteboard
verify pasteboard
return focus
emit ReadyToPaste
```

Tests:

- manual paste into remote text box gets current text,
- repeated `Alpha`, `Bravo`, `Charlie` controlled sequence works,
- stale clipboard paste is logged as sync failure.

## Phase 7: TriggerController

Start with manual trigger.

Options:

- global hotkey,
- menu item,
- status item click.

Do not make automatic `Ctrl+Option` release detection the default until the manual trigger workflow is stable.

Tests:

- trigger while Screen Sharing is frontmost,
- trigger while another app is frontmost,
- trigger with no new row,
- trigger after Wispr delayed row.

## Phase 8: RemoteCleanup

Add leaked-`v` cleanup as an optional feature.

Modes:

- off,
- Backspace,
- Backspace then Space.

Tests:

- cleanup only runs when returning to Screen Sharing,
- cleanup does not run in local apps,
- cleanup does not delete real text.

Implementation notes:

- Settings exposes the existing `RemoteCleanupMode`,
- the app captures the target app before donor clipboard sync,
- cleanup runs only after donor clipboard verification succeeds,
- cleanup reactivates the captured Screen Sharing app before sending keys,
- cleanup posts keys to the captured Screen Sharing process,
- cleanup logs whether it ran or skipped.

Default:

- off for first app build,
- enable only after module-level testing.

## Phase 9: Optional Auto-Paste

Auto-paste should be treated as a final convenience feature.

Rules:

- only runs after `ReadyToPaste`,
- configurable delay,
- disabled by default until acceptance tests pass.

Acceptance:

- no stale paste,
- no focus-loss paste,
- no repeated prior transcript.

If auto-paste fails, do not destabilize the core workflow. Keep manual paste mode.

## Packaging

Package as a signed local macOS app if practical.

Installer responsibilities:

- install the app,
- install/bundle Focus Donor helper if needed,
- request Accessibility permission,
- document Full Disk Access or file permission needs if SQLite access requires it,
- provide uninstall instructions.

Settings to expose:

- Wispr DB path,
- trigger hotkey,
- row wait timeout,
- clipboard sync delay if still needed,
- cleanup mode,
- auto-paste enabled,
- auto-paste delay,
- log level.

## Done Criteria

Core workflow is done when:

- one dictation works 5 times,
- three controlled dictations work 3 times,
- five controlled dictations work once,
- timeout recovers without restart,
- manual paste after ready uses current transcript,
- logs explain failures.

Auto-paste is done only when:

- current transcript is pasted,
- no stale clipboard values appear,
- focus returns correctly,
- failures recover without restart.
