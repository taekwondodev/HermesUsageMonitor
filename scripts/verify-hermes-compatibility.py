#!/usr/bin/env python3
"""Verify the Hermes update-to-app compatibility path without changing Hermes state."""
from __future__ import annotations

import hashlib
import json
import os
import pathlib
import subprocess
import sys
from datetime import datetime, timezone
from typing import Any

PROJECT_ROOT = pathlib.Path(__file__).resolve().parents[1]
HERMES_HOME = pathlib.Path(os.environ.get("HERMES_HOME", pathlib.Path.home() / ".hermes")).expanduser()
HERMES_ROOT = HERMES_HOME.parent.parent if HERMES_HOME.parent.name == "profiles" else HERMES_HOME
REPORT_DIR = HERMES_ROOT / "update-safe"
PROVIDERS = ("openai-codex", "opencode-go")


def run(command: list[str], *, env: dict[str, str] | None = None) -> tuple[int, str]:
    result = subprocess.run(command, cwd=PROJECT_ROOT, env=env, capture_output=True, text=True)
    return result.returncode, result.stdout


def hermes_executable() -> pathlib.Path | None:
    candidates = [HERMES_ROOT / "hermes-agent/venv/bin/hermes"]
    for directory in os.environ.get("PATH", "").split(":"):
        if directory:
            candidates.append(pathlib.Path(directory) / "hermes")
    return next((path for path in candidates if path.is_file() and os.access(path, os.X_OK)), None)


def hermes_checkout() -> pathlib.Path | None:
    candidates: list[pathlib.Path] = [HERMES_ROOT / "hermes-agent", pathlib.Path.home() / ".hermes" / "hermes-agent"]
    for directory in os.environ.get("HERMES_HOME", "").split(os.pathsep):
        candidates.append(pathlib.Path(directory).expanduser() / "hermes-agent")
    seen: set[str] = set()
    for candidate in candidates:
        key = str(candidate.resolve())
        if key in seen:
            continue
        seen.add(key)
        if (candidate / "agent" / "account_usage.py").is_file():
            return candidate
    return None


def checkout_venv_python(checkout: pathlib.Path) -> pathlib.Path | None:
    for name in ("venv/bin/python", "venv/bin/python3"):
        candidate = checkout / name
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate
    return None


def digest(path: pathlib.Path) -> str | None:
    if not path.is_file():
        return None
    hasher = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def credential_files() -> list[pathlib.Path]:
    candidates = [HERMES_ROOT / ".env", HERMES_ROOT / "auth.json"]
    profiles = HERMES_ROOT / "profiles"
    if profiles.is_dir():
        for profile in profiles.iterdir():
            if profile.is_dir():
                candidates.extend([profile / ".env", profile / "auth.json"])
    return sorted({path for path in candidates if path.is_file()})


def main() -> int:
    report: dict[str, Any] = {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "project": str(PROJECT_ROOT),
        "hermesRoot": str(HERMES_ROOT),
        "status": "failed",
        "providers": {},
    }
    state_db = HERMES_ROOT / "state.db"
    before = digest(state_db)
    credential_before = {path: digest(path) for path in credential_files()}
    executable = hermes_executable()
    if executable is None:
        report["hermes"] = {"status": "unavailable", "reason": "commandMissing"}
    else:
        version_code, version_output = run([str(executable), "--version"])
        report["hermes"] = {
            "status": "available" if version_code == 0 else "unavailable",
            "version": version_output.strip()[:120] if version_code == 0 else None,
        }

        command_env = {**os.environ, "HERMES_HOME": str(HERMES_ROOT)}
        bridge = PROJECT_ROOT / "scripts" / "hermes_usage_bridge.py"
        checkout = hermes_checkout()
        venv_python = checkout_venv_python(checkout) if checkout else None
        if venv_python is None:
            report["usage"] = {"status": "unavailable", "reason": "checkoutMissing"}
        else:
            usage_code, usage_output = run(
                [str(venv_python), str(bridge), "--json", "--hermes-root", str(checkout)],
                env=command_env,
            )
            if usage_code == 0:
                try:
                    payload = json.loads(usage_output)
                    for provider in PROVIDERS:
                        value = payload.get("providers", {}).get(provider, {})
                        report["providers"][provider] = {
                            "status": value.get("status", "unavailable"),
                            "subscription": value.get("subscription"),
                            "windows": [
                                {
                                    "kind": window.get("kind"),
                                    "label": window.get("label"),
                                    "usedPercent": window.get("usedPercent"),
                                    "resetAt": window.get("resetAt"),
                                }
                                for window in value.get("windows", [])
                            ],
                            "reason": value.get("reason"),
                        }
                    report["usage"] = {"status": "available"}
                except (ValueError, AttributeError):
                    report["usage"] = {"status": "unavailable", "reason": "malformedPayload"}
            else:
                report["usage"] = {"status": "unavailable", "reason": "commandFailed"}

    test_code, _ = run(["swift", "test"])
    build_code, _ = run(["swift", "build", "-c", "release"])
    report["app"] = {
        "tests": "passed" if test_code == 0 else "failed",
        "releaseBuild": "passed" if build_code == 0 else "failed",
    }
    after = digest(state_db)
    state_unchanged = before == after
    report["stateDb"] = {"unchanged": state_unchanged, "present": after is not None}
    credential_after = {path: digest(path) for path in credential_files()}
    credentials_unchanged = credential_before == credential_after
    report["credentials"] = {
        "unchanged": credentials_unchanged,
        "filesChecked": len(set(credential_before) | set(credential_after)),
    }

    usage_status = report.get("usage", {}).get("status") if isinstance(report.get("usage"), dict) else "unavailable"
    app_ok = test_code == 0 and build_code == 0
    if executable is not None and usage_status == "available" and app_ok and state_unchanged and credentials_unchanged:
        report["status"] = "ok"
    elif app_ok and state_unchanged and credentials_unchanged:
        report["status"] = "partial-degradation"
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    report_path = REPORT_DIR / f"compatibility-{stamp}.json"
    latest_path = REPORT_DIR / "compatibility-latest.json"
    content = json.dumps(report, indent=2, sort_keys=True) + "\n"
    report_path.write_text(content, encoding="utf-8")
    latest_path.write_text(content, encoding="utf-8")
    print(json.dumps({"status": report["status"], "report": str(latest_path)}, indent=2))
    return 0 if report["status"] in {"ok", "partial-degradation"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
