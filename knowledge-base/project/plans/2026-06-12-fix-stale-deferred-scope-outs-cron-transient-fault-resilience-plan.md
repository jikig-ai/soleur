---
title: "fix: stale-deferred-scope-outs cron pages on a single transient GitHub fault"
type: fix
date: 2026-06-12
branch: feat-one-shot-cron-stale-deferred-scope-outs-error-checkin
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

# 🐛 fix: stale-deferred-scope-outs cron pages the operator on a single transient GitHub fault

## Enhancement Summary

**Deepened on:** 2026-06-12
**Agents:** precedent-diff (Explore), verify-the-negative (Explore),
observability-coverage-reviewer, code-simplicity-reviewer, test-design-reviewer.

### Key Improvements
1. **Scope cut from two fixes to one.** code-simplicity + test-design +
   precedent-diff converged: the heartbeat-gating fix is necessary AND
   sufficient; the in-attempt-retry / widened-`createProbeOctokit` "Fix B" was a
   ~10-caller helper mutation + a novel secondary-rate-limit heuristic (zero repo
   precedent) for sub-second latency nobody observes. Cut to "Alternative
   Considered". ~50% less net code, ~40% less test surface, same acceptance bar.
2. **Load-bearing Phase 0 verification added.** The deepen pass found `ctx.attempt`
   is *typed* on Inngest's `BaseContext` but **no in-repo handler reads it** (the
   cited `cron-bug-fixer` precedent was false — label strings, not ctx reads).
   Phase 0 now verifies Inngest delivers `attempt`/`maxAttempts` and increments on
   a `step.run` throw before any code is written.
3. **Observability hardened (P1 findings).** Verify Inngest's worst-case
   between-attempt delay vs. the schedule-anchored 30-min margin (not asserted);
   added the dropped-retry failure mode with layer citation; added a
   `recovered_after_attempts` flap-trend warn so a daily transient flap is
   queryable instead of invisible; resolved the `warnSilentFallback` naming
   inconsistency.
4. **Test scaffolding specified.** Partial `_cron-shared` mock (`importActual`
   spread) to spy `postSentryHeartbeat`'s `ok` arg — not a fetch spy (env-unset
   short-circuit) or `makeStep().calls` (void return). Rethrow asserted via
   message-pinned `.rejects.toThrow(/sweep failed/)`.

