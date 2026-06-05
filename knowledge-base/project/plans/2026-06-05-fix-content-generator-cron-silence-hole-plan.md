---
title: Fix content-generator scheduled Inngest cron silence hole (#4960)
type: fix
classification: bug-fix
brand_survival_threshold: aggregate pattern
lane: cross-domain
issue: 4960
status: draft
created: 2026-06-05
---

# fix: content-generator scheduled Inngest cron can never go silent again (#4960)

## Enhancement Summary

**Deepened on:** 2026-06-05
**Sections enhanced:** Deliverable 1 (Sentry pull), Research Reconciliation, Precedent verification.

### Key Improvements (deepen pass)
1. **Deliverable 1 resolved authoritatively from Sentry** (org `jikigai-eu`, event
   `141195ed5158459d951bc273d1e5be01`): the 2026-06-05 manual run died at ~6.1 min with an
   **Anthropic API 500** (`exitCode 1`, `signal null`, no max-turns notice) — failure mode
   (c), NOT a turn-kill. This **resolves Deliverable 3 to DO-NOT-BUMP** `--max-turns`.
2. **Verify-the-negative confirmed**: `_cron-shared.ts` has zero issue-CREATE — grep CONFIRMS
   `resolveOutputAwareOk` / `verifyScheduledIssueCreated` are read-only. The handler-level
   fallback issue-create is genuinely net-new across the cohort.
3. **All attribution + line citations verified live**: PR #4932 (MERGED 2026-06-04),
   `cron-cloud-task-heartbeat.ts:70,133,162,256-262`, `cron-skill-freshness.ts:234,267`,
   `cron-oauth-probe.ts:510`, `cron-strategy-review.ts:479`, `probe-octokit.ts:116`,
   community-monitor `50→80 on 2026-06-03`. No drift.

### Precedent-Diff (deepen Phase 4.4)
- **Scheduled-work pattern**: 39 `cron-*.ts` Inngest functions exist; this plan EDITS an
  existing Inngest function (introduces NO new schedule). ADR-033 Inngest path is already
  satisfied — no GH-Actions-cron temptation. PASS.
- **Handler-level `POST /repos/{owner}/{repo}/issues` precedent**: 8 sibling crons use it
  (`cron-skill-freshness.ts:267`, `cron-oauth-probe.ts:510`, `cron-strategy-review.ts:479`,
  `cron-github-app-drift-guard.ts:591/635`, `cron-content-vendor-drift.ts:697`,
  `cron-supabase-disk-io.ts:226`, `cron-membership-health.ts:210`,
  `cron-linkedin-token-check.ts:112`). The fallback-issue create mirrors
  `cron-skill-freshness.ts:255-275` (title build → `POST /issues` with labels). The
  dedup-before-create mirrors `searchExistingFreshnessIssue` (`cron-skill-freshness.ts:234`).
  **Pattern is established; only its use as a *fallback* gated on the output-aware result is
  novel** — reviewers should scrutinize the gate condition and the replay/retry idempotency,
  not the `POST /issues` call shape itself.

## Overview

The `cron-content-generator` Inngest function can terminate without producing its
`scheduled-content-generator`-labeled audit issue. When that happens it is **silent**:
no `[Scheduled] Content Generator` issue, no PR, no `ci/content-gen-*` branch — and
the only signal is the per-function Sentry monitor going RED plus, eventually, the
`cron-cloud-task-heartbeat` watchdog filing a `[cloud-task-silence]` issue once the
absence exceeds its 9-day `maxGapDays` threshold (this is exactly what filed **#4960**
on 2026-06-05, "Days since last issue: 14").

The watchdog keys on the **`created_at` of the most-recent `scheduled-content-generator`
issue** (`cron-cloud-task-heartbeat.ts:70,133,162`): `silent = daysSince > 9`. So the
single load-bearing invariant is: **every terminal path of the handler must guarantee a
`scheduled-content-generator`-labeled issue gets created within the window** — success or
self-reported failure. Today nothing in the handler creates that issue; the prompt's
in-prompt `STEP 1b / STEP 2 / STEP 4 / STEP 6` "create issue and stop" guards are the
ONLY producers, and any termination that bypasses the prompt (a mid-eval crash, an API
error that kills `claude --print`, a max-turns kill, or a hard spawn failure) produces
nothing.

This plan adds a **handler-level fallback guard**: after the existing output-aware check
(`resolveOutputAwareOk` / `verify-output` step) determines no `scheduled-content-generator`
issue exists in the run window, the handler itself creates a `[Scheduled] Content Generator
- <date>` issue labeled `scheduled-content-generator` (a FAILED/self-report issue) before
returning. This is the same primitive used by ~8 sibling crons that already create issues
from the handler (`cron-skill-freshness.ts:267`, `cron-oauth-probe.ts:510`,
`cron-strategy-review.ts:479`, etc.) — but no always-create producer currently uses it as
a *fallback*. A handler-level guard survives a max-turns kill or a mid-eval crash that
bypasses every prompt step, which is the whole point.

## Diagnosis (carried forward + confirmed this session)

The original cross-cron silence (bwrap user-namespace sysctl drift) was **fixed and merged
in PR #4932 on 2026-06-04** (confirmed `MERGED`, mergedAt 2026-06-04T14:29:07Z). The
sandbox is healthy: roadmap-review and community-monitor both produced their `[Scheduled]`
issues on 2026-06-05 on the same substrate. **Do NOT re-touch the bwrap/sysctl/server.tf
path, roadmap-review, or community-monitor.**

content-generator has a **distinct residual** — a silence hole independent of the bwrap fix.

## Deliverable 1 — Failure-mode confirmation (Sentry, authoritative)

Per `hr-no-dashboard-eyeball-pull-data-yourself` / `hr-observability-layer-citation`, the
2026-06-05 manual run was pulled directly from Sentry (org `jikigai-eu`, monitor slug
`scheduled-content-generator`, event `141195ed5158459d951bc273d1e5be01`). **Sentry was
reachable from the worktree** via `doppler secrets get SENTRY_AUTH_TOKEN -p soleur -c prd`.

| Signal | Value |
| --- | --- |
| Monitor check-in (2026-06-05T15:11:30Z) | `error` (output-aware heartbeat RED — correct) |
| Run trigger | `manual-api`, started `2026-06-05T15:05:11.992Z` |
| `scheduled-output-missing` event title | "cron-content-generator spawn exited non-zero AND created no `scheduled-content-generator` issue in the run window" |
| `exitCode` | **`1`** |
| `signal` | `null` |
| `spawnOk` | `false` |
| `durationMs` | **`368727`** (~6.1 min — NOT near the 55-min wall-clock ceiling) |
| `abortedByTimeout` | `false` (no timeout event emitted) |
| `stdoutTail` | **`"API Error: 500 Internal server error. This is a server-side issue, usually temporary — try again in a moment. If it persists, check status.claude.com."`** |
| `stderrTail` | empty |

**Verdict: failure mode (c) — a STEP errored before its create-issue guard.** Specifically
an **upstream Anthropic API 500** killed `claude --print` ~6 minutes in (exit 1, signal
null, no "Reached max turns" notice anywhere in `stdoutTail`, far from the wall-clock
budget). The `retries: 1` retry also did not recover (single error check-in). This is the
`H2` runbook class ("task runs but fails fast before the audit-issue step"), **not** `H7`
(max-turns starvation).

This makes the silence hole **mode-independent in practice**: even a perfectly-authored
prompt cannot self-report when the eval process is killed mid-run by an upstream API error.
The fix must live in the handler, above the prompt.

## Deliverable 3 — Turn-budget decision (resolved by Deliverable 1): DO NOT BUMP

PR #4932 deferred the `--max-turns 50→80` bump pending working-bash evidence. That evidence
now exists, and **it does not support a turn-kill hypothesis**: the 2026-06-05 run died at
~6.1 min with an API 500, `exitCode 1`, no max-turns notice in `stdoutTail`. The
community-monitor 50→80 bump (2026-06-03) was justified by a Sentry event whose `stdoutTail`
literally read `"Error: Reached max turns (50)"` — the content-generator evidence shows the
opposite. **Leave `--max-turns 50` and `MAX_TURN_DURATION_MS = 55 min` unchanged**; bumping
on this evidence would be cargo-culting the sibling fix. (Recorded for completeness: 55÷80 =
0.6875 min/turn would still be in the 0.55–1.2 peer band per
`knowledge-base/project/learnings/2026-03-20-claude-code-action-max-turns-budget.md`, so IF
a future turn-kill is observed the bump is mechanically safe with no wall-clock change — but
this PR does not make it.)

## Research Reconciliation — Spec vs. Codebase

| Diagnosis claim | Codebase / Sentry reality | Plan response |
| --- | --- | --- |
| "at least one exit path terminates without creating its audit issue" | Confirmed. The handler has NO issue-create call; only the prompt creates issues. `resolveOutputAwareOk` is **read-only** (turns monitor RED, never creates an issue). | Add handler-level fallback issue-create. |
| "mirror the community-monitor / heartbeat post-run output-check pattern" | community-monitor uses the **same** `resolveOutputAwareOk` read-only pattern — it does NOT create a fallback issue either. NO always-create producer does. | The output-check pattern (`verify-output`) is reused as the *gate*; the issue-create is **net-new** behavior layered on top. Surface this divergence explicitly so the reviewer is not misled into expecting a copy of an existing sibling step. |
| "run is likely forced into STEP 1b growth-plan path or hitting --max-turns 50" | Neither. Sentry shows an Anthropic API 500 at ~6 min. The seo-refresh-queue exhaustion is real but irrelevant to *this* fire — the eval never reached topic selection. | H2 fix is mode-independent and lands regardless; turn-budget bump is dropped (Deliverable 3). |
| "the handler already has a runStartedAt post-run output check" | Confirmed: `cron-content-generator.ts` mints `runStartedAt` and passes it to `resolveOutputAwareOk`. | Reuse `runStartedAt` as the fallback issue's window anchor and as the title-dedup signal. |

## Files to Edit

- `apps/web-platform/server/inngest/functions/cron-content-generator.ts`
  - Add a handler-level fallback step (`ensure-audit-issue`) AFTER the existing
    `verify-output` step. When `heartbeatOk === false`, create the
    `[Scheduled] Content Generator - <YYYY-MM-DD>` issue labeled
    `scheduled-content-generator`, with a body summarizing the silent termination
    (exitCode, abortedByTimeout, durationMs, redacted stdoutTail/stderrTail tail) so the
    issue is self-diagnosing. Wrap in `try/catch` → `reportSilentFallback` (never throw;
    a fallback-issue failure must not crash the finally/teardown).
  - Idempotency: before creating, re-check via `verifyScheduledIssueCreated` (the read
    already imported transitively through `resolveOutputAwareOk`) — but since
    `heartbeatOk === false` already means "no issue in window", the create is gated on that
    boolean. Add a defensive title-dedup (search open issues with the label whose title
    starts with `[Scheduled] Content Generator -` for today) to avoid double-filing across
    the `retries: 1` replay, mirroring `searchExistingFreshnessIssue`
    (`cron-skill-freshness.ts:234`).
  - Keep `--max-turns 50` and `MAX_TURN_DURATION_MS` unchanged (Deliverable 3).
  - Reuse `createProbeOctokit()` (`apps/web-platform/server/github/probe-octokit.ts:116`)
    or the already-minted `installationToken` for the issue-create. **Decision point for
    /work**: the prompt's `gh issue create` uses the spawn's `GH_TOKEN` (installation token);
    the handler should use the same installation-token-authed octokit it already mints, NOT
    `createProbeOctokit` if the probe app lacks issue-write — verify the probe octokit's
    permissions at /work time (`hr-github-app-auth-not-pat`). Sibling handler creators
    (`cron-skill-freshness`, `cron-oauth-probe`, `cron-strategy-review`) use
    `createProbeOctokit` and successfully `POST /repos/{owner}/{repo}/issues`, so the probe
    app already has issue-write — prefer it for parity, but confirm.

- `apps/web-platform/test/server/inngest/cron-content-generator.test.ts`
  - Add source-shape anchors asserting the fallback step exists (`ensure-audit-issue`,
    the `[Scheduled] Content Generator -` title literal, the `scheduled-content-generator`
    label literal, the `try/catch` → `reportSilentFallback` guard, and the gate on the
    output-aware result).
  - Assert `--max-turns 50` is STILL present (regression guard that this PR did NOT bump).

- `knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md`
  - Update `H2 — Restore` to note that content-generator now has a **handler-level**
    fallback (not only the prompt-level guards), so a mid-eval crash / API-500 / max-turns
    kill self-reports a FAILED audit issue. Cross-reference the new step.

## Files to Create

- None. (No new infra, no new secret, no new vendor — pure code change against the
  already-provisioned cron substrate.)

## Implementation Phases

### Phase 1 — RED: failing source-shape + behavioral tests
1. Extend `cron-content-generator.test.ts` with the fallback-step anchors (above). These
   fail against current source (no `ensure-audit-issue` step exists).
2. If a behavioral test is feasible against the handler (the file already imports the
   handler), add a unit test driving `cronContentGeneratorHandler` with a stubbed `step.run`
   that returns `spawnOk:false` + a stubbed octokit, asserting a `POST /issues` with the
   right label+title-prefix fires exactly once when `verify-output` returns false, and
   zero times when it returns true. Mirror the injectable-octokit pattern
   `resolveOutputAwareOk` already uses (`octokit?` arg in `_cron-shared.ts`). If the handler
   does not expose an injection seam for the issue-create, prefer extracting a small
   `ensureContentGeneratorAuditIssue({ octokit?, runStartedAt, spawnResult })` helper into
   the handler module (NOT `_cron-shared.ts` — scope is content-generator only) so it is
   unit-testable, mirroring how `verifyScheduledIssueCreated` is structured.

### Phase 2 — GREEN: handler-level fallback guard
1. Add the `ensure-audit-issue` step after `verify-output`, gated on `heartbeatOk === false`.
2. Title: `[Scheduled] Content Generator - ${runStartedAt.slice(0,10)}` (UTC date from the
   replay-stable `runStartedAt`, so retries do not drift the date).
3. Body: include `fn`, `runStartedAt`, `exitCode`, `signal`, `abortedByTimeout`,
   `durationMs`, and the bounded redacted `stdoutTail`/`stderrTail` tail (the API-500 line)
   so the issue is self-diagnosing without SSH; include a one-line pointer to the H2 runbook.
4. Label: `["scheduled-content-generator"]`. (Confirm whether to also add `do-not-autoclose`
   — skill-freshness uses it; for a FAILED self-report we likely want the daily-triage/
   watchdog auto-close path to work normally, so OMIT `do-not-autoclose` unless /work finds
   a reason — note this decision in the PR.)
5. Wrap in `try/catch` → `reportSilentFallback({ feature:"cron-content-generator",
   op:"ensure-audit-issue-failed", ... })`; never throw (the `finally` teardown must still run).
6. Idempotency dedup: search open `scheduled-content-generator` issues for a title matching
   today's prefix before creating (avoids a second FAILED issue on the `retries:1` replay).

### Phase 3 — Runbook + regression anchors
1. Update `cloud-scheduled-tasks.md` H2 Restore note.
2. Confirm the `cron-producer-output-wiring.test.ts` still passes unchanged (content-generator
   remains a wired always-create producer; this PR adds a fallback, not a rewiring).

### Phase 4 — Verify locally
1. `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-content-generator.test.ts test/server/inngest/cron-producer-output-wiring.test.ts test/server/inngest/cron-shared.test.ts`
   (use vitest per the runner; bun test is blocked by `apps/web-platform/bunfig.toml`).
2. `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (or the workspace's typecheck script).

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `cron-content-generator.ts` contains an `ensure-audit-issue` step that runs AFTER
      `verify-output` and creates a `scheduled-content-generator`-labeled issue titled
      `[Scheduled] Content Generator - <date>` when the output-aware result is `false`.
      (Verify: `grep -n "ensure-audit-issue" cron-content-generator.ts` returns ≥1; the
      issue-create is gated on the `verify-output` boolean.)
- [ ] The fallback issue-create is wrapped in `try/catch` → `reportSilentFallback` and never
      throws. (Verify: the `POST .../issues` call site is inside a `try` whose `catch` calls
      `reportSilentFallback`.)
- [ ] `--max-turns 50` is UNCHANGED and `MAX_TURN_DURATION_MS` is `55 * 60 * 1000`.
      (Verify: `grep -c '"50"' ...CLAUDE_CODE_FLAGS region` and the existing MAX_TURN test
      both pass — this PR explicitly does NOT bump the turn budget; Deliverable-1 evidence
      shows an API-500, not a turn-kill.)
- [ ] Unit test asserts: `verify-output=false` → exactly one `POST /issues` with the right
      label + title prefix; `verify-output=true` → zero `POST /issues`.
- [ ] `vitest run` over the touched test files is green; `tsc --noEmit` is clean.
- [ ] Runbook H2 Restore updated to describe the handler-level fallback.
- [ ] PR body uses **`Closes #4960`** (in the body, not the title) per
      `wg-use-closes-n-in-pr-body-not-title-to`.

### Post-merge (operator / automated)
- [ ] `web-platform-release.yml` restarts the container on merge to `apps/web-platform/**`
      (path-filtered `on.push`) — the PR merge IS the deploy + function-sync remediation; no
      separate operator restart step.
- [ ] (Optional verification, automatable) Fire `cron/content-generator.manual-trigger` once
      via `/soleur:trigger-cron` after deploy and confirm EITHER a healthy
      `[Scheduled] Content Generator` issue OR a self-reported FAILED audit issue appears with
      label `scheduled-content-generator` — i.e. the run is no longer silent end-to-end.
      Then confirm the watchdog auto-closes #4960 on its next fire (recovery path
      `cron-cloud-task-heartbeat.ts:256-262` closes the `cloud-task-silence` issue once
      `daysSince` falls back within threshold).

