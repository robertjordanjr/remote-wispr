# Remote Wispr

Remote Wispr is a local macOS helper project for using Wispr Flow on a local Mac while entering the transcript into a text box on a remote Mac screen-sharing session.

Install and run any helper on the **local Mac that runs Wispr**, not on the remote Mac.

Remote Wispr is not affiliated with Wispr Flow. It depends on your own local Wispr Flow installation and on Wispr local history storage being enabled.

The target workflow is simple:

1. Hold your configured Wispr shortcut and dictate with Wispr on the local Mac.
2. Release the shortcut.
3. Remote Wispr reads the resulting local transcript row.
4. Remote Wispr syncs the transcript into the Apple Screen Sharing shared clipboard.
5. If Auto paste is enabled, Remote Wispr cleans up the leaked `v` and pastes into the remote text box.
6. If Auto paste is disabled, paste through the remote session with normal `Cmd+V`.

Remote Wispr is currently a source-build alpha. It is intended for technical Mac users who are comfortable reading the source, building locally, and granting macOS permissions intentionally.

## Project Layout

- `docs/architecture.md`: current module/state-machine design for a robust app.
- `docs/test-plan.md`: discrete test plan for transcript, clipboard, focus, cleanup, paste, and recovery.
- `docs/implementation-roadmap.md`: phased path from prototype to menu bar app.
- `docs/input-automation-spike.md`: separate proof plan for remote cleanup and auto-paste.
- `docs/spike-1-app-clipboard-baseline.md`: current spike instructions and local smoke test.
- `docs/spike-2-focus-sync.md`: focus-donor clipboard sync spike instructions.
- `docs/adapting-targets.md`: notes for adapting the Screen Sharing target layer to other remote-control tools.
- `docs/public-release.md`: source-build alpha release and public export checklist.
- `docs/public-maintenance.md`: lightweight process for public fixes, verification, versioning, and local install checks.
- `Sources/RemoteWisprCore/`: testable Swift core for transcript reading, waiting, and clipboard writing.
- `Sources/RemoteWisprSpike/`: tiny command-line spike runner for local testing.
- `Sources/RemoteWisprMenuBar/`: menu bar app for the accepted local Wispr shortcut trigger, donor handoff, cleanup, and paste workflow.
- `app/`: notes for the future macOS app wrapper.

## Quick Start

Current status:

- The robust target is a local macOS helper with independently testable modules.
- The accepted local app baseline is configurable Wispr shortcut trigger, donor clipboard sync, donor focus handoff, optional leaked-`v` cleanup, and optional auto-paste into Apple Screen Sharing.
- The CLI component proofs are documented in `docs/spike-1-app-clipboard-baseline.md` and `docs/spike-2-focus-sync.md`.
- Repo-level fixture tests should pass before local Mac testing.

Run repo tests:

```zsh
make test-fixtures
make build-spike
make build-donor-app
make build-menubar-app
```

Build the menu bar app on the local Mac:

```zsh
make build-menubar-app
open ".build/apps/Remote Wispr.app"
```

Install the menu bar app and donor app for local daily use:

```zsh
make install-local
```

On a new Mac, `make install-local` automatically creates a local code signing identity named `Remote Wispr Local Code Signing` in your login keychain before it builds and installs the app. It uses that identity to keep the installed app's macOS identity stable across rebuilds.
`make install-local` refuses to install an ad-hoc-signed app by default. For non-permission smoke tests only, set `REMOTE_WISPR_REQUIRE_STABLE_SIGNING=0`.

`make install-local` installs both apps into:

```text
$HOME/Applications/Remote Wispr.app
$HOME/Applications/Remote Wispr Copy Donor.app
```

It closes a running `Remote Wispr.app`, replaces the installed app bundles, creates or upgrades the Remote Wispr settings file, and starts `Remote Wispr.app` again. It does not modify Wispr, Screen Sharing, Accessibility permissions, login items, the clipboard, or the Wispr database.

For non-GUI install checks, skip the restart step:

```zsh
REMOTE_WISPR_REQUIRE_STABLE_SIGNING=0 REMOTE_WISPR_RESTART_AFTER_INSTALL=0 make install-local
```

Use the accepted local baseline:

1. Open `Settings...`.
2. Enable `Wispr shortcut trigger`.
3. Set `Wispr Shortcut` to match Wispr Flow's push-to-talk shortcut. The default is Control+Option.
4. Optional: enable `Auto paste` and `Clean up leaked v`.
5. Click the remote Screen Sharing text box.
6. Hold the configured Wispr shortcut, dictate, then release.
7. Wait for `RW Ready` or `Paste sent`.
8. If Auto paste is disabled, press `Cmd+V` in the remote text box.

