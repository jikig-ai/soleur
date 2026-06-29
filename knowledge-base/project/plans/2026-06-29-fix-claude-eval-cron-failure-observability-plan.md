---
title: "fix: make claude-eval cron failures observable (#5674)"
issue: 5674
type: bug
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
date: 2026-06-29
branch: feat-one-shot-5674-cron-eval-failure-observability
---

# fix: make claude-eval cron failures observable (#5674)

## Overview

On 2026-06-29 ~10:36Z the operator Anthropic API credit balance hit zero. Every
`claude-eval` cron firing after that received **`Credit balance is too low`**
(HTTP 400 `invalid_request_error`) from the Anthropic API and produced no work.
The fleet silently no-op'd with **green** Sentry monitors and `status=completed`
`routine_runs` rows for an unknown window. The balance was topped up (operator),
but the incident exposed three durable observability bugs in the cron substrate:

1. **The real failure reason is dropped.** On a claude-eval non-zero exit the
   four "best-effort" crons emit a Sentry warning whose `extra` carries only
   `{ exitCode, durationMs }` — **not** the captured `stdoutTail` where
   `Credit balance is too low` actually lives. The `routine_runs.error_summary`
   is `null` because the handler returns `{ ok: false }` *without throwing*, and
   the run-log middleware only writes `error_summary` when the handler throws.
2. **Inconsistent heartbeat policy masks failures.** Four crons post a **green**
   Sentry check-in regardless of the claude-eval exit code (logging
   `"cron monitor stays green (liveness, not success)"`, op
   `claude-eval-nonzero-noop` for the three audits / `claude-eval-nonzero-nofix`
   for bug-fixer). Eight others (the `resolveOutputAwareOk` cohort) flip the
   monitor red only when their output issue is absent. So the Sentry cron monitors
   are an unreliable success signal — `cron-agent-native-audit` claude-eval
   *failed* at 10:36:25 yet its monitor `scheduled-agent-native-audit` posted `ok`
   at 10:36:47.