## Observability

```yaml
liveness_signal:
  what: scheduled-content-generator issue created every run (success OR handler fallback)
  cadence: cron 0 10 * * 2,4 UTC + manual cron/content-generator.manual-trigger
  alert_target: Sentry monitor "scheduled-content-generator" (output-aware heartbeat) AND cron-cloud-task-heartbeat watchdog (maxGapDays 9)
  configured_in: apps/web-platform/server/inngest/functions/cron-content-generator.ts
error_reporting:
  destination: Sentry via reportSilentFallback / warnSilentFallback (op ensure-audit-issue-failed, scheduled-output-missing)
  fail_loud: true
failure_modes:
  - mode: eval crashes / API 500 mid-run (the #4960 case)
    detection: resolveOutputAwareOk returns false then handler creates FAILED audit issue + Sentry scheduled-output-missing event carries exitCode/stdoutTail
    alert_route: per-function Sentry monitor RED + watchdog stays green (issue created)
  - mode: max-turns kill bypassing prompt steps
    detection: same handler fallback (gated on output-aware result, not on the prompt)
    alert_route: same
  - mode: handler fallback issue-create itself fails (e.g. GitHub 5xx)
    detection: reportSilentFallback op ensure-audit-issue-failed
    alert_route: Sentry; watchdog still catches the absence after threshold (defense-in-depth)
logs:
  where: Sentry events (app stdout is NOT shipped to Better Stack — stdoutTail tail folded into Sentry extra)
  retention: Sentry default
discoverability_test:
  command: "gh issue list --label scheduled-content-generator --state all --search '\"Content Generator\" in:title' --json number,title,createdAt --limit 5"
  expected_output: a [Scheduled] Content Generator - <date> issue dated within the last cron window (success or FAILED self-report)
```

