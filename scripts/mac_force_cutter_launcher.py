#!/usr/bin/env python3

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path


APP_PACKAGE = "com.example.flutter_project"
APP_COMPONENT = f"{APP_PACKAGE}/com.example.flutter_project.MainActivity"
PACKAGE_KEYWORDS = (
    "cutter",
    "plotter",
    "skycut",
    "upus",
    "upprinting",
    "sunshine",
    "mechanic",
    "phonefilm",
    "vinyl",
)
SKIP_PACKAGES = {
    APP_PACKAGE,
    "android",
    "com.android.settings",
    "com.android.systemui",
}


def log(message: str) -> None:
    print(f"[launcher-install] {message}")


def die(message: str) -> None:
    print(f"[launcher-install] ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def run_command(
    args: list[str],
    *,
    check: bool = True,
    capture: bool = False,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        check=check,
        text=True,
        capture_output=capture,
    )


def adb_args(device_serial: str, *extra: str) -> list[str]:
    return ["adb", "-s", device_serial, *extra]


def adb_capture(device_serial: str, *extra: str) -> str:
    result = run_command(adb_args(device_serial, *extra), capture=True)
    return result.stdout.replace("\r", "").strip()


def adb_shell_capture(device_serial: str, command: str, *, use_root: bool) -> str:
    shell_args = ["shell"]
    if use_root:
        shell_args.extend(["su", "-c", command])
    else:
        shell_args.append(command)
    return adb_capture(device_serial, *shell_args)


def _last_non_empty_lines(output: str, count: int = 1) -> list[str]:
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    if count <= 0:
        return []
    return lines[-count:]


def adb_shell_success(device_serial: str, command: str, *, use_root: bool) -> bool:
    shell_args = ["shell"]
    if use_root:
        shell_args.extend(["su", "-c", command])
    else:
        shell_args.append(command)
    result = run_command(adb_args(device_serial, *shell_args), check=False)
    return result.returncode == 0


def detect_default_apk(project_root: Path, explicit_apk: str | None) -> Path:
    if explicit_apk:
        apk_path = Path(explicit_apk).expanduser().resolve()
        if not apk_path.is_file():
            die(f"APK not found: {apk_path}")
        return apk_path

    candidates = (
        project_root / "update.apk",
        project_root / "build" / "app" / "outputs" / "flutter-apk" / "app-release.apk",
    )
    for candidate in candidates:
        if candidate.is_file():
            return candidate

    die("No APK found. Build the app first or pass --apk /path/to/file.apk")


def _candidate_aapt_paths() -> list[Path]:
    candidates: list[Path] = []

    direct_env = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    if direct_env:
        candidates.append(Path(direct_env))

    candidates.append(Path.home() / "Library" / "Android" / "sdk")

    aapt_paths: list[Path] = []
    seen: set[Path] = set()
    for sdk_root in candidates:
        if not sdk_root.exists():
            continue
        build_tools_dir = sdk_root / "build-tools"
        if not build_tools_dir.is_dir():
            continue
        for child in sorted(build_tools_dir.iterdir(), reverse=True):
            aapt = child / "aapt"
            if aapt.is_file() and aapt not in seen:
                seen.add(aapt)
                aapt_paths.append(aapt)
    return aapt_paths


def detect_apk_version(apk_path: Path) -> str | None:
    version_name_re = re.compile(r"versionName='([^']+)'")
    version_code_re = re.compile(r"versionCode='([^']+)'")

    for aapt_path in _candidate_aapt_paths():
        try:
            output = run_command(
                [str(aapt_path), "dump", "badging", str(apk_path)],
                capture=True,
            ).stdout
        except (subprocess.CalledProcessError, FileNotFoundError):
            continue

        version_name_match = version_name_re.search(output)
        version_code_match = version_code_re.search(output)
        if version_name_match and version_code_match:
            return (
                f"{version_name_match.group(1)}"
                f" ({version_code_match.group(1)})"
            )

    return None


def detect_device(explicit_device: str | None) -> str:
    if explicit_device:
        return explicit_device

    output = run_command(["adb", "devices"], capture=True).stdout.replace("\r", "")
    devices = []
    for line in output.splitlines()[1:]:
        parts = line.split()
        if len(parts) >= 2 and parts[1] == "device":
            devices.append(parts[0])

    if not devices:
        die("No authorized adb device is connected.")

    if len(devices) > 1:
        log(f"Multiple devices detected. Using: {devices[0]}")
    return devices[0]


def require_tools() -> None:
    if shutil.which("adb") is None:
        die("adb is not installed or not in PATH.")


def require_root(device_serial: str) -> None:
    if not adb_shell_success(device_serial, "id >/dev/null 2>&1", use_root=True):
        die("Root is required on the connected device.")


def install_app(device_serial: str, apk_path: Path, dry_run: bool) -> None:
    log(f"Installing APK: {apk_path}")
    if dry_run:
        return

    result = run_command(
        adb_args(device_serial, "install", "-r", "-d", str(apk_path)),
        check=False,
        capture=True,
    )
    if result.returncode != 0:
        stderr = result.stderr.strip() or result.stdout.strip() or "APK install failed."
        die(stderr)


