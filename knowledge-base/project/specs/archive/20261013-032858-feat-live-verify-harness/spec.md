---
feature: live-verify-harness
issue: 5452
branch: feat-live-verify-harness
pr: 5453
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
created: 2026-06-17
---

# Feature: Autonomous post-deploy live-verification harness + fail-closed postmerge gate

## Problem Statement

Fixes ship green and reach the non-technical operator still broken. One rail bug got three
fixes (#5391 → #5421 → #5436), each passing unit tests AND multi-agent review, none working in
production. The existing Playwright e2e suite drives `localhost` + **mock Supabase**, which
**structurally cannot** reproduce the realtime / server-commit-timing class (mock-supabase
returns HTTP 200 on `/realtime/*` instead of upgrading the WebSocket). The bug was found only by
a headless-browser harness driving the **deployed** app with a **real session** (#5449, #5451).
`/soleur:postmerge` Phase 5 browser verification exists but skips-with-warning when Playwright
MCP is unavailable — the punt that let the broken fixes pass.

## Goals

- Verify the **deployed artifact** (not the model) for the PR classes where mock tests lie.
- A committed, reusable harness with **no operator-OTP and no MCP-browser dependency**.
- Make post-deploy live verification a **fail-closed gate** that cannot be silently skipped.

## Non-Goals

- Replacing the mock-hermetic e2e suite (it stays fast + CI-blocking for the model layer).
- Plan-time executable acceptance-criteria deliverable — **deferred** (fast-follow issue).
- Fix-PR "must reference a live repro" guard — **deferred** (fast-follow issue).
- Verifying non-realtime/non-UI PRs (logic/docs/copy/config stay unit-only).

## Functional Requirements

### FR1: Real-session mint against prod
Mint a session for a **dedicated synthetic prod Supabase user** via `@supabase/ssr`
`createServerClient` → `signInWithPassword`, capturing cookies (port the `dev-signin` pattern,
run server-side). Password from **Doppler `prd`** (`LIVE_VERIFY_USER_PASSWORD`), never a
`DEV_USER_*` secret.

### FR2: UID-allowlist code-gate (CLO guardrail)
Before `setSession`, hard-fail if the target session UID is not on the synthetic-account
allowlist. A code gate, not a convention — the harness can never mint a real end-user's session.

### FR3: Drive the deployed app + capture
Inject cookies via playwright-core `chromium.launch` + `context.addCookies()`; drive the
deployed UI; capture WS frames / DOM / console / network with bounded waits on observable state
(no fixed sleeps).

### FR4: Redaction-before-persist + ephemeral artifacts (CLO guardrail)
Scrub tokens/JWTs/cookies/emails from all captured artifacts before any land in a PR/log;
default attach redacted-only; destroy session + raw captures after the run; never commit them.

### FR5: Deterministic teardown
Delete records created during the run (delete-by-conversation-id) with a unique-marker
convention so a failed teardown never accumulates synthetic rows in prod.

### FR6: Fail-closed postmerge gate
`/soleur:postmerge` records a required tri-state result **`PASS` / `FAIL` /
`CANT-RUN:<reason>+#issue`**. Empty fails closed; `CANT-RUN` auto-files a tracking issue.

### FR7: Path-triggered scope
The gate fires only for PRs touching realtime/WS, session/auth state, or DOM-rendered
server-timing surfaces (keyed on changed paths).

## Technical Requirements

### TR1: Location
Standalone `scripts/live-verify/` (not a skill, not an e2e helper) — keep e2e mock-hermetic.

### TR2: Driver
playwright-core only (`agent-browser` CLI has no cookie/storageState-injection flag).

### TR3: No retries
`retries: 0` for the live harness so a flake is a signal, not masked noise.

### TR4: ADR
Write an ADR for the synthetic prod auth principal + live-mutation verification gate
(cross-boundary: prod Supabase auth + Doppler `prd` + merge pipeline).

### TR5: Synthetic-user provisioning
Seed the synthetic prod user via a committed migration/admin script where possible (automate;
avoid an operator manual step).
