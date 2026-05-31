# Privacy

Remote Wispr is designed as a local-only source-build utility.

## What Remote Wispr Reads

- The configured Wispr Flow SQLite history database.
- Only read-only SQLite queries are used.
- The transcript text for the next usable Wispr row after the trigger marker.
- The local macOS frontmost application, to confirm Apple Screen Sharing is the active target.

## What Remote Wispr Writes

- Its own settings file at `$HOME/Library/Application Support/RemoteWispr/settings.json`.
- Its own local log file at `$HOME/Library/Logs/RemoteWispr/menu-bar.log`.
- The macOS clipboard, through the bundled copy donor app.

Remote Wispr does not write to the Wispr Flow database.

## What Remote Wispr Does Not Do

- No telemetry.
- No analytics.
- No network service.
- No cloud sync.
- No account system.
- No upload of transcripts, logs, settings, screenshots, or clipboard contents.
- No database repair, checkpoint, vacuum, migration, sidecar edit, or write pragma.

## Permissions

The optional cleanup and auto-paste features require macOS Accessibility and Automation permissions because they send keystrokes to Apple Screen Sharing through System Events.

The manual clipboard path can be used without enabling auto-paste.

## Sensitive Data Warning

Wispr history may contain dictated text. Treat this repository, logs, screenshots, diagnostics, and issue reports as potentially sensitive. Before posting diagnostics publicly, remove transcript text, usernames, local paths, client names, and private remote-host details.
