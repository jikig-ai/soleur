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

## Plan-review addenda (#5452 plan, 2026-06-17)

4. **`@playwright/test` bundles the `chromium` driver** (`.launch()` + `context.addCookies()`) — a
   session-injection harness needs NO `playwright-core` dependency; `import { chromium } from
   "@playwright/test"` (verified at v1.58.2). The CTO's "use playwright-core" instinct was a false
   new-dep. Run `.ts` scripts via `bun run` (apps/web-platform uses `bun.lock`), not bare `node`.

5. **A new/changed postmerge deploy-gate must ship report-only first** (`wg-dark-launch-deploy-gates`):
   it cannot ship blocking on the same PR that introduces it — must be observed passing on ≥1 real
   qualifying deploy before it gates. A live-verification gate is a deploy-gate; ship it report-only,
   track the blocking flip in a follow-up issue.

6. **Porting a dev-gated seed script to prod is not a config swap.** `seed-dev-users.sh` asserts a
   canonical `…\.supabase\.co$` URL and matches the JWT ref to the URL host — both break against the
   prod custom domain (`api.soleur.ai`, `PROD_ALLOWED_HOSTS`). Derive the ref from the service-role
   JWT and validate the URL against the allowed-hosts set. The synthetic prod user also needs the
   full `public.users` + `api_keys` ladder or middleware bounces it off the target page.

## Tags
category: integration-issues
module: web-platform/e2e, postmerge, live-verify
related: #5452, #5449, #5451, #5463, knowledge-base/project/learnings/bug-fixes/2026-06-17-rail-realtime-race-needs-deterministic-signal-not-timing-tweaks.md
