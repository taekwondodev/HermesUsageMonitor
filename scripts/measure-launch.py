#!/usr/bin/env python3

import argparse
import hashlib
import json
import math
import os
import platform
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any

APP_NAME = "HermesUsageMonitor"
APP_PATH = Path.home() / "Applications" / f"{APP_NAME}.app"
EXECUTABLE = APP_PATH / "Contents" / "MacOS" / APP_NAME
PROBE_ENVIRONMENT_KEY = "HERMES_LAUNCH_PROBE_FILE"
DEFAULT_SAMPLES = 20
DEFAULT_TIMEOUT = 5.0
BUDGET_MULTIPLIER = 1.2


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Measure menu-bar first appearance across fresh launches.")
    parser.add_argument("--samples", type=int, default=DEFAULT_SAMPLES)
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--record-baseline", type=Path)
    mode.add_argument("--baseline", type=Path)
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
        process.wait(timeout=2)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=2)


def measure_once(index: int, timeout: float) -> float:
    if process_is_running():
        raise RuntimeError(f"sample {index}: {APP_NAME} is already running")

    with tempfile.TemporaryDirectory(prefix="hermes-launch-") as directory:
        probe_path = Path(directory) / "first-appearance.json"
        environment = os.environ.copy()
        environment[PROBE_ENVIRONMENT_KEY] = str(probe_path)
        started_at = time.clock_gettime(time.CLOCK_UPTIME_RAW)
        process = subprocess.Popen(
            [str(EXECUTABLE)],
            env=environment,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        deadline = time.monotonic() + timeout
        try:
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    raise RuntimeError(
                        f"sample {index}: process exited with status {process.returncode} before the milestone"
                    )
                if probe_path.exists():
                    payload = json.loads(probe_path.read_text(encoding="utf-8"))
                    if payload.get("pid") != process.pid:
                        raise RuntimeError(f"sample {index}: probe PID does not match launched process")
                    duration = float(payload["systemUptime"]) - started_at
                    if duration <= 0 or duration > timeout:
                        raise RuntimeError(f"sample {index}: invalid duration {duration:.6f}s")
                    return duration * 1_000
                time.sleep(0.005)
            raise RuntimeError(f"sample {index}: milestone timed out after {timeout:.1f}s")
        finally:
            terminate(process)


def nearest_rank_percentile(values: list[float], percentile: float) -> float:
    ordered = sorted(values)
    rank = math.ceil(percentile * len(ordered))
    return ordered[rank - 1]


def machine_identity() -> dict[str, str]:
    model = subprocess.run(
        ["sysctl", "-n", "hw.model"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()
    return {
        "model": model,
        "os": platform.mac_ver()[0],
        "architecture": platform.machine(),
    }


def executable_sha256() -> str:
    digest = hashlib.sha256()
    with EXECUTABLE.open("rb") as executable:
        for chunk in iter(lambda: executable.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def measurement(samples: list[float], executable_hash: str) -> dict[str, Any]:
    median = statistics.median(samples)
    p95 = nearest_rank_percentile(samples, 0.95)
    return {
        "schemaVersion": 1,
        "milestone": "menu-bar-identity-first-appearance",
        "sampleCount": len(samples),
        "samplesMilliseconds": [round(sample, 3) for sample in samples],
        "medianMilliseconds": round(median, 3),
        "p95Milliseconds": round(p95, 3),
        "machine": machine_identity(),
        "executableSHA256": executable_hash,
    }


def print_measurement(result: dict[str, Any]) -> None:
    for index, sample in enumerate(result["samplesMilliseconds"], start=1):
        print(f"sample {index:02d}: {sample:.3f} ms")
    print(f"median: {result['medianMilliseconds']:.3f} ms")
    print(f"p95: {result['p95Milliseconds']:.3f} ms")
    machine = result["machine"]
    print(f"machine: {machine['model']} {machine['architecture']} macOS {machine['os']}")
    print(f"artifact sha256: {result['executableSHA256']}")


def main() -> int:
    arguments = parse_arguments()
    if arguments.samples < 1:
        raise RuntimeError("sample count must be positive")
    if arguments.timeout <= 0:
        raise RuntimeError("timeout must be positive")
    if not EXECUTABLE.is_file() or not os.access(EXECUTABLE, os.X_OK):
        raise RuntimeError(f"installed release executable is missing: {EXECUTABLE}")
    if process_is_running():
        raise RuntimeError(f"close {APP_NAME} before measuring launch")

    executable_hash = executable_sha256()
    samples = [measure_once(index, arguments.timeout) for index in range(1, arguments.samples + 1)]
    if executable_sha256() != executable_hash:
        raise RuntimeError("installed executable changed during measurement")
    result = measurement(samples, executable_hash)
    print_measurement(result)

    if arguments.record_baseline:
        result["budgetP95Milliseconds"] = round(
            float(result["p95Milliseconds"]) * BUDGET_MULTIPLIER,
            3,
        )
        arguments.record_baseline.parent.mkdir(parents=True, exist_ok=True)
        arguments.record_baseline.write_text(
            json.dumps(result, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        print(f"baseline: {arguments.record_baseline}")
        print(f"budget p95: {result['budgetP95Milliseconds']:.3f} ms")
        return 0

    if arguments.baseline:
        baseline = json.loads(arguments.baseline.read_text(encoding="utf-8"))
        if baseline["machine"] != result["machine"]:
            raise RuntimeError("baseline machine and current machine do not match")
        if baseline["sampleCount"] != result["sampleCount"]:
            raise RuntimeError("baseline and current sample counts do not match")
        budget = float(baseline["budgetP95Milliseconds"])
        current = float(result["p95Milliseconds"])
        if current > budget:
            print(f"FAIL: p95 {current:.3f} ms exceeds budget {budget:.3f} ms", file=sys.stderr)
            return 1
        print(f"PASS: p95 {current:.3f} ms is within budget {budget:.3f} ms")

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"launch measurement failed: {error}", file=sys.stderr)
        raise SystemExit(2)