Use the menu bar item as a fallback/manual trigger:

1. Choose `Copy Next Wispr Transcript`.
2. Return to the remote Screen Sharing text box if needed.
3. Dictate with Wispr.
4. Wait until the menu bar title changes to `RW Ready`.
5. Press `Cmd+V` in the remote text box.

The menu bar app implements the accepted local Wispr shortcut baseline. Current local testing shows donor clipboard sync, focus handoff, cleanup, and auto-paste working in Apple Screen Sharing. Manual `Cmd+V` remains the fallback if Auto paste is disabled.

The Wispr shortcut trigger only arms when Apple Screen Sharing is frontmost at key-down. If you use Wispr in a local app, Remote Wispr skips the workflow, so it does not launch the donor app, copy to the clipboard, reactivate Screen Sharing, or change focus.

Remote Wispr appends one trailing space to the text it places on the donor clipboard. The Wispr database text is not modified.

Use `Disable Remote Wispr` from the menu bar item, or Option-click the `RW` menu bar item, to temporarily disable/enable the helper. When disabled, the menu bar title shows `RW Off`. Remote Wispr does not use a global utility keystroke for this toggle because global shortcuts can interfere with frontmost apps.

Wispr must be configured to keep local history for Remote Wispr to work. In Wispr's data/storage setting, choose at least the `24 hours` local storage option, or choose the all-local option. If Wispr is set to store no history, Remote Wispr can read the database but no new transcript row will appear.

`Auto paste` is available in Settings but remains disabled by default. The reliable path is donor clipboard sync followed by reactivating Screen Sharing and sending Command+V through System Events. The donor app receives the captured Screen Sharing process ID and hands focus back before exiting. Remote Wispr waits for that donor handoff before attempting paste. The `Paste Focus Wait` setting is treated as a bounded focus wait after donor clipboard sync. During that wait, Remote Wispr keeps asking Screen Sharing to activate, then sends Backspace/Command+V as soon as Screen Sharing is truly frontmost. If Screen Sharing does not become frontmost inside that wait, Remote Wispr does not send cleanup or paste keystrokes.

For cleanup or auto-paste, choose `Check Input Permissions` from the menu after install. This checks both gates: Accessibility for `$HOME/Applications/Remote Wispr.app` and Automation permission for Remote Wispr to control System Events.

When both Remote Cleanup and Auto paste are enabled, Remote Wispr sends cleanup plus Command+V in one System Events script.

Use `Settings...` to configure:

- Wispr DB path,
- donor app path, default `$HOME/Applications/Remote Wispr Copy Donor.app`,
- timeout seconds, default `60`,
- hidden donor window,
- Wispr shortcut trigger,
- Wispr shortcut modifiers,
- auto paste,
- paste focus wait seconds,
- Wispr shortcut minimum hold seconds,
- cleanup setting.

Settings are saved at:

```text
$HOME/Library/Application Support/RemoteWispr/settings.json
```

`make install-local` creates `settings.json` when it is missing. On app launch, Remote Wispr also rewrites the settings file with the current schema and fills in any missing defaults without changing existing user choices.

The app writes a local log at:

```text
$HOME/Library/Logs/RemoteWispr/menu-bar.log
```

Use `Diagnostics...` from the menu bar item to inspect:

- installed app version and build number,
- settings schema version,
- current Wispr DB path and max row,
- current status and running state,
- manual disable state,
- Wispr shortcut trigger state,
- Wispr shortcut modifiers,
- last skipped reason,
- baseline health check results,
- last marker row and copied row,
- donor clipboard verification,
- auto-paste result,
- paste focus wait,
- last error.

Use `Copy Diagnostics` in the Diagnostics window to copy the current diagnostics text.

Use `Open Log` to inspect the raw event log.

Use `Run Baseline Health Check` after install, relaunch, or reboot to check the app-owned baseline without dictation or Screen Sharing. It verifies:

- app version/build,
- settings file,
- settings schema,
- read-only Wispr DB query,
- copy donor app path,
- Wispr shortcut trigger setting,
- auto-paste setting,
- remote cleanup mode,
- timing settings.

It does not launch the donor app, write to the clipboard, modify Wispr files, touch database sidecars, request permissions, register Login Items, or paste into the remote Mac.

The app version is stored in `VERSION`. Bundle build numbers default to the git commit count when the app bundle is built.

The app icon is stored at `assets/RemoteWispr.icns`. To regenerate it from the deterministic Swift renderer:

```zsh
scripts/generate-app-icon.zsh assets/RemoteWispr.icns
```