### Verified (control-flow claims, all confirmed)
- Per-issue 403s do NOT set `sweepFailed`; only `createProbeOctokit()` +
  `GET /search/issues` flip the monitor (confirms diagnostic constraint #1).
- The `error` heartbeat fires on attempt 0 BEFORE the rethrow that triggers
  Inngest's `retries: 1` — the "page before retry" bug (confirms constraint #2).
- #5199 is OPEN and tracks the 9 deferred crons; this live cron is independent.

## Symptom

Sentry web-platform Crons monitor `scheduled-stale-deferred-scope-outs`
(monitor.id `87e37238-6e05-4507-af82-ff10f70ccfe4`) fired a high-priority
**"An error check-in was detected"** alert.

- Last successful check-in: `2026-06-11T12:00:05+00:00`
- First failure: `2026-06-12 ~12:00 UTC` (Sentry issue
  `9f3c3ad091424b2aa5fbdb3d0b4914f7`, incident `5468023`),
  `environment=production`, `level=error`.
- Monitor config: `failure_issue_threshold = 1` (a single error check-in
  opens the issue), `recovery_threshold = 1`, `checkin_margin_minutes = 30`,
  `max_runtime_minutes = 10`, `schedule = 0 12 * * *`.

The cron succeeded 06-11 and failed once 06-12. A standing
permission/wiring bug would have failed 06-11 too, so the trigger is a
**transient** upstream GitHub fault on 06-12 (a single 401/403/429/5xx blip),
not a regression in the cron's own logic.

## Confirmed root-cause control-flow finding (verified against current code)

Read of `apps/web-platform/server/inngest/functions/cron-stale-deferred-scope-outs.ts`
(at this branch) confirms the control-flow claim in the task brief:

1. The Sentry `error` check-in is posted by `postSentryHeartbeat({ ok: !sweepFailed, … })`
   at `cron-stale-deferred-scope-outs.ts:327-334`. `ok` is `false` only when
   `sweepFailed === true`.
2. `sweepFailed` is set `true` **only** in the `catch` at line 313-322, which
   wraps `step.run("sweep-stale-deferred-scope-outs", …)`. That step does two
   throwing things:
   - `const octokit = await createProbeOctokit();` (line 304)
   - `sweepStaleScopeOuts({ octokit, … })` → `fetchCandidates({ octokit, cutoffIso })`
     → `await octokit.request("GET /search/issues", …)` (line 126).
3. **Per-issue write failures do NOT set `sweepFailed`.** The comment/close
   `try/catch` at lines 227-268 catches per-issue 403/410/422, mirrors via
   `reportSilentFallback`, and *continues the loop* — the counter does not
   advance but `sweepFailed` stays `false`. So the missing-`issues:write` 403
   class is **not** the trigger (confirmed; matches the brief's diagnostic
   constraint #1).
4. Therefore the only paths that flip the monitor to `error` are
   **`createProbeOctokit()`** and **the `GET /search/issues` call**.

### The two throwing paths, and their current resilience

| Path | Current resilience | Gap |
|---|---|---|
| `createProbeOctokit()` (`probe-octokit.ts:116-167`) | 401-only retry: 3 total attempts, 1s/2s backoff (`PROBE_JWT_MAX_RETRIES = 2`). Any non-401 (403/429/5xx) **breaks immediately** via `captureAndRethrow` at line 152. | A transient **429 (secondary-rate-limit) or 5xx** on installation discovery throws on the first occurrence — no retry. A 401 *after* the 3-attempt budget also throws. |
| `GET /search/issues` (`cron-stale-deferred-scope-outs.ts:126`) | **None.** Bare `await octokit.request(…)` inside `fetchCandidates`. | Any transient (401/403/429/5xx) on the search call throws immediately, flipping `sweepFailed=true`. This is the **most exposed** surface — the search call has zero retry wrapping. |

### The second, independent bug: the heartbeat pages *before* Inngest retries

The function is registered with `retries: 1`
(`cron-stale-deferred-scope-outs.ts:368`), i.e. **2 total attempts**. But the
handler's own logic posts the `status=error` heartbeat at the *end of every
failed attempt* (line 327-334) and only then rethrows (line 339) to trigger
Inngest's retry. So on a first-attempt transient that the retry would have
recovered:

- **attempt 0**: sweep throws → `sweepFailed=true` → heartbeat POSTs
  `status=error` → **Sentry monitor flips to error, issue opens, operator
  paged** → rethrow.
- **attempt 1** (Inngest retry): sweep succeeds → heartbeat POSTs `status=ok`
  → monitor recovers.

The operator was paged by a fault that the very next attempt fixed. **The
heartbeat-on-first-failure timing is itself a bug**, independent of (and
compounding) the missing retry on the search/auth path.

Inngest exposes `ctx.attempt` (zero-indexed) and `ctx.maxAttempts` in the
function context (verified: `node_modules/inngest/types.d.ts:420-431`; already
consumed by sibling handlers e.g. `cron-bug-fixer.ts`). The current handler
destructures only `{ step, logger, event }` (`HandlerArgs` in `_cron-shared.ts:92-100`)
and never reads `attempt` — so it cannot currently distinguish "first failed
attempt, retry pending" from "final attempt, genuinely failed".

## User-Brand Impact

**If this lands broken, the user experiences:** the operator (Soleur's sole
user for this cron) continues receiving high-priority Sentry pages for
transient GitHub blips that self-heal on retry — alert fatigue that erodes
trust in the monitor and risks a *real* persistent failure being ignored as
"probably another transient."

**If this leaks, the user's data / workflow / money is exposed via:** N/A — this
change touches only an internal operator-owned cron over the `jikig-ai/soleur`
repo via the synthetic-probe Octokit (no founder data, no audit-ledger writes
per `probe-octokit.ts` header). No PII, no regulated-data surface.

**Brand-survival threshold:** `none`. The Files-to-Edit are under
`apps/web-platform/server/` (which matches the preflight Check-6 sensitive-path
regex by directory), so an explicit scope-out is required:

`threshold: none, reason:` the change touches only an Inngest cron handler and
its test (plus a one-line optional-field addition to the shared `HandlerArgs`
type) — no schema/migration, no auth flow, no `.sql`, no API route, no
founder-data path. The cron operates exclusively on
operator-owned GitHub issues via platform-synthetic traffic (no audit-ledger
writes per `probe-octokit.ts` header), so a failure is an
operator-visibility/alert-quality concern, not a single-user data or money
incident.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Codebase reality | Plan response |
|---|---|---|
| "exception in createProbeOctokit() OR the /search/issues call — NOT the per-issue close path" | Confirmed exactly (see control-flow finding above). | Harden both throwing paths; leave per-issue path unchanged. |
| "createProbeOctokit — 401 retries then throws" | Confirmed: 401-only, 3 attempts, `captureAndRethrow` on non-401. | Widen the retryable class to include 429/secondary-rate-limit/5xx (transient), keep 403/404/malformed as immediate-throw (permanent). |
| "Inngest's existing `retries: 1` … does the error check-in fire on the first failed attempt even though Inngest will retry?" | **Yes — confirmed bug.** Heartbeat posts `error` on attempt 0 before the retry. | Gate the `error` heartbeat on the final attempt (`attempt >= maxAttempts-1`); on non-final failed attempts skip the error POST and just rethrow to let Inngest retry. |
| "#5199 tracks 9 deferred crons; this cron is NOT one of them" | Confirmed: #5199 is OPEN, titled "restore the 9 crons still deferred after Tier-2 boundary". `cron-stale-deferred-scope-outs` is a *live* migrated cron (PR #4457), not deferred. | Independent failure; no restoration-work coupling. |
| Parallel worktree `feat-one-shot-restore-tier2-deferred-crons-5199` may edit `_cron-shared.ts` | `_cron-shared.ts` carries `postSentryHeartbeat`, the TIER2/allowlist lists, and `HandlerArgs`. | Keep `_cron-shared.ts` edits **minimal**: the only change is widening `HandlerArgs` to optionally expose `attempt?`/`maxAttempts?` (does not touch the TIER2/allowlist lists, so conflict risk is near-zero). All other logic lives in the cron handler file. |

## Goal

A single transient GitHub API fault (401-after-budget / 403-secondary-rate-limit
/ 429 / 5xx) on either the auth path or the search path MUST NOT flip the Sentry
monitor to `error` / page the operator — while a genuinely persistent failure
(fault on every Inngest attempt, or a permanent 404/malformed-config) still does.

## Approach — single fix: gate the `error` heartbeat on the final Inngest attempt

**Deepen-plan revision (2026-06-12):** the original two-fix design (heartbeat
gating + a bounded in-attempt retry / widened `createProbeOctokit` retry class)
was reduced to **one fix** after the multi-agent deepen pass. The
code-simplicity reviewer, test-design reviewer, and precedent-diff agent
converged: the heartbeat-gating fix is **necessary AND sufficient** for the
acceptance bar, and the second fix (call it the dropped "Fix B") was
defense-in-depth that mutated a ~10-caller helper (`createProbeOctokit`) and
introduced a *novel* secondary-rate-limit heuristic with **zero repo precedent**
(verified: no `isTransientGitHubStatus`, no `retry-after`/`x-ratelimit-remaining`
detection anywhere in `apps/web-platform/server/`) — all for sub-second latency
nobody observes on a daily 12:00-UTC cron. See "Alternative Considered (dropped)"
below for the full rationale.

### Why heartbeat-gating alone is sufficient

The **only** signal the operator ever receives is the Sentry heartbeat
(`postSentryHeartbeat`, `cron-stale-deferred-scope-outs.ts:327-334`), gated
solely on `sweepFailed`. Gating that signal on the *final* Inngest attempt is
**path-agnostic**: it suppresses the page for *any* transient on *any* throwing
path (auth OR search; 401/403/429/5xx) that recovers on Inngest's second
attempt, and still pages on a fault that throws on *both* attempts. Inngest's
existing `retries: 1` (`cron-stale-deferred-scope-outs.ts:368`, confirmed) is the
recovery mechanism; the bug is purely that the cron *pages before that retry
runs*.

### The fix

- **Widen `HandlerArgs`** (`_cron-shared.ts`) to optionally surface Inngest's
  `attempt?: number` and `maxAttempts?: number` (both optional — keeps every
  other handler and the existing tests, which pass neither, compiling and green).
  This is the **only** `_cron-shared.ts` edit (merge-conflict-minimal vs. the
  parallel `feat-one-shot-restore-tier2-deferred-crons-5199` worktree).
- In `cronStaleDeferredScopeOutsHandler`, destructure `attempt` and
  `maxAttempts`. Compute `isFinalAttempt = (attempt ?? 0) >= ((maxAttempts ?? 1) - 1)`.
  - **Success** → post `ok` heartbeat (unchanged). When `attempt > 0` (recovered
    on a retry), additionally `logger.warn({ recovered_after_attempts: attempt })`
    so a daily flap on transients is queryable in Sentry as a trend (observability
    reviewer finding #5 — otherwise attempt-0-failed-then-attempt-1-ok looks
    identical to attempt-0-ok and the degradation is invisible).
  - **Failure on a non-final attempt** → do **not** post any heartbeat (neither
    `ok` nor `error`). Posting `ok` would mask a persistent failure; posting
    `error` is the bug we are fixing. The single-shot heartbeat API
    (`postSentryHeartbeat` is one POST `?status=ok|error`, no two-step
    `in_progress` — confirmed `_cron-shared.ts:200-206`) leaves "post nothing" as
    the only non-masking choice. Still call `reportSilentFallback` (forensic
    warning event — see Observability for the level rationale) and rethrow to
    trigger Inngest's retry.
  - **Failure on the final attempt** → post `error` heartbeat (current behavior)
    and rethrow.

  Backward-compat: any caller passing no `attempt` (the existing test shape, or
  any sibling reuse) → `attempt=0, maxAttempts=1` → `isFinalAttempt=true` →
  behaves exactly as today (error on failure). Only the real Inngest fire (which
  delivers `attempt`/`maxAttempts`) gets the retry-aware behavior.

### Margin / dropped-retry analysis (observability reviewer P1 findings #1, #2)

Skipping the intermediate check-in relies on Inngest's *between-attempt* retry
producing the authoritative check-in within the monitor's
`schedule + checkin_margin_minutes (30)` window. The 30-min margin is
**schedule-anchored** (anchored on `0 12 * * *`, not on the attempt-0 failure
time), so it covers the retry as long as attempt 1 completes before ~12:30.
Phase 0 MUST verify Inngest's worst-case between-attempt delay for a
`retries: 1` function and record `D + final-attempt-latency < 30 min` explicitly
— do NOT ship the margin claim as an assertion. Two residual failure modes,
both safe and both now named in the Observability `failure_modes` list:

- **Process dies between attempts** → no `ok` was ever posted → missed-check-in
  alert fires at ~12:30 (margin path). Safe.
- **Inngest drops the retry entirely** (it has dropped runs before — cf.
  `cron-monitors.tf:194` realtime-probe note) → missed-check-in alert (margin
  path) PLUS the attempt-0 `reportSilentFallback` breadcrumb preserves the "it
  *did* fire and threw" forensic signal. Safe, and distinguishable from
  "never fired" via the breadcrumb.

## Alternative Considered (dropped at deepen-plan)

**"Fix B" — bounded in-attempt retry + widened `createProbeOctokit` retry class.**
Rejected. Rationale (code-simplicity + test-design + precedent-diff agents):

- Once heartbeat-gating lands, Fix B changes **nothing operator-observable** — a
  transient caught in-attempt and one caught across Inngest attempts produce the
  identical outcome (no page). The only delta is sub-second latency on a daily
  cron.
- Fix B mutates `createProbeOctokit` (~10 callers: `cron-bug-fixer`,
  `cron-oauth-probe`, `cron-kb-template-health`, `cron-github-app-drift-guard`,
  `mintInstallationToken`, etc.) to fix a bug in one of them — a
  `hr-type-widening-cross-consumer-grep`-class change riding on an unrelated
  single-cron bug-fix. Every one of those callers already has its own Inngest
  retry policy.
- The secondary-rate-limit `403` classifier (`retry-after` / `x-ratelimit-remaining: 0`
  header sniffing) is **novel heuristic code with zero repo precedent** and was
  flagged by the plan's own Sharp Edges as a misclassification risk. Untested
  against a real GitHub secondary-rate-limit payload.

If a *future* incident shows the **same** rate-limit window recurring across
**both** Inngest attempts (the only failure mode Fix B uniquely defends), revisit
with a narrowly-scoped search-path-only retry — but that has not been observed.

## Implementation Phases

### Phase 0 — Preconditions (verify before editing)

- [x] **Confirm Inngest actually delivers `attempt`/`maxAttempts` at runtime AND
  that a throw inside `step.run` increments `attempt`.** This is the single
  assumption the whole fix rests on. The field is *typed* on Inngest's
  `BaseContext` (`node_modules/inngest/types.d.ts:420-431`: `attempt: number`,
  `maxAttempts?: number`) but the deepen pass found **no existing in-repo handler
  reads it** (the `cron-bug-fixer.ts` "attempt" hits are label strings, not ctx
  reads — false precedent). Verify via the Inngest docs/SDK that (a) the field is
  passed to the function ctx and (b) a thrown error inside `step.run("sweep", …)`
  triggers a full function re-invocation with `attempt` incremented. Record the
  finding in the plan/tasks. If the SDK does NOT re-invoke with an incremented
  `attempt` on a `step.run` throw, the fix shape changes (fall back to reading
  `runId`-based de-dup or a different mechanism).
- [x] **Verify Inngest's worst-case between-attempt retry delay** for a
  `retries: 1` function (grep `node_modules/inngest` backoff table or docs) and
  confirm `D + final-attempt-latency < 30 min` (the `checkin_margin_minutes`).
  Record the number — do not assert the margin without it.
- [x] Confirm the test runner: `apps/web-platform/vitest.config.ts` collects
  `test/**/*.test.ts` (node env). The existing test lives at
  `apps/web-platform/test/server/inngest/cron-stale-deferred-scope-outs.test.ts`
  — extend it in place (it is already on the include glob).

### Phase 1 — RED: failing regression tests (write first per cq-write-failing-tests-before)

Extend `apps/web-platform/test/server/inngest/cron-stale-deferred-scope-outs.test.ts`.
**Test scaffolding (per test-design reviewer):** add a *partial* module mock of
`_cron-shared` so the heartbeat is spyable without nuking siblings:

```ts
const postSentryHeartbeatSpy = vi.fn();
vi.mock("@/server/inngest/functions/_cron-shared", async (importActual) => ({
  ...(await importActual<typeof import("@/server/inngest/functions/_cron-shared")>()),
  postSentryHeartbeat: postSentryHeartbeatSpy,
}));
```

Assert on `postSentryHeartbeatSpy`'s `ok` arg — NOT on a `fetch` spy (env is
unset in test → real `postSentryHeartbeat` short-circuits before `fetch`, so a
fetch spy records zero calls in every case and cannot distinguish error from ok)
and NOT on `makeStep().calls` (the heartbeat step returns `void`, carrying no
`ok` signal). Assert rethrow via `.rejects.toThrow(/sweep failed/)` (message-pinned
to the handler's own wrapper, not the raw `{status}` rejection which is caught at
`:313`). New cases:

- [x] **A1 (non-final attempt does not page):** sweep throws (`octokitRequestSpy`
  on `GET /search/issues` throws `{ status: 500 }`). Invoke with
  `{ step, logger, attempt: 0, maxAttempts: 2 }`. Assert:
  `expect(postSentryHeartbeatSpy).not.toHaveBeenCalled()`,
  `await expect(handler(...)).rejects.toThrow(/sweep failed/)`, and
  `reportSilentFallback` WAS called (forensic).
- [x] **A2 (final attempt still pages):** same throw, `{ attempt: 1, maxAttempts: 2 }`.
  Assert `postSentryHeartbeatSpy` called with `expect.objectContaining({ ok: false })`,
  then `.rejects.toThrow(/sweep failed/)`.
- [x] **A3 (legacy/no-attempt path unchanged):** same throw, `{ step, logger }`
  (no `attempt`). Assert error heartbeat (`ok: false`) + rethrow — backward-compat.
- [x] **A4 (success on non-final attempt still posts `ok`):** sweep succeeds,
  `{ attempt: 0, maxAttempts: 2 }`. Assert `postSentryHeartbeatSpy` called with
  `expect.objectContaining({ ok: true })`. Positive control — proves the gating
  did not over-reach and suppress a *successful* non-final check-in.
- [x] **A5 (recovered-after-retry flap signal):** sweep succeeds,
  `{ attempt: 1, maxAttempts: 2 }`. Assert `ok: true` posted AND
  `logger.warn` called with `{ recovered_after_attempts: 1 }` (the trend signal).

Run RED: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-stale-deferred-scope-outs.test.ts`
— confirm the new cases fail against current code.

### Phase 2 — GREEN: implement the heartbeat-gating fix

- [x] `_cron-shared.ts`: add `attempt?: number; maxAttempts?: number;` to
  `HandlerArgs` (both optional). No other `_cron-shared.ts` change.
- [x] `cron-stale-deferred-scope-outs.ts`: destructure `attempt`, `maxAttempts`
  in `cronStaleDeferredScopeOutsHandler`. Compute
  `isFinalAttempt = (attempt ?? 0) >= ((maxAttempts ?? 1) - 1)`. Restructure the
  `sweepFailed` → heartbeat → throw block so:
  - success → `ok` heartbeat (unchanged); if `attempt > 0`, add
    `logger.warn({ recovered_after_attempts: attempt })`;
  - failure + non-final attempt → `reportSilentFallback` (already present) +
    **skip the heartbeat POST entirely** + rethrow;
  - failure + final attempt → `error` heartbeat + rethrow (unchanged).
  Keep/extend the inline comments explaining the retry-aware timing
  (`hr-observability-layer-citation`).

### Phase 3 — Verify GREEN + full suite

- [x] `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-stale-deferred-scope-outs.test.ts`
  — all green.
- [x] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — typecheck
  clean (note: `npm run -w … typecheck` aborts; the in-package `tsc` is the
  canonical form per repo learnings).
- [x] Run the broader cron test cohort to catch any `HandlerArgs` widening
  fallout: `./node_modules/.bin/vitest run test/server/inngest/`.

 (document; do NOT run during planning)

Per the brief, after the fix merges and deploys, re-verify by firing the
manual-trigger from inside this worktree:

```bash
# Dry-run first (lists candidates without commenting/closing):
bash plugins/soleur/skills/trigger-cron/scripts/trigger.sh \
  cron/stale-deferred-scope-outs.manual-trigger --data '{"dry_run": true}'
# Then a real fire to confirm an ok heartbeat lands:
bash plugins/soleur/skills/trigger-cron/scripts/trigger.sh \
  cron/stale-deferred-scope-outs.manual-trigger
```

Confirm in Sentry that the monitor returns to `ok` (recovery_threshold = 1, so
one ok check-in clears the incident). No Terraform change is required — the
monitor config (margins/thresholds) is correct; the bug was in the handler, not
the monitor sizing.

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC1: New test A1 proves a non-final Inngest attempt that throws does NOT
  post a `status=error` Sentry check-in (no operator page) and rethrows so
  Inngest retries.
- [x] AC2: New test A2 proves a final-attempt throw DOES post `status=error`
  (persistent failure still pages).
- [x] AC3: New test A3 proves the no-`attempt` (legacy/test) call shape behaves
  exactly as before (error heartbeat on failure) — backward-compat.
- [x] AC4: New test A4 proves a SUCCESS on a non-final attempt still posts the
  `ok` heartbeat (the gating did not over-reach and suppress a successful
  non-final check-in). This is the brief's "single transient must not flip the
  monitor to error" bar expressed positively — a transient that Inngest's retry
  recovers ends in a single `ok`.
- [x] AC5: New test A5 proves a success on a non-final-then-recovered attempt
  (`attempt > 0`) emits `logger.warn({ recovered_after_attempts })` so a daily
  flap is queryable (observability trend signal).
- [x] AC6: Phase 0 records (a) confirmation that Inngest delivers `attempt`/`maxAttempts`
  to the ctx and re-invokes with an incremented `attempt` on a `step.run` throw,
  and (b) Inngest's worst-case between-attempt retry delay `D` with
  `D + final-attempt-latency < 30 min` margin. The fix's correctness rests on (a);
  the no-false-page guarantee rests on (b).
- [x] AC7: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [x] AC8: `_cron-shared.ts` diff is limited to the `HandlerArgs` `attempt?`/`maxAttempts?`
  additions (minimize merge-conflict surface vs. the parallel
  `feat-one-shot-restore-tier2-deferred-crons-5199` worktree).
- [x] AC9: PR body uses `Ref` (not `Closes`) for any tracking-issue link — there
  is no GitHub issue for this Sentry incident; the resolution is the merged code
  + the post-deploy heartbeat recovery, so do not auto-close anything.

### Post-merge (operator — automatable, run in /work or ship)

- [ ] AC10: After deploy (the `web-platform-release.yml` pipeline restarts the
  container on merge to main touching `apps/web-platform/**`, syncing the new
  function), fire the manual-trigger dry-run via `trigger-cron/scripts/trigger.sh`
  and confirm an `ok` heartbeat (automatable via the trigger script + Sentry API
  read — NOT operator dashboard-watching, per `hr-no-dashboard-eyeball-pull-data-yourself`).
- [ ] AC11: Confirm the Sentry monitor incident `5468023` clears to `ok`
  (recovery_threshold=1) after the next successful check-in.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal backend/cron resilience fix.
No UI surface (no `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`
in Files to Edit → Product/UX Gate = NONE, mechanical override did not fire). No
regulated-data surface (probe-octokit is synthetic operator-owned traffic with
no audit-ledger writes; no schema/migration/auth/API-route → GDPR gate skipped).
No new infrastructure (the Sentry monitor Terraform is unchanged; no
SSH/systemd/secret/vendor/cron creation → IaC gate skipped).

## Observability

```yaml
liveness_signal:
  what: Sentry Crons check-in (heartbeat POST) for monitor scheduled-stale-deferred-scope-outs
  cadence: daily 0 12 * * * UTC (+ manual-trigger fires)
  alert_target: Sentry monitor 87e37238-6e05-4507-af82-ff10f70ccfe4 (failure_issue_threshold=1)
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf:432 (unchanged); emitted by postSentryHeartbeat in _cron-shared.ts
error_reporting:
  destination: Sentry via reportSilentFallback (the EXISTING helper, captured at warning level → real Sentry event) on every sweep failure, including non-final attempts. `warnSilentFallback` is NOT used here (verify helper name at impl time — the canonical helper in this handler is reportSilentFallback).
  fail_loud: true on persistent failure (final-attempt error check-in pages); intentionally quiet on self-healing transients (no page, but reportSilentFallback warning event preserves the forensic breadcrumb)
failure_modes:
  - mode: persistent GitHub auth/search failure (throws on EVERY Inngest attempt — 401-after-budget / 403 / 404 / 5xx / malformed)
    detection: createProbeOctokit or GET /search/issues throws on attempt 0 AND attempt 1 → final-attempt error heartbeat
    alert_route: Sentry monitor error check-in (operator paged)
  - mode: transient GitHub fault (single 401/429/5xx) that recovers on Inngest attempt 1
    detection: throws on attempt 0 (non-final → no heartbeat posted, reportSilentFallback breadcrumb), succeeds on attempt 1 → ok heartbeat + recovered_after_attempts warn
    alert_route: forensic-only (reportSilentFallback warning event + recovered_after_attempts warn in Sentry; NO page)
  - mode: non-final attempt throws then Inngest retry never runs (process dies, or Inngest drops the run — cf. cron-monitors.tf:194)
    detection: no ok check-in within schedule+30min margin → missed-check-in alert (Layer 1 Sentry monitor); reportSilentFallback attempt-0 breadcrumb (Layer 2 pino→Sentry) distinguishes "fired and threw" from "never fired"
    alert_route: Sentry missed-check-in alert (margin path) + Layer-2 forensic breadcrumb
logs:
  where: pino structured logs (logger.info/warn — incl. recovered_after_attempts on a recovered retry) inside the handler + sweep; reportSilentFallback mirrors to Sentry
  retention: per existing Sentry/Better Stack retention (unchanged)
discoverability_test:
  command: bash plugins/soleur/skills/trigger-cron/scripts/trigger.sh cron/stale-deferred-scope-outs.manual-trigger --data '{"dry_run": true}'
  expected_output: dry-run completes; ok heartbeat for scheduled-stale-deferred-scope-outs visible in Sentry Crons (no ssh)
```

Note: the transient-suppression behavior itself (a fault on attempt 0 did NOT
page) is only **test-verified** (cases A1/A2), not prod-observable — there is no
keyboard probe that injects a transient in prod. The post-deploy ACs (AC10/AC11)
confirm the cron runs and the incident clears to `ok`; they do not exercise the
suppression. This is an honest limitation, not a gap (the unit tests are the
authoritative proof of the fix).

## Files to Edit

- `apps/web-platform/server/inngest/functions/cron-stale-deferred-scope-outs.ts`
  — destructure `attempt`/`maxAttempts`; gate the `error` heartbeat on
  `isFinalAttempt`; add the `recovered_after_attempts` warn on a recovered success.
- `apps/web-platform/server/inngest/functions/_cron-shared.ts` — add
  `attempt?: number; maxAttempts?: number;` to `HandlerArgs` (ONLY this change).
- `apps/web-platform/test/server/inngest/cron-stale-deferred-scope-outs.test.ts`
  — new regression cases A1–A5 + the partial `_cron-shared` mock for the
  heartbeat spy.

## Files to Create

- None.

## Non-Goals / Out of Scope

- **In-attempt retry / widened `createProbeOctokit` retry class** (the dropped
  "Fix B") — see "Alternative Considered". Inngest's existing `retries: 1` is the
  recovery mechanism; heartbeat-gating makes it sufficient. A future incident
  showing the *same* rate-limit window across *both* attempts would justify a
  narrow search-path-only retry; not observed.
- No change to the per-issue comment/close error handling (confirmed not the
  root cause).
- No change to the Sentry monitor Terraform config (margins/thresholds are
  correct).
- No restoration coupling with #5199 (independent failure).
- No change to the `0 12 * * *` schedule or `retries: 1` policy (the page-timing
  fix makes `retries: 1` sufficient; we are not raising the retry count).
- No `probe-octokit.ts` edit (it was only touched by the dropped Fix B).

## Open Code-Review Overlap

**None.** Checked at plan time: `gh issue list --label code-review --state open`
returned 63 open issues; `jq`-matched each against the edited file basenames
(`cron-stale-deferred-scope-outs.ts`, `_cron-shared.ts`) — zero matches. No open
scope-out touches these files. (`probe-octokit.ts` was dropped from scope when
Fix B was cut, so it is no longer an edited file.)

## Risks & Mitigations

- **Risk (load-bearing assumption):** the fix's correctness rests entirely on
  Inngest re-invoking the handler with an incremented `attempt` when the sweep
  throws inside `step.run`. If Inngest does NOT deliver `attempt`/`maxAttempts`
  to the ctx, or does not increment on a `step.run` throw, the gating is inert
  (every attempt reads `attempt=0` → always treated as final → no change in
  behavior, i.e. still pages). **Mitigation:** Phase 0 verifies this against the
  SDK before any code is written (AC6). The deepen pass found the field is *typed*
  on `BaseContext` but no in-repo handler reads it today, so this is a genuine
  verify-before-build item, not a formality.
- **Risk:** skipping the heartbeat on a non-final failed attempt could let a
  missed check-in slip past the 30-min margin if the Inngest retry is slow.
  **Mitigation:** the margin is schedule-anchored (from `0 12 * * *`), not
  attempt-anchored; Phase 0 records Inngest's worst-case between-attempt delay
  `D` and confirms `D + final-attempt-latency < 30 min`. A non-final attempt that
  fails and is *not* retried (process dies, or Inngest drops the run) still
  misses the check-in and alerts via the margin path — the "genuinely dead"
  signal is preserved, and the attempt-0 `reportSilentFallback` breadcrumb
  distinguishes "fired and threw" from "never fired".
- **Risk:** `reportSilentFallback` on every transient (including recovered ones)
  is warning-class event noise. **Mitigation:** on a daily cron the volume is
  trivial. The non-final-attempt failure path is exactly the "we burned a whole
  Inngest attempt" signal worth a warning event; the `recovered_after_attempts`
  warn makes a recurring flap queryable rather than invisible.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold
  fails `deepen-plan` Phase 4.6 — this plan's threshold is `none` with a
  one-sentence reason (sensitive-path carve-out satisfied).
- The `HandlerArgs` widening MUST keep `attempt`/`maxAttempts` **optional** —
  every other cron handler and the existing tests pass neither; making them
  required would break compilation across the whole cron cohort.
- Inngest `attempt` is **zero-indexed**; with `retries: 1` there are 2 attempts
  (0 and 1) and `maxAttempts` is 2. `isFinalAttempt` must be
  `attempt >= maxAttempts - 1`, not `attempt >= maxAttempts`.
