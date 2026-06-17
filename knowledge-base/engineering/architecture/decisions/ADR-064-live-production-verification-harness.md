# ADR-064: Synthetic-principal live production-verification harness + fail-closed postmerge gate

- **Status:** Accepted
- **Date:** 2026-06-17
- **Issue:** #5452 (PR #5453); blocking-flip follow-up #5463; deferred fast-follows #5460 (plan-time executable AC), #5461 (fix-PR live-repro guard)
- **Supersession:** **partial-supersedes [ADR-049](./ADR-049-headless-visual-regression-gate.md)**, scoped to the realtime/server-commit-timing trigger class only (see below).
- **Lineage:** ADR-033 (credential-heavy real-stack execution — substrate Option C), ADR-044 (workspace-as-source-of-truth owner-gate), ADR-038 (workspace path id-shape), AP-009 (never delete user data — carve-out), AP-015 (always-enforce-workspace canary).

## Context

Fixes ship green (mock-verified + multi-agent-reviewed) and still reach the
non-technical operator broken. One rail bug got three fixes (#5391 → #5421 →
#5436), each passing unit tests AND review, none working in production. The
committed Playwright e2e suite drives `localhost` + **mock Supabase**, which
**structurally cannot** reproduce the realtime / server-commit-timing class: the
mock returns HTTP 200 on `/realtime/*` instead of upgrading the WebSocket, so the
"freshly-started conversation never appears in the Recent Conversations rail" bug
is invisible to it. The bug was found only by a headless browser driving the
**deployed** app with a **real session** (#5449/#5451). `/soleur:postmerge`
Phase 5 had a browser-verification step that **skipped-with-warning** when
Playwright MCP was unavailable — the punt that let the broken fixes pass.

## Decision

The merge pipeline authenticates to **prod** as a dedicated, persistent
**synthetic Supabase principal** (`live-verify@soleur.ai`) and performs **live,
conversation-scoped mutation** on qualifying PRs to verify the deployed
artifact — the only way to exercise the realtime/server-commit-timing class. The
harness (`apps/web-platform/scripts/live-verify/run.ts`) drives the deployed UI
via the chromium bundled in `@playwright/test` (no `playwright-core`, no
MCP-browser dependency), asserting a fresh conversation appears in the rail, then
tears it down. It is wired into `/soleur:postmerge` as a **path-triggered,
report-only** gate (Phase 5.5).

### Partial-supersession of ADR-049 (load-bearing)

ADR-049 (Headless Visual-Regression Gate) mandates "runs with zero credentials,"
"no dev-signin, no live backend, no real credentials," and "the gate must never
point at a live/staging origin. If it ever does, re-trigger the gdpr-gate"
(ADR-049:27,35,62-63). This ADR **partial-supersedes ADR-049, scoped to the
realtime/server-commit-timing trigger class only** — CSS/structural visual diffs
stay on ADR-049's zero-cred mock gate. The new fact ADR-049 did not weigh:
realtime timing is invisible to mock-Supabase. **ADR-049's gdpr-gate clause is
armed** → `/soleur:gdpr-gate` was run inline at /work Phase 0 (output recorded in
the PR, AC6b).

### Verification mechanism — `I-action-send-free` (CTO ruling, 2026-06-17)

The plan's original deepen invariant was **I-message-free** ("start a fresh
conversation, assert it appears in the rail, NEVER send a message"). During /work
this was found **structurally vacuous** and routed to the `cto` agent for a
binding ruling. The contradiction:

- `conversations` rows are materialized **lazily on the first user message**
  (`server/ws-handler.ts:2164` — "Materialize pending conversation on first real
  message"; the INSERT is at `:2191`). Session-start only sets `session.pending`.
  A strictly message-free run produces **no `conversations` row**, so nothing
  enters the rail and the #5391/#5436 path is never exercised — a green
  message-free harness is false confidence.
- `messages` is **not** in the `supabase_realtime` publication (mig 039);
  `conversations` **is** (mig 034). The rail's realtime feed observes the
  `conversations` INSERT, which only the message path produces.

**Ruling (Option B, message-minimal):** the harness sends **exactly one benign
user message** through the browser UI (the only path that produces the rail's
realtime INSERT), then tears down. The WORM concern that motivated I-message-free
is narrower than stated: `action_sends.message_id → messages` is `NO ACTION`
(≈RESTRICT) with a WORM no-delete trigger (mig 051:103,144-154), but the **sole**
`action_sends` writer is `server/action-sends/write-action-send.ts` (agent
scope-gated action sends). A plain user message writes **no** `action_sends` row,
and the synthetic principal holds **zero `scope_grants`**, so the agent Send route
403s before `write-action-send.ts` can ever run — **no `action_sends` row is
reachable by construction**. The harness writes no `messages`/`action_sends` row
in code (the message is sent through the UI), keeping the structural greps
(AC2c) at zero.

## Binding invariants

- **I-allowlist:** exactly one synthetic principal; the gate asserts
  **ref (from anon JWT) before sign-in**, then **UID + email after sign-in**, all
  **before** the browser launch. `chromium.launch` is reachable only via a single
  function (`driveAndVerify`) that takes a `VerifiedPrincipal` branded type as a
  typed argument — a future refactor cannot bypass a boolean.
- **I-action-send-free** (supersedes I-message-free): the harness writes no
  `messages`/`action_sends` row in code; the principal has zero `scope_grants` so
  no WORM `action_sends` row is reachable; teardown asserts the principal has
  **0 `action_sends`** before deleting, else
  `CANT-RUN:CANT-TEARDOWN-has-action-sends+#5463` (escalate; never reap-next-run,
  never force-delete).
- **I-service-role-bootstrap-only:** the service role is used only at one-time
  **local** bootstrap (`scripts/bootstrap-live-verify.sh`, never in CI). The
  gate-run path never references `SUPABASE_SERVICE_ROLE_KEY` (AC2b); teardown runs
  as the synthetic user's **own** session (RLS).
- **I-teardown:** delete-by-conversation-id **with `user_id=<allowlisted UID>` as
  a mandatory predicate** (a no-op on an empty marker — AC2d). `messages` +
  `chat_attachments` CASCADE (mig 001:70 / 019:22); the concurrency slot is
  released first by archiving the conversation (fires the mig-036 slot-release
  trigger; `user_concurrency_slots` has no FK so a bare delete leaks it). A
  queryable `session_id = "live-verify:<run-id>"` marker lets the start-of-run
  reaper clean orphans from a crashed run (`conversations` has no title column).
- **I-blast-radius:** read-mostly + conversation-scoped mutation only, in a
  1-member personal workspace (ADR-044 owner-gate / AP-015 canary); never touches
  another user's data.
- **I-no-founder-context:** no BYOK/operator credentials beyond its own session
  (ADR-033 I2 mirror).
- **I-ephemerality:** session + raw captures destroyed at end of run; only a
  **redacted** RESULT summary is emitted (`scripts/live-verify/redact.ts` scrubs
  by structural location — WS-URL `access_token`/`apikey` params, `Authorization`
  headers, `sb-*-auth-token` cookies, `refresh_token` JSON keys, emails).

## Alternatives considered

- **(a) mock-only e2e** — rejected; cannot reproduce realtime (the status quo
  that let #5391/#5421/#5436 pass).
- **(b) operator's own account** — rejected (CLO impersonation/PII).
- **(c) preview-deploy target** — rejected: a preview points at **dev** Supabase
  (ADR-023), a different realtime backend, so it cannot reproduce the prod race.
- **(d) ADR-049's zero-cred mock-storageState gate** — rejected for this class
  (mock can't upgrade the WS).
- **(A) message-free, verify only the client conversation-created event** —
  rejected by the CTO ruling: does not exercise the server-commit/realtime path,
  so it cannot regression-guard the bug it exists for.

**Honest consequence:** this is a **detect-fast gate, not a prevent gate** — it
verifies post-merge, so a regression is briefly live. Prevention would need a
prod-realtime-pointing preview (separate, larger infra; deferred).

## Substrate (reconcile with ADR-033)

Report-only v1 lives in the agent-driven `/soleur:postmerge` skill (acceptable
for dark-launch observation per `wg-dark-launch-deploy-gates`). The **#5463
blocking flip is gated on re-homing the harness into a GitHub Action /
`workflow_dispatch`-from-`web-platform-release.yml` with a Sentry-observable
result** (ADR-033 Option C for credential-heavy real-stack execution) — **never a
boolean flip in an agent skill** (that would recreate the #4932
non-deterministic-blocking-gate class). This precondition is recorded on #5463.

### Inngest re-home considered and rejected (2026-06-17, CTO ruling)

The Inngest substrate was evaluated as an alternative to the GitHub-Action
re-home (#5487), on the basis that (a) the prod runner image already bakes
Chromium (`apps/web-platform/Dockerfile`; ADR-033 I4) and `cron-ux-audit.ts`
already drives a Playwright browser in-container, so "ubuntu-latest is the only
place with a working browser" no longer holds, and (b) Inngest functions already
run with Doppler `prd` secrets + Sentry in-process. **Rejected.**

A blocking deploy-gate requires a *deterministic, synchronous* signal *isolated
from the system under test*. An Inngest function produces an **asynchronous**
result, on the **same prod host** whose deploy is being gated; gating on it would
require the release workflow to poll a written verdict (a poll-with-timeout
fallback = silent-pass-or-flaky-block — the #4932 non-deterministic-blocking-gate
class this §Substrate already forbids), and it lets a browser-driving job perturb
the prod server under test. It would also couple a *mutating* synthetic-prod
session to the `cron-platform` concurrency slot shared with agent-loop crons. The
GH-Action's **exit-code-as-required-check** is deterministic and host-isolated.
This aligns with ADR-033 Option C's own scope-note: a job that must stay in an
ephemeral runner isolated from the long-lived app host keeps the GHA shape. The
hybrid (Inngest-runs / CI-polls) was rejected as combining both substrates' costs.

The recorded substrate (GitHub Action in `web-platform-release.yml`, ADR-033
Option C, Sentry-observable result) **stands unchanged.** Report-only v1 lands as
a `live-verify:` job in `web-platform-release.yml` (#5487, item 3 of the #5463
chain) — report-only by topology (no job `needs:` it) + `continue-on-error`, per
`wg-dark-launch-deploy-gates` — superseding the original `/soleur:postmerge`-skill
location named above for the report-only stage. The C4 edge "live-verify harness
→ deployed web-platform + prod Supabase" is unchanged in endpoints; its **driver**
is now the release workflow, not the agent-driven `/soleur:postmerge` skill. No
ADR-033 Option-set change.

### Runner browser + cookie shape (#5485)

Two harness-runnability facts pinned by a live MCP/system-Chrome repro (#5485):

- **Browser binary.** `run.ts` launches the bundled `@playwright/test` chromium
  by default. On a host whose OS that bundled browser does not support (the
  bundled `chrome-headless-shell` is then absent and `chromium.launch()` fails),
  set `LIVE_VERIFY_BROWSER_CHANNEL` (e.g. `chrome`) or `LIVE_VERIFY_BROWSER_PATH`
  (an explicit executable path, which wins over the channel) to point at a system
  browser. Both are **optional** — unset on ubuntu-latest CI, where the bundled
  chromium installs cleanly, so the GH-Action re-home substrate is unaffected. A
  launch failure now surfaces as the distinct, diagnosable
  `CANT-RUN:browser-launch:<error.name>` (fail-loud, never a silent fallback).
- **Injected cookie `httpOnly: false` is load-bearing.** Client-guarded routes
  (`/dashboard/chat/new`, the gate path) hydrate the session via the
  `@supabase/ssr` BROWSER client, which reads the auth-token cookie from
  `document.cookie` — a path `httpOnly` blocks. Injecting `httpOnly: true` made
  the client guard win a hydration race and bounce to `/login` ~20% of runs
  (measured live); `httpOnly: false` was 5/5 clean and matches the proven
  cookie-injection references (`bot-signin.ts`, `e2e/global-setup.ts`). The
  earlier "cookie does not authenticate / lands on /login" framing was a partial
  diagnosis — auth works; the bug was the `httpOnly` flag + the missing runner
  browser. Locked by `test/live-verify/cookie-injection.test.ts`.

## Principle-register alignment

AP-001 (Terraform — aligned; `-target=` is a scoped bootstrap escape hatch),
AP-008 (Doppler — aligned), **AP-009 (never delete user data — carve-out:**
synthetic-principal rows are not user data; teardown is scoped to the allowlisted
UID), AP-015 (always-enforce-workspace — synthetic user is a 1-member personal
workspace; does not perturb the canary).

## C4 views

Container view: new edge **"live-verify harness → deployed web-platform (HTTPS) +
prod Supabase (auth)"**, `status: adopting`. To be reflected in the C4 model via
the `c4-edit` Concierge path (KB-write gated) as a follow-up; this ADR is the
authoritative record of the edge until then.

## Password rotation / revocation (runbook)

Leak response:
1. `terraform -chdir=apps/web-platform/infra apply -replace=random_password.live_verify_user`
   (mints a new password → republishes the Doppler `prd` secret).
2. `doppler run -p soleur -c prd -- bash apps/web-platform/scripts/seed-live-verify-user.sh`
   (idempotent admin password update for the synthetic UID).
3. `auth.admin` sign-out-all for the synthetic UID (revokes any live session).

## Consequences

- The realtime/server-commit-timing regression class gains a deployed-artifact
  backstop the mock suite structurally cannot provide.
- A persistent prod auth principal exists; its blast radius is bounded by the
  invariants above (allowlist code-gate, zero scope_grants, conversation-scoped
  teardown, RLS-only gate-run path) and its leak path is the rotation runbook.
- The mock-hermetic e2e suite is unchanged and stays CI-blocking for the model
  layer (Non-Goal: do not replace it).
