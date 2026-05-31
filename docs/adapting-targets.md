# Adapting Remote Wispr To Other Remote-Control Apps

Remote Wispr currently has local proof for Apple Screen Sharing only.

The useful idea is broader than Apple Screen Sharing:

1. Wispr Flow produces text locally.
2. Remote Wispr waits for the next local transcript row.
3. A donor app verifies that the transcript reached the local clipboard.
4. Remote Wispr verifies the intended remote-control app is still the target.
5. Optional automation cleans up the trigger artifact and sends paste.

Other remote-control apps may be adaptable, but they need their own proof.

Examples of possible future targets:

- Jump Desktop
- Microsoft Remote Desktop
- VNC clients
- Parsec
- Other remote-control or virtual desktop clients

These are not currently supported.

## Target Adapter Questions

For a new target, answer these before changing code:

- What is the macOS bundle identifier?
- Does the app accept normal `Cmd+V` into the remote session?
- Does clipboard sharing need to be enabled separately?
- Does the app stay frontmost while Wispr shows its local UI?
- Does it work in windowed mode?
- Does it work in full-screen mode?
- Does System Events paste work, or is manual paste the only reliable path?
- Does the target preserve focus after a donor app briefly copies text?

## Proof Levels

- External proof: vendor docs or credible examples show clipboard and paste behavior.
- Local proof: it works on an actual Mac with the target app, Wispr Flow, permissions, and a remote text field.
- Production proof: it survives reboot, reinstall, permissions refresh, and repeated real use with documented recovery.

Do not mark a target as supported without local proof.

## Timing Lessons

Remote input is timing-sensitive:

- Wispr writes transcript rows asynchronously.
- Remote-control apps can have their own clipboard bridges.
- Focus can appear unchanged while macOS still reports another app as frontmost.
- A donor app can perturb focus or clipboard state.
- Sending paste early is worse than failing safely.

For this reason, the app should stop when verification fails:

- clipboard mismatch,
- donor still frontmost,
- target not frontmost,
- input permission missing,
- no new Wispr row before timeout.

## Where To Start In Code

- `Sources/RemoteWisprMenuBar/RemoteInputAutomationController.swift`
- `Sources/RemoteWisprMenuBar/main.swift`
- `Sources/RemoteWisprCore/PersistentDonorApp.swift`
- `docs/test-plan.md`

Keep the transcript reader and donor clipboard sync generic. Put target-specific behavior behind small, testable boundaries.
