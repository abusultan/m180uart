#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_PACKAGE="com.example.flutter_project"
APP_COMPONENT="${APP_PACKAGE}/com.example.flutter_project.MainActivity"
DEFAULT_APK="$PROJECT_ROOT/update.apk"
FALLBACK_APK="$PROJECT_ROOT/build/app/outputs/flutter-apk/app-release.apk"

typeset -a PACKAGE_KEYWORDS=(
  cutter
  plotter
  skycut
  upus
  upprinting
  sunshine
  mechanic
  phonefilm
  vinyl
)

typeset -a REMOVAL_CANDIDATES=()

DEVICE_SERIAL=""
APK_PATH=""
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage:
  ./scripts/mac_force_cutter_launcher.zsh [--device SERIAL] [--apk /path/to/app.apk] [--dry-run]

What it does:
  1. Detects the connected Android device.
  2. Requires root on the device.
  3. Installs this app APK.
  4. Finds other HOME/launcher apps and cutter-related packages.
  5. Uninstalls them for user 0 when possible, otherwise disables them.
  6. Forces this app as the default HOME launcher.

Notes:
  - Default APK path is ./update.apk, then ./build/app/outputs/flutter-apk/app-release.apk
  - If multiple devices are connected, the first authorized device is used unless --device is set.
  - Use --dry-run to preview removal targets without changing the device.
EOF
}

log() {
  print -r -- "[launcher-install] $*"
}

die() {
  print -u2 -r -- "[launcher-install] ERROR: $*"
  exit 1
}

add_candidate() {
  local pkg="$1"
  [[ -z "$pkg" ]] && return

  local existing
  for existing in "${REMOVAL_CANDIDATES[@]:-}"; do
    [[ "$existing" == "$pkg" ]] && return
  done

  REMOVAL_CANDIDATES+=("$pkg")
}

should_skip_package() {
  local pkg="$1"
  [[ "$pkg" == "$APP_PACKAGE" ]] && return 0
  [[ "$pkg" == "android" ]] && return 0
  [[ "$pkg" == "com.android.settings" ]] && return 0
  [[ "$pkg" == "com.android.systemui" ]] && return 0
  return 1
}

adb_base() {
  adb -s "$DEVICE_SERIAL" "$@"
}

adb_shell_capture() {
  adb_base shell "$@" | tr -d '\r'
}

adb_su_capture() {
  adb_base shell su -c "$1" | tr -d '\r'
}

adb_su_run() {
  adb_base shell su -c "$1" >/dev/null
}

pick_device() {
  if [[ -n "$DEVICE_SERIAL" ]]; then
    return
  fi

  local devices
  devices="$(adb devices | awk 'NR>1 && $2=="device" {print $1}')"
  local count
  count="$(print -r -- "$devices" | sed '/^$/d' | wc -l | tr -d ' ')"

  if [[ "$count" == "0" ]]; then
    die "No authorized adb device is connected."
  fi

  DEVICE_SERIAL="$(print -r -- "$devices" | sed '/^$/d' | head -n 1)"
  if [[ "$count" != "1" ]]; then
    log "Multiple devices detected. Using: $DEVICE_SERIAL"
  fi
}

detect_apk_path() {
  if [[ -n "$APK_PATH" ]]; then
    [[ -f "$APK_PATH" ]] || die "APK not found: $APK_PATH"
    return
  fi

  if [[ -f "$DEFAULT_APK" ]]; then
    APK_PATH="$DEFAULT_APK"
    return
  fi

  if [[ -f "$FALLBACK_APK" ]]; then
    APK_PATH="$FALLBACK_APK"
    return
  fi

  die "No APK found. Build the app first or pass --apk /path/to/file.apk"
}

require_tools() {
  (( $+commands[adb] )) || die "adb is not installed or not in PATH."
}