## User-Brand Impact

**If this lands broken, the user experiences:** the content-generator cron continues to go
silent on a mid-eval crash — no blog article, no distribution content, and no signal until
the watchdog files another `[cloud-task-silence]` issue ~9 days later. The founder's content
pipeline stalls invisibly.

**If this leaks, the user's data is exposed via:** N/A — the fallback issue body includes only
the cron's own redacted `stdoutTail`/`stderrTail` tail (already redacted of the installation
token via the substrate's `redactToken`), `exitCode`, and timing. No operator-session or
customer data is in scope. The issue-create uses the GitHub App installation token already
minted for the run (`hr-github-app-auth-not-pat`), not a PAT.

**Brand-survival threshold:** aggregate pattern — a single silent fire is a content-cadence
hiccup, not a per-user incident; the harm is the *pattern* of repeated silence eroding the
content pipeline. (No per-PR CPO sign-off required at this threshold.)

## Domain Review

**Domains relevant:** Engineering (CTO)

### Engineering (CTO)
**Status:** reviewed (carry-forward — infrastructure/observability cron change)
**Assessment:** Single-file handler change adding a fallback issue-create gated on the existing
output-aware result. Reuses the established handler-level `POST /issues` primitive (8 sibling
crons) and the already-minted installation token. No schema, no migration, no new infra, no
new secret. The one design subtlety the CTO lens flags: this is the FIRST always-create
producer to add a *fallback* issue-create — the reviewer must not expect it to mirror an
existing sibling step verbatim (it does not; `resolveOutputAwareOk` is read-only by design).
Idempotency under `retries: 1` replay is the main correctness risk → addressed by the
today's-prefix title dedup. No Product/UX surface (no `components/`, no `app/**/page.tsx`).

