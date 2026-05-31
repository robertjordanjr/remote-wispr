# Public Source Release Checklist

Remote Wispr should be published as a clean source-build repository, not as a fork of a private/internal repository and not with historical commits.

## Release Model

- Source-build alpha.
- No prebuilt binaries.
- No DMG or package installer.
- No Mac App Store claim.
- Apple Screen Sharing is the only proven target.
- Other remote-control tools are extension points, not supported targets.

## Sanitization Requirements

Before publishing, the public tree must not contain:

- internal organization names,
- client names,
- real user names,
- real local paths,
- private GitHub remotes,
- old commit history,
- logs,
- screenshots with private data,
- old prototype artifacts,
- transcript text from real usage.

Run:

```zsh
make privacy-scan
```

Review every match before publishing.

## Clean Export

Use:

```zsh
scripts/export-public-source.zsh /path/to/clean/remote-wispr-public
```

Then inspect the exported tree, initialize a fresh git repository, and push it to a new public repository under the desired GitHub account.

Do not use GitHub's Fork button when privacy separation from an internal repository matters.

## Fresh Public Repo Commands

From the exported directory:

```zsh
git init
git add .
git commit -m "Initial public source release"
git branch -M main
git remote add origin git@github.com:YOUR_USERNAME/remote-wispr.git
git push -u origin main
```

## Suggested Public Description

Remote Wispr is a source-build macOS utility for using Wispr Flow while controlling another Mac through Apple Screen Sharing. It reads Wispr's local history database read-only, copies the latest transcript through a verified local clipboard donor, and optionally cleans/pastes into the remote text field.

## Before Posting A Link

- Confirm `make test-fixtures` passes.
- Confirm `make build-menubar-app` passes.
- Confirm `make privacy-scan` has no unreviewed sensitive matches.
- Confirm README install steps work on a clean Mac.
- Confirm `PRIVACY.md` and `SECURITY.md` are present.