require_root() {
  if ! adb_base get-state >/dev/null 2>&1; then
    die "adb cannot talk to device $DEVICE_SERIAL."
  fi

  if ! adb_base shell su -c "id >/dev/null 2>&1"; then
    die "Root is required on the connected device."
  fi
}

collect_home_packages() {
  local output
  output="$(
    adb_su_capture \
      "cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null || pm query-intent-activities -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null || true"
  )"

  local line pkg
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    [[ "$line" == *"/"* ]] || continue
    pkg="${line%%/*}"
    add_candidate "$pkg"
  done <<< "$output"
}

collect_keyword_packages() {
  local packages_output
  packages_output="$(adb_shell_capture pm list packages)"

  local line pkg lower keyword
  while IFS= read -r line; do
    [[ "$line" == package:* ]] || continue
    pkg="${line#package:}"
    lower="${pkg:l}"
    for keyword in "${PACKAGE_KEYWORDS[@]}"; do
      if [[ "$lower" == *"$keyword"* ]]; then
        add_candidate "$pkg"
        break
      fi
    done
  done <<< "$packages_output"
}

install_our_app() {
  log "Installing APK: $APK_PATH"
  if (( DRY_RUN )); then
    return
  fi

  adb_base install -r -d "$APK_PATH" >/dev/null || die "APK install failed."
}

remove_or_disable_package() {
  local pkg="$1"

  if should_skip_package "$pkg"; then
    return
  fi

  log "Removing competing package: $pkg"
  if (( DRY_RUN )); then
    return
  fi

  adb_su_run "am force-stop '$pkg' >/dev/null 2>&1 || true" || true

  if adb_base shell su -c "pm uninstall --user 0 '$pkg' >/dev/null 2>&1"; then
    return
  fi

  if adb_base shell su -c "pm disable-user --user 0 '$pkg' >/dev/null 2>&1 || pm disable '$pkg' >/dev/null 2>&1"; then
    return
  fi

  log "Could not remove or disable: $pkg"
}

force_launcher_default() {
  log "Making $APP_PACKAGE the HOME launcher"
  if (( DRY_RUN )); then
    return
  fi

  adb_su_run "pm enable '$APP_PACKAGE' >/dev/null 2>&1 || true" || true
  adb_su_run "cmd package set-home-activity '$APP_COMPONENT' >/dev/null 2>&1 || pm set-home-activity '$APP_COMPONENT' >/dev/null 2>&1 || true" || true
  adb_su_run "am start -n '$APP_COMPONENT' >/dev/null 2>&1 || true" || true
  adb_su_run "input keyevent KEYCODE_HOME >/dev/null 2>&1 || true" || true
}

show_summary() {
  local resolved focus
  resolved="$(
    adb_su_capture \
      "cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null | tail -n 1 || true"
  )"
  focus="$(
    adb_shell_capture dumpsys window windows 2>/dev/null | \
      grep -E 'mCurrentFocus|mFocusedApp' | \
      tail -n 2 || true
  )"

  log "Resolved HOME: ${resolved:-unknown}"
  if [[ -n "$focus" ]]; then
    print -r -- "$focus"
  fi
}

while (( $# > 0 )); do
  case "$1" in
    --device)
      [[ $# -ge 2 ]] || die "--device requires a value"
      DEVICE_SERIAL="$2"
      shift 2
      ;;
    --apk)
      [[ $# -ge 2 ]] || die "--apk requires a value"
      APK_PATH="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

require_tools
pick_device
detect_apk_path
require_root

log "Device: $DEVICE_SERIAL"
install_our_app

collect_home_packages
collect_keyword_packages

if (( ${#REMOVAL_CANDIDATES[@]} > 0 )); then
  log "Candidate packages: ${REMOVAL_CANDIDATES[*]}"
fi

local_pkg=""
for local_pkg in "${REMOVAL_CANDIDATES[@]:-}"; do
  remove_or_disable_package "$local_pkg"
done

force_launcher_default
show_summary

log "Done."