### Product/UX Gate
Not relevant — no UI-surface file in Files to Edit (no `components/**`, `app/**/page.tsx`,
`app/**/layout.tsx`). Mechanical UI-surface override did not fire.

## Infrastructure (IaC)
Skipped — no new infrastructure. Pure code change against the already-provisioned
`cron-content-generator` Inngest function (registered in-process; no server, systemd unit,
secret, DNS, or vendor account introduced). `web-platform-release.yml` handles the
container restart / function sync on merge.

## Non-Goals / Out of Scope

- **roadmap-review and community-monitor** — out of scope per the directive (roadmap-review
  recovered this session; community-monitor was fixed 2026-06-03). Do NOT touch.
- **The bwrap / sysctl / server.tf path** — fixed and verified in PR #4932. Do NOT re-touch.
- **The `--max-turns 50→80` bump** — explicitly dropped (Deliverable 3): the 2026-06-05
  Sentry evidence shows an API-500 mid-eval crash, not turn-exhaustion.
- **Cohort-wide generalization (the 7 OTHER always-create producers with the same hole):**
  `cron-producer-output-wiring.test.ts` lists 8 always-create producers
  (roadmap-review, content-generator, competitive-analysis, growth-audit, growth-execution,
  seo-aeo-audit, community-monitor, campaign-calendar). They ALL share the read-only
  `resolveOutputAwareOk` pattern and therefore the SAME silence hole — none creates a
  handler-level fallback issue. The directive scopes this PR to **content-generator ONLY**,
  so the cohort fix is deliberately deferred. **Deferral tracking:** file a follow-up issue
  ("generalize handler-level fallback audit-issue to all always-create cron producers")
  referencing this PR as the proof-of-pattern, milestone from
  `knowledge-base/product/roadmap.md`. Re-evaluation criterion: after this PR proves the
  pattern on content-generator, extract the fallback into a shared
  `_cron-shared.ts` helper and wire all 8 producers. **Do not silently leave this
  undocumented** (`wg-when-deferring-a-capability-create-a`).

