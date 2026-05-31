# Input Automation Spike

## Purpose

Prove one reliable way to send an input action into the active remote Mac text box through Apple Screen Sharing.

This spike covers both future features:

- removing the leaked remote `v`,
- auto-pasting the transcript after donor clipboard sync.

These features share the same hard dependency: Remote Wispr must be able to affect the remote text field deliberately and observably. The accepted `0.4.4` baseline does not depend on that ability.

## Current Baseline

Keep this path stable while the spike runs:

1. Control+Option trigger marks the current Wispr row.
2. Remote Wispr waits for the next usable Wispr row.
3. Remote Wispr reads Wispr SQLite read-only.
4. The persistent donor app writes and verifies the local clipboard.
5. Remote Wispr shows `RW Ready`.
6. The user presses physical `Cmd+V` in the remote text box.

Local proof exists for this baseline in both windowed and full-screen Screen Sharing. Do not add focus-return behavior unless that proof changes.

## Risky Assumption

Remote Wispr can programmatically send a keystroke or paste action that reaches the remote text box through Apple Screen Sharing.

Proof required before accepting any feature built on this:

- local proof on the user's actual local Mac,
- active Apple Screen Sharing session,
- real remote text field,
- Accessibility permissions configured for the installed app,
- repeated runs without restarting Remote Wispr, Screen Sharing, or Wispr Flow.

Production proof is not required for the first spike, but the test must make failures obvious and leave the baseline intact.

## Negative Proof Already Observed

The existing Remote Cleanup implementation is not accepted:

- Diagnostics reported that Backspace was posted to the Screen Sharing process.
- The leaked remote `v` remained.
- Therefore, "posted a synthetic key event" is not enough proof.

This also weakens the case for auto-paste through the same synthetic-key path.

## Boundaries

Do not change these while running the spike:

- Wispr SQLite stays read-only.
- No database repair, checkpoint, vacuum, pragma writes, sidecar manipulation, or snapshot-copy fallback.
- Transcript row selection stays fixed.
- Donor clipboard sync stays fixed.
- Manual paste remains the accepted fallback.
- No silent termination of helper, donor, Wispr, or Screen Sharing processes.
- No in-app launch-at-login work.

## Candidate Mechanisms

Each candidate must be tested as a tiny standalone proof before it is wired into Remote Wispr.

1. Physical-user-equivalent event path
   - Try the smallest possible action: one visible character or one Backspace.
   - Passes only if the remote text field changes.
   - Current synthetic Backspace path appears to fail.

2. Screen Sharing menu or system event path
   - Investigate whether Apple Screen Sharing exposes a safer paste/menu action than posting raw key events.
   - Passes only if the remote text field receives the current shared clipboard.

3. Focused local helper path
   - Use a helper only to prepare clipboard/focus, then require a physical paste.
   - This is already the accepted baseline, so it is not enough for auto-paste.

4. Remote-side helper path
   - A helper running on the remote Mac could type/paste locally there.
   - This is a different product boundary and should not be adopted without a separate design decision.

## Test Harness

Start with a standalone spike command or app action that does not involve Wispr:

1. User opens a simple text field in the remote Mac.
2. User types a known marker manually, such as `START `.
3. Spike sends exactly one candidate input action.
4. User reports the final remote text field contents.
5. Spike logs the target app, mechanism, timestamp, and result.

Good first tests:

- send one `x`,
- send one Backspace,
- paste a fixed local clipboard string like `REMOTE_WISPR_INPUT_TEST`,
- run each test three times in a row,
- repeat once in windowed Screen Sharing and once in full-screen Screen Sharing.

## Spike Commands

Build the standalone input spike:

```zsh
make build-input-spike
```

After clicking into the remote Mac text field, confirm the target:

```zsh
make input-spike-target-info
```

The Make targets wait 3 seconds before capturing the target. Start the command, click back into the remote Screen Sharing text field during that countdown, and then wait for the result. It must report `Screen Sharing frontmost: yes`.

Then test one mechanism at a time:

```zsh
make input-spike-send-x
make input-spike-backspace
make input-spike-backspace-system
make input-spike-space-system
make input-spike-paste-fixed
make input-spike-paste-system
make input-spike-paste-keys
make input-spike-donor-paste-fixed
make input-spike-donor-clean-paste-system
make input-spike-donor-clean-paste-keys
make input-spike-type-fixed
make input-spike-type-modifiers
make input-spike-type-unicode
```

The direct binary also supports explicit methods:

