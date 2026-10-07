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
    def test_tracks_chatgpt_and_claude(self):
        self.assertEqual(bridge.PROVIDERS, (("openai-codex", "chatgpt"), ("anthropic", "claude")))

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
        self.assertEqual(result.payload["windows"][0]["label"], "5 hours")
        self.assertEqual(result.payload["windows"][0]["usedPercent"], 40.0)
        self.assertEqual(result.payload["windows"][1]["kind"], "weekly")

    def test_worker_preserves_unknown_chatgpt_windows_and_disambiguates_duplicates(self):
        result = self.run_openai_worker([])

        self.assertEqual(
            [(window["kind"], window["label"]) for window in result["windows"]],
            [
                ("rolling-5h", "5 hours"),
                ("rolling-7d", "Weekly"),
                ("rolling-7d#2", "Longer window copy"),
                ("rolling-7d#2#2", "Collision kind"),
                ("experimental", "Experimental"),
            ],
        )

    def test_worker_preserves_unknown_technical_kind_verbatim(self):
        result = bridge.snapshot_payload(
            "openai-codex",
            "chatgpt",
            SimpleNamespace(
                source="usage_api",
                fetched_at=datetime(2030, 3, 17, 12, 0, tzinfo=timezone.utc),
                plan=None,
                unavailable_reason=None,
                windows=(SimpleNamespace(
                    kind="FutureWindow",
                    label="Future window",
                    used_percent=10.0,
                    reset_at=None,
                    detail=None,
                ),),
            ),
        )
        self.assertEqual(result.payload["windows"][0]["kind"], "FutureWindow")

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

    def test_chatgpt_technical_kind_precedes_conflicting_label(self):
        snapshot = SimpleNamespace(
            source="usage_api",
            fetched_at=datetime(2030, 3, 17, 12, 0, tzinfo=timezone.utc),
            plan=None,
            unavailable_reason=None,
            windows=(SimpleNamespace(
                kind="rolling-5h",
                label="Weekly",
                used_percent=12.5,
                reset_at=None,
                detail=None,
            ),),
        )
        result = bridge.snapshot_payload("openai-codex", "chatgpt", snapshot)
        self.assertEqual(result.payload["windows"][0]["kind"], "rolling-5h")

    def test_invalid_percentage_becomes_unavailable(self):
        snapshot = SimpleNamespace(
            source="usage_api", fetched_at=datetime(2030, 3, 17, 12, 0, tzinfo=timezone.utc),
            plan=None, unavailable_reason=None,
            windows=(SimpleNamespace(label="Weekly", used_percent=101.0, reset_at=None, detail=None),),
        )
        result = bridge.snapshot_payload("openai-codex", "chatgpt", snapshot)
        self.assertEqual(result.payload["status"], "unavailable")
        self.assertEqual(result.payload["reason"], "quota unavailable")

    def test_empty_technical_kind_does_not_fall_back_to_label(self):
        snapshot = SimpleNamespace(
            source="usage_api",
            fetched_at=datetime(2030, 3, 17, 12, 0, tzinfo=timezone.utc),
            plan=None,
            unavailable_reason=None,
            windows=(SimpleNamespace(
                kind="",
                label="Weekly",
                used_percent=10.0,
                reset_at=None,
                detail=None,
            ),),
        )
        result = bridge.snapshot_payload("openai-codex", "chatgpt", snapshot)
        self.assertEqual(result.payload["status"], "unavailable")

    def test_provider_failure_is_sanitized(self):
        def fail(_provider):
            raise RuntimeError("secret-token must not escape")

        result = bridge.collect_provider("openai-codex", "chatgpt", bridge.UsageAPI(
            fetch_account_usage=fail,
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
            "openai-codex", "chatgpt", Path("/tmp/hermes"), float("inf"),
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

    def test_redeem_maps_provider_outcomes(self):
        for code, expected in {
            "reset": "reset",
            "already_redeemed": "already_redeemed",
            "nothing_to_reset": "nothing_to_reset",
            "no_credit": "no_credit",
            "mystery": "unverified",
        }.items():
            with tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                (root / "agent").mkdir()
                (root / "agent" / "__init__.py").write_text("")
                (root / "agent" / "account_usage.py").write_text(textwrap.dedent("""
                    def fetch_account_usage(_provider):
                        return None

                    def _resolve_codex_usage_credentials(*_args):
                        return ("test-token", "https://example.invalid", "test-account")

                    def _codex_backend_urls(_base):
                        return ("usage", "credits", "consume")
                """))
                (root / "httpx.py").write_text(textwrap.dedent("""
                    CODE = {"code": __CODE__}

                    class Response:
                        def raise_for_status(self):
                            pass

                        def json(self):
                            return CODE

                    class Client:
                        def __init__(self, **_kwargs):
                            pass

                        def __enter__(self):
                            return self

                        def __exit__(self, *_args):
                            pass

                        def post(self, _url, **_kwargs):
                            return Response()
                """).replace("__CODE__", json.dumps(code)))
                completed = subprocess.run(
                    [
                        sys.executable,
                        str(SCRIPT),
                        "--redeem",
                        "--request-id",
                        "00000000-0000-0000-0000-000000000000",
                        "--hermes-root",
                        str(root),
                    ],
                    check=False,
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(completed.returncode, 0, completed.stderr)
                payload = json.loads(completed.stdout)
                self.assertEqual(payload["status"], expected)

    def test_redeem_requires_request_id(self):
        completed = subprocess.run(
            [sys.executable, str(SCRIPT), "--redeem"],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 2)

    def test_redeem_maps_http_status_error_to_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "agent").mkdir()
            (root / "agent" / "__init__.py").write_text("")
            (root / "agent" / "account_usage.py").write_text(textwrap.dedent("""
                def fetch_account_usage(_provider):
                    return None

                def _resolve_codex_usage_credentials(*_args):
                    return ("test-token", "https://example.invalid", "test-account")

                def _codex_backend_urls(_base):
                    return ("usage", "credits", "consume")
            """))
            (root / "httpx.py").write_text(textwrap.dedent("""
                class HTTPStatusError(Exception):
                    pass

                class Response:
                    def json(self):
                        return {}

                class Client:
                    def __init__(self, **_kwargs):
                        pass

                    def __enter__(self):
                        return self

                    def __exit__(self, *_args):
                        pass

                    def post(self, _url, **_kwargs):
                        raise HTTPStatusError("401")
            """))
            completed = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--redeem",
                    "--request-id",
                    "00000000-0000-0000-0000-000000000000",
                    "--hermes-root",
                    str(root),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            payload = json.loads(completed.stdout)
            self.assertEqual(payload["status"], "rejected")

    def test_anthropic_structured_limits_keep_fable_identity_and_percentages(self):
        snapshot = bridge._anthropic_snapshot({"limits": [
            {"kind": "session", "group": "session", "percent": 100, "resets_at": "2030-03-17T17:00:00Z"},
            {"kind": "weekly_all", "group": "weekly", "percent": 0.5, "resets_at": None},
            {"kind": "weekly_scoped", "group": "weekly", "percent": 74, "is_active": False,
             "scope": {"model": {"id": None, "display_name": "Fable"}},
             "resets_at": "2030-03-20T12:00:00Z"},
            {"kind": "weekly_scoped", "group": "weekly", "percent": 99,
             "scope": {"model": {"display_name": "Opus"}}},
        ]})
        result = bridge.snapshot_payload("anthropic", "claude", snapshot)
        self.assertEqual(result.payload["status"], "available")
        self.assertEqual(
            [(w["kind"], w["label"], w["usedPercent"]) for w in result.payload["windows"]],
            [("rolling-5h", "5 hours", 100.0), ("weekly", "Weekly", 0.5),
             ("fable-weekly", "Fable", 74.0)],
        )
        self.assertEqual(result.payload["windows"][1]["resetAt"], None)
        self.assertEqual(result.payload["windows"][2]["resetAt"], "2030-03-20T12:00:00Z")

    def test_anthropic_flat_fallback_only_when_structured_limits_absent(self):
        fallback = bridge._anthropic_snapshot({
            "five_hour": {"utilization": 0.5, "resets_at": None},
            "seven_day": {"utilization": 66, "resets_at": "2030-03-20T12:00:00Z"},
            "iguana_necktie": {"utilization": 99},
        })
        result = bridge.snapshot_payload("anthropic", "claude", fallback)
        self.assertEqual([w["kind"] for w in result.payload["windows"]], ["rolling-5h", "weekly"])
        self.assertEqual(result.payload["windows"][0]["usedPercent"], 0.5)
        self.assertEqual(result.payload["windows"][0]["resetAt"], None)
        no_fable = bridge._anthropic_snapshot({"limits": [
            {"kind": "session", "group": "session", "percent": 1},
            {"kind": "weekly_all", "group": "weekly", "percent": 2},
        ]})
        self.assertEqual([w["kind"] for w in bridge.snapshot_payload("anthropic", "claude", no_fable).payload["windows"]],
                         ["rolling-5h", "weekly"])
        self.assertEqual(bridge._anthropic_snapshot({"limits": [], "five_hour": {"utilization": 5}}).windows, ())

    def test_anthropic_malformed_input_is_sanitized_and_duplicates_rejected(self):
        for payload in (
            [], {"limits": {}}, {"limits": [{"kind": "session", "group": "session", "percent": float("nan")}]},
            {"limits": [{"kind": "session", "group": "session", "percent": 101}]},
            {"limits": [{"kind": "session", "group": "session", "percent": 1, "resets_at": "not-a-date"}]},
            {"limits": [{"kind": "session", "group": "session", "percent": 1}, {"kind": "session", "group": "session", "percent": 2}]},
        ):
            with self.subTest(payload=payload):
                try:
                    snapshot = bridge._anthropic_snapshot(payload)
                except ValueError:
                    continue
                result = bridge.snapshot_payload("anthropic", "claude", snapshot)
                self.assertEqual(result.payload["status"], "unavailable")
                self.assertNotIn("not-a-date", json.dumps(result.payload))

    def test_anthropic_worker_uses_existing_oauth_only_and_is_read_only(self):
        available = self.run_anthropic_worker(
            [{"auth_type": "oauth", "access_token": "oauth-test-token-live", "expires_at": 4102444800}],
            {"limits": [
                {"kind": "session", "group": "session", "percent": 5},
                {"kind": "weekly_all", "group": "weekly", "percent": 66},
                {"kind": "weekly_scoped", "group": "weekly", "percent": 74,
                 "scope": {"model": {"display_name": "Fable"}}},
            ]},
        )
        self.assertEqual(available["status"], "available")
        self.assertEqual([w["kind"] for w in available["windows"]],
                         ["rolling-5h", "weekly", "fable-weekly"])
        expired = self.run_anthropic_worker(
            [{"auth_type": "oauth", "access_token": "oauth-test-token-expired", "expires_at": 1}],
            {"limits": []},
        )
        non_oauth = self.run_anthropic_worker(
            [{"auth_type": "api_key", "access_token": "api-key-test-value"}], {"limits": []},
        )
        missing = self.run_anthropic_worker([], {"limits": []})
        corrupt = self.run_anthropic_worker([], {"limits": []}, corrupt_store=True)
        for result in (expired, non_oauth, missing, corrupt):
            self.assertEqual(result["status"], "unavailable")
            self.assertEqual(result["reason"], "OAuth credentials unavailable")

    def test_anthropic_worker_network_failure_is_safe_and_provider_isolated(self):
        failed = self.run_anthropic_worker(
            [{"auth_type": "oauth", "access_token": "oauth-test-token-live", "expires_at": 4102444800}],
            {"secret": "raw-body-must-not-escape"}, fail=True,
        )
        self.assertEqual(failed, {
            "status": "unavailable", "subscription": "claude", "reason": "provider unavailable",
        })
        chatgpt = bridge.collect_provider("openai-codex", "chatgpt", bridge.UsageAPI(
            fetch_account_usage=lambda _provider: None, httpx=None,
        ))
        self.assertEqual(chatgpt.payload["subscription"], "chatgpt")

    def run_anthropic_worker(self, entries, response_payload, fail=False, corrupt_store=False):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "agent").mkdir()
            (root / "agent" / "__init__.py").write_text("")
            (root / "agent" / "account_usage.py").write_text("def fetch_account_usage(_provider): return None\n")
            (root / "agent" / "anthropic_credentials.py").write_text(textwrap.dedent("""
                def _is_oauth_token(value):
                    return isinstance(value, str) and value.startswith("oauth-test-token-")
                def _first_env(*_names): return None
                def is_claude_code_token_valid(_record): return False
                def resolve_anthropic_token(*_args, **_kwargs): raise AssertionError("resolver must not run")
                def read_hermes_oauth_credentials(): return None
                def read_claude_code_credentials(): return None
            """))
            (root / "hermes_cli").mkdir()
            (root / "hermes_cli" / "__init__.py").write_text("")
            auth_path = root / "auth.json"
            auth_content = "not-json" if corrupt_store else json.dumps({"credential_pool": {"anthropic": entries}})
            auth_path.write_text(auth_content)
            (root / "hermes_cli" / "auth.py").write_text(
                "from pathlib import Path\n"
                "def _auth_file_path(): return Path(__file__).parents[1] / 'auth.json'\n"
                "def _global_auth_file_path(): return None\n"
                "def read_credential_pool(*_args): raise AssertionError('write-capable loader forbidden')\n"
                "def _save_auth_store(*_args, **_kwargs): raise AssertionError('writes forbidden')\n"
            )
            (root / "httpx.py").write_text(textwrap.dedent(f"""
                PAYLOAD = {response_payload!r}
                class Response:
                    def raise_for_status(self):
                        {"raise RuntimeError('secret-token raw-body-must-not-escape')" if fail else "pass"}
                    def json(self): return PAYLOAD
                class Client:
                    def __init__(self, **_kwargs): pass
                    def __enter__(self): return self
                    def __exit__(self, *_args): pass
                    def get(self, _url, **_kwargs): return Response()
            """))
            completed = subprocess.run(
                [sys.executable, str(SCRIPT), "--worker", "anthropic", "--json", "--hermes-root", str(root)],
                check=False, capture_output=True, text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertNotIn("secret-token", completed.stdout)
            self.assertNotIn("oauth-test-token-", completed.stdout)
            self.assertEqual(auth_path.read_text(), auth_content)
            self.assertFalse((root / "auth.json.corrupt").exists())
            self.assertFalse((root / "auth.lock").exists())
            return json.loads(completed.stdout)

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
            (root / "agent" / "__init__.py").write_text("")
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
                        windows=(
                            SimpleNamespace(
                                label="Session",
                                used_percent=40.0,
                                reset_at=None,
                                detail=None,
                            ),
                            SimpleNamespace(
                                kind="rolling-7d",
                                label="Weekly",
                                used_percent=25.0,
                                reset_at=None,
                                detail=None,
                            ),
                            SimpleNamespace(
                                kind="rolling-7d",
                                label="Longer window copy",
                                used_percent=20.0,
                                reset_at=None,
                                detail=None,
                            ),
                            SimpleNamespace(
                                kind="rolling-7d#2",
                                label="Collision kind",
                                used_percent=15.0,
                                reset_at=None,
                                detail=None,
                            ),
                            SimpleNamespace(
                                label="Experimental",
                                used_percent=10.0,
                                reset_at=None,
                                detail=None,
                            ),
                        ),
                    )
            """)
            (root / "agent" / "account_usage.py").write_text(
                account_usage_source + "\n" + textwrap.dedent(helpers)
            )
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
