# Public Maintenance Process

Remote Wispr is a source-build alpha. Keep public updates small, reproducible, and easy to audit.

## Lightweight Loop

1. Capture evidence.
   - Copy Diagnostics from the menu bar app.
   - Include the relevant tail of `menu-bar.log` when timing, paste, focus, donor, or permission behavior is involved.
   - Note which Mac/account ran the app and whether the test required Wispr Flow, Apple Screen Sharing, Accessibility, Automation, or shared clipboard behavior.

2. Classify the change.
   - `repo-only`: fixture tests, docs, pure formatting, parsing, settings serialization.
   - `local-mac`: requires the installed app, Wispr Flow, Screen Sharing, permissions, or clipboard bridge.
   - `public-release`: changes behavior users will see, install instructions, permissions, privacy, or troubleshooting.

3. Make the narrowest fix.
   - Keep Wispr SQLite access read-only.
   - Do not add database repair, sidecar copying, checkpointing, migrations, or write pragmas.
   - Keep optional input automation behind explicit settings.
   - Do not terminate external Remote Wispr helper or donor processes silently.

4. Add or update focused tests.
   - Use fixture tests for row selection, transcript waiting, settings, formatting, and pure workflow behavior.
   - Label anything that still requires local Mac validation.

5. Verify before push.
   - Run `make test-fixtures`.
   - Run `make build-menubar-app` for app-facing changes.
   - Run `make privacy-scan` before public-facing releases or docs that may include copied logs, diagnostics, screenshots, or user paths.

6. Version and publish.
   - Bump `VERSION` for user-visible behavior changes.
   - Commit focused changes with a plain message.
   - Push `main` only after tests/builds pass.

7. Local Mac install check.
   - Pull the public repo on the local Mac.
   - Run `make install-local`.
   - Run Baseline Health Check.
   - For cleanup or auto-paste changes, run Check Input Permissions.
   - Test in Apple Screen Sharing with a short dictation and, when timing changed, a longer dictation.

## Timing Notes

The Wispr shortcut marker is captured on key down. Remote Wispr starts waiting for the next usable transcript after key up, when the copy workflow begins. The `Timeout Seconds` setting applies to that post-release wait.

Long dictations can still matter because Wispr may expose partial or raw transcript rows before the final text is ready. Changes in this area should be validated with Diagnostics that show:

- last marker row,
- last row seen,
- last row status,
- last row text length,
- last copied length,
- donor clipboard match,
- last error.

## Local Command Context

When asking someone to run local commands, include a one-line no-op at the top of the command block with only the computer and account.

```zsh
: "Computer: Local Mac | Account: rojo"
cd /path/to/remote-wispr
git pull
make install-local
```