def add_candidate(candidates: list[str], package_name: str) -> None:
    if not package_name or package_name in candidates:
        return
    candidates.append(package_name)


def collect_home_packages(device_serial: str) -> list[str]:
    output = adb_shell_capture(
        device_serial,
        (
            "cmd package query-activities --brief "
            "-a android.intent.action.MAIN "
            "-c android.intent.category.HOME 2>/dev/null || "
            "pm query-intent-activities "
            "-a android.intent.action.MAIN "
            "-c android.intent.category.HOME 2>/dev/null || true"
        ),
        use_root=True,
    )
    candidates: list[str] = []
    for line in output.splitlines():
        if "/" not in line:
            continue
        add_candidate(candidates, line.split("/", 1)[0].strip())
    return candidates


def collect_keyword_packages(device_serial: str) -> list[str]:
    output = adb_shell_capture(device_serial, "pm list packages", use_root=False)
    candidates: list[str] = []
    for line in output.splitlines():
        if not line.startswith("package:"):
            continue
        package_name = line.removeprefix("package:").strip()
        lower_name = package_name.lower()
        if any(keyword in lower_name for keyword in PACKAGE_KEYWORDS):
            add_candidate(candidates, package_name)
    return candidates


def remove_or_disable_package(device_serial: str, package_name: str, dry_run: bool) -> None:
    if package_name in SKIP_PACKAGES:
        return

    log(f"Removing competing package: {package_name}")
    if dry_run:
        return

    adb_shell_success(
        device_serial,
        f"am force-stop '{package_name}' >/dev/null 2>&1 || true",
        use_root=True,
    )

    if adb_shell_success(
        device_serial,
        f"pm uninstall --user 0 '{package_name}' >/dev/null 2>&1",
        use_root=True,
    ):
        return

    if adb_shell_success(
        device_serial,
        (
            f"pm disable-user --user 0 '{package_name}' >/dev/null 2>&1 || "
            f"pm disable '{package_name}' >/dev/null 2>&1"
        ),
        use_root=True,
    ):
        return

    log(f"Could not remove or disable: {package_name}")


def force_launcher_default(device_serial: str, dry_run: bool) -> None:
    log(f"Making {APP_PACKAGE} the HOME launcher")
    if dry_run:
        return

    commands = (
        f"pm enable '{APP_PACKAGE}' >/dev/null 2>&1 || true",
        (
            f"cmd package set-home-activity '{APP_COMPONENT}' >/dev/null 2>&1 || "
            f"pm set-home-activity '{APP_COMPONENT}' >/dev/null 2>&1 || true"
        ),
        f"am start -n '{APP_COMPONENT}' >/dev/null 2>&1 || true",
        "input keyevent KEYCODE_HOME >/dev/null 2>&1 || true",
    )
    for command in commands:
        adb_shell_success(device_serial, command, use_root=True)


def show_summary(device_serial: str) -> None:
    resolved_home_output = adb_shell_capture(
        device_serial,
        (
            "cmd package resolve-activity --brief "
            "-a android.intent.action.MAIN "
            "-c android.intent.category.HOME 2>/dev/null || true"
        ),
        use_root=True,
    )
    resolved_home_lines = _last_non_empty_lines(resolved_home_output, 1)
    resolved_home = resolved_home_lines[0] if resolved_home_lines else ""

    focus_output = adb_shell_capture(
        device_serial,
        (
            "dumpsys window windows 2>/dev/null | "
            "grep -E 'mCurrentFocus|mFocusedApp' || true"
        ),
        use_root=False,
    )
    focus_lines = _last_non_empty_lines(focus_output, 2)
    log(f"Resolved HOME: {resolved_home or 'unknown'}")
    if focus_lines:
        print("\n".join(focus_lines))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Install this app, remove competing cutter launchers, "
            "and force it as the default HOME launcher."
        )
    )
    parser.add_argument("--device", help="Specific adb device serial")
    parser.add_argument("--apk", help="Path to the APK to install")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview target packages without changing the device",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    require_tools()

    project_root = Path(__file__).resolve().parents[1]
    apk_path = detect_default_apk(project_root, args.apk)
    device_serial = detect_device(args.device)
    require_root(device_serial)

    log(f"Device: {device_serial}")
    apk_version = detect_apk_version(apk_path)
    if apk_version:
        log(f"APK version: {apk_version}")
    install_app(device_serial, apk_path, args.dry_run)

    removal_candidates: list[str] = []
    for package_name in collect_home_packages(device_serial):
        add_candidate(removal_candidates, package_name)
    for package_name in collect_keyword_packages(device_serial):
        add_candidate(removal_candidates, package_name)

    if removal_candidates:
        log(f"Candidate packages: {' '.join(removal_candidates)}")

    for package_name in removal_candidates:
        remove_or_disable_package(device_serial, package_name, args.dry_run)

    force_launcher_default(device_serial, args.dry_run)
    show_summary(device_serial)
    log("Done.")


if __name__ == "__main__":
    main()