## Open Code-Review Overlap

None. (No open `code-review` issue references `cron-content-generator.ts`,
`_cron-shared.ts`, or `cloud-scheduled-tasks.md` at plan time — to be re-verified at /work
via the two-stage `gh issue list --json` + standalone `jq --arg` query.)

## Sharp Edges

- **`resolveOutputAwareOk` is read-only — do NOT mistake "mirror the output-check pattern"
  for "an existing sibling already creates the fallback issue."** No always-create producer
  creates a fallback issue from the handler. The output-check is the *gate*; the issue-create
  is net-new. A reviewer expecting a copy-paste from a sibling will not find one.
- **Idempotency under `retries: 1`.** The handler retries once on failure. Without a
  today's-prefix title dedup, a transient failure that retries could file TWO FAILED audit
  issues. Gate the create on a label+title-prefix search (mirror
  `cron-skill-freshness.ts:234 searchExistingFreshnessIssue`). Note: Inngest `step.run`
  memoizes successful steps across replays, but a step that THREW is re-run — so the dedup
  must be inside the step, not rely on memoization.
- **Token choice.** Prefer the installation-token-authed octokit (or `createProbeOctokit`,
  which 8 sibling handlers already use successfully for `POST /issues`) — never a PAT
  (`hr-github-app-auth-not-pat`). Verify the probe app has issue-write at /work; sibling
  precedent says it does.
