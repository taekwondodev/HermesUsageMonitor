# ADR-0008: Validate provider window identity at the quota boundary

- Status: Accepted
- Date: 2026-08-25

## Context

ChatGPT can add quota windows without first exposing a commercial name known by HermesUsageMonitor. The app must preserve those observations, while OpenCode Go keeps its existing closed set of supported windows. Window kind and label are provider-controlled input and cross the bridge into the Swift domain, UI, refresh scheduler, and reset notifications.

## Decision

The bundled bridge uses the provider technical kind as the primary identity. When ChatGPT does not provide one, it uses a normalized label as the documented fallback. Labels are trimmed, limited to 200 characters, and reject control characters before entering the contract. ChatGPT duplicate candidate identities receive a provider-order occurrence suffix so observations remain separate. Unknown kinds are accepted only for ChatGPT live observations. File-based snapshots reject unknown kinds for other subscriptions.

The domain represents an accepted opaque kind as a typed `QuotaWindowKind.opaque` value. OpenCode Go display ordering handles an unexpected opaque value without terminating the process, even though its repository boundary rejects it. No credentials, authorization contents, or provider raw error data cross the bridge output boundary.

## Threat model

- Trust boundary: Hermes/provider output enters the bundled Python bridge, then the Swift command reader and domain.
- Assets: process availability, quota lifecycle identity, notification correctness, and provider-sensitive data.
- Spoofing: a provider label cannot replace a supplied technical kind.
- Tampering and repudiation: stable kind identity and occurrence disambiguation preserve refresh/reset matching as observations move through the app.
- Information disclosure: labels are bounded and control characters are rejected; the bridge continues to emit sanitized outcomes only.
- Denial of service: malformed or unsupported non-ChatGPT kinds become unavailable data, and ordering never uses a terminating precondition for external values.
- Elevation of privilege: the feature adds no write capability, authentication path, or permission.

## Consequences

Future ChatGPT windows remain visible and operational without a provider-specific hardcoded name. OpenCode Go behavior remains unchanged for valid payloads and fails safely for unsupported external data. Identity occurrence is tied to provider order, so a provider that reorders duplicate windows may produce a new observation identity rather than silently merging limits.
