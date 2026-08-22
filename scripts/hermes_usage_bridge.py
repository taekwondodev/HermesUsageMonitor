#!/usr/bin/env python3
"""Emit Hermes quota usage for the providers tracked by HermesUsageMonitor."""

from __future__ import annotations

import argparse
import concurrent.futures
import importlib
import json
import math
import os
import signal
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace
from typing import Any, Callable

PROVIDERS = (
    ("openai-codex", "chatgpt"),
    ("opencode-go", "opencode-go"),
)
TIMEOUT_SECONDS = 15.0
_ACTIVE_WORKERS: list[Any] = []


class BridgeError(Exception):
    pass


@dataclass(frozen=True)
class UsageAPI:
    fetch_account_usage: Callable[[str], Any]
    resolve_runtime_provider: Callable[..., Any]
    httpx: Any
    resolve_codex_usage_credentials: Callable[..., Any] | None = None
    codex_backend_urls: Callable[..., Any] | None = None


@dataclass(frozen=True)
class ProviderResult:
    provider: str
    subscription: str
    payload: dict[str, Any]


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def isoformat(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def parse_datetime(value: Any) -> datetime | None:
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        numeric = float(value)
        if not math.isfinite(numeric):
            return None
        try:
            return datetime.fromtimestamp(numeric, timezone.utc)
        except (OSError, OverflowError, ValueError):
            return None
    if isinstance(value, str):
        text = value.strip()
        if text.endswith("Z"):
            text = text[:-1] + "+00:00"
        try:
            parsed = datetime.fromisoformat(text)
        except ValueError:
            return None
        return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
    return None


def resolve_hermes_root(explicit: str | None) -> Path:
    candidates: list[Path] = []
    if explicit:
        candidates.append(Path(explicit).expanduser())
    for variable in ("HERMES_AGENT_ROOT", "HERMES_ROOT"):
        value = os.environ.get(variable)
        if value:
            candidates.append(Path(value).expanduser())
    hermes_home = os.environ.get("HERMES_HOME")
    if hermes_home:
        home = Path(hermes_home).expanduser()
        candidates.extend((home / "hermes-agent", home.parent / "hermes-agent"))
    candidates.append(Path.home() / ".hermes" / "hermes-agent")

    for candidate in candidates:
        root = candidate.resolve()
        if (root / "agent" / "account_usage.py").is_file():
            return root
    raise BridgeError("Hermes upstream checkout not found")


def load_usage_api(root: Path) -> UsageAPI:
    root_text = str(root)
    if root_text not in sys.path:
        sys.path.insert(0, root_text)
    try:
        account_usage = importlib.import_module("agent.account_usage")
        runtime_provider = importlib.import_module("hermes_cli.runtime_provider")
        httpx = importlib.import_module("httpx")
    except Exception:
        raise BridgeError("Hermes usage API could not be imported") from None

    fetch = getattr(account_usage, "fetch_account_usage", None)
    resolve_runtime = getattr(runtime_provider, "resolve_runtime_provider", None)
    resolve_codex = getattr(account_usage, "_resolve_codex_usage_credentials", None)
    codex_urls = getattr(account_usage, "_codex_backend_urls", None)
    if (
        not callable(fetch)
        or not callable(resolve_runtime)
        or not callable(getattr(httpx, "Client", None))
    ):
        raise BridgeError("Hermes usage API is incompatible")
    for module in (account_usage, runtime_provider):
        module_file = Path(str(getattr(module, "__file__", ""))).resolve()
        if root not in module_file.parents:
            raise BridgeError("Hermes usage API resolved outside the selected checkout")
    return UsageAPI(fetch, resolve_runtime, httpx, resolve_codex, codex_urls)


def classify_window(label: str) -> str | None:
    normalized = " ".join(label.strip().lower().split())
    if normalized in {"session", "5 hours", "5 hour", "rolling", "rolling 5h", "rolling 5 hours"}:
        return "rolling-5h"
    if normalized in {"daily", "day", "today"}:
        return "daily"
    if normalized in {"weekly", "week", "this week"}:
        return "weekly"
    if normalized in {"monthly", "month", "this month"}:
        return "monthly"
    return None


def window_payload(window: Any) -> dict[str, Any] | None:
    label = str(getattr(window, "label", "") or "").strip()
    kind = classify_window(label)
    if not label or kind is None:
        return None
    used_percent = getattr(window, "used_percent", None)
    if used_percent is not None:
        try:
            used_percent = float(used_percent)
        except (TypeError, ValueError):
            return None
        if not math.isfinite(used_percent) or not 0 <= used_percent <= 100:
            return None
    reset_at = getattr(window, "reset_at", None)
    return {
        "kind": kind,
        "label": label,
        "usedPercent": used_percent,
        "resetAt": isoformat(reset_at) if isinstance(reset_at, datetime) else None,
        "detail": getattr(window, "detail", None),
    }


def snapshot_payload(provider: str, subscription: str, snapshot: Any) -> ProviderResult:
    if snapshot is None or getattr(snapshot, "unavailable_reason", None):
        return unavailable(provider, subscription, "provider unavailable")
    windows = [
        payload
        for window in getattr(snapshot, "windows", ())
        if (payload := window_payload(window)) is not None
    ]
    if not windows:
        return unavailable(provider, subscription, "quota unavailable")
    captured_at = getattr(snapshot, "fetched_at", None)
    if not isinstance(captured_at, datetime):
        return unavailable(provider, subscription, "captured timestamp unavailable")
    return ProviderResult(
        provider=provider,
        subscription=subscription,
        payload={
            "status": "available",
            "subscription": subscription,
            "source": str(getattr(snapshot, "source", "usage_api")),
            "capturedAt": isoformat(captured_at),
            "plan": getattr(snapshot, "plan", None),
            "windows": windows,
        },
    )


def unavailable(provider: str, subscription: str, reason: str) -> ProviderResult:
    return ProviderResult(
        provider=provider,
        subscription=subscription,
        payload={"status": "unavailable", "subscription": subscription, "reason": reason},
    )


def opencode_snapshot(api: UsageAPI) -> Any | None:
    runtime = api.resolve_runtime_provider(requested="opencode-go")
    token = str(runtime.get("api_key", "") or "").strip()
    if not token:
        return None
    base_url = str(runtime.get("base_url", "") or "https://opencode.ai/zen/go/v1").rstrip("/")
    headers = {
        "Authorization": f"Bearer {token}",
        "x-api-key": token,
        "Accept": "application/json",
        "User-Agent": "hermes-usage-bridge",
    }
    with api.httpx.Client(timeout=TIMEOUT_SECONDS) as client:
        response = client.get(f"{base_url}/usage", headers=headers)
        response.raise_for_status()
    payload = response.json() or {}
    body = payload.get("data") if isinstance(payload, dict) else None
    body = body if isinstance(body, dict) else payload if isinstance(payload, dict) else {}
    raw_windows = body.get("windows") or []
    if not raw_windows and isinstance(body.get("usage"), dict):
        raw_windows = [
            {
                "kind": "rolling-5h" if key == "rolling" else key,
                "label": "5 hours" if key == "rolling" else key.title(),
                "used_percent": value.get("percent"),
                "reset_at": value.get("resetsAt"),
            }
            for key, value in body["usage"].items()
            if isinstance(value, dict)
        ]
    windows = []
    for raw in raw_windows:
        if not isinstance(raw, dict):
            continue
        kind = str(raw.get("kind") or raw.get("type") or "").strip().lower()
        label = str(raw.get("label") or {
            "rolling-5h": "5 hours",
            "weekly": "Weekly",
            "monthly": "Monthly",
        }.get(kind, kind)).strip()
        if kind == "rolling":
            kind, label = "rolling-5h", "5 hours"
        if kind not in {"rolling-5h", "weekly", "monthly", "daily"}:
            kind = classify_window(label) or ""
        used = raw.get("usedPercent", raw.get("used_percent", raw.get("percent")))
        if (
            kind
            and isinstance(used, (int, float))
            and not isinstance(used, bool)
            and math.isfinite(float(used))
            and 0 <= float(used) <= 100
        ):
            windows.append(SimpleNamespace(
                label=label,
                used_percent=float(used),
                reset_at=parse_datetime(raw.get("resetAt", raw.get("reset_at", raw.get("resetsAt")))),
                detail=raw.get("detail"),
            ))
    if not windows:
        return None
    return SimpleNamespace(
        source="usage_api",
        fetched_at=utc_now(),
        plan=body.get("plan") if isinstance(body.get("plan"), str) else None,
        unavailable_reason=None,
        windows=tuple(windows),
    )


def manual_reset_unavailable(reason: str) -> dict[str, Any]:
    return {"status": "unavailable", "reason": reason}


def codex_manual_reset_payload(api: UsageAPI) -> dict[str, Any]:
    if not callable(api.resolve_codex_usage_credentials) or not callable(api.codex_backend_urls):
        return manual_reset_unavailable("manual reset source unavailable")
    try:
        token, base_url, account_id = api.resolve_codex_usage_credentials(None, None)
        usage_url, credits_url, _consume_url = api.codex_backend_urls(base_url)
        headers = {
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
            "User-Agent": "codex-cli",
        }
        if account_id:
            headers["ChatGPT-Account-Id"] = account_id
        with api.httpx.Client(timeout=TIMEOUT_SECONDS) as client:
            usage_response = client.get(usage_url, headers=headers)
            usage_response.raise_for_status()
            credits_response = client.get(credits_url, headers=headers)
            credits_response.raise_for_status()
        usage_payload = usage_response.json() or {}
        credits_payload = credits_response.json() or {}
    except Exception:
        return manual_reset_unavailable("manual reset provider unavailable")

    counts = usage_payload.get("rate_limit_reset_credits")
    credits = credits_payload.get("credits")
    if not isinstance(counts, dict) or not isinstance(credits, list):
        return manual_reset_unavailable("manual reset data malformed")
    available = counts.get("available_count")
    applicable = counts.get("applicable_available_count")
    if (
        not isinstance(available, int)
        or isinstance(available, bool)
        or not isinstance(applicable, int)
        or isinstance(applicable, bool)
        or available < 0
        or applicable < 0
        or applicable > available
    ):
        return manual_reset_unavailable("manual reset data malformed")

    mapped: list[dict[str, Any]] = []
    for credit in credits:
        if not isinstance(credit, dict):
            return manual_reset_unavailable("manual reset data malformed")
        identifier = credit.get("id")
        title = credit.get("title")
        status = credit.get("status")
        supported = credit.get("is_supported_by_plan")
        if (
            not isinstance(identifier, str)
            or not identifier.strip()
            or not isinstance(title, str)
            or not title.strip()
            or status not in {"available", "redeemed", "expired"}
            or not isinstance(supported, bool)
        ):
            return manual_reset_unavailable("manual reset data malformed")
        granted_at = parse_datetime(credit.get("granted_at"))
        expires_at = parse_datetime(credit.get("expires_at"))
        if credit.get("granted_at") is not None and granted_at is None:
            return manual_reset_unavailable("manual reset data malformed")
        if credit.get("expires_at") is not None and expires_at is None:
            return manual_reset_unavailable("manual reset data malformed")
        mapped.append({
            "id": identifier.strip(),
            "title": title.strip(),
            "status": status,
            "isSupportedByPlan": supported,
            "grantedAt": isoformat(granted_at) if granted_at else None,
            "expiresAt": isoformat(expires_at) if expires_at else None,
        })

    return {
        "status": "available",
        "capturedAt": isoformat(utc_now()),
        "availableCount": available,
        "applicableAvailableCount": applicable,
        "credits": mapped,
    }


def codex_redeem_payload(request_id: str, root: Path) -> dict[str, Any]:
    """Consume one banked Codex rate-limit reset credit (POST consume).

    Mirrors the official Hermes redeem flow: send a structured JSON body with a
    single fresh UUID idempotency key and no credit identifier; the backend
    selects the next available credit. Return a non-sensitive outcome payload.
    """
    try:
        api = load_usage_api(root)
    except BridgeError:
        return {"status": "unverified", "reason": "provider unavailable"}
    if not callable(api.resolve_codex_usage_credentials) or not callable(api.codex_backend_urls):
        return {"status": "unverified", "reason": "redemption source unavailable"}
    try:
        token, base_url, account_id = api.resolve_codex_usage_credentials(None, None)
        _usage_url, _credits_url, consume_url = api.codex_backend_urls(base_url)
        headers = {
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
            "User-Agent": "codex-cli",
            "Content-Type": "application/json",
        }
        if account_id:
            headers["ChatGPT-Account-Id"] = account_id
        with api.httpx.Client(timeout=TIMEOUT_SECONDS) as client:
            response = client.post(
                consume_url,
                headers=headers,
                json={"redeem_request_id": request_id},
            )
            response.raise_for_status()
            payload = response.json() or {}
    except Exception as error:
        if _is_http_rejection(api.httpx, error):
            return {"status": "rejected"}
        return {"status": "unverified", "reason": "redemption outcome unknown"}

    code = str(payload.get("code", "") or "").strip().lower()
    if code == "reset":
        return {"status": "reset"}
    if code == "already_redeemed":
        return {"status": "already_redeemed"}
    if code == "nothing_to_reset":
        return {"status": "nothing_to_reset"}
    if code == "no_credit":
        return {"status": "no_credit"}
    return {"status": "unverified", "reason": "redemption outcome unknown"}


def _is_http_rejection(httpx_module: Any, error: Exception) -> bool:
    http_error = getattr(httpx_module, "HTTPStatusError", None)
    if http_error is None:
        return False
    return isinstance(error, http_error)


def collect_provider(provider: str, subscription: str, api: UsageAPI) -> ProviderResult:
    manual_resets = (
        codex_manual_reset_payload(api)
        if provider == "openai-codex"
        else None
    )
    try:
        snapshot = opencode_snapshot(api) if provider == "opencode-go" else api.fetch_account_usage(provider)
    except Exception:
        result = unavailable(provider, subscription, "provider unavailable")
    else:
        result = snapshot_payload(provider, subscription, snapshot)
    if manual_resets is None:
        return result
    return ProviderResult(
        provider=result.provider,
        subscription=result.subscription,
        payload={**result.payload, "manualResets": manual_resets},
    )


def start_worker(provider: str, root: Path, popen: Callable[..., Any] = subprocess.Popen) -> Any:
    return popen(
        [
            sys.executable,
            str(Path(__file__).resolve()),
            "--worker",
            provider,
            "--json",
            "--hermes-root",
            str(root),
        ],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        env=os.environ.copy(),
    )


def await_worker(
    provider: str,
    subscription: str,
    worker: Any,
    deadline: float,
) -> ProviderResult:
    try:
        stdout, _stderr = worker.communicate(timeout=max(0.0, deadline - time.monotonic()))
    except subprocess.TimeoutExpired:
        worker.kill()
        worker.communicate()
        return unavailable(provider, subscription, "provider timed out")
    if worker.returncode != 0:
        return unavailable(provider, subscription, "provider worker failed")
    try:
        payload = json.loads(stdout)
    except (TypeError, json.JSONDecodeError):
        return unavailable(provider, subscription, "provider returned malformed data")
    if not isinstance(payload, dict):
        return unavailable(provider, subscription, "provider returned malformed data")
    return ProviderResult(provider, subscription, payload)


def run_worker(
    provider: str,
    subscription: str,
    root: Path,
    deadline: float,
    popen: Callable[..., Any] = subprocess.Popen,
) -> ProviderResult:
    try:
        worker = start_worker(provider, root, popen)
    except OSError:
        return unavailable(provider, subscription, "provider worker failed")
    return await_worker(provider, subscription, worker, deadline)


def collect(root: Path) -> dict[str, Any]:
    load_usage_api(root)
    results: list[ProviderResult] = []
    deadline = time.monotonic() + TIMEOUT_SECONDS
    workers: list[tuple[str, str, Any]] = []
    try:
        for provider, subscription in PROVIDERS:
            try:
                worker = start_worker(provider, root)
                workers.append((provider, subscription, worker))
                _ACTIVE_WORKERS.append(worker)
            except OSError:
                results.append(unavailable(provider, subscription, "provider worker failed"))
        for provider, subscription, worker in workers:
            results.append(await_worker(provider, subscription, worker, deadline))
    finally:
        for _provider, _subscription, worker in workers:
            if worker in _ACTIVE_WORKERS:
                _ACTIVE_WORKERS.remove(worker)
            if worker.poll() is None:
                worker.kill()
                worker.communicate()
    results.sort(key=lambda result: next(index for index, item in enumerate(PROVIDERS) if item[0] == result.provider))
    return {
        "generatedAt": isoformat(utc_now()),
        "providers": {result.provider: result.payload for result in results},
    }


def terminate_workers(_signum: int, _frame: Any) -> None:
    for worker in list(_ACTIVE_WORKERS):
        if worker.poll() is None:
            worker.kill()
    raise SystemExit(143)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("--json", action="store_true", help="emit the JSON contract")
    parser.add_argument("--redeem", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--request-id", help=argparse.SUPPRESS)
    parser.add_argument("--worker", choices=[provider for provider, _ in PROVIDERS], help=argparse.SUPPRESS)
    parser.add_argument("--hermes-root", help=argparse.SUPPRESS)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.redeem:
        if not args.request_id or not args.request_id.strip():
            print("redeem requires --request-id", file=sys.stderr)
            return 2
        try:
            root = resolve_hermes_root(args.hermes_root)
        except BridgeError as error:
            print(str(error), file=sys.stderr)
            return 4
        payload = codex_redeem_payload(args.request_id.strip(), root)
        print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
        return 0
    if not args.json:
        print("usage: hermes-usage-bridge --json", file=sys.stderr)
        return 2
    signal.signal(signal.SIGTERM, terminate_workers)
    signal.signal(signal.SIGINT, terminate_workers)
    try:
        root = resolve_hermes_root(args.hermes_root)
        if args.worker:
            api = load_usage_api(root)
            provider, subscription = next(item for item in PROVIDERS if item[0] == args.worker)
            result = collect_provider(provider, subscription, api)
            print(json.dumps(result.payload, ensure_ascii=False, separators=(",", ":")))
            return 0
        payload = collect(root)
    except concurrent.futures.TimeoutError:
        print("Hermes usage bridge timed out", file=sys.stderr)
        return 3
    except BridgeError as error:
        print(str(error), file=sys.stderr)
        return 4
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
