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
   `claude-eval-nonzero-noop` / `-nofix`). Nine others flip the monitor red when
   their output issue is absent. So the Sentry cron monitors are an unreliable
   success signal — `cron-agent-native-audit` claude-eval *failed* at 10:36:25
   yet its monitor `scheduled-agent-native-audit` posted `ok` at 10:36:47.
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
| "Add an Anthropic balance/usage alert (low-balance threshold → Sentry)" | No balance endpoint exists; only Admin usage/cost (spend) under a separate `sk-ant-admin` key, and consumption per-message via `response.usage`. | Primary detector = a **canary probe** (1-token message on the existing operator key) that pages on the `Credit balance is too low` 400 — no new secret, catches exhaustion within one cron interval. Optional spend-trend "before" alert via Admin cost API is gated behind an **optional** `ANTHROPIC_ADMIN_KEY`; the cron degrades to canary-only when unset, so the observability fix ships without a hard secret dependency. |
| "stdout dropped per ADR-033 I5" | ADR-033 I5 is about *deterministic capture for memoization*, not redaction. The tails ARE captured (`spawnClaudeEval` builds `stdoutTail`/`stderrTail`); they are dropped only at the *Sentry-extra* layer of the 4 masked crons. | Fold the already-captured, redaction-scrubbed tails into the Sentry extra at the 4 masked sites; cite the real redaction layer (`redactGithubSourcedText`). |

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

