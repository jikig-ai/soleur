---
date: 2026-06-17
topic: live-verify-harness
issue: 5452
branch: feat-live-verify-harness
pr: 5453
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstorm-complete
---

# Brainstorm: Autonomous post-deploy live-verification harness (#5452)

## What We're Building

A committed, reusable harness that drives the **deployed** app with a **real session**
and asserts the change actually works — plus a **fail-closed `/soleur:postmerge` gate**
that runs it for the PR classes where mock tests structurally lie.

Scope chosen (operator, 2026-06-17): **Harness + fail-closed gate** (triad's recommended
middle slice). Plan-time executable acceptance-criteria and the fix-PR live-repro guard are
**deferred to fast-follow issues** — they should be designed against a working harness.

## Why This Approach

The inciting failure: one rail bug ("a freshly-started conversation doesn't appear in the
Recent Conversations rail") shipped **three** fixes (#5391 → #5421 → #5436), each of which
**passed unit tests AND multi-agent review** and **did not work in production**. The operator
re-reported after every one. The real cause was found only by a headless-browser harness
driving the *deployed* app (#5449), which then exposed a second residual server-commit-timing
race (#5451) that a passing, mutation-verified unit test could not catch.

**Meta-lesson:** unit tests verify the *model*; only live verification against the *deployed
artifact* verifies *reality*.

**Crux confirmed during research (de-stales the issue's "no harness exists" framing):**
the existing Playwright suite in `apps/web-platform/e2e/` (including a WS injector and a rail
test) runs against `localhost` + **MOCK Supabase**. The rail test's own comment records that
mock-supabase "rejects /realtime/* with HTTP 200 instead of upgrading the WebSocket" — so the
mock harness **structurally cannot reproduce** the realtime / server-commit-timing bug class.
The gap is not "no harness"; it is "the harness drives a mocked app." The dev-only
`dev-signin` route (404 in prd) can't drive production either, and `/soleur:postmerge` Phase 5
browser verification already **skips with a warning** when Playwright MCP is unavailable — the
documented punt the issue targets.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Driver | **playwright-core `chromium.launch` + `context.addCookies()`** | CTO verified `agent-browser` CLI has **no** cookie/storageState-injection flag (only `--session-name`); Playwright `addCookies` is the canonical session-bootstrap mechanism. |
| Session mint | Port the `dev-signin` `createServerClient` → `signInWithPassword` → captured-cookies pattern into a committed script | Pattern already proven in `app/api/auth/dev-signin/route.ts`; just needs to run server-side and target prod. |
| Auth principal | **Dedicated synthetic prod Supabase user**, password in **Doppler `prd`** (e.g. `LIVE_VERIFY_USER_PASSWORD`) — NOT `DEV_USER_*` | `hr-dev-prd-distinct-supabase-projects`: dev users live in the dev Supabase project; prod verification needs a prod principal. New secret + new prod auth principal. |
| Account guardrail | **UID-allowlist code-gate before `setSession`; hard-fail on any non-synthetic UID** | CLO load-bearing guardrail #1 — must be a code gate, not a convention, so the harness can never mint a real end-user's session. |
| Artifact safety | **Redact-before-persist** (tokens/JWTs/cookies/emails) on all captured WS/DOM/network/screenshots; default attach redacted-only; **ephemeral** session + captures, never committed | CLO guardrails #2/#3 — captured prod artifacts could contain another user's data or secrets. |
| Location | Standalone **`scripts/live-verify/`** (not a skill, not an e2e helper) | CTO: e2e config is mock-coupled (mock-Supabase globalSetup + `storageState`); a second Playwright project would fight it. Keep e2e mock-hermetic; live-verify is its own deterministic-infra entrypoint. |
| Gate shape | `/soleur:postmerge` records a tri-state required field **`PASS` / `FAIL` / `CANT-RUN:<reason>+#issue`**; **empty fails closed** and auto-files a tracking issue | CPO: the skip is the actual failure mode. Fail-closed-on-empty makes skip-by-omission impossible; `CANT-RUN` is the honest, dead-end-free escape hatch (reuses the `wg-when-deferring-a-capability` pattern). |
| Gate trigger | **Path-triggered**: realtime/WS, session/auth state, or DOM-rendered server-timing surfaces. Pure logic/docs/copy/config/backend-with-unit-coverage stay unit-only | CPO YAGNI line — applies live-verify only to the #5391/#5421/#5436 class, not universally. |
| Flakiness posture | `retries: 0` (a flake is a signal, not noise); bounded waits on observable WS frames / settled DOM, never fixed sleeps; deterministic teardown (delete-by-conversation-id) + unique-marker convention | CTO: the bug class being caught *is* timing-sensitive; retries would mask it; every run mutates prod under the synthetic user. |
| Architecture record | Write an **ADR** for the synthetic prod principal + live-mutation verification gate | CTO: cross-boundary infra (prod Supabase auth + Doppler `prd` + merge pipeline). |

## Open Questions

- Should the synthetic prod user be seeded via a committed migration/admin script (automatable,
  preferred per "never defer operator actions") or one-time operator provisioning? Default:
  automate the seed in-PR.
- Where does `/soleur:postmerge` read deployed base URL from for the harness (DEPLOY_URL /
  PRODUCTION_URL already referenced in postmerge Phase 3)? Confirm at plan time.
- Preview-deploy vs production target for the live run — production is where the real timing
  lives, but a preview URL avoids prod mutation. Default: production with deterministic teardown
  (the realtime timing only reproduces against the real stack).

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Crux confirmed — the mock e2e harness structurally can't reproduce the realtime/
server-timing class. Use playwright-core + `addCookies` (NOT agent-browser — no cookie flag);
port the `dev-signin` session-mint pattern; dedicated synthetic prod user in Doppler `prd`;
standalone `scripts/live-verify/`; `retries: 0` + deterministic teardown; write an ADR. Scope
middle (harness + gate), defer plan-time AC.

### Product (CPO)

**Summary:** The fail-closed gate is the lever, the harness is its ammunition — build together,
lead with enforcement. Un-skippable via tri-state `PASS/FAIL/CANT-RUN:<reason>+#issue` (empty
fails closed, auto-files an issue). Live-verify mandatory only for realtime/WS/auth/DOM-timing
PRs; everything else stays unit-only. Promote from milestone 6 given the proven 3× trust cost.

### Legal (CLO)

**Summary:** Permitted-with-guardrails for operator-self-use against a synthetic account.
Mandatory: (1) synthetic/operator-owned account only, enforced as a UID-allowlist **code gate**
before `setSession`; (2) redaction-before-persist on all captured artifacts; (3) ephemeral
session + captures, never committed. Re-evaluation trigger: first arms-length/real user or any
EEA data subject.

## User-Brand Impact

- **Artifact:** the `scripts/live-verify/` harness + the `/soleur:postmerge` live-verification gate.
- **Vector:** a broken fix ships green (mock-verified) and reaches the non-technical operator as a
  re-reported, still-broken feature — eroding trust on every cycle; OR the harness mints/captures a
  real user's prod session data and leaks it into a PR/log.
- **Threshold:** single-user incident.

## Productize Candidate

The harness IS the productized artifact (it ends the throwaway-script cycle). No further
productize candidate — the deferred plan-time executable-AC work is tracked as a follow-up issue.
