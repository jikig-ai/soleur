---
title: "fix: scheduled-community-monitor missed check-ins despite digests produced (heartbeat delivery/timing defect)"
issue: 5728
type: bug
lane: cross-domain
brand_survival_threshold: aggregate pattern
status: complete
created: 2026-06-29
---

# fix #5728 — scheduled-community-monitor missed check-ins 2026-06-13→06-21 despite digests produced

🐛 **Bug** · observability / inngest-cron-substrate · WORK TARGET: open issue **#5728**

> Spec lacks valid `lane:` (no `spec.md` for this branch) — defaulted to `cross-domain` (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-06-29
**Grounding:** direct reads of `_cron-shared.ts`, `cron-community-monitor.ts`, `cron-monitors.tf`,
`cron-stale-deferred-scope-outs.ts`, `107_routine_runs.sql`, ADR-033 I8 + runbook H10; 3 research
agents (repo-research, learnings, spec-flow-analyzer); live `gh`/`grep` citation verification.

### Key Improvements (vs. first draft)
1. **Premise-validation save (Phase 0.6):** the obvious `in_progress` two-phase fix is
   **ADR-033-I8-rejected** (and learning-discouraged) — re-scoped to the delivery-guarantee gap I8
   left (#5087-class trap caught at plan time, not /work).
2. **H4 added (SpecFlow):** the shared `account` `limit:1` concurrency makes **dispatch/queue
   delay** a fourth hypothesis the issue didn't name; Phase 0 now pulls dispatch-vs-start latency.
3. **Latent bug surfaced (SpecFlow Q3):** `postSentryHeartbeat` **never inspects `resp.ok`** today —
   a 5xx silently reads as success, so H3 is currently invisible; Phase 1 fixes this first.
4. **Phase 2 corrected to the flag pattern** (not a second post site) + carry `heartbeatOk` (a
   trailing persistence throw must not false-red an output-present run) + **`DeployInProgressError`
   exclusion** (G1, fixes the existing first catch too).
5. **Phase 3 reframed:** margin sizing is **mandatory iff H1/H4** and must cover the retry-chain +
   shared-slot wall-clock (G3); the late-retry-`ok`-can't-clear-`missed` residual (G2) is recorded
   in the ADR amendment as the accepted cost of the in_progress rejection.

### New Considerations Discovered
- The deploy-kill (H2) remedy **already shipped** as ADR-076/#5686 (2026-06-29, after the window) —
  so PR scope **branches on the Phase 0 verdict**; Phase 1/2 fix the throw/POST classes, not kills.
- A SIGKILL has **no in-process fix** (no catch runs) — `missed` is honest for a killed run.
- Precedent-diff (Phase 4.4): the `cron-stale-deferred-scope-outs.ts` flag/skip-on-non-final
  heartbeat is the canonical retry-aware shape to mirror — cited side-by-side, no novel pattern.

## Overview

The Inngest cron `cron-community-monitor` records a **single terminal** Sentry check-in
heartbeat (`postSentryHeartbeat` → fire-and-forget `POST …/cron/<slug>/<key>/?status=ok|error`)
at the **end** of the run. From **2026-06-13 → 06-21** the `scheduled-community-monitor`
monitor recorded `missed` every day even though a full daily digest issue was produced each
day (e.g. #5586, #5596, #5597 — real digests, not the `#4960` FAILED self-report fallback).
Last `ok` = 06-12. This is **distinct** from the later **2026-06-22 → 06-29 credit-exhaustion**
regime (`?status=error`, already resolved 2026-06-29 by operator top-up) and **distinct** from
the #5674/PR #5680 observability that already shipped for the credit regime.

The check-in layer and the GitHub-digest layer disagree; **Sentry's alert keys off the
check-in layer** (last ok = 06-12). For 9 days the monitor under-reported run success, so a
genuine outage in that window would be **indistinguishable** from this benign-but-broken state,
and Sentry's auto-mute/disable clock runs against it (runbook H10).

**Root-cause shape (from code reading — confirmed at Phase 0 against live evidence):**
The heartbeat is the *single last thing* the handler does, gated behind everything that can be
slow or die, and it is delivered by a *fire-and-forget POST that swallows its own failure*:

- `cron-community-monitor.ts:349-462` — the `claude-eval → verify-output → safe-commit-pr →
  sentry-heartbeat` steps live inside a `try` whose **only** protection is a `finally` (teardown).
  There is **no `catch`**. Any *throw* on the final Inngest attempt (`retries: 1`) propagates →
  the function fails → `step.run("sentry-heartbeat")` **never executes** → Sentry sees **no
  check-in** → `missed` (not `error`).
- `_cron-shared.ts:294-307` — `postSentryHeartbeat` POSTs once, fire-and-forget, and on any
  fetch failure (5xx / timeout / network) **swallows** it into `reportSilentFallback`. A
  transient drop of the OK POST leaves a `missed` whose only trace is a `cron-sentry-heartbeat`
  Sentry event.
- The run is long (claude-eval budget `MAX_TURN_DURATION_MS = 50 min` + depth-1 clone + commit/PR),
  and the deploy-lease drain that protects in-flight crons from container-swap **SIGKILL**
  (ADR-076 / PR #5686) landed **2026-06-29 — AFTER the window**, so during 06-13→06-21 a merge
  landing in the 08:00–09:00 run window killed the container mid-run, dropping the heartbeat and
  triggering an Inngest retry that re-ran claude-eval (→ the **two-digest-issues/day** seen
  06-19→06-21).

This is the issue's three hypotheses — plus a fourth surfaced by SpecFlow: **H1** run-duration >
margin (slow path posts no/late OK), **H2** mid-run crash/kill before `postSentryHeartbeat` (→
silent `missed`, not `error`), **H3** swallowed/transient-failed OK POST, **H4** dispatch/queue
delay — the function's concurrency is `{ scope: "account", key: "cron-platform", limit: 1 }`
(`cron-community-monitor.ts:487-489`), shared by **all** `cron-*`, so the 08:00 fire can queue
behind another long cron and *start* 30–50 min late; a 50-min run then posts `ok` past the 60-min
margin with **no kill and no throw**. **Phase 0 discriminates them — per-day AND per-attempt, not
one global winner (a single day can be H2+H3) — against live data before any code lands.**

> **SpecFlow load-bearing caveat:** the normal failure paths are **already loud** —
> `resolveOutputAwareOk` *returns* `false` (never throws) on no-output/non-zero-exit and the
> heartbeat posts `?status=error`. So `missed` (not `error`) means the `sentry-heartbeat` step
> **literally never executed** — exit-code is a red herring (already handled). And if Phase 0
> shows **H2 (kill)** dominated, the real remediation **already shipped as ADR-076/#5686** and the
> Phase 1/2 code fixes a *different* (throw) class — **PR scope must branch on the Phase 0
> verdict**, not assume the throw class.

### ⚠️ Premise-validation finding (Phase 0.6) — the obvious fix is ADR-rejected

The standard remedy for "a long run reads as missed" is an **early `in_progress` check-in**
(arm the margin at run start, close with `ok`/`error` + `max_runtime`). **Do NOT do this.** It is
an **explicitly-rejected alternative** in **ADR-033 invariant I8** (added 2026-06-29, #5674):

> *"Alternatives considered (rejected): … (3) the `in_progress → ok/error` two-phase check-in —
> not needed once classify-fatal distinguishes the classes at the source."*

and is independently warned against by learning
`2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md` (the two-step `|| true` check-in is the
"Last successful check-in: Never" silent-fail trap; the repo's adopted shape is a **single
end-of-job POST**). Planning the rejected mechanism is the #5087-class trap Phase 0.6 exists to
catch. **The fix re-scopes to the gap I8 left open** (see Research Reconciliation): I8 reasoned
about distinguishing *fatal-vs-benign non-zero exits* and **assumed the run reaches the heartbeat
step**. #5728 is the orthogonal case — the heartbeat is **never delivered** (kill / throw / dropped
POST). classify-fatal cannot color a check-in that never posts. So the fix is **delivery
robustness of the existing single-POST heartbeat**, not a check-in state-machine change.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / instinct) | Reality (verified) | Plan response |
| --- | --- | --- |
| Fix by adding an `in_progress` check-in so a slow run isn't "missed" | **ADR-033 I8 rejects** the `in_progress → ok/error` two-phase check-in; learning `2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md` warns the two-step is the silent-fail trap | **Do not** add `in_progress`. Close the gap I8 left (delivery guarantee for the single terminal POST). Amend I8 to record the gap-closure + reaffirm the rejection (Phase 4). |
| margin "30→60 min" too tight on a slow run (H1) | `cron-monitors.tf:288-298` — `scheduled_community_monitor` margin **already 60**, max_runtime 55, schedule `0 8 * * *`. On `abortedByTimeout` the handler still reaches `verify-output`+`sentry-heartbeat` (posts, just late) | H1 is unlikely the dominant cause on healthy-digest days; Phase 0 measures `duration_ms` per run. Re-evaluate margin **only** if Phase 0 shows runs > 60 min — and never via `in_progress`. |
| "crash before postSentryHeartbeat" (H2) | The inner `try` (`cron-community-monitor.ts:349-462`) has **no catch**; `claude-eval` (substrate `:846` returns `{exitCode:-1}` rather than throwing) and `safeCommitAndPr` (`_cron-safe-commit.ts` returns `failure(...)`, does not throw) rarely throw — but a **SIGKILL** (deploy swap, pre-ADR-076) bypasses every catch | Phase 2 adds a final-attempt `catch → ?status=error`. **SIGKILL has no in-process fix** — ADR-076/#5686 (landed 06-29) removes the dominant cause; "missed for a genuinely killed run is honest" is the accepted residual. |
| "swallowed OK POST" (H3) | `_cron-shared.ts:299-307` confirms POST failure is swallowed into `reportSilentFallback` (a Sentry event, not a check-in) | Phase 1 adds a **bounded retry** to the POST so a transient drop doesn't lose the only check-in; keep `reportSilentFallback` as the terminal fallback. |
| dual digest issues/day 06-19→06-21 = a separate "non-scheduled path" | `retries: 1` + a mid-run kill that never completed `step.run("claude-eval")` → the retry **re-runs** claude-eval → second digest issue | Phase 0 reads `routine_runs.trigger_source` per run to confirm scheduled-vs-manual and pair the two issues to one fire's retry. |
| deploy-kill already handled by ADR-076 | PR #5686 (deploy-lease drain) merged **2026-06-29**, *after* the 06-13→06-21 window | Note in plan: #5728 fix is **complementary** to #5686 (delivery robustness vs. fewer kills); neither subsumes the other. |
| (SpecFlow H4) only H1/H2/H3 exist | The function shares one `account` slot (`{ scope: "account", key: "cron-platform", limit: 1 }`, `:487-489`) across **all** `cron-*` — the 08:00 fire can queue behind another long cron and *start* 30–50 min late → posts `ok` past the 60-min margin with no kill/throw | Add **H4 dispatch/queue delay** to Phase 0; pull Inngest dispatch-vs-start latency. If H4 dominant, **margin sizing is mandatory** (Phase 3), not conditional. |
| (SpecFlow Q2/G2) Phase 1+2 fix the missed-on-a-healthy-run | A killed/queued run whose retry posts `ok` **80–110 min** after the anchor lands past the margin; a standalone late `ok` **cannot retroactively clear** a `missed` period (no run-correlation ID — the very thing `in_progress` would give, which I8 rejects) | The late-finish-on-a-healthy-run class is **NOT** closed by Phase 1/2 — only margin/runtime (Phase 3) or kill-prevention (ADR-076) closes it. Record the `in_progress`-rejection **cost** in the Phase 4 ADR note (G2). |
| (H4, SpecFlow) the 08:00 fire ran on time | concurrency `{ scope: "account", key: "cron-platform", limit: 1 }` (`cron-community-monitor.ts:487-489`) is shared by ALL `cron-*` — the fire can queue behind another long cron and *start* late | Phase 0 pulls Inngest **dispatch-vs-start latency**; H4 confirmed if start ≫ 08:00 with no kill/throw. Remedy is margin sizing (Phase 3), not Phase 1/2. |
| a late retry `?status=ok` clears the `missed` day | a standalone late `ok` does **not** retroactively clear a `missed` period (no run-correlation ID — the very thing `in_progress` would give, rejected by I8) | **Accepted residual** — recorded in the ADR amendment (Phase 4 G2): for a killed/late-finishing run, **margin/runtime is the only lever**; Phase 1/2 cannot close this. |

## User-Brand Impact

**If this lands broken, the user experiences:** the operator (single-operator tenant) keeps
seeing a `scheduled-community-monitor` "failing since DATE" Sentry page that does not correspond
to a real failure — and, worse, a *genuine* community-monitor outage during a delivery-flaky
window is indistinguishable from the benign noise, so a real regression is missed and the monitor
is auto-muted/disabled (runbook H10) — silencing the alarm entirely.

**If this leaks, the user's data / workflow / money is exposed via:** N/A — the change touches
only cron heartbeat *delivery* (POST retry + a catch that posts `error`) and a read-only
investigation query over `routine_runs` (operator-readable, single-operator tenant). No new
processing of user data, no auth/PII/payment/migration surface, no secret read/write change.

**Brand-survival threshold:** `aggregate pattern` — the harm is systemic observability
degradation (the monitor fleet's missed-vs-error signal becoming unreliable across runs), not a
single-user data incident. No per-PR CPO sign-off required; section present per gate.

## Implementation Phases

### Phase 0 — Evidence-gather & discriminate (NO code; gates the fix)

Per `hr-no-dashboard-eyeball-pull-data-yourself` and learning
`2026-06-29-cron-health-run-log-green-masks-claude-eval-failure.md` ("the green status layer you
read first is the one most likely to be lying" — rank signals by authority), pull the three
layers for `cron-community-monitor` over **2026-06-13 → 2026-06-21** and reconcile:

0.1 **`routine_runs` (Supabase, authoritative liveness + duration).** Query rows where
`routine_id = 'cron-community-monitor'` in the window: `status`, `started_at`, `ended_at`,
`duration_ms`, `error_summary`, `trigger_source`, `run_id`. Use the Supabase MCP / read-only SQL
(operator-readable SELECT policy, mig `107_routine_runs.sql`). Tabulate **per day AND per attempt**:
`{ start_lag (started_at − 08:00, for H4), duration_ms vs 60-min margin, status completed|failed,
ended_at NULL? (orphaned "running" = SIGKILL signature, NOT status=missed), error_summary,
#rows (dual-fire), trigger_source }`. **Join the dual-issue days on the Inngest run-group / attempt
index** (NOT `trigger_source` alone) to prove retry-after-kill vs. a same-day manual trigger — a
manual same-day fire would have hit the 24h DEDUP RULE (`cron-community-monitor.ts:224-226`) and
*commented* on issue #1, so two distinct *issues* means the 2nd run started before issue #1 existed
(retry-after-kill).

0.2 **Better Stack stdout tail (the only layer carrying the actual cause).** Run
`scripts/betterstack-query.sh` under `doppler run -p soleur -c prd_terraform` (table per
`runbooks/betterstack-log-query.md`; ClickHouse query creds live in **`prd_terraform`**, NOT
`prd`) filtered to `fn: 'cron-community-monitor'` in the window. Look for: SIGKILL / container-swap
markers (`spawn cwd … no longer exists`), the `cron-sentry-heartbeat`/`fetch` swallowed-POST
warning, and the `sentry-heartbeat` step's last log line per run.

0.3 **Sentry check-in timeline + heartbeat-POST events.** `GET …/monitors/scheduled-community-monitor/checkins/`
for the window (confirm the `missed` daily / last-ok 06-12) AND query Sentry issues for
`feature:cron-sentry-heartbeat op:fetch` events in the window (presence ⇒ **H3** swallowed POST).

0.4 **Verify the Sentry Crons check-in ingest contract** (premise verification before any
heartbeat code; Sharp Edge "verify third-party API contract"). WebFetch the Sentry Crons HTTP
check-in docs and confirm: the exact `POST …/cron/<slug>/<key>/?status=` shape, the `ok|error`
enum, the missed/timed-out state machine, and the retry/idempotency semantics of repeated POSTs to
the same slug. Pin `<!-- verified: 2026-06-29 source: <url> -->` in the plan/PR notes.

**Discrimination verdict (per-day, multiple may apply; decides which fix is load-bearing):**
- **H2** (kill) if orphaned null-`ended_at`/`failed` rows + SIGKILL markers + dual run-group rows
  06-19→06-21 (expected, pre-ADR-076). → **The remedy already shipped (ADR-076/#5686)**; Phase 1/2
  fix a *different* class. Say so in the PR; do not claim Phase 1/2 fixes the kill class.
- **H3** (swallowed POST) if `completed` rows + a `cron-sentry-heartbeat/fetch` Sentry event the
  same minute. → Phase 1 is the load-bearing fix.
- **H1/H4** (slow / late-start) if `duration_ms` > 60 min (H1) OR `start_lag` pushes the finish
  past the margin (H4). → **Phase 3 margin sizing is MANDATORY** (sized against the retry-chain +
  shared-slot queue wall-clock, not single-run duration), and Phase 1/2 do not close it.

Record the per-day verdict in the PR body and a learning. The Phase 1/2 ACs are written to be
**robust across the classes** so the fix is not blocked on one confirmed cause, but **the verdict
sets which phase is load-bearing vs. defense-in-depth** (e.g. margin change is mandatory iff H1/H4
confirmed; Phase 2's catch is the fix only for a genuine *throw*, which the evidence may show was
NOT the dominant 06-13→06-21 cause).

### Phase 1 — Bounded retry on the heartbeat POST (fleet-wide, in the shared helper)

**File:** `apps/web-platform/server/inngest/functions/_cron-shared.ts` (`postSentryHeartbeat`,
`:256-308`).

- **First, inspect `resp.ok` (latent bug — SpecFlow Q3).** Today `postSentryHeartbeat` does
  `await fetch(...)` and **only catches network/abort errors — it never reads `resp.ok`**, so a
  Sentry **5xx resolves and is silently treated as success** → **H3 is invisible today and no
  "retry on 5xx" can even fire** until the response is inspected. Add `resp.ok` inspection as the
  first change.
- Wrap the `fetch` in a **bounded retry** (e.g. up to 3 attempts, exponential-ish backoff,
  **total wall-clock bounded well under the 60-min margin and the Inngest step budget** — target
  ≤ ~25s total, each attempt keeping the existing `AbortSignal.timeout(SENTRY_HEARTBEAT_TIMEOUT_MS)`
  = 10s). **Retry only on 5xx / network / timeout; NEVER retry a 4xx** — a 4xx is a permanent
  bad-slug/DSN error, and retrying it only burns the margin and delays the `reportSilentFallback`.
- Only after the bounded retries are exhausted (or on a non-retryable 4xx), fall back to the
  existing `reportSilentFallback` (keep it — durable trace; per `cq-silent-fallback-must-mirror-to-sentry`).
- This is the single-POST-hardening the repo's heartbeat doctrine endorses (NOT a second
  `in_progress` POST). Lands fleet-wide because every cron routes through this one helper —
  parity-asserted by `sentry-monitor-iac-parity.test.ts` (no slug churn).

### Phase 2 — Guarantee a terminal `?status=error` on the THROW path (output-aware cohort)

**File:** `apps/web-platform/server/inngest/functions/cron-community-monitor.ts` (lead), then the
output-aware cohort (see Files to Edit). A throw inside the catch-less inner `try` (`:349-462`)
currently yields a silent `missed`; the fix makes a throw produce a loud `?status=error` ("the cron
RAN and failed", disambiguated from "never fired"). **Use the FLAG pattern, NOT a second post site
(SpecFlow Q4).** Constraints:

- **Flag pattern, single last heartbeat step.** Do NOT add a `catch` that calls `postSentryHeartbeat`
  at a *second* site — under `retries: 1` memoization, if attempt-0 ran the existing
  `sentry-heartbeat` step (posted `ok`) and a *later* step threw, the rethrow→retry **replays the
  memoized `ok`** while a second catch-site posts `error` → the monitor sees **both**. Instead,
  catch the throw into a `heartbeatOk = false` flag and post from **one** heartbeat step that is the
  *genuinely last* step, exactly as the in-repo precedent `cron-stale-deferred-scope-outs.ts`
  (`:358,397-433` — catch into a flag, **skip the whole heartbeat `step.run`** on a non-final
  attempt, rethrow to retry; post one authoritative heartbeat on success or final-failed attempt).
- **Final-attempt gate (load-bearing).** Gate as above: `isFinalAttempt = (attempt ?? 0) >=
  ((maxAttempts ?? 1) - 1)`; skip the whole `step.run` (not just the POST) on non-final failure.
  Thread `attempt`/`maxAttempts` from `HandlerArgs` (already declared, `_cron-shared.ts:190-191`).
  Ref learning `2026-06-12-inngest-cron-heartbeat-gate-on-final-attempt-and-step-memoization.md`.
- **A trailing throw must NOT flip an output-present run to red (SpecFlow Q4.2).** `safe-commit-pr`
  runs *before* the heartbeat and `ensure-audit-issue` *after* it; the heartbeat decision is owned
  by `resolveOutputAwareOk` (issue present ⇒ green). Carry the already-computed `heartbeatOk` into
  the catch so a trailing `safe-commit-pr` persistence throw on a run that **already produced its
  digest issue** stays GREEN (the persistence failure self-reports via `reportSilentFallback`), not
  a false-red. Only a throw on a run with **no** output posts `error`.
- **Exclude `DeployInProgressError` from every error-posting catch (SpecFlow G1, HIGH).**
  `setupEphemeralWorkspace` throws `DeployInProgressError` (`_cron-shared.ts:98-109`) so Inngest
  retries after the deploy (fail-SAFE skip, ADR-076). It must **rethrow bare with NO heartbeat**
  (the non-final-attempt pattern), never `?status=error`. **Also fix the EXISTING first catch**
  (`cron-community-monitor.ts:332-347`): today it treats `DeployInProgressError` like any failure —
  `reportSilentFallback` + `postSentryHeartbeat({ok:false})` + `return` — which red-flags a benign
  deploy-defer AND defeats the ADR-076 retry intent. Branch: `if (err instanceof
  DeployInProgressError) throw err;` before the error-heartbeat.
- **Do not disturb the resolver carve-outs.** `resolveOutputAwareOk` (`:392-402`) + the `#4960`
  silence-hole fallback (`:439-460`) stay; `resolveBestEffortEvalOk`'s benign-non-zero-stays-GREEN
  carve-out (`_cron-shared.ts:859-866`) must be preserved for the best-effort cohort.
- **Extract the flag/skip wrapper into a shared helper** so the cohort adopts one vetted shape
  (mirrors `ensureScheduledAuditIssue`/`resolveOutputAwareOk` centralization). **Per-cron
  step-ordering verification before rollout (SpecFlow Q4.3):** the 8 output-aware producers do NOT
  all place the heartbeat last — grep each handler's step order and confirm the single-last-heartbeat
  invariant holds before adopting. Lead with `cron-community-monitor`.

### Phase 3 — IaC + runbook (margin sizing MANDATORY if Phase 0 confirms H1/H4)

- `apps/web-platform/infra/sentry/cron-monitors.tf` — re-evaluate
  `scheduled_community_monitor.checkin_margin_minutes` **iff Phase 0 confirms H1 or H4**. Size the
  margin against the **worst-case retry-chain + shared-slot (`account` `limit:1`) queue wall-clock**
  — NOT single-run duration (SpecFlow G3): anchor → attempt-0 runtime + retry backoff + retry
  runtime + queue-wait behind sibling crons. Stay within the claude-eval cohort rationale (header
  lines 37-55) and **never** add an `in_progress`/`max_runtime` two-step. If Phase 0 shows H2/H3
  only (no slow/late finishes), leave the margin at 60 (no TF diff). (This root auto-applies on
  merge via `apply-sentry-infra.yml` — see IaC section.)
- Extend `knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md` with a new
  **H11 — "missed (not error) on a claude-eval cron whose digest WAS produced"**: the
  delivery/timing class, the missed-vs-error disambiguation, the Phase-0 three-layer pull recipe,
  and the cross-link to H10 (re-enable a prolonged-mute monitor via the Sentry REST API).

### Phase 4 — ADR-033 I8 amendment (architecture decision is a plan deliverable)

Amend `ADR-033` I8 (via `/soleur:architecture`) to add a dated note: the `in_progress` two-phase
check-in **remains rejected**; #5728's *missed-on-a-healthy-run* class is closed by **(i)** a
guaranteed terminal `?status=error` on the throw path (final-attempt-gated), **(ii)** a bounded
retry on the heartbeat POST for transient drops, and **(iii)** ADR-076/#5686 removing the dominant
SIGKILL cause. Record the accepted residual: a *genuinely killed* run reads `missed` until a late
retry, and `missed` is an honest signal for a killed run. **Explicitly record the `in_progress`-
rejection COST (SpecFlow G2)** so a future reader does not re-open the I8 debate: because I8 forbids
the run-correlation `in_progress` would provide, a **late or retry-chain finish cannot reconcile to
its scheduled period** — therefore **margin/runtime sizing is the only lever** for the slow/late
class, and it must cover the full retry-chain + shared-slot queue wall-clock (not single-run
duration).

## Tests (write failing first — `cq-write-failing-tests-before`)

- `apps/web-platform/test/server/inngest/cron-shared.test.ts` — `postSentryHeartbeat`: (a) a
  transient 5xx then 200 → exactly one effective check-in, no `reportSilentFallback`; (b) all
  retries 5xx → `reportSilentFallback` fired once, bounded by the wall-clock cap; (c) a non-2xx
  *resolved* response is treated as failure (regression for today's "ignore the response" gap).
- `apps/web-platform/test/server/inngest/cron-community-monitor.test.ts` — (a) an inner step throws
  with **no output** on the **final** attempt → a `?status=error` heartbeat is posted exactly once;
  (b) a throw on a **non-final** attempt → **no** heartbeat step runs, function rethrows (retry);
  (c) the happy path still posts exactly one `ok`; (d) **no double-signal under replay** — attempt-0
  runs to a posted heartbeat, a later step throws → the retry does NOT emit a conflicting check-in
  (memoization, SpecFlow Q4.1); (e) **trailing `safe-commit-pr` throw on an output-PRESENT run stays
  GREEN** (not false-red, SpecFlow Q4.2); (f) **`DeployInProgressError` posts NO heartbeat and
  rethrows** — both the new inner catch AND the corrected first catch (`:332-347`) (SpecFlow G1).
- `apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts` — unchanged green (no
  slug churn; assert the cohort rollout didn't drop/rename a slug).
- Runner: per `package.json scripts.test` / vitest config `include:` globs — confirm before
  prescribing the path (these suites already live in `test/server/inngest/`). Typecheck:
  `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] **Phase 0 is a hard gate** — a **per-day, per-attempt** cause table (`routine_runs` incl.
  `start_lag` + null-`ended_at` SIGKILL signature + Inngest run-group join for the dual-issue days,
  Better Stack stdout, Sentry checkins) is in the PR body covering **H1/H2/H3/H4**; PR scope
  **branches** on the verdict (if H2/H4 dominate, state that Phase 1/2 are not the #5728 fix and the
  remedy is ADR-076/#5686 + Phase 3 margin). Sentry check-in ingest contract WebFetch-verified with
  a pinned `<!-- verified: 2026-06-29 source: … -->` line.
- [ ] `postSentryHeartbeat` **inspects `resp.ok`**, retries only **5xx/network/timeout** (NEVER a
  4xx) a bounded number of times (total wall-clock provably < the 60-min margin and the Inngest step
  budget), then falls back to `reportSilentFallback`. Regression test: a stubbed 5xx now fires
  `reportSilentFallback` (today it is silently swallowed). (test: cron-shared.test.ts)
- [ ] Phase 2 uses the **flag pattern** — one heartbeat step that is the genuine *last* step,
  `heartbeatOk` computed once and carried into the catch; final-attempt-gated exactly as
  `cron-stale-deferred-scope-outs.ts:358`. On a final-attempt **no-output** throw → one
  `?status=error`; on a non-final throw → no heartbeat step + rethrow; **no double-signal under
  replay**; a trailing `safe-commit-pr` throw on an **output-present** run stays GREEN.
  (test: cron-community-monitor.test.ts)
- [ ] **`DeployInProgressError` is excluded from every error-posting catch** (rethrow bare, no
  heartbeat) — including the **corrected existing first catch** (`:332-347`), so an ADR-076 deploy
  defer is no longer posted as `?status=error` nor blocks the retry. (test: cron-community-monitor.test.ts)
- [ ] The flag/skip wrapper is a **shared helper** in `_cron-shared.ts`; the output-aware cohort
  rollout list is enumerated AND **each handler's step ordering is grep-verified** so the
  single-last-heartbeat invariant holds (the 8 producers don't all put the heartbeat last);
  `resolveBestEffortEvalOk`'s benign-green carve-out preserved. (grep: ≤1 heartbeat per terminal path)
- [ ] `sentry-monitor-iac-parity.test.ts` green; `tsc --noEmit` clean; full suite green.
- [ ] Phase 3: margin re-sized **iff** H1/H4 confirmed (against retry-chain + shared-slot
  wall-clock); else no TF diff. Runbook H11 added; ADR-033 I8 amended with the gap-closure note,
  reaffirmed `in_progress` rejection, **and the recorded rejection-cost**. No `in_progress`/two-phase
  check-in introduced anywhere (grep `in_progress` over `apps/web-platform/server/inngest/` returns
  only comments/the reaffirmation, no POST).

### Post-merge (operator)
- [ ] After deploy, confirm the next `scheduled-community-monitor` fire posts an `ok` check-in
  within the 60-min margin — verified by `GET …/monitors/scheduled-community-monitor/checkins/`
  (read-only Sentry API; no SSH). `Ref #5728` in PR body (not `Closes`) is NOT required here —
  this is a code fix that *Closes #5728* at merge; the verification is a confidence check, not the
  remediation.
- [ ] Soak (see Follow-Through): `scheduled-community-monitor` posts `ok` (no `missed` attributable
  to delivery) for **7 consecutive daily fires** post-deploy → then close any soak tracker.

## Domain Review

**Domains relevant:** Engineering (CTO)

### Engineering (CTO)
**Status:** reviewed (inline, plan-author CTO-class analysis; deepen-plan + plan_review provide the
multi-agent depth)
**Assessment:** This is a substrate observability fix bounded to `_cron-shared.ts` +
`cron-community-monitor.ts` (+ output-aware cohort) + one TF file (conditional) + ADR/runbook. Key
architectural risk — re-introducing the ADR-033-I8-rejected `in_progress` mechanism — is the
explicit premise-validation finding above and is forbidden by AC. Retry-memoization correctness
(the final-attempt gate) is the second risk, mitigated by following the `cron-stale-deferred-scope-outs`
precedent verbatim. Blast radius of the cohort rollout (double-post / cohort heartbeat semantics)
is gated by the per-handler mutual-exclusion AC.

### Product/UX Gate
Not applicable — no UI-surface file in Files to Create/Edit (the mechanical UI-surface scan finds
no `components/**`, `app/**/page.tsx`, `app/**/layout.tsx`). Product domain = **NONE**.

## Infrastructure (IaC)

### Terraform changes
`apps/web-platform/infra/sentry/cron-monitors.tf` — **conditional** (only if Phase 0 confirms H1
runs > 60 min): adjust `scheduled_community_monitor.checkin_margin_minutes` within the claude-eval
cohort rationale. No new resource, no new provider, no new variable. Provider: `jianyuan/sentry`
(pinned in `versions.tf`); secrets unchanged.
### Apply path
Cloud-init/CI auto-apply: this root is auto-applied on merge to main by
`.github/workflows/apply-sentry-infra.yml` (TF header lines 13-15). No operator `terraform apply`,
no SSH. If no margin change is needed (expected), no TF diff at all.
### Distinctness / drift safeguards
`dev != prd` N/A (single Sentry org); the provider is import-only/beta for some resource classes —
a margin field change is an in-place update (no taint). `sentry-monitor-iac-parity.test.ts` guards
slug parity so the cohort rollout cannot drop a monitor.
### Vendor-tier reality check
N/A — `sentry_cron_monitor` margin is not a paid-tier-gated attribute; no `count` gate needed.

## Observability

```yaml
liveness_signal:
  what: "scheduled-community-monitor Sentry cron monitor — now delivery-robust: a bounded-retry terminal POST + a final-attempt error heartbeat on the throw path"
  cadence: "daily 08:00 UTC (cron 0 8 * * *)"
  alert_target: "Sentry cron monitor scheduled-community-monitor (checkin_margin 60m); backstop cron-inngest-cron-watchdog"
  configured_in: "apps/web-platform/infra/sentry/cron-monitors.tf:288 + _cron-shared.ts postSentryHeartbeat"
error_reporting:
  destination: "Sentry (?status=error check-in on throw-path final attempt) + reportSilentFallback (cron-sentry-heartbeat/fetch) after bounded POST retries exhaust + routine_runs.error_summary (run-log middleware)"
  fail_loud: true
failure_modes:
  - { mode: "inner step throws on final attempt", detection: "new catch posts ?status=error → monitor RED (not silent missed)", alert_route: "Sentry cron monitor" }
  - { mode: "heartbeat POST transiently 5xx/timeout", detection: "bounded retry recovers; if all fail, reportSilentFallback event", alert_route: "Sentry issue feature:cron-sentry-heartbeat op:fetch" }
  - { mode: "run SIGKILLed mid-flight (deploy swap/OOM)", detection: "no in-process signal possible — Sentry missed-checkin margin (honest for a killed run); frequency reduced by ADR-076/#5686", alert_route: "Sentry missed check-in + cron-inngest-cron-watchdog" }
  - { mode: "run duration > 60-min margin (H1)", detection: "routine_runs.duration_ms (Phase 0 + ongoing)", alert_route: "Sentry missed check-in; margin re-eval if confirmed" }
logs:
  where: "Better Stack (claude-eval stdout/stderr tail, table per runbooks/betterstack-log-query.md; query creds in Doppler prd_terraform) + routine_runs (Supabase, terminal row per run)"
  retention: "routine_runs indefinite (operational audit, low volume); Better Stack per warehouse retention"
discoverability_test:
  # Secret-free, no-SSH reachability probe of the Sentry Crons monitor REST path
  # (EU regional host, org in path — the live-verified shape mirrored by
  # scripts/followthroughs/community-monitor-checkin-soak-5728.sh). Unauthenticated
  # returns 401, which PROVES the monitor endpoint resolves (DNS + TLS + routing) —
  # the #4148 typo'd-hostname class. An operator adds `-H "Authorization: Bearer
  # $SENTRY_AUTH_TOKEN"` to get 200 + the actual check-in timeline; a read-only
  # routine_runs query (SELECT status,duration_ms,trigger_source,error_summary FROM
  # routine_runs WHERE routine_id='cron-community-monitor' ORDER BY started_at DESC
  # LIMIT 14) over Doppler DATABASE_URL_POOLER is the secondary, authoritative
  # liveness+duration layer.
  command: curl -sS -o /dev/null -w "%{http_code}" --max-time 10 https://de.sentry.io/api/0/organizations/jikigai-eu/monitors/scheduled-community-monitor/checkins/
  expected_output: "401"
```

## Architecture Decision (ADR/C4)

### ADR
**Amend ADR-033 invariant I8** (`/soleur:architecture`) — add a dated note recording the #5728
**heartbeat-delivery-guarantee** gap-closure: I8 reasoned about classifying fatal-vs-benign non-zero
*exits* and assumed the run reaches the heartbeat step; #5728 is the orthogonal *never-delivered*
case (kill / throw / dropped POST). The `in_progress → ok/error` two-phase check-in **remains
rejected**; the gap is closed by (i) final-attempt error heartbeat on the throw path, (ii) bounded
POST retry, (iii) ADR-076/#5686 reducing SIGKILLs. Accepted residual: a genuinely killed run reads
`missed` (honest). This is an amendment, not a new ADR — I8 is the heartbeat contract invariant.

### C4 views
**No C4 impact.** Checked all three model files (`model.c4`, `views.c4`, `spec.c4`): the C4 models
the `inngest` container + its edges (`model.c4:155-165, 245-252`) but does **not** model Sentry or
Better Stack as external systems — the platform→Sentry heartbeat check-in edge is below the modeled
granularity. Enumeration for this change: **external human actors** — none new (operator reads
Sentry alerts, unchanged); **external systems/vendors** — Sentry (monitoring sink) and Better Stack
(log warehouse, read-only in Phase 0) both pre-exist and are unmodeled-by-choice, neither
added/removed by this fix; **containers/data-stores** — `routine_runs` (read-only) and `inngest`
unchanged; **access relationships** — the existing platform→Sentry check-in edge is *hardened*
(retry + guaranteed terminal), no new/changed ownership or sharing edge. A delivery-robustness bug
fix to a pre-existing edge does not warrant adding the edge to C4.

### Sequencing
The ADR-033 I8 amendment + runbook H11 ship **in this PR** with the code fix (the decision is true
the moment the delivery-guarantee lands; no soak-gated status flip on the ADR itself).

## Follow-Through Enrollment (soak)

The post-deploy soak criterion ("`scheduled-community-monitor` posts `ok` with no delivery-attributable
`missed` for 7 consecutive daily fires") is time-gated, so enroll it rather than leaving it to memory:
- **Script:** `scripts/followthroughs/community-monitor-checkin-soak-5728.sh` — exit 0 when the
  Sentry checkins for `scheduled-community-monitor` show no `missed` (delivery-class) since
  `deploy+0`, mirroring `scripts/followthroughs/reconcile-ff-only-sentry-4977.sh` with `start=`
  pinned strictly after deploy.
- **Tracker directive:** `<!-- soleur:followthrough script=scripts/followthroughs/community-monitor-checkin-soak-5728.sh earliest=<deploy+7d> secrets=SENTRY_AUTH_TOKEN -->` + `follow-through` label on #5728 (or a soak tracker issue).
- **Sweeper secrets:** wire `SENTRY_AUTH_TOKEN` into `.github/workflows/scheduled-followthrough-sweeper.yml` if not already present.

## Open Code-Review Overlap
None. `gh issue list --label code-review --state open` returned no open issue whose body references
`_cron-shared.ts`, `cron-community-monitor.ts`, or `cron-monitors.tf`.

## Files to Edit
- `apps/web-platform/server/inngest/functions/_cron-shared.ts` — bounded POST retry in
  `postSentryHeartbeat`; new shared final-attempt throw-path catch helper.
- `apps/web-platform/server/inngest/functions/cron-community-monitor.ts` — adopt the catch helper
  (final-attempt-gated `?status=error`); thread `attempt`/`maxAttempts`.
- **Output-aware cohort rollout** (adopt the shared catch helper; verify ≤1 heartbeat/terminal path):
  `cron-roadmap-review.ts`, `cron-content-generator.ts`, `cron-competitive-analysis.ts`,
  `cron-campaign-calendar.ts`, `cron-growth-audit.ts`, `cron-growth-execution.ts`,
  `cron-seo-aeo-audit.ts` (the `resolveOutputAwareOk` producers sharing the same try/finally shape;
  final list confirmed at /work by grepping `resolveOutputAwareOk` + the try-with-only-finally pattern).
- `apps/web-platform/test/server/inngest/cron-shared.test.ts` — POST-retry tests.
- `apps/web-platform/test/server/inngest/cron-community-monitor.test.ts` — throw-path heartbeat tests.
- `apps/web-platform/infra/sentry/cron-monitors.tf` — **conditional** margin (only if H1 confirmed).
- `knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md` — add H11.
- `knowledge-base/engineering/architecture/decisions/ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md` — amend I8.

## Files to Create
- `scripts/followthroughs/community-monitor-checkin-soak-5728.sh` — soak probe (see Follow-Through).

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder, or
  omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above: threshold `aggregate pattern`.)
- **Do not reach for `in_progress`** — it is ADR-033-I8-rejected (and the `|| true` two-step is a
  documented silent-fail trap). The fix is single-POST delivery robustness, not a check-in state machine.
- **Step memoization across `retries: 1`:** a heartbeat posted on a non-final failing attempt
  replays and never emits the recovered `ok`. Skip the *whole* `step.run` on non-final failure
  (not just the POST) — mirror `cron-stale-deferred-scope-outs.ts:400-413`.
- **Bound the POST retry** strictly under the Inngest step budget and the 60-min margin — an
  unbounded/long retry would itself push the check-in past the margin (re-creating H1).
- **No double-post:** the new catch and the existing success-path heartbeat must be mutually
  exclusive — exactly one check-in per terminal run.
- **Verify the Sentry check-in ingest contract** (Phase 0.4 WebFetch) before writing POST code —
  do not assume the `?status=` enum or the non-2xx semantics from memory.
- **SIGKILL has no in-process fix** — Phase 2's catch covers throws, not kills; the kill class is
  ADR-076/#5686's job. Don't promise the catch fixes the deploy-kill case.
