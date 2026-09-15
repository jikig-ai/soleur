---
title: "Codex web-engine qualification record"
date: 2026-09-14
status: synthetic-only
engine: codex
---

# Codex qualification record

This record separates deterministic implementation evidence from the approvals
required before customer repository content can leave Soleur. The reviewed
registry keeps Codex disabled for new and existing runs until the pending rows
below are completed. No provider credential, prompt, repository content, or
remote response is stored in this record.

## Auth-mode matrix

| Auth mode | Credential boundary | Synthetic evidence | Customer-content status | Vendor/CLO disposition |
|---|---|---|---|---|
| API key | Mode-stable server-side lease; browser tokens rejected | `test/codex-code-adapter.test.ts` auth, refresh, logout, sanitization, replay, egress, usage, and cancellation cases | Disabled | Pending provider DPA, transfer geography, retention/deletion evidence, and CLO review |
| Managed ChatGPT sign-in | Mode-stable server-side lease; refresh and logout remain server-side | Same deterministic adapter boundary tests with `managed` mode fixtures | Disabled | Pending subscription data-control terms, transfer geography, retention/deletion evidence, and CLO review |

## Qualification matrix

| Workflow / control | Evidence | Result |
|---|---|---|
| Credential isolation and mode stability | `test/codex-code-adapter.test.ts` | PASS for synthetic fixtures |
| One-shot authorization recovery | `test/codex-code-adapter.test.ts` | PASS for synthetic fixtures |
| Provider-error sanitization | `test/codex-code-adapter.test.ts` | PASS; generic message and stable code |
| Event run binding and positive sequencing | `test/codex-code-adapter.test.ts` | PASS for synthetic fixtures |
| HTTPS exact-host egress | `test/codex-code-adapter.test.ts`, `test/agent-engine-data-egress-policy.test.ts` | PASS for synthetic fixtures |
| DPA, geography, approval, and deletion evidence gate | `test/agent-engine-data-egress-policy.test.ts` | PASS; missing evidence fails closed |
| Persisted engine binding and no alternate adapter | `test/agent-engine-dispatch.test.ts` | PASS for synthetic fixtures |
| Lifecycle telemetry without payload or credential fields | `test/agent-engine-observability.test.ts`, `test/agent-engine-dispatch.test.ts` | PASS for synthetic fixtures |
| Restart/reconcile, cancellation, attachment handling, and live provider usage | No live provider qualification run yet | PENDING |

## Release decision

The only permitted use of the Codex adapter in this phase is internal,
synthetic or explicitly redacted dogfooding under the identity-aware,
default-off `codex-engine` runtime flag. Customer content remains blocked until
both auth modes have:

1. a reviewed vendor/DPA and transfer-geography record;
2. verified retention and remote-erasure behavior (or an approved restriction
   to synthetic data); and
3. a CLO disposition covering the auth-mode-specific billing and data-control
   profile.

Grok Build, Devin, and later engines must provide their own record using this
same distinction between synthetic qualification and customer enablement.