```zsh
.build/debug/remote-wispr-input-spike send-key --key v --method hid --capture-delay 3
.build/debug/remote-wispr-input-spike send-key --key x --method hid --capture-delay 3
.build/debug/remote-wispr-input-spike send-key --key delete --method hid --capture-delay 3
.build/debug/remote-wispr-input-spike send-key --key forward-delete --method hid --capture-delay 3
.build/debug/remote-wispr-input-spike send-key --key left --method hid --capture-delay 3
.build/debug/remote-wispr-input-spike send-key --key right --method hid --capture-delay 3
.build/debug/remote-wispr-input-spike send-key --key x --method pid --capture-delay 3
.build/debug/remote-wispr-input-spike send-key --key delete --method pid --capture-delay 3
.build/debug/remote-wispr-input-spike send-key --key delete --method system-events --capture-delay 3
.build/debug/remote-wispr-input-spike send-key --key space --method system-events --capture-delay 3
.build/debug/remote-wispr-input-spike paste-fixed --method command-v --text REMOTE_WISPR_INPUT_TEST --capture-delay 3
.build/debug/remote-wispr-input-spike paste-fixed --method command-v-keys --text REMOTE_WISPR_INPUT_TEST --capture-delay 3
.build/debug/remote-wispr-input-spike paste-fixed --method pid --text REMOTE_WISPR_INPUT_TEST --capture-delay 3
.build/debug/remote-wispr-input-spike paste-fixed --method menu-paste --text REMOTE_WISPR_INPUT_TEST --capture-delay 3
.build/debug/remote-wispr-input-spike paste-fixed --method system-events --text REMOTE_WISPR_INPUT_TEST --capture-delay 3
.build/debug/remote-wispr-input-spike donor-paste-fixed --text REMOTE_WISPR_DONOR_PASTE_TEST --capture-delay 3
.build/debug/remote-wispr-input-spike cleanup-paste-fixed --clipboard donor --cleanup backspace-space --cleanup-method system-events --paste-method system-events --text REMOTE_WISPR_CLEAN_PASTE_SYSTEM --capture-delay 3
.build/debug/remote-wispr-input-spike cleanup-paste-fixed --clipboard donor --cleanup backspace-space --cleanup-method hid-modifiers --paste-method command-v-keys --text REMOTE_WISPR_CLEAN_PASTE_KEYS --capture-delay 3
.build/debug/remote-wispr-input-spike type-fixed --method hid --text "Remote Wispr type test." --capture-delay 3
.build/debug/remote-wispr-input-spike type-fixed --method hid-modifiers --text "Remote Wispr MOD test!" --capture-delay 3
.build/debug/remote-wispr-input-spike type-fixed --method pid --text "Remote Wispr type test." --capture-delay 3
.build/debug/remote-wispr-input-spike type-fixed --method unicode --text "Remote Wispr unicode test." --capture-delay 3
```

Method meanings:

- `hid`: post a keyboard event at the HID event tap.
- `hid-modifiers`: post explicit modifier key-down/key-up events around shifted characters.
- `pid`: post a keyboard event directly to the Screen Sharing process ID.
- `command-v`: set the local pasteboard to the test text, then send physical-equivalent `Cmd+V` at the HID event tap.
- `command-v-keys`: set the local pasteboard, then post explicit Command key-down, `v`, and Command key-up events.
- `menu-paste`: set the local pasteboard to the test text, then ask System Events to click Screen Sharing's Edit > Paste menu item.
- `system-events`: ask System Events to activate Screen Sharing and send the key code or Command+V keystroke.
- `unicode`: type text with CGEvent Unicode payloads instead of key-code mappings.
- `donor-paste-fixed`: use the same persistent donor app as the accepted baseline to sync a fixed clipboard string, then post explicit Command+V key events.
- `cleanup-paste-fixed`: use local pasteboard or the persistent donor app, optionally send cleanup keys, then send paste. This is the main isolated proof path for the leaked-`v` cleanup plus auto-paste sequence.

Latest signal:

- `send-key --key x --method hid` reached the remote text field.
- `send-key --key delete --method hid` did not remove text.
- `paste-fixed --method command-v` did not paste.
- `type-fixed --method hid` typed the text, but shifted characters were lowercased.
- `type-fixed --method unicode` produced repeated `a` characters.
- `type-fixed --method hid-modifiers` typed shifted text correctly.
- `paste-fixed --method command-v-keys` triggered paste, but the remote field received stale clipboard text instead of the fixed test string.
- `donor-paste-fixed` pasted the intended donor text: `REMOTE_WISPR_DONOR_PASTE_TEST`.
- Auto-paste has a viable experimental path: donor clipboard sync, donor reports `clipboardMatches=yes`, then explicit Command+V key events.
- Cleanup is still not proven because Backspace did not affect the remote text box.

Next spike round:

1. Focus a remote Screen Sharing text box.
2. Type a literal leading `v` manually, leaving the cursor after it.
3. Run `make input-spike-backspace-system`.
4. If the `v` disappears, type a leading `v` again and run `make input-spike-donor-clean-paste-system`.
5. If System Events does not work, run `make input-spike-donor-clean-paste-keys`.
6. Record the final text in the remote field and whether focus moved.

The process running the command needs macOS Accessibility permission. When running from Terminal or iTerm, that terminal app may be the process that needs permission. Donor commands launch only the configured `Remote Wispr Copy Donor.app`; the spike does not read Wispr history or touch Remote Wispr settings.

## Pass Criteria

A candidate input mechanism passes local proof only if:

- it changes the remote text field correctly,
- it works three times in a row,
- it works without reloading Remote Wispr,
- it works without restarting Screen Sharing,
- it does not disturb the local clipboard beyond the explicit test value,
- it fails visibly with a logged reason when the target is not Screen Sharing,
- it does not break the accepted manual paste baseline.

## Fail Criteria

Stop testing a candidate and mark it failed if:

- Diagnostics claims success but the remote text field does not change,
- it works only after app restarts or focus gymnastics,
- it depends on arbitrary sleeps without an observable readiness signal,
- it leaves the user in the wrong Space or app,
- it requires extra permissions beyond Accessibility without a clear reason.

## Integration Rule

Only after a candidate passes local proof:

1. create a module boundary such as `RemoteInputAutomation`,
2. keep it disabled by default,
3. expose it as experimental,
4. add Diagnostics fields for mechanism, last attempt, and last result,
5. add an independent test command before connecting it to cleanup or auto-paste.

Cleanup and auto-paste should consume this module. They should not each invent their own keystroke/focus behavior.
