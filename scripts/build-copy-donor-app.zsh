#!/usr/bin/env zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="${1:-$repo_root/.build/apps}"
app_name="Remote Wispr Copy Donor"
bundle_id="com.remote-wispr.CopyDonor"
app_path="$output_dir/$app_name.app"
contents="$app_path/Contents"
macos="$contents/MacOS"
resources="$contents/Resources"
version="${REMOTE_WISPR_VERSION:-$(tr -d '[:space:]' < "$repo_root/VERSION")}"
build_number="${REMOTE_WISPR_BUILD_NUMBER:-$(git -C "$repo_root" rev-list --count HEAD 2>/dev/null || print 1)}"

mkdir -p "$macos" "$resources"

cd "$repo_root"
CLANG_MODULE_CACHE_PATH="$repo_root/.module-cache" swift build --product remote-wispr-donor-app

cp "$repo_root/.build/debug/remote-wispr-donor-app" "$macos/$app_name"
chmod +x "$macos/$app_name"
cp "$repo_root/assets/RemoteWispr.icns" "$resources/RemoteWispr.icns"

cat >"$contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$app_name</string>
  <key>CFBundleIdentifier</key>
  <string>$bundle_id</string>
  <key>CFBundleName</key>
  <string>$app_name</string>
  <key>CFBundleDisplayName</key>
  <string>$app_name</string>
  <key>CFBundleIconFile</key>
  <string>RemoteWispr</string>
  <key>CFBundleIconName</key>
  <string>RemoteWispr</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$version</string>
  <key>CFBundleVersion</key>
  <string>$build_number</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

"$repo_root/scripts/sign-app.zsh" "$app_path" "$bundle_id" >/dev/null

echo "$app_path"
