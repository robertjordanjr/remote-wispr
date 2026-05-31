# Remote Wispr App

This folder is reserved for the future macOS app wrapper.

The current implementation spike lives in the Swift package at the repo root:

- `../Sources/RemoteWisprCore/`
- `../Sources/RemoteWisprSpike/`
- `../Tests/RemoteWisprCoreTests/`

The eventual target is a small local menu bar app that owns the Remote Wispr workflow:

1. wait for a trigger,
2. wait for the next Wispr transcript row,
3. select the oldest unprocessed row,
4. write and verify the local pasteboard,
5. perform the focus-donor clipboard sync,
6. return focus to Screen Sharing,
7. report ready-to-paste,
8. optionally clean up the leaked `v`,
9. optionally auto-paste after the core path is proven stable.

Start with the design docs:

- `../docs/architecture.md`
- `../docs/test-plan.md`
- `../docs/implementation-roadmap.md`
- `../docs/spike-1-app-clipboard-baseline.md`
