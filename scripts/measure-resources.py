#!/usr/bin/env python3

import argparse
import hashlib
import json
import os
import platform
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any

APP_NAME = "HermesUsageMonitor"
APP_PATH = Path.home() / "Applications" / f"{APP_NAME}.app"
EXECUTABLE = APP_PATH / "Contents" / "MacOS" / APP_NAME
PROFILE_ENVIRONMENT_KEY = "HERMES_RESOURCE_PROFILE_FILE"
DEFAULT_TIMEOUT = 600.0


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Capture a manual resident resource profile.")
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT)
    parser.add_argument("--record-baseline", type=Path)
    return parser.parse_args()


def process_is_running() -> bool:
    return subprocess.run(
        ["pgrep", "-x", APP_NAME],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    ).returncode == 0


def terminate(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=3)


def machine_identity() -> dict[str, str]:
    model = subprocess.run(
        ["sysctl", "-n", "hw.model"], capture_output=True, text=True, check=True
    ).stdout.strip()
    return {"model": model, "os": platform.mac_ver()[0], "architecture": platform.machine()}


def executable_sha256() -> str:
    digest = hashlib.sha256()
    with EXECUTABLE.open("rb") as executable:
        for chunk in iter(lambda: executable.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def wait_for_session(path: Path, process: subprocess.Popen[bytes], timeout: float) -> dict[str, Any]:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.exists():
            return json.loads(path.read_text(encoding="utf-8"))
        if process.poll() is not None:
            raise RuntimeError(f"app exited with status {process.returncode} before writing the session")
        time.sleep(0.25)
    raise RuntimeError(f"manual session timed out after {timeout:.0f} seconds")


def baseline_from_session(session: dict[str, Any], executable_hash: str) -> dict[str, Any]:
    if not session.get("valid", False):
        raise RuntimeError("session does not cover at least 15 seconds in both states")
    return {
        "schemaVersion": 1,
        "coverageThresholdSeconds": session["coverageThresholdSeconds"],
        "aggregates": session["aggregates"],
        "machine": machine_identity(),
        "executableSHA256": executable_hash,
    }


def print_report(session: dict[str, Any]) -> None:
    print(f"session valid: {'yes' if session.get('valid') else 'no'}")
    for state in ("closed", "open"):
        aggregate = session["aggregates"][state]
        print(
            f"{state}: {aggregate['durationSeconds']:.1f}s, "
            f"memory average {aggregate['memoryAverageMegabytes']:.1f} MB, "
            f"peak {aggregate['memoryPeakMegabytes']:.1f} MB, "
            f"CPU average {aggregate['cpuAveragePercent']:.2f}%"
        )


def main() -> int:
    arguments = parse_arguments()
    if arguments.timeout <= 0:
        raise RuntimeError("timeout must be positive")
    if not EXECUTABLE.is_file() or not os.access(EXECUTABLE, os.X_OK):
        raise RuntimeError(f"installed release executable is missing: {EXECUTABLE}")
    if process_is_running():
        raise RuntimeError(f"close {APP_NAME} before measuring resources")

    executable_hash = executable_sha256()
    with tempfile.TemporaryDirectory(prefix="hermes-resource-") as directory:
        session_path = Path(directory) / "resource-profile.json"
        environment = os.environ.copy()
        environment[PROFILE_ENVIRONMENT_KEY] = str(session_path)
        process = subprocess.Popen(
            [str(EXECUTABLE)], env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        print("App launched. Keep the popover closed for at least 15 seconds, open it for at least 15 seconds, then quit the app.")
        try:
            session = wait_for_session(session_path, process, arguments.timeout)
        finally:
            terminate(process)

    if executable_sha256() != executable_hash:
        raise RuntimeError("installed executable changed during measurement")

    print_report(session)
    if not session.get("valid", False):
        return 1
    if arguments.record_baseline:
        baseline = baseline_from_session(session, executable_hash)
        arguments.record_baseline.parent.mkdir(parents=True, exist_ok=True)
        arguments.record_baseline.write_text(json.dumps(baseline, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"baseline: {arguments.record_baseline}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"resource measurement failed: {error}", file=sys.stderr)
        raise SystemExit(2)
