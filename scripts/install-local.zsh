#!/usr/bin/env zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
install_dir="${REMOTE_WISPR_INSTALL_DIR:-$HOME/Applications}"
settings_path="${REMOTE_WISPR_SETTINGS_PATH:-$HOME/Library/Application Support/RemoteWispr/settings.json}"
restart_menu_app="${REMOTE_WISPR_RESTART_AFTER_INSTALL:-1}"
build_dir="$repo_root/.build/apps"
wispr_db_path="$HOME/Library/Application Support/Wispr Flow/flow.sqlite"
settings_schema_version="2"
export REMOTE_WISPR_REQUIRE_STABLE_SIGNING="${REMOTE_WISPR_REQUIRE_STABLE_SIGNING:-1}"
codesign_identity="${REMOTE_WISPR_CODESIGN_IDENTITY:-Remote Wispr Local Code Signing}"
auto_setup_signing="${REMOTE_WISPR_AUTO_SETUP_SIGNING:-1}"

menu_app="Remote Wispr.app"
donor_app="Remote Wispr Copy Donor.app"
menu_bundle_id="com.remote-wispr.MenuBar"
menu_process_name="Remote Wispr"

running_menu_pids() {
  /usr/bin/pgrep -x "$menu_process_name" 2>/dev/null || true
}

codesign_identity_exists() {
  /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
    | /usr/bin/awk -v name="$codesign_identity" 'index($0, "\"" name "\"") > 0 { found = 1 } END { exit found ? 0 : 1 }'
}

ensure_codesign_identity() {
  if [[ "$REMOTE_WISPR_REQUIRE_STABLE_SIGNING" != "1" || "$codesign_identity" == "-" ]]; then
    return
  fi

  if codesign_identity_exists; then
    return
  fi

  if [[ "$auto_setup_signing" != "1" ]]; then
    print -u2 "error: stable code signing identity not found: $codesign_identity"
    print -u2 "Run 'make setup-local-signing' once, then run 'make install-local' again."
    exit 1
  fi

  print "Setting up local code signing identity:"
  print "  $codesign_identity"
  "$repo_root/scripts/setup-local-signing.zsh"

  if ! codesign_identity_exists; then
    print -u2 "error: stable code signing identity still not found after setup: $codesign_identity"
    exit 1
  fi
}

close_running_menu_app() {
  if [[ "$restart_menu_app" != "1" ]]; then
    return
  fi

  local pids
  pids="$(running_menu_pids)"
  if [[ -z "$pids" ]]; then
    return
  fi

  print "Closing running $menu_app..."
  /usr/bin/osascript -e "tell application id \"$menu_bundle_id\" to quit" >/dev/null 2>&1 || true

  local waited_tenths=0
  while [[ -n "$(running_menu_pids)" && "$waited_tenths" -lt 80 ]]; do
    sleep 0.1
    waited_tenths=$((waited_tenths + 1))
  done

  pids="$(running_menu_pids)"
  if [[ -n "$pids" ]]; then
    print -u2 "error: $menu_app is still running with process IDs: ${(f)pids}"
    print -u2 "Close $menu_app and run make install-local again."
    exit 1
  fi
}

ensure_codesign_identity

"$repo_root/scripts/build-copy-donor-app.zsh" "$build_dir" >/dev/null
"$repo_root/scripts/build-menubar-app.zsh" "$build_dir" >/dev/null

mkdir -p "$install_dir"
close_running_menu_app

for app in "$menu_app" "$donor_app"; do
  source_path="$build_dir/$app"
  target_path="$install_dir/$app"

  if [[ ! -d "$source_path" ]]; then
    print -u2 "error: built app not found: $source_path"
    exit 1
  fi

  if [[ -e "$target_path" && ! -d "$target_path" ]]; then
    print -u2 "error: target exists and is not an app directory: $target_path"
    exit 1
  fi

  rm -rf "$target_path"
  ditto "$source_path" "$target_path"
  touch "$target_path"
done

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  print -r -- "$value"
}

ensure_json_key() {
  local key="$1"
  local type="$2"
  local value="$3"
  local current

  current="$(/usr/bin/plutil -extract "$key" raw -o - "$settings_path" 2>/dev/null || true)"
  if [[ -n "$current" ]]; then
    return
  fi

  /usr/bin/plutil -replace "$key" "-$type" "$value" "$settings_path"
}

settings_dir="$(dirname "$settings_path")"
mkdir -p "$settings_dir"
donor_app_path="$install_dir/$donor_app"

if [[ ! -e "$settings_path" ]]; then
  escaped_wispr_db_path="$(json_escape "$wispr_db_path")"
  escaped_donor_app_path="$(json_escape "$donor_app_path")"
  cat > "$settings_path" <<EOF
{
  "autoPasteDelaySeconds" : 0.2,
  "automaticPasteEnabled" : false,
  "automaticTriggerEnabled" : false,
  "clipboardSyncMode" : "localOnly",
  "donorAppPath" : "$escaped_donor_app_path",
  "focusDonorBundleIdentifier" : "com.remote-wispr.FocusDonor",
  "hiddenDonorEnabled" : true,
  "hotkeyModifiers" : [
    "control",
    "option"
  ],
  "hotkeyMinimumHoldSeconds" : 0.2,
  "pollIntervalSeconds" : 0.25,
  "remoteCleanupMode" : "disabled",
  "settingsSchemaVersion" : $settings_schema_version,
  "waitTimeoutSeconds" : 60,
  "wisprDatabasePath" : "$escaped_wispr_db_path"
}
EOF
else
  if /usr/bin/plutil -p "$settings_path" >/dev/null 2>&1; then
    /usr/bin/plutil -replace settingsSchemaVersion -integer "$settings_schema_version" "$settings_path"
    donor_value="$(/usr/bin/plutil -extract donorAppPath raw -o - "$settings_path" 2>/dev/null || true)"
    if [[ -z "$donor_value" ]]; then
      /usr/bin/plutil -replace donorAppPath -string "$donor_app_path" "$settings_path"
    fi
    ensure_json_key wisprDatabasePath string "$wispr_db_path"
    ensure_json_key hiddenDonorEnabled bool YES
    ensure_json_key clipboardSyncMode string localOnly
    ensure_json_key focusDonorBundleIdentifier string com.remote-wispr.FocusDonor
    ensure_json_key remoteCleanupMode string disabled
    ensure_json_key automaticPasteEnabled bool NO
    ensure_json_key autoPasteDelaySeconds float 0.2
    ensure_json_key automaticTriggerEnabled bool NO
    current_hotkey_modifiers="$(/usr/bin/plutil -extract hotkeyModifiers json -o - "$settings_path" 2>/dev/null || true)"
    if [[ -z "$current_hotkey_modifiers" ]]; then
      /usr/bin/plutil -replace hotkeyModifiers -json '["control","option"]' "$settings_path"
    fi
    ensure_json_key hotkeyMinimumHoldSeconds float 0.2
    ensure_json_key waitTimeoutSeconds float 60
    ensure_json_key pollIntervalSeconds float 0.25
  else
    print -u2 "warning: settings file exists but is not valid JSON/plist; leaving unchanged: $settings_path"
  fi
fi

print "Installed:"
print "  $install_dir/$menu_app"
print "  $install_dir/$donor_app"
print "Settings:"
print "  $settings_path"
print ""
if [[ "$restart_menu_app" == "1" ]]; then
  print "Starting:"
  print "  $install_dir/$menu_app"
  /usr/bin/open "$install_dir/$menu_app"
else
  print "Open with:"
  print "  open \"$install_dir/$menu_app\""
fi
