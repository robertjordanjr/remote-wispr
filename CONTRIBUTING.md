# Contributing

Remote Wispr is currently focused on one proven target: Wispr Flow on the local Mac plus Apple Screen Sharing to a remote Mac.

Contributions are welcome, but please keep the project safe and boring.

## Design Rules

- Keep Wispr SQLite access read-only.
- Keep target-specific behavior isolated.
- Prefer explicit diagnostics over hidden timing assumptions.
- Do not send keystrokes unless the intended target app is verified.
- Preserve manual paste as a fallback.
- Keep optional cleanup and auto-paste separable from transcript reading and clipboard sync.

## Testing

Run the repo-level checks before opening a pull request:

```zsh
make test-fixtures
make build-menubar-app
```

Some tests require a real local Mac with Wispr Flow, Apple Screen Sharing, Accessibility permission, Automation permission, and a remote text field. Label those results clearly in the pull request.

## Supporting Other Remote Apps

Apple Screen Sharing is the only proven target. If you want to support another remote-control app, start by reading `docs/adapting-targets.md`.

Do not claim support for a new target until it has local proof.

## Privacy

Do not include real transcripts, client data, screenshots with private content, logs with sensitive paths, or machine names in issues or pull requests.
