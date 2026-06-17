# Learning: "We have an e2e harness" is not evidence the deployed realtime path is covered

## Problem

Brainstorm of #5452 (autonomous live-verification harness) opened on the premise that "no
reusable harness exists — the throwaway scripts from the rail-bug session are the seed."
Premise verification de-staled that framing and surfaced three reusable constraints that any
future "drive the deployed app" work must respect.

## Solution / Findings

1. **The existing `apps/web-platform/e2e/` Playwright suite runs against `localhost` + MOCK
   Supabase** (`playwright.config.ts` → `MOCK_SUPABASE_URL`, `baseURL: localhost:PORT`). It
   **structurally cannot reproduce** realtime / server-commit-timing bugs: the rail e2e test's
   own comment records that mock-supabase "rejects /realtime/* with HTTP 200 instead of
   upgrading the WebSocket." So a green e2e run proves the *reducer model*, never the *deployed
   realtime path*. This is the mechanism behind the #5391→#5421→#5436 broken-fix cycle.

2. **The `agent-browser` CLI has NO cookie / storageState-injection flag** (only
   `--session-name`, which persists a profile across invocations). Session-injection harnesses
   that need to drive an app as a pre-authenticated user must use **playwright-core
   `chromium.launch` + `context.addCookies()`**, not `agent-browser` — despite `agent-browser`
   being the otherwise-sanctioned browser CLI. Verify a CLI's cookie-injection capability
   before assuming it can bootstrap a session.

3. **`app/api/auth/dev-signin/route.ts` is dev-only** (`NODE_ENV === "development"`, 404 in
   prd). It is the right *pattern* to port for session-minting (`createServerClient` →
   `signInWithPassword` → captured cookies) but cannot itself drive production verification —
   prod verification needs a dedicated synthetic prod Supabase user (Doppler `prd`, distinct
   from `DEV_USER_*` per `hr-dev-prd-distinct-supabase-projects`).

## Key Insight

A passing e2e/unit suite verifies the *model*; only a harness driving the *deployed artifact*
with a *real (non-mock) session* verifies *reality*. When a suite mocks the very subsystem a bug
lives in (Realtime WS here), green is structurally meaningless for that bug class. Before
treating an existing test harness as coverage, check what its config *mocks*.

## Tags
category: integration-issues
module: web-platform/e2e, postmerge, live-verify
related: #5452, #5449, #5451, knowledge-base/project/learnings/bug-fixes/2026-06-17-rail-realtime-race-needs-deterministic-signal-not-timing-tweaks.md
