#!/usr/bin/env python3
import importlib.util
import json
import subprocess
import sys
import tempfile
import textwrap
import unittest
from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace

SCRIPT = Path(__file__).parents[1] / "scripts" / "hermes_usage_bridge.py"
spec = importlib.util.spec_from_file_location("hermes_usage_bridge", SCRIPT)
assert spec is not None and spec.loader is not None
bridge = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = bridge
spec.loader.exec_module(bridge)


class HermesUsageBridgeTests(unittest.TestCase):
    def test_builds_quota_payload_for_supported_windows(self):
        snapshot = SimpleNamespace(
            source="usage_api",
            fetched_at=datetime(2030, 3, 17, 12, 0, tzinfo=timezone.utc),
            plan="Plus",
            unavailable_reason=None,
            windows=(
                SimpleNamespace(
                    label="Session", used_percent=40.0,
                    reset_at=datetime(2030, 3, 17, 17, 0, tzinfo=timezone.utc), detail=None,
                ),
                SimpleNamespace(
                    label="Weekly", used_percent=55.0, reset_at=None, detail="provider detail",
                ),
            ),
        )
        result = bridge.snapshot_payload("openai-codex", "chatgpt", snapshot)
        self.assertEqual(result.payload["status"], "available")
        self.assertEqual(result.payload["subscription"], "chatgpt")
        self.assertEqual(result.payload["windows"][0]["kind"], "rolling-5h")
        self.assertEqual(result.payload["windows"][0]["usedPercent"], 40.0)
        self.assertEqual(result.payload["windows"][1]["kind"], "weekly")

    def test_manual_reset_contract_through_worker_process(self):
        positive = self.run_openai_worker([
            {
                "id": "credit-later",
                "title": "Full reset",
                "status": "available",
                "is_supported_by_plan": True,
                "granted_at": "2030-03-01T00:00:00Z",
                "expires_at": "2030-03-20T00:00:00Z",
            },
            {
                "id": "credit-sooner",
                "title": "Full reset",
                "status": "available",
                "is_supported_by_plan": True,
                "granted_at": None,
                "expires_at": None,
            },
        ])
        self.assertEqual(positive["status"], "available")
        self.assertEqual(positive["manualResets"]["availableCount"], 2)
        self.assertEqual(positive["manualResets"]["applicableAvailableCount"], 1)
        self.assertEqual(positive["manualResets"]["credits"][0]["id"], "credit-later")

        malformed = self.run_openai_worker([
            {
                "id": "credit-bad-date",
                "title": "Full reset",
                "status": "available",
                "is_supported_by_plan": True,
                "granted_at": None,
                "expires_at": float("nan"),
            },
        ], available_count=1)
        self.assertEqual(malformed["manualResets"], {
            "status": "unavailable",
            "reason": "manual reset data malformed",
        })

        older_hermes = self.run_openai_worker([], include_reset_helpers=False)
        self.assertEqual(older_hermes["status"], "available")
        self.assertEqual(older_hermes["manualResets"], {
            "status": "unavailable",
            "reason": "manual reset source unavailable",
        })

    def test_direct_opencode_payload_supports_usage_shape(self):
        class Response:
            def raise_for_status(self):
                pass

            def json(self):
                return {"usage": {
                    "rolling": {"percent": 12.5, "resetsAt": "2030-03-17T17:00:00Z"},
                    "weekly": {"percent": 45.0, "resetsAt": "2030-03-24T00:00:00Z"},
                }}

        class Client:
            def __init__(self, **_kwargs):
                pass

            def __enter__(self):
                return self

            def __exit__(self, *_args):
                pass

            def get(self, *_args, **_kwargs):
                return Response()

        api = bridge.UsageAPI(
            fetch_account_usage=lambda _provider: None,
            resolve_runtime_provider=lambda **_kwargs: {"api_key": "[REDACTED]", "base_url": "https://example.invalid"},
            httpx=SimpleNamespace(Client=Client),
        )
        snapshot = bridge.opencode_snapshot(api)
        result = bridge.snapshot_payload("opencode-go", "opencode-go", snapshot)
        self.assertEqual(result.payload["windows"][0]["kind"], "rolling-5h")
        self.assertEqual(result.payload["windows"][0]["usedPercent"], 12.5)

    def test_unknown_window_becomes_unavailable(self):
        snapshot = SimpleNamespace(
            source="usage_api", fetched_at=datetime(2030, 3, 17, 12, 0, tzinfo=timezone.utc),
            plan=None, unavailable_reason=None,
            windows=(SimpleNamespace(label="Yearly", used_percent=1.0, reset_at=None, detail=None),),
        )
        result = bridge.snapshot_payload("opencode-go", "opencode-go", snapshot)
        self.assertEqual(result.payload["status"], "unavailable")
        self.assertEqual(result.payload["reason"], "quota unavailable")

    def test_unknown_window_or_invalid_percentage_becomes_unavailable(self):
        snapshot = SimpleNamespace(
            source="usage_api", fetched_at=datetime(2030, 3, 17, 12, 0, tzinfo=timezone.utc),
            plan=None, unavailable_reason=None,
            windows=(SimpleNamespace(label="Weekly", used_percent=101.0, reset_at=None, detail=None),),
        )
        result = bridge.snapshot_payload("opencode-go", "opencode-go", snapshot)
        self.assertEqual(result.payload["status"], "unavailable")
        self.assertEqual(result.payload["reason"], "quota unavailable")

    def test_provider_failure_is_sanitized(self):
        def fail(_provider):
            raise RuntimeError("secret-token must not escape")

        result = bridge.collect_provider("openai-codex", "chatgpt", bridge.UsageAPI(
            fetch_account_usage=fail,
            resolve_runtime_provider=lambda **_kwargs: {},
            httpx=None,
        ))
        self.assertEqual(result.payload, {
            "status": "unavailable",
            "subscription": "chatgpt",
            "reason": "provider unavailable",
            "manualResets": {
                "status": "unavailable",
                "reason": "manual reset source unavailable",
            },
        })

    def test_worker_json_and_timeout_are_isolated(self):
        class Worker:
            def __init__(self, output, timed_out=False):
                self.output = output
                self.timed_out = timed_out
                self.returncode = 0
                self.killed = False

            def communicate(self, **_kwargs):
                if self.timed_out and not self.killed:
                    raise bridge.subprocess.TimeoutExpired("worker", 15)
                return self.output, ""

            def kill(self):
                self.killed = True

        valid = bridge.run_worker(
            "openai-codex", "chatgpt", Path("/tmp/hermes"), float("inf"),
            lambda *_args, **_kwargs: Worker('{"status":"available"}'),
        )
        timed_out = bridge.run_worker(
            "opencode-go", "opencode-go", Path("/tmp/hermes"), float("inf"),
            lambda *_args, **_kwargs: Worker("", timed_out=True),
        )
        self.assertEqual(valid.payload["status"], "available")
        self.assertEqual(timed_out.payload["reason"], "provider timed out")

    def test_malformed_worker_json_is_unavailable(self):
        class Worker:
            returncode = 0

            def communicate(self, **_kwargs):
                return "not-json", ""

        result = bridge.run_worker(
            "openai-codex", "chatgpt", Path("/tmp/hermes"), float("inf"),
            lambda *_args, **_kwargs: Worker(),
        )
        self.assertEqual(result.payload["reason"], "provider returned malformed data")

    def run_openai_worker(
        self,
        credits,
        available_count=2,
        applicable_count=1,
        include_reset_helpers=True,
    ):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "agent").mkdir()
            (root / "hermes_cli").mkdir()
            (root / "agent" / "__init__.py").write_text("")
            (root / "hermes_cli" / "__init__.py").write_text("")
            helpers = """
            def _resolve_codex_usage_credentials(*_args):
                return ("test-token", "https://example.invalid", "test-account")

            def _codex_backend_urls(_base):
                return ("usage", "credits", "consume")
            """ if include_reset_helpers else ""
            account_usage_source = textwrap.dedent("""
                from datetime import datetime, timezone
                from types import SimpleNamespace

                def fetch_account_usage(_provider):
                    return SimpleNamespace(
                        source="usage_api",
                        fetched_at=datetime(2030, 3, 17, 12, 0, tzinfo=timezone.utc),
                        plan="Plus",
                        unavailable_reason=None,
                        windows=(SimpleNamespace(
                            label="Session",
                            used_percent=40.0,
                            reset_at=None,
                            detail=None,
                        ),),
                    )
            """)
            (root / "agent" / "account_usage.py").write_text(
                account_usage_source + "\n" + textwrap.dedent(helpers)
            )
            (root / "hermes_cli" / "runtime_provider.py").write_text(textwrap.dedent("""
                def resolve_runtime_provider(**_kwargs):
                    return {}
            """))
            (root / "httpx.py").write_text(textwrap.dedent(f"""
                nan = float("nan")
                CREDITS = {credits!r}

                class Response:
                    def __init__(self, payload):
                        self.payload = payload

                    def raise_for_status(self):
                        pass

                    def json(self):
                        return self.payload

                class Client:
                    def __init__(self, **_kwargs):
                        pass

                    def __enter__(self):
                        return self

                    def __exit__(self, *_args):
                        pass

                    def get(self, url, **_kwargs):
                        if url == "usage":
                            return Response({{
                                "rate_limit_reset_credits": {{
                                    "available_count": {available_count},
                                    "applicable_available_count": {applicable_count},
                                }}
                            }})
                        return Response({{"credits": CREDITS}})
            """))
            completed = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--worker",
                    "openai-codex",
                    "--json",
                    "--hermes-root",
                    str(root),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            return json.loads(completed.stdout)

    def test_missing_capability_is_fatal(self):
        original_import = bridge.importlib.import_module
        bridge.importlib.import_module = lambda _name: SimpleNamespace(fetch_account_usage=None)
        try:
            with self.assertRaises(bridge.BridgeError):
                bridge.load_usage_api(Path("/tmp/hermes-usage-bridge-test"))
        finally:
            bridge.importlib.import_module = original_import


if __name__ == "__main__":
    unittest.main()
