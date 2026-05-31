#!/usr/bin/env zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

patterns=(
  "ariglobal"
  "/Users/rojo"
  "/Users/agent"
  "codex/app"
  "github.com:ariglobal"
  "github.com/ariglobal"
  "Hammerspoon"
  "hammerspoon"
  "prototypes/hammerspoon"
)

args=()
for pattern in "${patterns[@]}"; do
  args+=("-e" "$pattern")
done

if rg -n "${args[@]}" . \
  --glob '!/.git/**' \
  --glob '!/.build/**' \
  --glob '!/.module-cache/**' \
  --glob '!/Package.resolved' \
  --glob '!/scripts/privacy-scan.zsh'
then
  print -u2 ""
  print -u2 "privacy scan found matches; review and remove or explicitly document why they are safe."
  exit 1
fi

print "privacy scan passed"
