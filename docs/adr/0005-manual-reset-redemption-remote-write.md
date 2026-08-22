# ADR-0005: Single remote-write exception for manual reset redemption

- Status: Accepted
- Date: 2026-08-23

## Context

HermesUsageMonitor is otherwise read-only with respect to provider quota data and Hermes state. `Riscatta` in the `Reset manuale` section is the app's only remote write: it consumes one banked ChatGPT/Codex Full reset credit through the provider's `consume` endpoint. Redeeming is scarce, provider-owned, and not a quota-window reset.

This slice implements the redeem action that issue #35 specifies. The provider consumes one credit for the account and, unlike what an earlier version of the ticket assumed, does not accept a credit identifier: the POST body carries only a fresh UUID idempotency key (`redeem_request_id`), and the backend selects the credit. The app therefore replicates the provider's no-force exhaustion guard instead of sending a credit id.

## Decision

Redemption is permitted only when a ChatGPT/Codex quota window is fully used (100%) and the manual reset state is live, applicable, available, plan-supported, unexpired, and complete. There is no force path.

A redemption is one structured consume request carrying a single fresh UUID idempotency key and no credit identifier. The Service owns one key per confirmed user action and reuses it for any retry of that unresolved attempt. Repeated clicks while a redemption is in flight cannot start another provider write.

Outcomes map explicitly. `reset` and `already_redeemed` are confirmed or idempotent successes that trigger an immediate combined live refresh and suppress the generic quota-reset notification for that observation. `nothing_to_reset` and `no_credit` never consume a credit and surface a safe dialog. Rejection and ambiguous outcomes are distinguished: an ambiguous outcome (timeout after send, lost or malformed response, unverifiable result) enters verification-required state, which blocks further redemption until a coherent live refresh rebuilds provider state.

To avoid the verification block producing duplicate information, the redemption-triggered refresh is tagged so `QuotaResetNotificationService` suppresses the generic quota-reset notification for that single observation; ordinary manual and automatic refresh notification behavior is unchanged.

## Consequences

- The app's read-only contract now has exactly one documented write: a user-confirmed, exact single-credit redemption.
- No credit identifier, account id, idempotency key, credential, or raw provider body is exposed in UI, logs, dialogs, notifications, or summaries.
- A redemption can only start when a quota window is exhausted, so it never fails for the provider's own not-exhausted guard.
- The verification-required block is the safety mechanism that prevents a lost response from consuming two credits.
- The ADR records the exception so future work does not add new remote writes without a separate decision.