# Spike 2: Focus Donor Clipboard Sync

## Question

Can the helper perform the donor-app clipboard sync step while still leaving paste as a manual `Cmd+V`?

## Proof Target

Required proof level: local proof.

This spike is not accepted until it works on the user's local Mac with:

- Wispr Flow producing transcript rows,
- Apple Screen Sharing connected to the remote Mac,
- a persistent copy donor app installed or launchable,
- the helper able to capture Screen Sharing as the return app,
- the helper able to activate the donor, copy the transcript, verify the clipboard, and report ready.

## In Scope

- Capture the frontmost app before sync.
- Launch a persistent copy donor app.
- Copy text through normal foreground app copy behavior.
- Verify the local pasteboard while the donor is active.
- Let the donor app close itself.
- Keep manual `Cmd+V` as the paste action.

## Out Of Scope

- Automatic paste.
- Automatic dictation-release detection.
- Remote text cleanup.
- Full-screen Space return.
- Final menu bar UI.

## Repo Tests

Run from the repo:

```sh
make test-fixtures
make build-spike
```

These tests prove:

- focus sync has a separately testable broker interface,
- the donor bundle identifier is explicit,
- the clipboard is set during the sync workflow,
- donor copy can be tested separately from paste.

## Local Smoke Test

Run this on the local Mac.

1. Pull and rebuild:

   ```sh
   git pull
   make local-db-check
   make build-donor-app
   ```

2. Stop if `local-db-check` cannot prepare the Wispr query. Donor and focus tests are not meaningful until live read-only DB access works.

3. Check the donor app is available. The default donor bundle is:

   ```text
   com.remote-wispr.FocusDonor
   ```

4. Run the next-row local sync command:

   ```sh
   make local-sync-next
   ```

5. During the three-second delay, click the remote Screen Sharing text box.

6. Dictate one short phrase with Wispr.

7. Wait for the helper to print `Ready: row ####`.

8. Press physical `Cmd+V`.
9. The donor window should close itself.

Pass criteria:

- The helper captures Screen Sharing as the return app.
- The helper launches the donor app.
- The donor app reports `clipboardMatches=yes`.
- `Clipboard survived return` is `yes`.
- Manual `Cmd+V` pastes the current transcript.
- The pasted text is not stale clipboard text.
- The donor app closes itself before the next run.

If `Clipboard survived return` is `no`, Screen Sharing or the remote session changed the local clipboard after donor copy. That is a shared-clipboard/focus failure, not a transcript-read failure.

Known accepted limitations:

- The remote text box may contain the leaked leading `v`.
- In full-screen Screen Sharing, the donor can pull the user out to the Terminal Space. The user manually returns to the Screen Sharing Space before pressing `Cmd+V`.

These limitations are not part of the accepted baseline. They belong to `RemoteCleanup` and `FullScreenFocusReturn` experiments.

## Manual Return Diagnostic

If `foreground-copy` sets the correct clipboard but `Clipboard survived return` is `no`, test whether the overwrite is caused by programmatic focus return.

Run:

```sh
.build/debug/remote-wispr-spike wait-sync --after ROW --timeout 20 --capture-delay 3 --donor-hold 1.5 --copy-method foreground-copy --skip-return
```

Timing:

1. During the three-second countdown, click the remote text box.
2. After capture, dictate.
3. Let the donor window copy the transcript.
4. When `Ready` prints, manually click the remote text box.
5. Press physical `Cmd+V`.

Pass criteria:

- `Clipboard after set` and `Clipboard after return` both show the transcript.
- Manual click back to Screen Sharing does not replace the local clipboard before paste.
- Manual `Cmd+V` pastes the current transcript.

If this passes, the app should not programmatically return focus in the baseline. It should show `Ready`, leave the clipboard intact, and let the user click the remote text box.

## Keep Donor Open Diagnostic

If the clipboard is correct after foreground copy but changes as soon as the donor window closes, keep the donor window open through the manual paste.

Run:

```sh
.build/debug/remote-wispr-spike wait-sync --after ROW --timeout 20 --capture-delay 3 --donor-hold 1.5 --copy-method foreground-copy --skip-return --keep-donor-open
```

Timing:

1. During the three-second countdown, click the remote text box.
2. After capture, dictate.
3. Let the donor window copy the transcript and remain open.
4. When `Ready` prints, click the remote text box.
5. Press physical `Cmd+V`.
6. Return to Terminal and press Return to close the donor window.

This tests whether Apple Screen Sharing accepts the clipboard only while the foreground donor app that performed the copy remains alive.

## Copy Methods

The spike supports two copy methods:

- `pasteboard-donor`: activate the donor app, set `NSPasteboard`, then return focus.
- `foreground-copy`: show a small local donor window, place the transcript in a text view, run the normal copy action, then return focus.
- `persistent-donor-app`: launch a real app bundle, load the transcript into its text view, copy from that app, and leave the app open through manual paste.

The `pasteboard-donor` method failed local proof because Screen Sharing overwrote the local pasteboard with stale shared clipboard contents on return.

The `foreground-copy` method is the next proof target because manual local copy events have worked with Apple Screen Sharing in this environment.

## Persistent Donor App Diagnostic

The transient foreground-copy window still failed local proof because the clipboard was overwritten even when the donor remained open inside the CLI process.

The accepted baseline uses a real app bundle:

```sh
make build-donor-app
```

This installs:

```text
.build/apps/Remote Wispr Copy Donor.app
```

Then run:

```sh
.build/debug/remote-wispr-spike wait-sync --after ROW --timeout 20 --capture-delay 3 --copy-method persistent-donor-app --skip-return
```

Timing:

1. During the three-second countdown, click the remote text box.
2. After capture, dictate.
3. The persistent donor app opens, copies the transcript from its text view, writes ready, and closes itself.
4. When `Ready` prints, return to the remote text box if needed.
5. Press physical `Cmd+V`.

Pass criteria:

- The donor app reports `clipboardMatches=yes`.
- `Clipboard after return` shows the current transcript.
- Manual `Cmd+V` pastes the current transcript into the remote text box.
- The donor app closes itself before the next run.

Notes:

- The spike runner refuses to start if a persistent donor app is already running.
- The donor app retries the foreground copy and then uses a foreground pasteboard write fallback while it is active.
- Leaked remote `v` cleanup is not part of the baseline manual paste mode.
- Full-screen Space return is not part of the baseline manual paste mode.

If this fails, the app-bundle donor approach does not reproduce the old working behavior and the next investigation should compare against the exact old donor app behavior rather than adding more delay.

## If The Donor Is Missing

If the command reports that `com.remote-wispr.FocusDonor` is not found, stop there. That is not a transcript failure.

Options:

- Install or rebuild the donor app.
- Re-run with another explicit donor bundle for comparison:

  ```sh
  .build/debug/remote-wispr-spike wait-sync --after ROW --timeout 20 --capture-delay 3 --donor-bundle com.apple.finder
  ```

Using Finder is only a comparison path. It is not accepted as the final default unless it avoids Space jumps on the local Mac.

## Decision

If this passes, the shared clipboard/focus sync path has local proof.

The next step after that is a small menu bar wrapper with settings and diagnostics. Automatic paste remains disabled until the focus-sync path is boring.