The menu bar status item currently remains text (`RW`, `RW Ready`, or `RW Error`). The `.icns` is the app bundle icon used by Finder, Login Items, and macOS app metadata.

## Remote Cleanup

Remote cleanup is optional and defaults to off. It deletes the leaked remote trigger key from the Wispr shortcut before you manually paste or before Auto paste runs.

Settings has one cleanup checkbox. When enabled, Remote Wispr sends one Delete/Backspace key to the active Screen Sharing text box. The copied transcript already includes a trailing space, so cleanup does not send a separate Space key.

Cleanup only runs after the transcript has been copied through the donor app and only when the captured target app is Apple Screen Sharing. Remote Wispr sends cleanup and paste together in one System Events script when Auto paste is enabled. If Screen Sharing is not frontmost, Remote Wispr logs that cleanup/paste was skipped. The app needs macOS Accessibility permission and Automation permission for `System Events`.

Use `Reset Running State` only as a local app recovery action. It clears Remote Wispr's current in-memory task state, hotkey marker, and last error. It does not modify Wispr, Screen Sharing, Accessibility permissions, the clipboard, donor app processes, or any database files.

## Reboot/Login Checklist

After installing with `make install-local`, use this local Mac checklist:

1. Restart or log out and back in.
2. Confirm `$HOME/Applications/Remote Wispr.app` is running.
3. Confirm the `RW` menu bar item appears.
4. Open `Settings...` and confirm the Wispr DB path, timeout, hidden donor, and Wispr shortcut trigger settings persisted.
5. Confirm macOS Accessibility permission still applies to the installed app.
6. Open `Diagnostics...` and confirm the Wispr DB path and current max row are visible.
7. Choose `Run Baseline Health Check` and confirm Diagnostics shows `Baseline health: ok`.
8. If testing cleanup or auto-paste, choose `Check Input Permissions` and confirm Diagnostics says Accessibility is enabled and Remote Wispr can control System Events.
9. Click a text box in the remote Screen Sharing session.
10. Hold the configured Wispr shortcut, dictate, then release.
11. Wait for `Paste sent` if Auto paste is enabled, or `RW Ready` if Auto paste is disabled.
12. If Auto paste is disabled, press `Cmd+V` in the remote text box.
13. Reopen `Diagnostics...` and confirm last marker row, last copied row, donor clipboard match, donor handoff, focus readiness, and last error look correct.

## Manual Launch At Login

Remote Wispr no longer manages launch-at-login from inside the app. Local testing showed macOS could keep stale or duplicate Login Items across installed app bundle versions, so the app avoids `SMAppService` entirely.

Readiness gate:

- Risky assumption: macOS launches the manually added installed menu bar app at login and preserves Accessibility behavior.
- Required proof: local proof on the user's Mac.

Manual setup:

1. Install with `make install-local`.
2. Open System Settings > General > Login Items & Extensions.
3. Under Open at Login, remove stale or duplicate `Remote Wispr.app` entries.
4. Add `$HOME/Applications/Remote Wispr.app` manually if you want it to open at login.
5. Reboot or log out and back in.
6. Confirm `RW` appears automatically.
7. Run one Wispr shortcut dictation.
8. Confirm Diagnostics shows donor match `yes` and last error `none`.

The copy donor is hidden by default. If hidden donor mode fails to update the shared clipboard, run the visible fallback:

```zsh
make local-sync-next-visible-donor
```

First, test whether plain clipboard sharing works:

1. On the local Mac, copy some text from TextEdit.
2. Click a text box inside the remote Mac session.
3. Press `Cmd+V`.

If the text appears on the remote Mac, the remote-control clipboard path is viable. The new app should build on that.

## Permissions

The Wispr shortcut trigger and any optional cleanup/paste automation need macOS Accessibility permission.

Grant it in:

`System Settings > Privacy & Security > Accessibility`

If cleanup or auto-paste reports that Remote Wispr is not allowed to send keystrokes, first reinstall with the stable signing identity:

```zsh
make install-local
```

Then remove any stale `Remote Wispr.app` entry from Accessibility and add `$HOME/Applications/Remote Wispr.app` again one final time. Future signed installs should keep that permission. If it reports that Remote Wispr is not authorized to control System Events, open `System Settings > Privacy & Security > Automation` and enable `System Events` under Remote Wispr.

## Public Source Builds

Remote Wispr does not publish prebuilt binaries. The expected public install path is to clone the repository, inspect the source, and build locally with `make install-local`.

See `PRIVACY.md`, `SECURITY.md`, and `docs/public-release.md` before redistributing or adapting this project.