3. **No alert before the whole fleet dies.** Nothing pages when the operator
   Anthropic credit runs low/out. The exhaustion was found only by manual Better
   Stack log spelunking, and the egress firewall (#5413) was wrongly suspected
   for ~an investigation cycle because the real cause (billing) was invisible.

This plan fixes all three in the cron substrate
(`_cron-claude-eval-substrate.ts`, `_cron-shared.ts`), the run-log middleware,
the four masked cron handlers, and adds one new probe cron + Sentry monitor.

### Premise Validation (Phase 0.6)

- **Issue #5674** — `gh issue view 5674`: OPEN, `priority/p1-high`, `type/bug`,
  `domain/engineering`. Not closed by a merged PR. Premise holds.
- **Cited files exist on this branch.**
  `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts`
  (827 lines) and `_cron-shared.ts` (719 lines, `postSentryHeartbeat` at L173)
  confirmed. The masking op `claude-eval-nonzero-noop` exists verbatim in
  `cron-ux-audit.ts:379`, `cron-legal-audit.ts:313`,
  `cron-agent-native-audit.ts:296`; the sibling `claude-eval-nonzero-nofix` in
  `cron-bug-fixer.ts:793`. The `"cron monitor stays green (liveness, not
  success)"` literal is in all four.
- **Mechanism vs ADR corpus.** ADR-033 (`...child-process-spawn.md`) governs the
  spawn substrate. Invariant **I2** (operator `ANTHROPIC_API_KEY` only — never
  founder BYOK; enforced by `byok-audit-writer-sweep.test.ts`) is load-bearing
  for the new probe: the canary MUST use the operator key the substrate already
  holds, never `runWithByokLease`. **I5** (deterministic stdout capture for
  step memoization) is the ADR the issue cites for "stdout dropped"; the literal
  redaction discipline lives in `lib/safety/redaction-allowlist.ts`
  (`redactGithubSourcedText`) + the substrate's `redactToken`. The unified
  heartbeat policy is a *new* cross-cutting invariant ADR-033 does not yet state
  → this plan amends ADR-033 (see `## Architecture Decision`).
- **Anthropic balance API premise (verified live, WebFetch of
  `platform.claude.com/docs/en/api/usage-cost-api`, 2026-06-29):** there is **NO
  remaining-credit-balance / prepaid-balance endpoint.** The Admin Usage API
  (`GET /v1/organizations/usage_report/messages`) and Cost API
  (`GET /v1/organizations/cost_report`) report *consumption* and *spend* only,
  require an **Admin API key** (`sk-ant-admin01-…`, distinct from
  `ANTHROPIC_API_KEY`, sent via `x-api-key`), and have no notion of remaining
  credit. Therefore "low-balance, before exhaustion" cannot be read directly —
  it must be **inferred** (cheap canary that detects the credit-balance 400, or
  spend-rate vs an operator-set budget). This reshapes Part 3 (see below).

## Research Reconciliation — Spec vs. Codebase

No `spec.md` exists for this branch (direct one-shot entry). The issue body is
the spec; the only divergence found is the Part-3 "balance alert" premise:

| Issue claim | Codebase / API reality | Plan response |
| --- | --- | --- |
| "Add an Anthropic balance/usage alert (low-balance threshold → Sentry)" | No balance endpoint exists; only Admin usage/cost (spend) under a separate `sk-ant-admin` key, and consumption per-message via `response.usage`. | **Ship the canary, defer the spend-trend.** Detector = a **canary probe** (1-token message on the existing operator key) that pages on the `Credit balance is too low` 400 — no new secret, catches exhaustion within one cron interval (≤1h). The spend-rate "before exhaustion" alert via the Admin cost API is **cut from this PR to a tracked follow-up** (`Ref #5674`): it needs a *new* `sk-ant-admin` secret AND an operator-set monthly budget (no sensible default — every operator's spend differs), making it a distinct secret-gated feature. Shipping it half-configured would false-alarm or never fire. The canary-at-exhaustion residual ("we alert *at* zero, not *before*") is named as a conscious scope-out in `## User-Brand Impact`. |
| "stdout dropped per ADR-033 I5" | ADR-033 I5 is about *deterministic capture for memoization*, not redaction. The tails ARE captured (`spawnClaudeEval` builds `stdoutTail`/`stderrTail`); they are dropped only at the *Sentry-extra* layer of the 4 masked crons. | Fold the captured tails into the Sentry extra at the 4 masked sites, **scrubbed at write time by a new `formatTailForSentry`** — do NOT assume they are pre-scrubbed. **Correction (verify-negative pass):** today the tails reaching any Sentry extra are processed by `redactToken` (installation-token only); the multi-secret scrubber (`redactGithubSourcedText`) is applied **only** in `formatTailForIssue` for the GitHub issue body, NOT the Sentry path. So the new `sk-ant`-bearing tail sink is a *real* multi-secret leak we are introducing unless scrubbed — see Security finding F1 (the existing `resolveOutputAwareOk:573-576` extra is already exposed this way and is retrofitted in Phase 1). |

## User-Brand Impact

**If this lands broken, the user experiences:** a recurrence of the 2026-06-29
incident — the entire autonomous claude-eval fleet (bug-fixer, content,
roadmap-review, audits, community-monitor, …) silently produces nothing for
hours while every dashboard shows green, and the operator burns an investigation
cycle chasing the wrong cause (the egress firewall, as happened). The product
*is* the autonomous fleet; a silent fleet-wide stall with green monitors is a
direct brand-survival failure.

**If this leaks, the user's data/secrets are exposed via:** the new stdout/stderr
tail folded into Sentry events and `routine_runs.error_summary`. A claude crash
stack can spill `ANTHROPIC_API_KEY` (`sk-ant-…`), installation tokens, or PII.
Exposure vector = an unscrubbed tail reaching a durable Sentry extra or the WORM
`routine_runs` row. Mitigated by routing every new tail sink through the
canonical multi-secret scrubber (`redactGithubSourcedText` / `redactCommandForDisplay`)
*before* it lands, mirroring `formatTailForIssue` and the run-log `errorSummary`
scrubber.

**Residual the user still carries after this ships (conscious scope-out):** the
canary detects credit exhaustion **at zero**, within one hourly interval — not
*before* it. So the user can still hit a ≤1-hour window where the fleet no-ops
before the page fires; they just no longer burn an investigation cycle (the page
names the cause: credit exhausted). True *pre-exhaustion* warning needs the
deferred spend-vs-budget alert (`Ref #5674` follow-up: new `sk-ant-admin` secret +
operator budget). This is the right trade: ship the honest at-exhaustion signal
now, not a guessed pre-exhaustion threshold that false-alarms.

**Second residual (heartbeat policy, R1 → classify-fatal):** a claude-eval that
exits non-zero for a *benign* reason (e.g. `--print` hitting max-turns with no
artifact, which is a healthy, frequent outcome) deliberately keeps its monitor
**green** — only *fatal* classes (credit/auth/spawn-error) flip it red. So a user
cannot read "all non-zero = red"; the contract is "fatal-class non-zero = red,
benign non-zero = green + queryable reason in `routine_runs`." This is the
evidence-backed reversal of a naive flip-all (see Risk R1 + the #4730 precedent).

**Brand-survival threshold:** single-user incident. (`requires_cpo_signoff: true`
— CPO sign-off at plan time; `user-impact-reviewer` at PR review per the review
skill's conditional-agent block.) **CPO sign-off explicitly covers the R1
classify-fatal decision, which departs from the issue's literal "non-zero must not
post green" text** — see Risk R1.

## Implementation Phases

### Phase 1 — Capture the failure reason (Part 1) + unify the run-log

**Goal:** the `Credit balance is too low` line reaches Sentry AND
`routine_runs.error_summary` for every claude-eval cron, regardless of whether
the handler throws.

**Files to Edit:**

- `apps/web-platform/server/inngest/functions/_cron-shared.ts`
  - Add `formatTailForSentry(tail?: string): string | undefined` — applies the
    canonical multi-secret scrubber (`redactGithubSourcedText`) + a bounded
    `slice(-N)` (reuse the existing 4000-char Sentry bound in
    `resolveOutputAwareOk`). Single source of truth so the 4 masked sites and
    the **8** output-aware sites cannot drift on redaction discipline.
  - **Security F1 retrofit (pre-existing leak, fix in this PR):** the existing
    `resolveOutputAwareOk` builds its `scheduled-output-missing` Sentry extra from
    `stdoutTail`/`stderrTail` scrubbed by `redactToken` **only** (installation
    token; `_cron-shared.ts:573-576`) — an `sk-ant-…` in a crash stack reaches
    Sentry today. Route those two lines through the new `formatTailForSentry`.
    This is a 2-line internal change to *one* helper (no 8-site creep) and closes
    a durable multi-secret leak (`hr-write-boundary-sentinel-sweep`).
  - Define a shared return type both resolvers emit, so all ~13 eval crons get
    equal `routine_runs` fidelity through one contract:
    `type EvalHeartbeatDecision = { ok: boolean; errorSummary?: string;
    sentryExtra: Record<string, unknown> }`.
  - **Extend `resolveOutputAwareOk` to also emit `errorSummary`** (its
    output-missing message, scrubbed) so the 8 output-aware crons populate
    `routine_runs.error_summary` on a red run — not just the 4 masked ones.
  - Add the best-effort resolver `resolveBestEffortEvalOk(spawnResult):
    EvalHeartbeatDecision`. It now does **real classify-fatal work** (see Phase 2)
    — fatal-class markers → `ok:false`, benign non-zero → `ok:true` + reason — so
    it is no longer a thin `ok = exitCode===0` wrapper (this answers the
    simplicity objection: the resolver earns its existence). Both resolvers return
    the redaction-scrubbed tails via `formatTailForSentry` in `sentryExtra`.
- `apps/web-platform/server/inngest/middleware/run-log.ts`
  - **CRITICAL — gate ONLY the thrown path (this corrects a P0 regression the
    first draft of this plan codified).** Inngest retries **only on a thrown
    error**; a clean `return { ok:false }` is *terminal* (no retry). Every
    claude-eval cron is `retries:1` ⇒ `maxAttempts=2`, and a returned failure
    lands at `attempt=0` (NOT final). The original draft's
    `if (failed && !isFinalAttempt) return` would therefore **drop the write
    entirely** for the exact case we are trying to record — and there is no retry
    to fix it. Required shape:
    ```ts
    const threw = result.error != null;
    const data = result.data as { ok?: boolean; errorSummary?: string } | undefined;
    const failed = threw || data?.ok === false;
    const isFinalAttempt = attempt >= maxAttempts - 1;
    if (threw && !isFinalAttempt) return; // ONLY thrown errors retry; a returned ok:false is terminal → must write now
    ```
    The final-attempt gate guards the **throw** path only (a thrown error on a
    non-final attempt will retry, so suppress the interim write). A returned
    `{ ok:false }` is never retried and MUST be written on the spot.
  - Derive `error_summary` from whichever source is present, routed through one
    helper doing `firstLine → redact → truncate`:
    `p_error_summary: threw ? errorSummary(result.error) :
    (data?.ok === false ? formatErrorSummary(data?.errorSummary) : null)` where
    `formatErrorSummary` does `redactCommandForDisplay(firstLine(s)).slice(0,
    ERROR_SUMMARY_MAX)` and falls back to `"cron returned ok:false (see Sentry)"`
    when `errorSummary` is absent. Keep the existing `errorSummary()` scrub path
    for thrown errors.
  - **Scope correction (was overstated as "all 13 crons").** This change records
    failures for the crons that *return* `{ ok:false }` on real failure. Today
    that is the **8 output-aware crons** immediately (they already return
    `{ ok:false }` when output is absent). The **4 masked crons return
    `{ ok:true }` unconditionally** and only begin returning `{ ok:false }` once
    Phase 2 lands — so Phase 1 alone does NOT cover them. (Also: the middleware
    runs for **every** `ROUTINE_METADATA` cron, ~40, not 13 — the `ok:false`
    contract widening is fleet-wide; document it as such, see Observability.)
  - **Document the widened contract at the write site + ADR:** for any
    `ROUTINE_METADATA` cron, a returned `data.ok === false` now means *failed*.
    Add a cross-consumer sweep (`hr-type-widening-cross-consumer-grep`): grep all
    cron handlers for `return { ok:` to confirm none returns `ok:false` as a
    benign sentinel that this would mis-record (the classify-fatal design ensures
    benign non-zero returns `ok:true`, so this holds — but verify at /work).

### Phase 2 — Unify the heartbeat policy via **classify-fatal** (Part 2)

**Goal:** a claude-eval that fails for a *fatal* reason (credit exhausted, auth
revoked, spawn error) must flip its Sentry monitor red and record the reason — a
*benign* non-zero exit (e.g. `--print` hitting max-turns with no artifact) must
NOT page.

**Decision — classify-fatal, NOT flip-all (see Risk R1 + `## Architecture
Decision`).** A naive "every non-zero exit ⇒ red" reverses a settled fix: the
2026-06-01 bug-fixer plan (incident `5127648` / #4730 / PR #4727) *decoupled* the
heartbeat from `spawnResult.ok` precisely because `claude --print` exits non-zero
on healthy max-turns runs and was daily-false-paging. Flip-all would reintroduce
that alert-fatigue AND pollute the WORM `routine_runs` with false-`failed` rows.
Instead, `resolveBestEffortEvalOk(spawnResult)` classifies the captured tail:

- **fatal** → `ok:false` (monitor red + `routine_runs.failed` + scrubbed reason):
  body/tail matches the credit marker `/credit balance is too low/i`, an
  auth/401/`invalid x-api-key` marker, OR a spawn fault (`exitCode === -1`,
  `ENOENT`/`EACCES`, `abortedByTimeout`).
- **benign** → `ok:true` (monitor stays green, liveness) **plus** the existing
  `warnSilentFallback` + a scrubbed tail in `sentryExtra` and `errorSummary` so
  the reason is queryable in `routine_runs` even on a green run: any other
  non-zero exit (max-turns notice, clean no-artifact).

**Single source of truth for the fatal markers:** the same matcher the Part-3
canary uses for `/credit balance is too low/i` — define it once in
`_cron-shared.ts` and import it in both the resolver and the probe, so the credit
pattern cannot drift.

The 8 output-aware crons are already honest (output present ⇒ green; output absent
+ non-zero ⇒ red); they are left as-is for the heartbeat but gain
`routine_runs.error_summary` via the Phase-1 `resolveOutputAwareOk` extension.

**Files to Edit (the 4 masked crons):**

- `apps/web-platform/server/inngest/functions/cron-agent-native-audit.ts`
  (non-zero block ~L279-313, final heartbeat ~L313, `return { ok: true }` ~L316)
- `apps/web-platform/server/inngest/functions/cron-legal-audit.ts`
  (non-zero block ~L296-323, final heartbeat ~L330)
- `apps/web-platform/server/inngest/functions/cron-ux-audit.ts`
  (non-zero block ~L361-389, step-9 heartbeat ~L412)
- `apps/web-platform/server/inngest/functions/cron-bug-fixer.ts`
  (non-zero block ~L786-803 `claude-eval-nonzero-nofix`; the **multiple**
  `ok:true` heartbeats/returns at ~L819/L860/L901 that fire on a non-zero/no-PR
  run — **audit every return site**, not just the first; bug-fixer has the
  highest healthy-non-zero frequency so its benign path MUST stay green)

For each: replace the `if (!spawnResult.ok)` warn-then-green pattern with the
shared `resolveBestEffortEvalOk(spawnResult)` call, then
`postSentryHeartbeat({ ok: decision.ok, … })` and
`return { ok: decision.ok, errorSummary: decision.errorSummary }`. On a
**fatal** class the resolver returns `ok:false` + scrubbed reason → monitor flips
red AND the reason lands in `routine_runs` (Phase 1); on a **benign** non-zero it
returns `ok:true` + reason (green liveness, queryable reason — no page). The
`abortedByTimeout` infra-fault path is folded into the *fatal* class (keep a
single signal; do not double-signal with the old strict early-return). Update the
now-stale "stays green (liveness, not success)" comment blocks to describe the
classify-fatal policy and cite this plan + the ADR amendment + the #4730
precedent.

> **Reviewer caveat (Risk R1 — CPO sign-off required):** classify-fatal departs
> from the issue's *literal* text ("a non-zero exit must NOT post a green
> check-in") by keeping benign non-zero exits green. This is deliberate and
> evidence-backed (the #4730 daily-false-page incident the issue author may not
> have had in view). The departure is gated on CPO / issue-author sign-off (the
> plan already carries `requires_cpo_signoff: true`). /work MUST still pull Better
> Stack history for the 4 crons to *confirm* the benign-non-zero frequency that
> motivates the carve-out and to validate the fatal-marker set against real tails
> (the substrate logs `op=claude-eval-nonzero-noop exitCode=…`).

### Phase 3 — Anthropic credit/usage probe (Part 3)

**Goal:** page Sentry the moment the operator Anthropic key cannot do work
(credit exhaustion / auth failure), and — when the optional Admin key is
configured — warn on month-to-date spend approaching an operator budget.

**Files to Edit (prerequisite — widen the shared transport so the canary can
read the failure body):**

- `apps/web-platform/server/inngest/functions/_cron-shared.ts` —
  `postAnthropicMessage` (L277-318) currently throws `Anthropic API ${resp.status}`
  at L311 and **discards the response body**. The canary needs the body to match
  `/credit balance is too low/i`, so this is a blocker, not an enhancement. Widen
  it to surface a **bounded, redaction-scrubbed** body on a non-ok response — e.g.
  throw a typed `AnthropicApiError` carrying `{ status, bodyExcerpt }` (excerpt =
  `formatTailForSentry(rawBody)?.slice(0, 600)`), or append the scrubbed excerpt
  to the message. **Cross-consumer sweep** (`hr-type-widening-cross-consumer-grep`):
  the two existing callers — `cron-compound-promote.ts:438` and
  `cron-weekly-release-digest.ts:328` — and their tests read only `.message` /
  status today, so appending is backward-compatible; verify and update both
  call-site tests. The L306-307 comment warning that callers/tests depend on the
  thrown shape MUST be updated to document the new shape.

**Files to Create:**

- `apps/web-platform/server/inngest/functions/cron-anthropic-credit-probe.ts`
  - Hourly Inngest cron (`{ cron: "<:NN> * * * *" }` — pick an off-peak minute,
    document in ROUTINE_METADATA `scheduleLabel`). Pure-TS probe, **no
    claude-eval spawn**.
  - **Canary:** call `postAnthropicMessage({ apiKey:
    process.env.ANTHROPIC_API_KEY, model: <cheapest tier from
    `lib/ai/model-tiers.ts`, NOT a raw model literal — `RAW_MODEL_LITERAL` guard>,
    maxTokens: 1, messages: [{ role: "user", content: "ping" }] })` (reuse the
    now-widened shared transport). Branch on the error the transport throws:
    - body matches the **shared fatal credit marker** `/credit balance is too
      low/i` (or `invalid_request_error` billing variant) →
      `reportSilentFallback({ op: "anthropic-credit-exhausted" })` +
      `postSentryHeartbeat({ ok: false, sentryMonitorSlug:
      "scheduled-anthropic-credit-probe" })` → monitor red, pages.
    - `401` / auth error → same page, `op: "anthropic-key-invalid"`.
    - **transient/unclassified** (`429`, `500`, `529 overloaded`, network/DNS,
      any body NOT matching a known fatal marker) → **re-throw** so Inngest
      retries and the missed-checkin margin backstops; do NOT page as
      credit-exhausted (a 529 is not an empty wallet — false-paging here would
      itself be the alert-fatigue bug). Only *classified* fatal bodies page.
    - clean reply → `ok:true` heartbeat (liveness AND success: a 1-token ping IS
      the success contract here, unlike the audit crons).
    The probe MUST NOT consult any captured stdout (it is its own request).
  - **Spend trend (cut to follow-up — NOT in this PR).** The month-to-date
    spend-vs-budget alert via the Admin `cost_report` API is deferred to a tracked
    follow-up (`Ref #5674`): it requires a *new* `sk-ant-admin` secret and an
    operator-set `ANTHROPIC_MONTHLY_BUDGET_USD` (no sensible default), making it a
    distinct secret-gated feature. The probe ships **canary-only**; do NOT add an
    `ANTHROPIC_ADMIN_KEY` branch in this PR (it would be dead, untested code). The
    follow-up issue records the re-evaluation trigger "operator wants
    spend-before-exhaustion alerting" and the no-balance-endpoint constraint.
  - **Redaction:** the operator key is a secret; rely on the widened transport's
    redact-then-throw (`formatTailForSentry` on the body excerpt). Never
    interpolate the key into a log/Sentry payload.

**Files to Edit (wire the new cron):**

- `apps/web-platform/app/api/inngest/route.ts` — import `cronAnthropicCreditProbe`
  and add it to the `serve({ functions: [...] })` array (mirrors
  `cronEmailIngressProbe` at L34/L131).
- `apps/web-platform/server/inngest/cron-manifest.ts` — add
  `"cron-anthropic-credit-probe"` to `EXPECTED_CRON_FUNCTIONS`.
- `apps/web-platform/server/inngest/routine-metadata.ts` — add a `ROUTINE_METADATA`
  entry: `{ description: "Hourly 1-token canary on the operator Anthropic API key;
  pages Sentry when credit is exhausted or the key is invalid.", domain:
  "Engineering", ownerRole: "CTO", scheduleLabel: "Hourly (:NN)", manualTrigger:
  "allowed" }`. (Description reflects the canary-only scope — spend-trend cut to a
  follow-up. `routine-metadata-parity.test.ts` + the non-empty-`description` guard
  force this edit; keep the description 10–160 chars.)
- `apps/web-platform/infra/sentry/cron-monitors.tf` — add a
  `sentry_cron_monitor` resource `scheduled_anthropic_credit_probe`. It is a
  **small / pure-TS Inngest cron → 30-min `checkin_margin_minutes`** (NOT the
  60-min claude-eval cohort — it has no 50-min budget; the file's CLAUDE-EVAL
  COHORT note explicitly carves out small crons at 30). `max_runtime_minutes`:
  reuse the small-cron default. Auto-applied on push to main via
  `apply-sentry-infra.yml` (no operator step).

**Files to Edit (tests that count the surface):**

- `apps/web-platform/test/server/inngest/function-registry-count.test.ts` —
  bump `routeEntries.length` `toBe(56)` → `toBe(57)` (L135) and any
  slug-map / tf-monitor count assertions that enumerate the registered set.
  Run the suite to discover the exact assertions (the test cross-checks the
  route functions array, the `cron-*.ts` file list, the slug map, and the
  `cron-monitors.tf` resource set — all four must include the new cron).

### Phase 4 — Docs, ADR amendment, C4 review

- Amend ADR-033 (`## Decision` + `## Alternatives Considered`) with the unified
  heartbeat invariant and the no-balance-endpoint canary decision (see ADR/C4
  section). Update the cron substrate runbook
  (`knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md` — the
  file `ensureScheduledAuditIssue` already cites) with the new
  `anthropic-credit-exhausted` / `anthropic-key-invalid` Sentry ops and triage
  steps.

## Acceptance Criteria

### Pre-merge (PR)

1. **Reason reaches Sentry (fatal class).** A unit test drives
   `resolveBestEffortEvalOk` with a `SpawnResult` whose `stdoutTail` contains
   `"Credit balance is too low"` and a non-zero `exitCode`; asserts the returned
   `sentryExtra` carries the scrubbed tail substring and `ok === false`.
2. **Redaction holds.** `formatTailForSentry` test: an input tail containing a
   synthesized `sk-ant-<<placeholder>>` and an installation-token-shaped string
   returns a value with neither token present. (Use a non-alnum placeholder in
   the fixture per the synthetic-token push-protection Sharp Edge.) **Plus F1
   regression guard:** a `resolveOutputAwareOk` test asserts its
   `scheduled-output-missing` Sentry extra also passes through
   `formatTailForSentry` (no raw `sk-ant` in the extra) — locks the retrofit.
3. **run-log gates ONLY the thrown path (P0 regression guard).** A run-log
   middleware test with a `maxAttempts:2` cron:
   - result `{ error: null, data: { ok: false, errorSummary: "Credit balance is
     too low" } }` on **attempt 0 (NON-final)** → **WRITES** `p_status:"failed"`
     with a non-null scrubbed `p_error_summary` (a returned `ok:false` is terminal
     — it must NOT be suppressed by the final-attempt gate). This is the exact case
     the first draft got wrong; assert the write happens.
   - a **thrown** error on attempt 0 (non-final) → **NO** write (it will retry).
   - a thrown error on the final attempt → writes `failed`.
   - `{ ok: true }` → writes `completed` / `error_summary: null`.
4. **Classify-fatal: red on fatal, green on benign.** For the masked crons, handler
   tests assert: a `spawnResult` whose tail matches `/credit balance is too low/i`
   (or 401/auth, or spawn fault) → `postSentryHeartbeat({ ok:false })` and the
   handler returns `{ ok:false, errorSummary:<reason> }`; a `spawnResult` that
   exits **non-zero for a benign reason** (max-turns, no artifact) →
   `postSentryHeartbeat({ ok:true })` (monitor stays green) yet still surfaces the
   scrubbed reason via `warnSilentFallback` + `sentryExtra`. bug-fixer's benign
   no-PR path is covered explicitly (every return site).
5. **Canary pages on credit-balance 400, re-throws on transient.** A
   `cron-anthropic-credit-probe` test stubs the widened `postAnthropicMessage` to
   throw the typed error carrying a credit-balance body excerpt and asserts
   `postSentryHeartbeat({ ok:false })` + `reportSilentFallback({ op:
   "anthropic-credit-exhausted" })`; a `401` body → `op: "anthropic-key-invalid"`;
   a `529 overloaded` / `429` / unclassified body → **re-throws** (no page, lets
   Inngest retry); a clean reply → `ok:true`. (No `ANTHROPIC_ADMIN_KEY` branch
   exists — spend-trend is a follow-up.)
6. **Reason survives the scrub+slice pipeline.** A test feeds a tail where the
   `Credit balance is too low` line sits within the last-N window alongside a
   synthetic `sk-ant-<<…>>` and asserts the *reason* substring survives
   `formatTailForSentry` (scrub removes the secret but NOT the human-readable
   cause) — guards against an over-eager slice/redact dropping the very line we
   page on.
7. **Registry/monitor parity.** `function-registry-count.test.ts` and
   `routine-metadata-parity.test.ts` pass with the new cron present in the route
   array, `EXPECTED_CRON_FUNCTIONS`, `ROUTINE_METADATA`, and a
   `scheduled_anthropic_credit_probe` resource in `cron-monitors.tf`.
8. **Transport widening is backward-compatible.** The existing
   `postAnthropicMessage` callers (`cron-compound-promote`,
   `cron-weekly-release-digest`) and their tests still pass with the widened
   error shape (cross-consumer sweep).
9. **Typecheck:** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
   passes (NOT `npm run -w` — repo root declares no `workspaces`).
10. **No BYOK regression (ADR-033 I2):** `byok-audit-writer-sweep.test.ts` still
    passes — the new `cron-anthropic-credit-probe.ts` must NOT import
    `runWithByokLease` (it uses the operator `ANTHROPIC_API_KEY` only).
11. **R1 classify-fatal evidence + sign-off recorded.** The PR body records (a) the
    Better Stack healthy-non-zero-exit frequency per masked cron that justifies the
    benign carve-out, (b) the fatal-marker set validated against real tails, and
    (c) CPO / issue-author sign-off on the departure from the issue's literal
    "non-zero must not post green" text.

### Post-merge (automated, no operator step)

12. **Live monitor exists.** After `apply-sentry-infra.yml` runs on merge, the
    `scheduled-anthropic-credit-probe` monitor exists in Sentry (verify via the
    Sentry Crons monitors API, read-only — `hr-no-dashboard-eyeball-pull-data-yourself`).
    Automation: in-scope for `/soleur:ship` post-merge verification. No operator
    action — the canary needs no new secret (it reuses `ANTHROPIC_API_KEY`).

### Follow-up (tracked, NOT this PR)

13. **File the spend-trend follow-up issue** (`Ref #5674`): pre-exhaustion
    spend-vs-budget alert via the Admin `cost_report` API, requiring a new
    `sk-ant-admin` secret + operator `ANTHROPIC_MONTHLY_BUDGET_USD`. Records the
    no-balance-endpoint constraint and the re-evaluation trigger "operator wants
    spend-before-exhaustion alerting." Filed at /work, before PR-ready, per the
    defer-only-after-inline-triage gate.

## Architecture Decision (ADR/C4)

This plan changes a cross-cutting invariant (every claude-eval cron's
success/heartbeat contract) and adds a new monitoring substrate edge → ADR/C4
update is an in-scope deliverable, not a follow-up.

### ADR

- **Amend ADR-033** (`...child-process-spawn.md`). Add to `## Decision`:
  - *The classify-fatal heartbeat invariant* — a claude-eval non-zero exit whose
    captured tail matches a **fatal class** (credit exhausted, auth/401 revoked,
    spawn fault) MUST flip the Sentry monitor red and write `routine_runs.failed`;
    a **benign** non-zero exit (max-turns, clean no-artifact) MUST stay green
    (liveness) but still record the redaction-scrubbed reason in
    `routine_runs.error_summary`. This **supersedes and reconciles** the
    2026-06-01 decision (incident `5127648` / #4730 / PR #4727) that decoupled the
    heartbeat from `spawnResult.ok` — that fix correctly stopped benign
    max-turns false-pages; classify-fatal keeps that protection while restoring a
    red signal for the genuinely-fatal classes it over-suppressed.
  - *The widened `routine_runs` failure contract* — for any `ROUTINE_METADATA`
    cron, a handler that **returns** `data.ok === false` (without throwing) is
    recorded as `failed`, and the run-log middleware gates only the **thrown**
    path on the final-attempt retry window (a returned `ok:false` is terminal and
    is written immediately). The failure reason (scrubbed last-N stdout/stderr)
    MUST reach both Sentry and `routine_runs.error_summary`.
  - Add to `## Alternatives Considered`: (1) the "liveness, not success"
    unconditional green check-in (superseded) — wrong because credit-exhaustion
    non-zero was indistinguishable from clean-no-artifact at the monitor level;
    (2) **flip-all non-zero → red** (rejected) — reintroduces the #4730 daily
    false-page because `claude --print` exits non-zero on healthy max-turns runs;
    (3) the `in_progress → ok/error` two-phase check-in the issue offered (not
    needed once classify-fatal distinguishes the classes at the source).
  - Add the **no-balance-endpoint** finding: Anthropic exposes no remaining-credit
    endpoint; exhaustion is detected by an hourly 1-token canary on the operator
    key (ships now), and pre-exhaustion spend-trend by the Admin `cost_report` API
    under a separate `sk-ant-admin` key + operator budget (**deferred** follow-up,
    `Ref #5674`).

### C4 views

Read all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`)
before concluding impact — do NOT grep only the feature noun. Enumerate for this
change: external system = **Anthropic API** (the canary's outbound edge + the
existing claude-eval edge), external system = **Sentry Crons** (the monitor
sink whose semantics change), data store = **`routine_runs`** (now carries eval
`error_summary`). For each, confirm it is already modeled; if the Anthropic API
edge or the Sentry monitor edge is absent, add the element (`#external` tag if
outside the boundary) + the relationship edge + the `view … include` line in
`views.c4`, then run `c4-code-syntax.test.ts` + `c4-render.test.ts`. A "no C4
impact" conclusion MUST cite which of these three were checked and found
already-modeled.

### Sequencing

The ADR target state is true at merge (the policy and the probe ship together);
no soak gate.

## Infrastructure (IaC)

The only new infrastructure **in this PR** is the Sentry cron monitor (handled in
code via `cron-monitors.tf` + `apply-sentry-infra.yml` — no SSH, no manual
dashboard step, no new secret: the canary reuses the existing `ANTHROPIC_API_KEY`).
The spend-trend path's Doppler secret + admin-key mint are deferred to the
`Ref #5674` follow-up and described below for that issue's benefit only.

### Terraform changes

- `apps/web-platform/infra/sentry/cron-monitors.tf` — one new
  `sentry_cron_monitor.scheduled_anthropic_credit_probe` resource (30-min margin,
  small-cron tier). Provider: `jianyuan/sentry` (already pinned in this root).
  No new provider, no new `TF_VAR_*`. Auto-applied by `apply-sentry-infra.yml` on
  merge to main.

### Apply path

(b) cloud-init not applicable; the monitor is applied by the existing
`apply-sentry-infra.yml` push-to-main workflow. Zero downtime, blast-radius =
one new monitor resource (`-target` scoped by the workflow).

### Vendor-tier reality check

The Sentry Crons monitor is within the existing paid plan (42 monitors already
defined). No new tier gate. This PR provisions **no new secret**.

### Follow-up only — Admin-key mint (automation-feasibility, `Ref #5674`)

(For the deferred spend-trend issue, not this PR.) `ANTHROPIC_ADMIN_KEY` +
`ANTHROPIC_MONTHLY_BUDGET_USD` would be **runtime env secrets read by the cron**,
not Terraform vars (they do not enter `terraform.tfstate`), provisioned in Doppler
`dev` + `prd` (distinct projects per `hr-dev-prd-distinct-supabase-projects`).
Minting `ANTHROPIC_ADMIN_KEY` is a console action at `console.anthropic.com →
Settings → Admin keys`. **`automation-status: UNVERIFIED — the follow-up's /work
MUST run a Playwright attempt before any operator handoff.`** Per the operator-mint
Sharp Edge, a vendor dashboard under an authenticated session is presumptively
Playwright-automatable until a real attempt reaches a named human gate (MFA/TOTP);
do NOT pre-assume operator-only.

## Observability

```yaml
liveness_signal:
  what: scheduled-anthropic-credit-probe Sentry cron monitor (1-token canary)
  cadence: hourly
  alert_target: Sentry Crons (failure_issue_threshold=1) → GitHub issue
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf
error_reporting:
  destination: Sentry (reportSilentFallback / postSentryHeartbeat ok:false) + routine_runs.error_summary (run-log middleware)
  fail_loud: true  # FATAL-class claude-eval exit flips monitor red AND writes a failed routine_runs row with the scrubbed reason; benign non-zero stays green but still records the reason in routine_runs.error_summary
  note: postSentryHeartbeat swallows its own POST failure (_cron-shared.ts:216-218); the red flip is therefore margin-backed (missed-checkin within checkin_margin) not POST-guaranteed — acceptable because the Sentry-cron missed-checkin acts as the backstop signal.
failure_modes:
  - mode: Anthropic credit exhausted (whole fleet no-ops)
    detection: hourly canary 400 "Credit balance is too low"
    alert_route: Sentry op=anthropic-credit-exhausted + monitor red → GH issue
  - mode: Operator ANTHROPIC_API_KEY invalid/revoked
    detection: canary 401/auth error
    alert_route: Sentry op=anthropic-key-invalid + monitor red
  - mode: claude-eval FATAL-class non-zero exit on a masked cron (was silently green)
    detection: resolveBestEffortEvalOk classifies tail as fatal (credit/auth/spawn-fault)
    alert_route: postSentryHeartbeat ok:false + routine_runs.failed + scrubbed tail in Sentry extra
  - mode: claude-eval BENIGN non-zero exit (max-turns / no artifact)
    detection: resolveBestEffortEvalOk classifies tail as benign
    alert_route: stays green (liveness) + warnSilentFallback + reason in routine_runs.error_summary (queryable, non-paging — by design, see R1)
  - mode: probe transient/unclassified error (429/500/529/network)
    detection: error body matches no fatal marker
    alert_route: re-throw → Inngest retry; missed-checkin margin backstops (NOT paged as credit-exhausted)
  - mode: "[FOLLOW-UP Ref #5674] Spend approaching monthly budget (before exhaustion)"
    detection: Admin cost_report month-to-date >= threshold% of ANTHROPIC_MONTHLY_BUDGET_USD
    alert_route: deferred — needs sk-ant-admin secret + operator budget (not in this PR)
logs:
  where: Sentry events (durable) + routine_runs table (WORM, Supabase). NOT app stdout (Vector does not ship it).
  retention: Sentry default project retention; routine_runs per anonymise_routine_runs lifecycle.
discoverability_test:
  command: "curl -s -H \"Authorization: Bearer $(doppler secrets get SENTRY_AUTH_TOKEN --plain --project soleur --config prd)\" 'https://sentry.io/api/0/organizations/jikigai/monitors/' | jq -r '.[].slug' | grep -x scheduled-anthropic-credit-probe"
  expected_output: "scheduled-anthropic-credit-probe (monitor exists; token from Doppler, no SSH, no dashboard eyeball)"
  note: org slug + SENTRY_AUTH_TOKEN secret name to be confirmed against apply-sentry-infra.yml at /work; the form is runnable (auth header + jq -x exact match), not a placeholder.
```

## Domain Review

**Domains relevant:** Engineering, Finance.

### Engineering (CTO)

**Status:** reviewed (carried into plan by author; CTO is the owning role for the
cron substrate). **Assessment:** core change is in the Inngest cron substrate,
run-log middleware, and Sentry IaC. Primary risks are the heartbeat-flip
false-positive (R1) and redaction completeness on the new tail sinks. Both are
addressed by Phase-1 scrubber centralization and the R1 Better Stack check.

### Finance (CFO)

**Status:** reviewed (advisory) — **no Finance surface remains in this PR.** The
spend-trend alert (the only budget-monitoring surface) is cut to the `Ref #5674`
follow-up, so the `ANTHROPIC_MONTHLY_BUDGET_USD` knob, the 80% threshold question,
and the Admin cost-API read all move to that issue's CFO review. This PR creates
**no new recurring vendor expense** (the canary is ~1 token/hour ≈ negligible on
the existing operator key; no new secret). CFO sign-off is therefore not a blocker
for this PR; it is recorded as a deliverable on the follow-up.

### Product/UX Gate

**Tier:** none. **Mechanical UI-surface override:** no file in `## Files to Edit`
or `## Files to Create` matches a UI-surface path (`components/**`, `app/**/page.tsx`,
`app/**/layout.tsx`) — the only `app/` edit is `app/api/inngest/route.ts` (an API
route, not a page). Product = NONE; gate skipped.

## Test Scenarios

- **Credit-exhaustion replay (fatal):** feed a `SpawnResult` with the real
  incident stdout (`Credit balance is too low`, exit 1) through
  `resolveBestEffortEvalOk` → assert `ok:false`, reason captured, scrubbed,
  monitor red.
- **Benign max-turns run (R1 carve-out):** a best-effort cron exits **non-zero**
  via max-turns with **no artifact** → assert `resolveBestEffortEvalOk` returns
  `ok:true` (monitor stays GREEN), `warnSilentFallback` fired, reason recorded in
  `routine_runs.error_summary`, and **no page**. This is the scenario flip-all
  would have broken (the #4730 incident); it must be an explicit, named test.
- **Healthy no-artifact, exit 0 (output-aware cron):** a clean run on an
  output-aware cron with exit 0 and no issue → `resolveOutputAwareOk` records the
  output-missing reason in `error_summary` while the monitor reflects the
  output-contract policy (do NOT assert `completed` for an output-aware miss —
  that cohort flips red on absent output; pin this scenario to a best-effort
  fixture for the green case and an output-aware fixture for the red case).
- **Canary paths** as in AC5: credit-400 → page; 401 → key-invalid page;
  529/429/unclassified → **re-throw (no page)**; clean → `ok:true`.
- **run-log gate (P0 guard):** returned `{ok:false}` on attempt 0 of
  `maxAttempts:2` → **WRITES** `failed` (terminal, not suppressed); thrown error on
  attempt 0 → no write (will retry); thrown on final attempt → writes (AC3).
- **Reason-survives-scrub:** credit line + synthetic `sk-ant-<<…>>` in the same
  tail window → reason substring survives, secret removed (AC6).
- **Redaction:** synthetic `sk-ant`/token in tail → absent from Sentry extra
  (incl. the retrofitted `resolveOutputAwareOk` extra) and `error_summary` (AC2).

## Risks & Sharp Edges

- **R1 (resolved by deepen-plan → classify-fatal; CPO sign-off on the
  issue-letter departure):** the issue's literal text mandates flip-all ("a
  non-zero exit must NOT post a green check-in"). deepen-plan proved flip-all is
  **wrong** and already-litigated: the 2026-06-01 bug-fixer plan (incident
  `5127648` / #4730 / PR #4727) decoupled the heartbeat from `spawnResult.ok`
  *because* `claude --print` exits non-zero on healthy max-turns runs and was
  daily-false-paging. Flip-all reverses that fix → alert fatigue + false-`failed`
  WORM rows. **Resolution: classify-fatal** — fatal classes (credit/auth/spawn
  fault) flip red; benign non-zero (max-turns) stays green + records the reason.
  The matcher is shared with the Part-3 canary (single source). This *departs from
  the issue's letter*, so it is gated on **CPO / issue-author sign-off**
  (`requires_cpo_signoff: true`). The residual risk is **marker drift** — a new
  fatal failure mode whose tail matches no marker would stay green; mitigated by
  /work validating the marker set against real Better Stack tails and by the
  benign path still recording the reason in `routine_runs` (queryable even when
  green). Classify-by-string-match is itself a fragile pattern (see next bullet) —
  keep the marker set small, centralized, and tested against real fixtures.
- **Classify-by-string-match fragility.** The fatal-marker regexes are
  load-bearing and brittle to Anthropic copy changes. Centralize them in ONE
  exported constant in `_cron-shared.ts` (shared by resolver + canary), pin them
  with fixtures drawn from the real incident tail, and treat an unmatched non-zero
  as **benign-but-recorded** (green + reason in `routine_runs`), never as a silent
  drop — so a missed marker degrades to "visible-but-not-paged," not "invisible."
- **Redaction is load-bearing.** Every NEW tail sink (Sentry extra,
  `routine_runs.error_summary`) must route through the canonical scrubber, not
  just `redactToken` (which strips only the installation token). A crash stack
  can spill `sk-ant-…`. Sweep ALL new write sites (`hr-write-boundary-sentinel-sweep`).
- **Synthetic-token push protection:** test fixtures that illustrate redaction
  must use non-alnum placeholder shapes (`sk-ant-<<…>>`), never literal
  `sk-ant-`-prefixed alnum strings, or GitHub push protection rejects the push.
- **No balance endpoint — do not fabricate one.** Any AC/code that names an
  Anthropic "balance" endpoint is wrong; the only signals are the canary 400 (this
  PR) and the Admin `cost_report` spend (deferred follow-up). Verified live
  2026-06-29.
- **Canary needs the response body — transport widening is a prerequisite.**
  `postAnthropicMessage` discards the 400 body today (L311); the canary cannot
  classify credit-exhaustion without it. The widening + 2-caller sweep is a
  blocking sub-task of Phase 3, not an optional enhancement.
- **Admin auth header (follow-up only):** the Admin API uses `x-api-key:
  <sk-ant-admin…>` + `anthropic-version: 2023-06-01` (NOT a Bearer token, NOT the
  regular key). Confirmed against the live docs — captured here for the `Ref #5674`
  spend-trend follow-up.
- **`function-registry-count` is a 4-way cross-check.** The new cron must appear
  in (a) the route functions array, (b) the `cron-*.ts` file list, (c) the slug
  map, and (d) `cron-monitors.tf` — adding the file alone fails the test. Run the
  suite to find every assertion, do not guess the count delta beyond the visible
  `toBe(56)`.
- **`tsc`/test invocation:** typecheck via `cd apps/web-platform &&
  ./node_modules/.bin/tsc --noEmit`; run tests via the package's actual runner
  (check `vitest.config.ts` `include:` globs — co-located tests are not picked
  up; place new tests under `apps/web-platform/test/server/inngest/`).
- A plan whose `## User-Brand Impact` section is empty, placeholder, or omits the
  threshold fails deepen-plan Phase 4.6 — it is filled above.

## Open Code-Review Overlap

None found at plan-write time (no open `code-review` issue body references the
four masked cron files, `_cron-shared.ts`, `_cron-claude-eval-substrate.ts`, or
`run-log.ts`). Re-run the overlap query at /work if the backlog changed.
