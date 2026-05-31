# Security

## Supported Use

Remote Wispr is a source-build alpha. Users are expected to clone the repository, inspect the source, build locally, and grant macOS permissions intentionally.

No prebuilt binaries are provided by this project.

## Reporting Security Issues

Do not open a public issue for a security or privacy vulnerability.

If this repository has a configured GitHub security advisory process, use that. Otherwise, contact the repository owner privately.

## Permission Model

Remote Wispr requests or uses only local macOS capabilities:

- Read-only file access to the configured Wispr Flow SQLite database.
- Clipboard access through macOS pasteboard APIs.
- Accessibility and Automation permissions only for optional cleanup and auto-paste.

Remote Wispr should never need write access to Wispr Flow data.

## Security Boundaries

The following behavior should be treated as a security bug unless explicitly approved and documented:

- Writing to the Wispr database.
- Repairing, checkpointing, vacuuming, migrating, or changing SQLite pragmas for the Wispr database.
- Editing SQLite sidecar files.
- Uploading transcripts, logs, diagnostics, screenshots, clipboard contents, or settings.
- Starting a network listener.
- Sending cleanup or paste keystrokes when Apple Screen Sharing is not the verified target.
- Silently terminating external helper apps or unrelated processes.

## Public Bug Reports

When filing a public bug report, remove:

- transcript contents,
- usernames,
- local paths,
- client names,
- machine names,
- remote hostnames,
- screenshots with private data.