**Brand-survival threshold:** single-user incident. (`requires_cpo_signoff: true`
— CPO sign-off at plan time; `user-impact-reviewer` at PR review per the review
skill's conditional-agent block.)

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
    the 9 output-aware sites cannot drift on redaction discipline.
  - Add a shared **eval-heartbeat resolver** for the non-output-contract crons:
    `resolveBestEffortEvalOk(spawnResult): { ok: boolean; errorSummary?: string;
    sentryExtra: {...} }`. It centralizes the Part-2 policy (see Phase 2) and
    returns the redaction-scrubbed tails in `sentryExtra` so each handler stops
    hand-rolling the `extra` object. (Mirrors how the 9 output-aware crons share
    `resolveOutputAwareOk`.)
- `apps/web-platform/server/inngest/middleware/run-log.ts`
  - Widen the terminal-result interpretation: today `failed = result.error !=
    null`. Change to also treat a handler that **returns** a non-ok result as
    failed: `const data = result.data as { ok?: boolean; errorSummary?: string }
    | undefined; const failed = result.error != null || data?.ok === false;`
  - Derive `error_summary` from whichever source is present:
    `p_error_summary: result.error ? errorSummary(result.error) :
    (failed ? (data?.errorSummary ? redactCommandForDisplay(data.errorSummary).slice(0, ERROR_SUMMARY_MAX)
    : "cron returned ok:false (see Sentry)") : null)`. Keep the existing
    `errorSummary()` scrub path for thrown errors. **This single change records
    eval failures in `routine_runs` for ALL 13 crons** (they already return
    `{ ok: false }` on real failure) — the per-cron edits below only enrich the
    reason and flip the masked monitors.
  - **Final-attempt gate is preserved.** The new `data?.ok === false` branch
    rides the *same* `isFinalAttempt` gate (`attempt >= maxAttempts - 1`) — a
    non-ok return on a non-final attempt must NOT double-write. Verify the gate
    still short-circuits before the `data?.ok === false` write.

### Phase 2 — Unify the heartbeat policy (Part 2)

**Goal:** a claude-eval non-zero exit must not post a green Sentry check-in.

**Decision (see `## Architecture Decision` for the ADR):** the four "best-effort"
crons stop posting `ok:true` on a non-zero exit. Output-aware crons are already
honest (output present ⇒ green even on a trailing non-zero exit; output absent +
non-zero ⇒ red) — they are left as-is for the heartbeat, but gain the run-log
`error_summary` for free via Phase 1.

**Files to Edit (the 4 masked crons):**

- `apps/web-platform/server/inngest/functions/cron-agent-native-audit.ts`
  (non-zero block ~L279-313, final heartbeat ~L313, `return { ok: true }` ~L316)
- `apps/web-platform/server/inngest/functions/cron-legal-audit.ts`
  (non-zero block ~L296-323, final heartbeat ~L330)
- `apps/web-platform/server/inngest/functions/cron-ux-audit.ts`
  (non-zero block ~L361-389, step-9 heartbeat ~L412)
- `apps/web-platform/server/inngest/functions/cron-bug-fixer.ts`
  (non-zero block ~L786-803 `claude-eval-nonzero-nofix`; the multiple
  `ok:true` heartbeats at ~L819/L860 that fire on a non-zero/no-PR run)

For each: replace the `if (!spawnResult.ok)` warn-then-green pattern with the
shared `resolveBestEffortEvalOk(spawnResult)` call, then
`postSentryHeartbeat({ ok: result.ok, … })` and
`return { ok: result.ok, errorSummary: result.errorSummary }`. On a non-zero
exit the resolver returns `ok:false` + the scrubbed-tail reason → monitor flips
to `error` AND the reason lands in `routine_runs` (Phase 1). The
`abortedByTimeout` infra-fault path keeps its existing strict `error`
early-return (do not double-signal). Update the now-stale "stays green
(liveness, not success)" comment blocks to describe the new policy and cite
this plan + the ADR amendment.

> **Reviewer caveat (Risk R1):** flipping all non-zero exits to `error` could
> page a genuinely best-effort run that legitimately exits non-zero (e.g.
> max-turns *after* useful work). Before merge, /work MUST pull Better Stack
> history for the 4 crons and confirm how often each exits non-zero on a healthy
> run (the substrate logs `op=claude-eval-nonzero-noop exitCode=…`). If a cron
> exits non-zero on healthy runs with material frequency, prefer the
> `in_progress → ok/error` two-phase check-in the issue offers ("post a distinct
> degraded/in_progress→error signal so the monitor still flips") for that cron
> rather than suppressing the flip. This is the single contested design point —
> deepen-plan + plan-review must weigh it (see Sharp Edges).

### Phase 3 — Anthropic credit/usage probe (Part 3)

**Goal:** page Sentry the moment the operator Anthropic key cannot do work
(credit exhaustion / auth failure), and — when the optional Admin key is
configured — warn on month-to-date spend approaching an operator budget.

**Files to Create:**

- `apps/web-platform/server/inngest/functions/cron-anthropic-credit-probe.ts`
  - Hourly Inngest cron (`{ cron: "<:NN> * * * *" }` — pick an off-peak minute,
    document in ROUTINE_METADATA `scheduleLabel`). Pure-TS probe, **no
    claude-eval spawn**.
  - **Canary (always):** call `postAnthropicMessage({ apiKey:
    process.env.ANTHROPIC_API_KEY, model: <cheapest tier>, maxTokens: 1, messages:
    [{ role: "user", content: "ping" }] })` (reuse the shared transport in
    `_cron-shared.ts:277`). On `Anthropic API 400` whose body matches
    `/credit balance is too low/i` (or `invalid_request_error` billing variant),
    `reportSilentFallback` with `op: "anthropic-credit-exhausted"` and post
    `postSentryHeartbeat({ ok: false, sentryMonitorSlug:
    "scheduled-anthropic-credit-probe" })` → monitor flips red, pages. A `401` /
    auth error → same page with `op: "anthropic-key-invalid"`. A clean reply →
    `ok:true` heartbeat (liveness AND success: a 1-token ping IS the success
    contract here, unlike the audit crons). The probe MUST NOT consult any
    captured stdout (it is its own request) — no redaction needed beyond the
    transport's existing redact-then-throw.
  - **Spend trend (optional):** if `process.env.ANTHROPIC_ADMIN_KEY` is set, GET
    `https://api.anthropic.com/v1/organizations/cost_report?starting_at=<billing-month-start>&ending_at=<now>`
    with header `x-api-key: <admin key>` + `anthropic-version: 2023-06-01`; sum
    the USD-cents amounts; if `ANTHROPIC_MONTHLY_BUDGET_USD` is set and
    month-to-date spend ≥ `threshold% (default 80)` of it,
    `warnSilentFallback(op: "anthropic-budget-threshold")`. When the admin key is
    **unset**, skip silently — the canary alone satisfies the acceptance
    criteria. (No balance endpoint exists; spend-vs-budget is the only "before"
    signal — documented in `## Architecture Decision`.)
  - **Redaction:** the admin/operator keys are secrets; reuse the transport's
    redact-then-throw (`postAnthropicMessage` already strips request context).
    Never interpolate either key into a log/Sentry payload.

**Files to Edit (wire the new cron):**

- `apps/web-platform/app/api/inngest/route.ts` — import `cronAnthropicCreditProbe`
  and add it to the `serve({ functions: [...] })` array (mirrors
  `cronEmailIngressProbe` at L34/L131).
- `apps/web-platform/server/inngest/cron-manifest.ts` — add
  `"cron-anthropic-credit-probe"` to `EXPECTED_CRON_FUNCTIONS`.
- `apps/web-platform/server/inngest/routine-metadata.ts` — add a `ROUTINE_METADATA`
  entry: `{ description: "Hourly probe of the operator Anthropic API key; pages
  when credit is exhausted or the key is invalid, and warns when spend nears the
  configured monthly budget.", domain: "Engineering", ownerRole: "CTO",
  scheduleLabel: "Hourly (:NN)", manualTrigger: "allowed" }`.
  (`routine-metadata-parity.test.ts` + the non-empty-`description` guard force
  this edit; keep the description 10–160 chars.)
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

1. **Reason reaches Sentry.** A unit test drives `resolveBestEffortEvalOk` with a
   `SpawnResult` whose `stdoutTail` contains `"Credit balance is too low"` and a
   non-zero `exitCode`; asserts the returned `sentryExtra` carries the
   scrubbed tail substring and `ok === false`. (Shape, not existence.)
2. **Redaction holds.** `formatTailForSentry` test: an input tail containing a
   synthesized `sk-ant-<<placeholder>>` and an installation-token-shaped string
   returns a value with neither token present. (Use a non-alnum placeholder in
   the fixture per the synthetic-token push-protection Sharp Edge.)
3. **run-log records eval failures.** A run-log middleware test: a handler result
   `{ error: null, data: { ok: false, errorSummary: "Credit balance is too low" } }`
   on the final attempt produces a `write_routine_run` call with
   `p_status: "failed"` and a non-null scrubbed `p_error_summary`; a non-final
   attempt with the same result produces **no** write (final-attempt gate intact);
   a `{ ok: true }` result still writes `completed` / `error_summary: null`.
4. **Monitor flips on non-zero.** For each of the 4 masked crons, a handler test
   asserts that a non-zero `spawnResult` leads to `postSentryHeartbeat` being
   called with `ok: false` (was `ok: true`), and the handler returns
   `{ ok: false, errorSummary: <reason> }`.
5. **Canary pages on credit-balance 400.** A `cron-anthropic-credit-probe` test
   stubs `postAnthropicMessage` to throw `new Error("Anthropic API 400")` with a
   credit-balance body and asserts `postSentryHeartbeat({ ok: false })` +
   `reportSilentFallback({ op: "anthropic-credit-exhausted" })`; a clean reply →
   `ok: true`; an unset `ANTHROPIC_ADMIN_KEY` → spend-trend branch skipped (no
   cost_report fetch).
6. **Registry/monitor parity.** `function-registry-count.test.ts` and
   `routine-metadata-parity.test.ts` pass with the new cron present in the route
   array, `EXPECTED_CRON_FUNCTIONS`, `ROUTINE_METADATA`, and a
   `scheduled_anthropic_credit_probe` resource in `cron-monitors.tf`.
7. **Typecheck:** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
   passes (NOT `npm run -w` — repo root declares no `workspaces`).
8. **No BYOK regression (ADR-033 I2):** `byok-audit-writer-sweep.test.ts` still
   passes — the new `cron-anthropic-credit-probe.ts` must NOT import
   `runWithByokLease` (it uses the operator `ANTHROPIC_API_KEY` only).
9. **Better Stack non-zero-frequency check recorded** (R1): the PR body or a
   plan note records the historical healthy-non-zero-exit frequency for each of
   the 4 masked crons and the resulting flip-vs-two-phase decision per cron.

### Post-merge (operator)

10. **Live monitor exists.** After `apply-sentry-infra.yml` runs on merge, the
    `scheduled-anthropic-credit-probe` monitor exists in Sentry (verify via the
    Sentry Crons monitors API, read-only — `hr-no-dashboard-eyeball-pull-data-yourself`).
    Automation: in-scope for `/soleur:ship` post-merge verification.
11. **Optional admin-key provisioning (deferrable).** If the spend-trend "before"
    alert is to go live, provision `ANTHROPIC_ADMIN_KEY` + `ANTHROPIC_MONTHLY_BUDGET_USD`
    in Doppler dev+prd (see `## Infrastructure (IaC)`). The canary is fully
    functional without this — the cron degrades to canary-only. `Ref #5674`
    (not `Closes`) if the admin-key path is deferred to a follow-up.

## Architecture Decision (ADR/C4)

This plan changes a cross-cutting invariant (every claude-eval cron's
success/heartbeat contract) and adds a new monitoring substrate edge → ADR/C4
update is an in-scope deliverable, not a follow-up.

### ADR

- **Amend ADR-033** (`...child-process-spawn.md`). Add to `## Decision`: *the
  unified heartbeat invariant* — a claude-eval non-zero exit MUST NOT post a
  green Sentry check-in; the success contract is "claude-eval exited 0 OR the
  cron produced its declared output," and the failure reason (redaction-scrubbed
  last-N stdout/stderr) MUST reach both Sentry and `routine_runs.error_summary`.
  Add to `## Alternatives Considered`: the "liveness, not success" best-effort
  green check-in (the pattern this plan supersedes) and *why* it was wrong
  (credit-exhaustion non-zero is indistinguishable from clean-no-artifact at the
  monitor level). Add the **no-balance-endpoint** finding: Anthropic exposes no
  remaining-credit endpoint; exhaustion is detected by a canary, spend-trend by
  the Admin cost API under an optional separate `sk-ant-admin` key.

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

The only new infrastructure is the Sentry cron monitor (handled in code via
`cron-monitors.tf` + `apply-sentry-infra.yml` — no SSH, no manual dashboard
step) and an **optional** Doppler secret for the spend-trend path.

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

### Distinctness / drift safeguards

The optional `ANTHROPIC_ADMIN_KEY` + `ANTHROPIC_MONTHLY_BUDGET_USD` are **runtime
env secrets read by the cron**, not Terraform vars — they do not enter
`terraform.tfstate`. They are provisioned in Doppler `dev` + `prd` (distinct
projects per `hr-dev-prd-distinct-supabase-projects`). The cron MUST treat both
as optional (unset ⇒ canary-only) so a missing secret never fails the probe.

### Vendor-tier reality check

The Sentry Crons monitor is within the existing paid plan (42 monitors already
defined). No new tier gate.

### Optional Admin-key mint (automation-feasibility)

Minting `ANTHROPIC_ADMIN_KEY` is a console action at
`console.anthropic.com` → Settings → Admin keys. **`automation-status:
UNVERIFIED — /work MUST run a Playwright attempt before any operator handoff.`**
Per the operator-mint Sharp Edge, a vendor dashboard under an authenticated
session is presumptively Playwright-automatable until a real attempt reaches a
named human gate (MFA/TOTP). Do NOT pre-assume operator-only. Because the canary
ships without this key, the mint is **deferrable** — it does not block the
observability fix. If deferred, file a tracking issue (`Ref #5674`) with the
re-evaluation trigger "operator wants spend-before-exhaustion alerting."

## Observability

```yaml
liveness_signal:
  what: scheduled-anthropic-credit-probe Sentry cron monitor (1-token canary)
  cadence: hourly
  alert_target: Sentry Crons (failure_issue_threshold=1) → GitHub issue
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf
error_reporting:
  destination: Sentry (reportSilentFallback / postSentryHeartbeat ok:false) + routine_runs.error_summary (run-log middleware)
  fail_loud: true  # non-zero claude-eval exit now flips monitor red AND writes a failed routine_runs row with the scrubbed reason
failure_modes:
  - mode: Anthropic credit exhausted (whole fleet no-ops)
    detection: hourly canary 400 "Credit balance is too low"
    alert_route: Sentry op=anthropic-credit-exhausted + monitor red → GH issue
  - mode: Operator ANTHROPIC_API_KEY invalid/revoked
    detection: canary 401/auth error
    alert_route: Sentry op=anthropic-key-invalid + monitor red
  - mode: claude-eval non-zero exit on a masked cron (was silently green)
    detection: spawnResult.exitCode != 0 in resolveBestEffortEvalOk
    alert_route: postSentryHeartbeat ok:false + routine_runs.error_summary + scrubbed tail in Sentry extra
  - mode: Spend approaching monthly budget (optional, before exhaustion)
    detection: Admin cost_report month-to-date >= threshold% of ANTHROPIC_MONTHLY_BUDGET_USD
    alert_route: Sentry warn op=anthropic-budget-threshold (non-paging)
logs:
  where: Sentry events (durable) + routine_runs table (WORM, Supabase). NOT app stdout (Vector does not ship it).
  retention: Sentry default project retention; routine_runs per anonymise_routine_runs lifecycle.
discoverability_test:
  command: "curl -s 'https://<sentry-domain>/api/0/organizations/<org>/monitors/?project=<id>' | jq '.[].slug' | grep scheduled-anthropic-credit-probe"
  expected_output: "scheduled-anthropic-credit-probe (monitor exists; no ssh)"
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

**Status:** reviewed (advisory). **Assessment:** the optional spend-trend alert
introduces an `ANTHROPIC_MONTHLY_BUDGET_USD` operator knob and reads the Admin
cost API. This is a budget-monitoring surface — CFO should confirm the default
threshold (80%) and whether the recurring Anthropic spend is already in the
expense ledger. No new recurring vendor expense is created (the Admin key is free;
the canary is ~1 token/hour ≈ negligible).

### Product/UX Gate

**Tier:** none. **Mechanical UI-surface override:** no file in `## Files to Edit`
or `## Files to Create` matches a UI-surface path (`components/**`, `app/**/page.tsx`,
`app/**/layout.tsx`) — the only `app/` edit is `app/api/inngest/route.ts` (an API
route, not a page). Product = NONE; gate skipped.

## Test Scenarios

- **Credit-exhaustion replay:** feed a `SpawnResult` with the real incident
  stdout (`Credit balance is too low`, exit 1) through `resolveBestEffortEvalOk`
  → assert `ok:false`, reason captured, scrubbed.
- **Healthy no-artifact run:** a clean audit run (exit 0, no issue) → assert the
  monitor stays green and `routine_runs` records `completed` (the policy must not
  flip on exit 0).
- **Canary happy/exhausted/auth paths** as in AC5.
- **run-log double-write guard:** non-final failed attempt → no row (AC3).
- **Redaction:** synthetic `sk-ant`/token in tail → absent from Sentry extra and
  `error_summary` (AC2).

## Risks & Sharp Edges

- **R1 (contested design):** flipping all non-zero exits to `error` may page
  best-effort runs that legitimately exit non-zero. The issue text mandates the
  flip ("a non-zero exit must NOT post a green check-in") and offers the
  `in_progress → ok/error` two-phase as the escape hatch. /work MUST verify
  per-cron healthy-non-zero frequency via Better Stack and choose flip vs
  two-phase per cron before merge. deepen-plan + the 5-agent plan-review must
  weigh this (single-user-incident threshold ⇒ run deepen-plan; plan-review
  alone is structurally blind to this kind of substance finding).
- **Redaction is load-bearing.** Every NEW tail sink (Sentry extra,
  `routine_runs.error_summary`) must route through the canonical scrubber, not
  just `redactToken` (which strips only the installation token). A crash stack
  can spill `sk-ant-…`. Sweep ALL new write sites (`hr-write-boundary-sentinel-sweep`).
- **Synthetic-token push protection:** test fixtures that illustrate redaction
  must use non-alnum placeholder shapes (`sk-ant-<<…>>`), never literal
  `sk-ant-`-prefixed alnum strings, or GitHub push protection rejects the push.
- **No balance endpoint — do not fabricate one.** Any AC/code that names an
  Anthropic "balance" endpoint is wrong; the only signals are the canary 400 and
  the Admin `cost_report` spend. Verified live 2026-06-29.
- **Admin auth header:** the Admin API uses `x-api-key: <sk-ant-admin…>` +
  `anthropic-version: 2023-06-01` (NOT a Bearer token, NOT the regular key).
  Confirmed against the live docs.
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