- **Do not throw from the fallback step.** It runs near the `finally` teardown; a throw could
  skip `teardownEphemeralWorkspace`. Wrap in `try/catch` → `reportSilentFallback`.
- **`runStartedAt` is the replay-stable date anchor.** Use `runStartedAt.slice(0,10)` for the
  title date, NOT `new Date()` inside the step (which would drift across replays/retries and
  defeat the dedup).
- A plan whose `## User-Brand Impact` section is empty or placeholder will fail
  `deepen-plan` Phase 4.6 — this section is filled (threshold: aggregate pattern).
- **`Closes #4960` goes in the PR BODY, not the title.** This is a code fix (not an
  ops-remediation applied post-merge), so `Closes` (auto-close at merge) is correct here —
  the deploy that makes the fix live happens automatically via `web-platform-release.yml` on
  merge, and the watchdog will additionally auto-close on its next fire once a non-silent run
  lands.

## Test Scenarios

1. `verify-output` returns `false` (no issue in window) → exactly one
   `POST /repos/.../issues` with label `scheduled-content-generator` and title
   `[Scheduled] Content Generator - <date>`.
2. `verify-output` returns `true` (issue already produced by the prompt) → zero handler
   issue-creates.
3. Fallback issue-create throws (stubbed octokit rejects) → `reportSilentFallback` called,
   handler still returns and teardown still runs (no unhandled throw).
4. Source-shape: `--max-turns 50` still present (this PR does NOT bump the turn budget).
5. `cron-producer-output-wiring.test.ts` still green (content-generator remains a wired
   always-create producer).
