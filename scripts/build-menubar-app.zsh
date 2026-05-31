#!/usr/bin/env zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="${1:-$repo_root/.build/apps}"
app_name="Remote Wispr"
bundle_id="com.remote-wispr.MenuBar"
app_path="$output_dir/$app_name.app"
contents="$app_path/Contents"
macos="$contents/MacOS"
resources="$contents/Resources"
version="${REMOTE_WISPR_VERSION:-$(tr -d '[:space:]' < "$repo_root/VERSION")}"
build_number="${REMOTE_WISPR_BUILD_NUMBER:-$(git -C "$repo_root" rev-list --count HEAD 2>/dev/null || print 1)}"

mkdir -p "$macos" "$resources"

cd "$repo_root"
CLANG_MODULE_CACHE_PATH="$repo_root/.module-cache" swift build --product remote-wispr-menubar

cp "$repo_root/.build/debug/remote-wispr-menubar" "$macos/$app_name"
chmod +x "$macos/$app_name"
cp "$repo_root/assets/RemoteWispr.icns" "$resources/RemoteWispr.icns"

plist="$contents/Info.plist"
{
  print '<?xml version="1.0" encoding="UTF-8"?>'
  print '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
  print '<plist version="1.0">'
  print '<dict>'
  print '  <key>CFBundleDevelopmentRegion</key>'
  print '  <string>en</string>'
  print '  <key>CFBundleExecutable</key>'
  print "  <string>$app_name</string>"
  print '  <key>CFBundleIdentifier</key>'
  print "  <string>$bundle_id</string>"
  print '  <key>CFBundleName</key>'
  print "  <string>$app_name</string>"
  print '  <key>CFBundleDisplayName</key>'
  print "  <string>$app_name</string>"
  print '  <key>CFBundleIconFile</key>'
  print '  <string>RemoteWispr</string>'
  print '  <key>CFBundleIconName</key>'
  print '  <string>RemoteWispr</string>'
  print '  <key>CFBundlePackageType</key>'
  print '  <string>APPL</string>'
  print '  <key>CFBundleShortVersionString</key>'
  print "  <string>$version</string>"
  print '  <key>CFBundleVersion</key>'
  print "  <string>$build_number</string>"
  print '  <key>LSMinimumSystemVersion</key>'
  print '  <string>13.0</string>'
  print '  <key>LSUIElement</key>'
  print '  <true/>'
  print '  <key>NSAppleEventsUsageDescription</key>'
  print '  <string>Remote Wispr needs permission to ask System Events to send Backspace and Command-V to Apple Screen Sharing for optional cleanup and auto-paste.</string>'
  print '</dict>'
  print '</plist>'
} >"$plist"

"$repo_root/scripts/sign-app.zsh" "$app_path" "$bundle_id" >/dev/null

echo "$app_path"
