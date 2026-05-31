#!/usr/bin/env zsh
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  print -u2 "usage: scripts/export-public-source.zsh /path/to/clean/export-dir"
  exit 2
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
target="$1"

if [[ -e "$target" ]]; then
  print -u2 "error: target already exists: $target"
  print -u2 "Choose a new empty path so old files cannot leak into the public export."
  exit 1
fi

mkdir -p "$target"

rsync -a \
  --exclude '.git' \
  --exclude '.build' \
  --exclude '.module-cache' \
  --exclude '.swiftpm' \
  --exclude '.DS_Store' \
  --exclude 'docs/handoff.md' \
  "$repo_root/" "$target/"

print "Exported public source tree:"
print "  $target"
print ""
print "Next:"
print "  cd \"$target\""
print "  make privacy-scan"
print "  make test-fixtures"
print "  make build-menubar-app"
print "  git init"
