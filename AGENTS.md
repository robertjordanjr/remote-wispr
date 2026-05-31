# Agent Notes

This project is about local Wispr or Flow dictation into a remote Mac text box during screen sharing.

Important boundaries:

- Every time you ask the user to run a command, put a one-line shell no-op at the top of the command block with only the computer and account, for example: `: "Computer: Local Mac | Account: rojo"`. Keep it simple, make it copy-paste safe in interactive `zsh`, and do this even when it feels obvious.
- Treat clipboard sharing as the first gate. Verify plain local copy/paste into the remote Mac before debugging Wispr.
- Keep Wispr local unless the remote Mac has a real microphone input path.
- The fallback is keystroke injection from the local clipboard into the active remote-control window.
- Development may happen on a remote computer while final real-world testing happens on the user's local Mac. Maximize tests that can run in the repo/remote environment, and explicitly label tests that require the local Mac, Wispr Flow, Apple Screen Sharing, microphone/hotkey input, Accessibility permissions, or the shared clipboard bridge.
- If a preferred tool is missing or blocked, explain the tool gap and tradeoff before switching. Use an alternate tool only when it is truly a better fit or clearly labeled as a temporary fallback.
- Never give the helper more access than it needs. Wispr SQLite access must stay read-only; do not add read/write fallback, repair, checkpoint, vacuum, migration, pragma writes, sidecar manipulation, or snapshot-copy fallback without explicit approval.
- Do not silently terminate or modify external processes. If another Remote Wispr helper or donor app is running, fail visibly and ask the user to close it.
- The current target is a small local macOS menu bar app with independently testable modules. Use `docs/architecture.md`, `docs/test-plan.md`, and `docs/implementation-roadmap.md` as the planning baseline.
- Use the implementation readiness gate before accepting OS-level, permission, external-app, or integration designs: name the risky assumption, classify proof as external/local/production, and run a small spike when proof is weak or generic.
- Prefer simple macOS-native components and clear operational docs. If building code, keep modules separately testable instead of adding timing behavior to the prototype.
- Do not imply there is a special Wispr remote-desktop integration. The reliable mechanism is clipboard redirection or typed keystrokes.
