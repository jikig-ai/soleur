---
title: "feat: Inngest dispatch cron for the merge-queue stall check"
date: 2026-10-04
slug: merge-queue-stall-dispatch-cron
branch: feat-one-shot-9482-merge-queue-stall-dispatch
issue: 9482
type: feat
priority: p2
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
---

# feat: Inngest dispatch cron for the merge-queue stall check

Ref #9482 (follow-up (a) only). PR: #9491 (draft). Do NOT use `Closes` in the PR body: #9482 holds open items.

## Enhancement Summary

**Deepened on:** 2026-10-04
**Research agents used:** framework-docs-researcher (Inngest replay semantics, SDK 3.54.2), Explore (plan-claims verification sweep), plus the plan-review panel (DHH, Kieran, code-simplicity, CTO) and the deepen gates 4.6 to 4.12.

### Key Improvements
1. Handler is replay-safe (catch and report inside the step, heartbeat as a callback step, mint failure posts an error heartbeat then rethrows); confirmed against the installed SDK.
2. Missed file found: the new test reads the real workflow from outside the app, so it must be listed in `apps/web-platform/test/repo-wide-suites.ts` (file 17) or `repo-wide-containment.test.ts` goes RED.
3. Overclaims corrected: `merge-queue-stall-check.test.sh` pins `workflow_dispatch` and the PRESENCE of a schedule cron, not `*/10`; ADR-248 is not the dispatch-shape authority (ADR-033's scope note is); Guard 3's forbidden set also includes the watchdog-table workflows.
4. Detection-margin arithmetic stated honestly (about 5 minutes best case, negative at the measured p90 runner wait); post-merge measurement now records `startedAt - createdAt` and filters cancelled runs.

### New Considerations Discovered
- Two reviewer challenges to operator-listed scope (drop the monitor; `*/5` cadence) are recorded in `knowledge-base/project/specs/feat-one-shot-9482-merge-queue-stall-dispatch/decision-challenges.md`; defaults kept.
- Deepen gate 4.10 (encryption posture) triggers on any `.tf` path; the plan carries an explicit "no new store" section.

## Overview

The merge-queue stall probe (`.github/workflows/merge-queue-stall-check.yml`) depends on GitHub `schedule:`
delivery, which is measured degraded on this repository. Follow-up (a) of #9482 moves the TRIGGER to an
Inngest cron that POSTs `workflow_dispatch` to the existing workflow. The GitHub-hosted runner stays the
EXECUTOR, so the probe keeps its documented property of using only the default `GITHUB_TOKEN` (no app secrets).
The workflow's own `*/10` `schedule:` stays byte-identical as the FALLBACK clock. The change is a copy of the
dispatch-hybrid precedent `cron-actions-queue-health-dispatch.ts` (#9273), plus an in-function Sentry
heartbeat so a dispatcher that stops firing is detectable.

Scope guard: follow-up (a) only. Follow-ups (b), (c), (d) and the three operator decisions in #9482 are not
touched; their defaults stand. The revert path for the queue change itself stays the Terraform diff in ADR-270.

## Research Insights

### Premise Validation (Phase 0.6)

- #9482 is OPEN; follow-up (a) is an unchecked box; no PR closes it. PR #9491 is the draft for this branch.
- The cited precedent file, workflow, manifest, placement, metadata, route, `.tf`, and parity-test paths all exist on
  `origin/main` (`git ls-files`). Trigger evidence reproduced: `gh run list --workflow merge-queue-stall-check.yml`
  shows the newest `schedule` run at 2026-07-01T08:03Z and the workflow state `active`. The six June 30 to July 1
  `schedule` runs give five gaps of 71, 86, 100, 236 and 249 minutes (median about 100 minutes against the
  15-minute window between the 45-minute threshold and the 60-minute timeout). That is the ADR-270 canary item 10
  condition ("a wider median gap makes Follow-up (a) the next change"), so the premise holds.
- ADR corpus check (mechanism = Inngest `workflow_dispatch` dispatcher): ADR-033's 2026-06-02 scope note says
  Inngest to `workflow_dispatch` is the CORRECT shape for an infra cron whose execution must stay in an ephemeral
  runner and only the "kill GHA scheduling jitter" goal applies; it explicitly warns against citing the Option C
  rejection as a blanket ban. The anti-circularity corollary (#6808) does not apply: the probe's subject is GitHub's
  merge queue, not web-1 or Inngest, and the `schedule:` fallback still fires through an Inngest outage. The
  yml header sentence "no Inngest needed (CTO ruling, #5780)" is about the EXECUTOR and stays true; the plan amends
  that header to say so rather than leaving a contradiction.
- Brief claim reconciled below: "about 8 files" and "cron-monitors.tf" (see Research Reconciliation).

### Research Reconciliation: spec vs codebase

| Brief claim | Reality (grep/read) | Plan response |
|---|---|---|
| Follow the precedent end to end, including `infra/sentry/cron-monitors.tf` | In the precedent, `cron-monitors.tf` carries the monitor `scheduled-actions-queue-health`, fed by the WORKFLOW's own heartbeat step. `merge-queue-stall-check.yml` has NO heartbeat step and NO monitor. `grep monitor-slug` finds nothing in it. There is nothing to "update"; a monitor must be created and given a feeder. | Create `scheduled-merge-queue-stall-dispatch`, fed by the dispatcher itself via `postSentryHeartbeat` (the `cron-bot-pr-reaper` pattern). The workflow is NOT given a heartbeat step (brief: only the comment block changes; the header documents "no app secrets"). |
| "About 8 files" | A new monitor moves counts pinned by parity gates: `README.md` (`**61 cron monitors**`), `sentry-monitors-audit.sh` (Class D sentence, `sentry-monitors-audit.test.sh` T25), `model.c4` clauses C4 `Of 61 cron monitors` and C6 `44 from webapp` (`c4-count-parity.test.sh`), `model.likec4.json` (freshness gate), `cron-monitor-alerts.tf` (routing parity Guard 1: a new monitor must be routed or listed unrouted with a `#N`), and `function-registry-count.test.ts` (route array count 71 to 72). Precedent #9280 touched the same set. | Plan carries 17 files, all mechanical parity edits. Nothing outside follow-up (a). |
| (implied) the new monitor is routable now | README "two-PR rule": a new monitor's detector id does not exist until its first apply, and the projection floor refuses to route an unknown id. | List `scheduled_merge_queue_stall_dispatch` in `cron_monitor_alert_unrouted` with a `#N` reason; routing is PR 2, tracked by one follow-up issue (Phase 0 task). |

### Property List (Phase 0.6b)

1. P1 The stall probe fires at its requested ~10-minute cadence regardless of GitHub `schedule:` delivery.
2. P2 A failed dispatch POST is reported loudly (Sentry issues stream) with the token redacted.
3. P3 A dispatcher that stops firing, or fails, is detectable by a Sentry cron monitor (missed or error check-in).
4. P4 An operator or agent can fire the dispatch on demand (manual-trigger event, allowlisted automatically).
5. P5 The dispatcher holds only a short-lived `actions: write`, repo-pinned token and no probe grants.
6. P6 The dispatch target exists on disk (a rename fails CI, not production); that it still accepts `workflow_dispatch` is already pinned by `merge-queue-stall-check.test.sh`.
7. P7 The recorded architecture and the workflow header no longer describe this follow-up as pending.

### Cut List (Phase 0.6b)

| Mechanism considered | Property it would buy | Disposition |
|---|---|---|
| Move the GraphQL read and issue filing into the Inngest function | P1 | CUT. P1 is bought by the trigger alone. It would put an App credential with `contents`/`issues` reach on the dispatcher, break the workflow's "default `GITHUB_TOKEN`, no app secrets" property, and violate the ADR-033 trigger/executor split. |
| Skip the dispatch when the queue is empty (pre-read of `mergeQueue`) | cost saving on 144 runs/day | CUT. Unmeasured (the repo is public: `gh api repos/jikig-ai/soleur --jq .private` returns `false`, so no billed minutes), adds a read grant to the dispatcher. A no-queue run exits green in seconds. |
| Executor-side heartbeat step in the workflow (end-to-end liveness: a dispatched run that never lands) | detects "dispatch OK but run never started" | DEFERRED, not built. Needs Sentry secrets in a workflow whose header documents none, and is outside "update the comment block". That failure mode is the SAME GitHub substrate the probe had before this change. Tracked in the single follow-up issue filed in Phase 0 (re-evaluate after the first measured check-in). |
| New ADR | P7 | CUT. No new decision: ADR-033's scope note already governs this shape. ADR-270's one stale sentence is amended instead. |
| Tighter cadence than `*/10`, or a higher threshold | wider detection margin | CUT. Out of scope; threshold and cadence are tied by `merge-queue-stall-check.test.sh` to `infra/github/ruleset-ci-required.tf`. Residual recorded under Risks. |
| Dedicated Inngest concurrency lane | isolation | CUT. Reuse the precedent's `"cron-dispatch"` account lane (a 2 to 5 second mint plus POST needs no host lane; `"cron-platform"` would let a 50-minute eval hold delay the dispatch). |

### Institutional learnings applied

- `knowledge-base/project/learnings/workflow-patterns/2026-09-30-monitor-trigger-substrate-conflation-and-list-read-verification.md`:
  delivery is not execution; keep `schedule:` byte-identical as the fallback; size the check-in margin to the measured delivery.
- `knowledge-base/engineering/operations/post-mortems/cron-monitors-paged-falsely-community-monitor-verify-race-queue-health-scheduler-deferral-2026-09-30-postmortem.md`: the incident this precedent answered.
- Open code-review overlap check: see `## Open Code-Review Overlap`.

## Open Code-Review Overlap

Queried 87 open `code-review` issues against every planned path. One match:

- #8595 "monitor registry guard gaps: `NON_INNGEST_MONITORS` stale entries + no cadence parity" touches `cron-monitors.tf` and
  `function-registry-count.test.ts`. **Acknowledge:** different concern (stale `NON_INNGEST_MONITORS` entries and
  cadence parity for GHA-fed monitors). This change adds an Inngest-slug monitor, so it adds no `NON_INNGEST_MONITORS` row
  and leaves #8595 open and unaffected.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "an Inngest dispatch cron for .github/workflows/merge-queue-stall-check.yml, so the stall probe no longer depends on GitHub's unreliable `schedule:` delivery" | Phase 1 (function), Phase 2 (registration) | mapped |
| 2 | "new apps/web-platform/server/inngest/functions/cron-merge-queue-stall-dispatch.ts that POSTs workflow_dispatch to merge-queue-stall-check.yml" | Files to Create 1 | mapped |
| 3 | "Follow the precedent cron-actions-queue-health-dispatch.ts end to end: cron-manifest.ts, execution-placement.ts, routine-metadata.ts, app/api/inngest/route.ts, infra/sentry/cron-monitors.tf, the test file, and the cron-safe-commit-parity test" | Files to Edit 1 to 5, 9 and 10; Files to Create 2 | mapped |
| 4 | "Also update the comment block in merge-queue-stall-check.yml that names this follow-up as pending" | Files to Edit 11 (Phase 4) | mapped |
| 5 | "Scope: follow-up (a) only. Do not touch (b), (c) or (d), and do not change the three operator decisions in #9482" | Non-Goals; no file for (b)-(d) | mapped |
| 6 | "Reference #9482 in the PR body with \"Ref #9482\", NOT \"Closes\"" | Acceptance Criteria (PR body) | mapped |
| 7 | "Revert path for the queue change itself stays the Terraform diff documented in ADR-270" | Non-Goals; ADR-270 edit touches only the stall-probe sentence | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| Create `cron-merge-queue-stall-dispatch.ts` | "new apps/web-platform/server/inngest/functions/cron-merge-queue-stall-dispatch.ts" | asked |
| Create its test file | "the test file" | asked |
| Edit `cron-manifest.ts`, `execution-placement.ts`, `routine-metadata.ts`, `route.ts` | "cron-manifest.ts, execution-placement.ts, routine-metadata.ts, app/api/inngest/route.ts" | asked |
| Edit `cron-safe-commit-parity.test.ts` | "the cron-safe-commit-parity test" | asked |
| Edit `cron-monitors.tf` (new monitor) | "infra/sentry/cron-monitors.tf" | asked |
| Edit `cron-monitor-alerts.tf` (unrouted entry) | none | inferred: routing parity Guard 1 (`sentry-cron-monitor-routing-parity.test.ts`) reds a monitor that is neither routed nor listed with a `#N` |
| Edit `README.md` count, `sentry-monitors-audit.sh` count | none | inferred: `sentry-monitors-audit.test.sh` T25 reds a stale cron-monitor count |
| Edit `model.c4` counts and regenerate `model.likec4.json` | none | inferred: `c4-count-parity.test.sh` C4/C6 and `c4-model-freshness.test.sh` red on a new monitor |
| Edit `repo-wide-suites.ts` | none | inferred: `repo-wide-containment.test.ts` reds a test that reads outside the app but is not listed |
| Edit `function-registry-count.test.ts` (71 to 72) | none | inferred: the route-array count pin reds on a new function |
| Edit ADR-270 stall-probe sentence | none | inferred: recorded architecture must not lag the change (`wg-architecture-decision-is-a-plan-deliverable`); the sentence says the cron is "a follow-up" |
| Edit the workflow comment block | "update the comment block in merge-queue-stall-check.yml that names this follow-up as pending" | asked |
| File one follow-up issue (route monitor in PR 2; decide executor-side heartbeat) | none | inferred: two-PR rule needs a `#N` tracking issue for the unrouted entry, and a deferral without an issue is invisible |

### Split Assessment

- Subsystems touched: 3 (apps/web-platform, .github/workflows, knowledge-base/engineering/architecture)
- Planned files: 17 | Estimated changed lines: about 450 (about 250 of them the new function and its test; the c4 JSON regeneration is machine output)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly. The worst case is the merge-queue stall probe going dark or
  double-firing: a wedged queue is reported later (or an extra suspected-stall issue is filed), and a PR waits longer for merge.
  No user data, billing, or customer-facing surface is involved.
- **If this leaks, the user's workflow is exposed via:** the minted GitHub App installation token (`actions: write`, pinned to
  this repo, 5-minute minimum lifetime) appearing in an error message sent to Sentry. Vector closed by `redactToken` on the
  caught error and a test with a positive control; same credential class as the three existing dispatchers.
- **Brand-survival threshold:** none
- threshold: none, reason: the diff touches `apps/web-platform/server/` and `apps/web-platform/infra/` (sensitive-path regex) but adds no new credential class, data surface, or user-facing path; it reuses the audited `mintInstallationToken` chokepoint with a narrower-than-default grant.

## Architecture Decision (ADR/C4)

No new ADR. The decision shape (Inngest trigger, GitHub-hosted executor) is already ADR-033's scope note; the plan's one ADR task is a
factual amendment so the record does not lag the change.

### ADR

- Amend ADR-270 `### Stall probe (best-effort)` with a ONE-CLAUSE replacement (the source text spans a line break: "`workflow_dispatch` cron, a follow-up" then "(`decision-challenges.md`, Follow-up (a))"; edit the multi-line span, not a single line): the fix is the Inngest `workflow_dispatch` cron `cron-merge-queue-stall-dispatch` (landed with #9482 follow-up (a)), the workflow's `schedule:` is now the fallback, and its header is the authority for the timing story. Add "(Follow-up (a) landed)" to canary item 10 so it does not read stale; leave its measurement text. Do not edit `## Decision`, the three operator decisions, or the revert path. ADR-270 stays `adopting`. Cite ADR-033's 2026-06-02 scope note (Inngest trigger, ephemeral-runner executor); do not cite ADR-248, which covers the in-process watchdog clock, not this shape.

### C4 views

All three of `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` are READ at work time before this task is closed (completeness mandate).
Enumeration checked so far (grep over `model.c4`, to be confirmed by the full read):

- External human actors: none new. External systems/vendors: GitHub REST (already an edge: `webapp`/`api -> github`) and Sentry (`github -> sentry` edge). No new vendor.
- Containers/data stores touched: none new (no store; Inngest run-state is the existing `inngest -> inngestRedis`).
- Actor-to-surface relationships: none change (the dispatcher uses the existing soleur-ai App token path).
- The merge queue and the stall probe are not modeled in `model.c4` today (no `queue` hit outside the Inngest queue), so no element description is falsified.
- Derived cardinalities that DO move (gated by `plugins/soleur/test/c4-count-parity.test.sh`): C4 `Of 61 cron monitors` to 62 and C6 `44 from webapp` to 45
  on the `github -> sentry` edge. C1/C2/C3/C5 do not move (no new workflow heartbeat step). Regenerate `model.likec4.json` with
  `scripts/regenerate-c4-model.sh`.

## Observability

```yaml
liveness_signal:
  what: Sentry cron check-in to monitor scheduled-merge-queue-stall-dispatch (status ok after each successful dispatch POST, error when the POST fails)
  cadence: every 10 minutes (crontab "*/10 * * * *"), checkin margin 30 minutes
  alert_target: Sentry issue on the monitor (declared-unrouted under the two-PR rule, #N of the Phase 0 follow-up issue; routed to email in PR 2)
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf (resource scheduled_merge_queue_stall_dispatch) and apps/web-platform/server/inngest/functions/cron-merge-queue-stall-dispatch.ts (SENTRY_MONITOR_SLUG)
error_reporting:
  destination: Sentry project soleur-web-platform via reportSilentFallback (feature cron-merge-queue-stall-dispatch, op dispatch-workflow); token-mint failures via the Inngest sentry-correlation middleware tagged inngest.fn_id
  fail_loud: Sentry issue "merge-queue-stall-dispatch workflow_dispatch failed" with the installation token redacted; the function returns ok false with errorSummary
failure_modes:
  - mode: dispatch POST rejected (403 App grant drift, 404 workflow renamed, 422 no workflow_dispatch trigger)
    detection: reportSilentFallback issue plus an error-status check-in on the monitor; P6 test fails CI on a rename or a removed trigger before it reaches production
    alert_route: Sentry issue stream now; monitor email after the PR 2 routing
  - mode: dispatcher stops firing (cron trigger lost on registration, Inngest outage, function unregistered)
    detection: missed check-in on the monitor after the 30-minute margin; an Inngest-substrate outage is also paged by scheduled-inngest-health
    alert_route: Sentry issue now; monitor email after the PR 2 routing
  - mode: dispatch OK but the executor run never lands (GitHub-side delay)
    detection: not detected by this change (same GitHub substrate as before); deferred to the executor-side heartbeat decision in the follow-up issue
    alert_route: none until that decision
logs:
  where: pino logger.info line "Dispatched merge-queue-stall-check workflow" to Better Stack via stdout; GitHub Actions run history for the dispatched run
  retention: Better Stack plan retention; GitHub Actions run history 90 days
discoverability_test:
  command: curl -fsS --max-time 10 https://api.github.com/repos/jikig-ai/soleur/actions/workflows/merge-queue-stall-check.yml/runs?event=workflow_dispatch
  expected_output: workflow_dispatch
```

### Infrastructure (IaC)

#### Terraform changes

`apps/web-platform/infra/sentry/cron-monitors.tf` (one `sentry_cron_monitor`, provider `jianyuan/sentry` already pinned; no new variables or secrets) and
`cron-monitor-alerts.tf` (one `cron_monitor_alert_unrouted` entry). Existing root with its R2 backend; no new root.

#### Apply path

`apply-sentry-infra.yml` auto-applies the sentry root on push to `main` (ADR-031, no dashboard step). The monitor is created in Sentry on that apply; the
first check-in arrives on the first dispatcher fire after the web deploy. No taint, no downtime.

#### Distinctness / drift safeguards

Slug `scheduled-merge-queue-stall-dispatch` equals the code constant (`sentry-monitor-iac-parity.test.ts`). State-storage notes unchanged (no secret value in state).

#### Vendor-tier reality check

Each declared cron monitor bills about $0.78 per month (`CRON_MONITOR_MONTHLY_USD` in `sentry-monitors-audit.sh`) under the existing Sentry PAYG cap; no free-tier gate.

## Encryption Posture

This plan edits `.tf` files (the deepen-plan 4.10 trigger matches on the path) but introduces no persistent store and no new connection class; the section records that explicitly.

```yaml
at_rest:
  - store: none introduced
    mechanism: not applicable (no volume, bucket, table, queue, cache, backup target or log sink is created; the only new resource is a Sentry cron-monitor definition, an existing resource type already classified in scripts/encryption-posture-ledger.json)
    evidence: scripts/lint-encryption-posture.py --repo-sweep resolves every resource type under apps/*/infra against the ledger; sentry_cron_monitor already has 61 instances there
    defends_against: not applicable
    does_not_defend: any data the monitor or its check-ins carry is only a slug and an ok/error status; no user data or secret is stored by this change
    disclosed_as: no new disclosure
    live_verification: the lint-encryption-posture.py run in Acceptance Criteria
in_transit:
  - connection: Inngest dispatcher (web-1) to api.github.com (REST workflow_dispatch) and to the Sentry ingest host (cron check-in)
    tls: HTTPS, the existing octokit and postSentryHeartbeat clients, unchanged
    cert_verification: on (no NODE_TLS_REJECT_UNAUTHORIZED override; unchanged from the three existing dispatchers)
    does_not_defend: a compromise of the dispatcher host itself, or of the App installation token inside its 5-minute lifetime; mitigated by the actions:write-only repo-pinned scope and token redaction, not by transport encryption
    disclosed_as: no new disclosure
```

## Guard Contract

### Guard 1 — dispatcher credential and target shape (the new test file)

**Property.** The dispatcher mints exactly one `actions: write` token pinned to this repo, issues exactly one request, and that request is a `workflow_dispatch` POST to a workflow file that exists.

**Assembly.** Chokepoints: (a) the single `mintInstallationToken({... permissions, repositories})` call site in the handler; (b) the single `octokit.request(...)` call site and its `{owner, repo, workflow_id, ref}` object; (c) the `WORKFLOW_FILE` constant versus `.github/workflows/<WORKFLOW_FILE>` on disk (existence only; the trigger shape and cron are owned by `merge-queue-stall-check.test.sh`); (d) the precedent's source-text anchors, cloned as is (no `issues:`/`actions: "read"` grant literal, no process-spawn import). A second request or a second mint anywhere in the file is a member the first-member check must not skip.

**Mutation matrix** (trimmed after plan review: rows that `merge-queue-stall-check.test.sh` already covers, and the cron-equality row, were cut):

| # | Mutation | Expected |
|---|---|---|
| 1 | add `issues: "write"` (or drop `repositories`) in the mint call | RED (`toEqual` on mint args, not `toMatchObject`) |
| 2 | handler returns before calling `mintInstallationToken` or `octokit.request` (the guard's own dispatch reports nothing) | RED (`toHaveBeenCalledTimes(1)` on both spies; also proves a blind spy cannot pass) |
| 3 | add a SECOND `octokit.request` after the compliant dispatch (for example a `GET` of the queue) | RED (call count 1 and exhaustive params `toEqual`) |
| 4 | change `WORKFLOW_FILE` to a name with no file on disk, or rename the workflow | RED (on-disk `existsSync` row) |

Harness row. Suite edit that MUST drive the suite RED: re-point the mocked `Octokit.request` at a function that is not `h.requestSpy`; row 2's `toHaveBeenCalledTimes(1)` must go RED. Must-PASS non-canonical input: a failure message that embeds a DIFFERENT fake token string than the mint mock returned must still be redacted when the mock's token is changed (the redaction test derives the token from the mock, not a literal), so the redaction row is not satisfied by a hard-coded string.

**Anchor.** The test compares the SUT's constants to a STORED expectation, so one diff could weaken both. The independent mover is the real workflow file on disk (row 4 reads it, not a literal), plus `merge-queue-stall-check.test.sh`, which already pins that file's `on:` keys including `workflow_dispatch` (S2, mutation M6) and the PRESENCE of a non-empty `schedule` cron (S1, mutation M5; it does not pin the `*/10` value, so byte-identity of the cron is owned by the comment-only `git diff` acceptance check below); weakening both the SUT constant and the workflow in one diff still fails the existing suite.

## Implementation Phases

### Phase 0: Tracking issue (before code)

- File ONE issue via `gh issue create --label deferred-automation` (label verified to exist with `gh label list`; the same label #9482 carries), milestone `Post-MVP / Later` unless
  `knowledge-base/product/roadmap.md` names a more specific CI/CD phase. Title: "route the scheduled-merge-queue-stall-dispatch cron monitor (two-PR rule)". Body:
  what was deferred and why (the PR 2 routing), re-evaluation trigger "after the first apply creates the monitor and its first check-in lands; owner: CTO routine owner", `Ref #9482`.
  Use its number as the `#N` in the unrouted-map reason. The executor-side-heartbeat deferral (Cut List row 3) is recorded as a comment on #9482 at ship time, not as a second issue;
  its re-evaluation trigger is the measured `run_started_at - created_at` latency of the dispatched runs (see Post-merge).

### Phase 1: The function (RED then GREEN, `cq-write-failing-tests-before`)

1. Write `apps/web-platform/test/server/inngest/cron-merge-queue-stall-dispatch.test.ts` first (RED), cloning `cron-actions-queue-health-dispatch.test.ts` and
   `cron-bot-pr-reaper.test.ts`'s heartbeat spy. Rows:
   - import-time smoke; registration source anchors: `id: "cron-merge-queue-stall-dispatch"`, `cron: "*/10 * * * *"`,
     `event: "cron/merge-queue-stall-dispatch.manual-trigger"`, `scope: "fn"`, `key: '"cron-dispatch"'`, `retries: 1`,
     `SENTRY_MONITOR_SLUG = "scheduled-merge-queue-stall-dispatch"`.
   - dispatch anchors: endpoint string, `"merge-queue-stall-check.yml"`, `ref: "main"`, `@octokit/core`, `reportSilentFallback`.
   - HARD NON-GOAL negative anchors (`actions: "read"`, `issues: "write"`, `mkdtemp`, `spawn(`, `child_process`).
   - behavior: mint args `toEqual({ tokenMinLifetimeMs: 5*60*1000, permissions: { actions: "write" }, repositories: ["soleur"] })`; request args `toEqual`
     `{ owner: "jikig-ai", repo: "soleur", workflow_id: "merge-queue-stall-check.yml", ref: "main" }` with `toHaveBeenCalledTimes(1)` on mint and request; `{ ok: true }`; heartbeat spy called once (use `toMatchObject`: the call also carries `logger`) with
     `{ ok: true, sentryMonitorSlug: "scheduled-merge-queue-stall-dispatch", cronName: "cron-merge-queue-stall-dispatch" }`.
   - dispatch failure: request rejects with a message containing the mock's token (derived from `h.mintSpy`, not a literal); `reportSilentFallback` called once with `feature`; message redacted with the
     `[REDACTED-INSTALLATION-TOKEN]` positive control; heartbeat spy called once with `ok: false`, `reportSilentFallback` still once under the replaying fake; result `{ ok: false, errorSummary }`.
   - mint failure: `mintSpy` rejects; the handler posts ONE `ok: false` heartbeat and then RETHROWS (so retries and the Inngest sentry-correlation middleware still apply); no dispatch is attempted.
   - on-disk row (Guard 1 row 4): `existsSync` of `.github/workflows/merge-queue-stall-check.yml` resolved from `__dirname`. No YAML parse and no cron-equality row: `merge-queue-stall-check.test.sh` owns the workflow's `on:` keys and the presence of a schedule cron, and leaving the dispatcher's cadence uncoupled from the fallback lets it be tuned later.
2. Write `apps/web-platform/server/inngest/functions/cron-merge-queue-stall-dispatch.ts` (GREEN), cloned from the precedent with: `FUNCTION_NAME`,
   `WORKFLOW_FILE = "merge-queue-stall-check.yml"`, `SENTRY_MONITOR_SLUG = "scheduled-merge-queue-stall-dispatch"`, cron `*/10 * * * *`,
   manual-trigger event `cron/merge-queue-stall-dispatch.manual-trigger`. Handler order (replay-safe: Inngest re-executes the whole handler after every step, so any side effect outside a `step.run` repeats on replay and a catch block that reports would report once per replay):
   (i) `let token; try { token = await step.run("mint-installation-token", ...) } catch (e) { await step.run("sentry-heartbeat-error", async () => { await postSentryHeartbeat({ ok: false, ... }) }); throw e }` (the mint is the most probable real failure; without this it surfaces only as a missed check-in about 40 minutes later; rethrow keeps retries and the middleware capture);
   (ii) `const dispatch = await step.run("dispatch-workflow", async () => { try { ...POST...; return { ok: true } } catch (err) { redact; reportSilentFallback; return { ok: false, errorSummary } } })` (catch and report INSIDE the step, as `cron-bot-pr-reaper.ts` does, so the report is memoized; the step never throws, so the function-level `retries: 1` no longer re-drives a failed POST, and the next 10-minute tick is the retry);
   (iii) `await step.run("sentry-heartbeat", async () => { await postSentryHeartbeat({ ok: dispatch.ok, sentryMonitorSlug, cronName, logger }) })` (a callback, not an eager promise); return `{ ok: dispatch.ok, errorSummary }`.
   Test coupling: the `step.run` fake used for the "called once" assertions must REPLAY (invoke the handler twice, returning memoized results for already-run step names) so a report-outside-the-step regression turns the `reportSilentFallback` count RED; the precedent's inline fake cannot show this. Header comment: reuse the precedent's WHY structure but state
   this probe's own facts (subject is the merge queue, not the Actions runner pool; the executor keeps the default `GITHUB_TOKEN`; measured gap about 100 minutes; the `schedule:` fallback is byte-identical;
   detection latency is now threshold 45 minutes + at most one 10-minute cadence + runner start). Do not name external-verifier workflow files in strings under `server/inngest/`
   other than the dispatched workflow (execution-placement Guard 3 scans strings there: run its test to confirm `merge-queue-stall-check.yml` is allowed, as the precedent's `scheduled-actions-queue-health.yml` is).

### Phase 2: Registration and parity rows

3. `server/inngest/cron-manifest.ts`: insert `"cron-merge-queue-stall-dispatch"` alphabetically (after `cron-membership-health`, before `cron-nag-4216-readiness`).
4. `server/inngest/execution-placement.ts`: row `portable`, reason "host-free: mints an actions:write-scoped App token and POSTs a workflow_dispatch; the probe itself runs on a GitHub-hosted runner (#9482)". Keep workflow file names out of the reason string.
5. `server/inngest/routine-metadata.ts`: description (10 to 160 chars) "Dispatches the merge-queue stall check every 10 minutes so GitHub schedule deferral cannot hide a stuck queue entry (#9482).", `domain: "Engineering"`, `ownerRole: "CTO"`, `scheduleLabel: "Every 10 min"`, `manualTrigger: "confirm"` (external-egress dispatcher, like the precedent).
6. `app/api/inngest/route.ts`: import and add `cronMergeQueueStallDispatch` to the `functions` array (keep array order consistent with neighbours).
7. `test/server/inngest/function-registry-count.test.ts`: `71` to `72` and the `// 71 -> 72: cron-merge-queue-stall-dispatch (#9482 follow-up (a))` history line. No `NON_INNGEST_MONITORS` row (the slug maps to code).
8. `test/server/inngest/cron-safe-commit-parity.test.ts`: acknowledge `cron-merge-queue-stall-dispatch` in the dispatch-hybrid sibling-set comment block (comment only; covered by invariant 1's directory walk).
8b. `apps/web-platform/test/repo-wide-suites.ts` (add `"test/server/inngest/cron-merge-queue-stall-dispatch.test.ts"` in sorted position near the other `test/server/inngest/` entries)

### Phase 3: Monitor, routing, and count parity

9. `infra/sentry/cron-monitors.tf`: `resource "sentry_cron_monitor" "scheduled_merge_queue_stall_dispatch"` (name `scheduled-merge-queue-stall-dispatch`, `crontab = "*/10 * * * *"`, `checkin_margin_minutes = 30`, `max_runtime_minutes = 5`, thresholds 1/1, UTC) with a header comment in the file's style: dispatcher-fed (not the executor), margin follows the Inngest-fired cohort convention, no runner-queue allowance because the heartbeat posts from the dispatcher, a dead dispatcher pages inside about 40 minutes.
10. `infra/sentry/cron-monitor-alerts.tf`: add `scheduled_merge_queue_stall_dispatch = "<reason> (#<Phase 0 issue>)"` to `cron_monitor_alert_unrouted`, with the two-PR-rule comment (real cover meanwhile: a failed POST still raises a `reportSilentFallback` Sentry issue; the workflow's own `schedule:` fallback keeps firing).
11. `infra/sentry/README.md`: `**61 cron monitors**` to `**62 cron monitors**` (grep every `61` that cites the monitor count). `scripts/sentry-monitors-audit.sh`: Class D sentence `61 \`resource "sentry_cron_monitor"\` blocks` to 62 and extend the addendum list with the new monitor (keep the count on ONE line; T25 greps it).
12. `knowledge-base/engineering/architecture/diagrams/model.c4`: `Of 61 cron monitors` to 62 and `44 from webapp` to 45 (one clause each; do not change the 17 or the 15). Run `scripts/regenerate-c4-model.sh` to refresh `model.likec4.json`.

### Phase 4: Documentation

13. `.github/workflows/merge-queue-stall-check.yml` COMMENT BLOCK ONLY (no `on:`, `permissions:`, `env:` or step change; byte-identical `*/10` cron):
    - TIMING paragraph: replace "FOLLOW-UP (not in this PR): ... workflow_dispatch stays available ..." with a statement that the primary trigger is `cron-merge-queue-stall-dispatch.ts` (Inngest, `*/10`) and the `schedule:` below is the FALLBACK; keep the measured evidence sentences; KEEP VERBATIM the literals `detection latency = threshold + schedule delivery`, `degraded`, `FALSE POSITIVES ARE POSSIBLE`, `SUSPECTED stall that needs verification` and `STALL_THRESHOLD_MINUTES, 45) sits BELOW the measured merge_group CI maximum` (`merge-queue-stall-check.test.sh` S11/S12 grep them; append the new text after them, never replace them). State the margin as `60 - (45 + up to 10 + dispatch-to-runner-start + run time)`: it is about 5 minutes only in the best case and negative at the measured p90 runner wait (about 20 minutes on a congested pool), so say that explicitly instead of a single figure. One further sentence: the 60-minute timeout may count from the merge_group build start rather than `enqueuedAt`, which would widen the real window (unverified). Residuals: detection latency is now threshold + one 10-minute cadence + runner start, a dispatch that lands but whose run is delayed on the runner pool is not detected, so the probe stays BEST-EFFORT in both directions. The function header is the single authority for the trigger story; the workflow header, ADR-270 and the README point at it rather than restating it.
    - Header "WHY GH-Actions cron" paragraph: say the EXECUTOR stays on a GitHub-hosted runner with the default `GITHUB_TOKEN` (ADR-033 scope note: trigger on Inngest, execution in the ephemeral runner); "no Inngest needed" becomes "no Inngest EXECUTION needed".
    - the inline comment on the `- cron:` line is a CODE line and stays untouched (byte-identical cron, and it keeps the comment-only diff check valid); put the fallback wording on a standalone `#` line directly above `on:` ("the `schedule:` below is the FALLBACK clock; do not remove it: it still fires through an Inngest-substrate outage").
14. `knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md`: the one-sentence amendment described under Architecture Decision.

## Files to Create

1. `apps/web-platform/server/inngest/functions/cron-merge-queue-stall-dispatch.ts`
2. `apps/web-platform/test/server/inngest/cron-merge-queue-stall-dispatch.test.ts`

## Files to Edit

1. `apps/web-platform/server/inngest/cron-manifest.ts`
2. `apps/web-platform/server/inngest/execution-placement.ts`
3. `apps/web-platform/server/inngest/routine-metadata.ts`
4. `apps/web-platform/app/api/inngest/route.ts`
5. `apps/web-platform/infra/sentry/cron-monitors.tf`
6. `apps/web-platform/infra/sentry/cron-monitor-alerts.tf`
7. `apps/web-platform/infra/sentry/README.md`
8. `apps/web-platform/scripts/sentry-monitors-audit.sh`
9. `apps/web-platform/test/server/inngest/function-registry-count.test.ts`
10. `apps/web-platform/test/server/inngest/cron-safe-commit-parity.test.ts`
11. `.github/workflows/merge-queue-stall-check.yml` (comments only)
12. `knowledge-base/engineering/architecture/diagrams/model.c4`
13. `knowledge-base/engineering/architecture/diagrams/model.likec4.json` (regenerated)
14. `knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md`
15. `apps/web-platform/test/repo-wide-suites.ts` (list the new test; it reads outside the app)

## Acceptance Criteria

### Pre-merge (PR)

- [x] `cron-merge-queue-stall-dispatch.ts` exists, id `cron-merge-queue-stall-dispatch`, triggers `{ cron: "*/10 * * * *" }` and `{ event: "cron/merge-queue-stall-dispatch.manual-trigger" }`, `retries: 1`, lanes `{scope:"fn"}` and account `"cron-dispatch"`.
- [x] The new function is in `cron-manifest.ts`, `execution-placement.ts` (portable), `routine-metadata.ts`, and the `route.ts` `functions` array; `function-registry-count.test.ts` pins 72.
- [x] `cd apps/web-platform && npx vitest run test/server/inngest test/lib/inngest test/server/routines test/repo-wide-containment.test.ts` is green, including the new test file, `execution-placement.test.ts`, `routine-metadata-parity.test.ts`, `sentry-monitor-iac-parity.test.ts`, `sentry-cron-monitor-routing-parity.test.ts`, `cron-safe-commit-parity.test.ts`, `function-registry-count.test.ts`, and `manual-trigger-allowlist.test.ts`.
- [x] Guard 1 mutation rows 1 to 4 and the harness row were each applied once to the finished tree and the suite went RED; the replaying-fake row goes RED when `reportSilentFallback` is moved outside the step.
- [x] `bash plugins/soleur/test/c4-count-parity.test.sh`, `bash plugins/soleur/test/c4-model-freshness.test.sh`, `bash apps/web-platform/scripts/sentry-monitors-audit.test.sh` (T25), and `bash plugins/soleur/test/merge-queue-stall-check.test.sh` all pass (the last proves the workflow edit is comment-only: its mutation rows still bite).
- [x] `git diff origin/main -- .github/workflows/merge-queue-stall-check.yml` shows ONLY `#` comment lines changed (assert with `git diff -U0 origin/main -- <file> | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' | grep -vE '^[+-][[:space:]]*#'` printing nothing).
- [x] The workflow header no longer contains the sentence "FOLLOW-UP (not in this PR)" and states the Inngest dispatch is the primary trigger and `schedule:` the fallback; ADR-270 no longer says the cron "is a follow-up".
- [x] `cron_monitor_alert_unrouted` carries the new label with a `#<n>` that resolves to the Phase 0 issue (`gh issue view <n>` returns it, `Ref #9482` in its body).
- [x] No file for follow-ups (b), (c), (d) is touched; the three operator decisions text in #9482 and ADR-270's `## Decision` and revert path are unchanged.
- [ ] PR body contains `Ref #9482` and does not contain `Closes #9482`.
- [x] `python3 scripts/lint-encryption-posture.py --repo-sweep` exits 0 (no new resource type; `sentry_cron_monitor` is already classified).
- [x] `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-10-04-feat-merge-queue-stall-dispatch-cron-plan.md` exits 0.

### Post-merge (verifiable by an agent, no operator step)

- [ ] `apply-sentry-infra.yml` run for the merge commit succeeded and `scheduled-merge-queue-stall-dispatch` exists in the org (`apps/web-platform/scripts/sentry-monitors-audit.sh` Class D shows no orphan, or the Sentry monitors API read).
- [ ] After the web deploy, `gh run list --workflow merge-queue-stall-check.yml --event workflow_dispatch --limit 30 --json createdAt,startedAt,conclusion` (filter out `conclusion=cancelled`, which the concurrency group produces on a duplicate slot) shows dispatch-event runs spaced about 10 minutes apart; record the median spacing AND the median and p90 of `startedAt - createdAt` in a comment on #9482 (do not edit the issue body). That latency is the trigger for the executor-side-heartbeat or `*/5` cadence decision.
- [ ] A first `ok` check-in appears on the monitor within 30 minutes of the first dispatched run.
- [ ] Comment on #9482 that follow-up (a) landed (PR number) and that (b), (c), (d) remain open; do not close #9482.

## Test Scenarios

- Registration shape and source anchors (cron, event, lanes, retries, slug).
- Narrowed-token mint and exhaustive dispatch params; heartbeat `ok: true` once.
- Dispatch failure: reported, token redacted with positive control, heartbeat `ok: false` once, `{ ok: false }` returned.
- Token-mint failure: one `ok: false` heartbeat, then the error is rethrown; no dispatch attempted.
- Replay safety: under a replaying `step.run` fake, a failed dispatch yields exactly one `reportSilentFallback` and one heartbeat.
- On-disk: the dispatched workflow file exists.

## Risks and Residuals

- **Detection window is still thin, by construction.** Threshold 45 minutes, timeout 60 minutes, cadence 10 minutes, plus runner start. Margin is `60 - (45 + up to 10 + dispatch-to-start + run)`: about 5 minutes at best and negative at the measured p90 runner wait (about 20 minutes on a congested pool, see the `cron-monitors.tf` queue-health header), so a stuck entry can still be missed. The post-merge measurement of `run_started_at - created_at` is the evidence for tuning cadence or adding the executor-side heartbeat. The workflow header says so; no threshold or cadence change is made here (tied to the ruleset by `merge-queue-stall-check.test.sh`; out of scope).
- **Duplicate fire at the shared `*/10` slot.** Dispatch plus fallback `schedule:` can fire in the same minute; the workflow's `concurrency` group (`cancel-in-progress: false`) queues the second run and the issue dedupe-by-title makes the probe idempotent. Same shape as the three existing dispatch-hybrids.
- **Unrouted monitor.** Until PR 2 routes it, a dead dispatcher opens a Sentry issue but emails nobody; real cover meanwhile is the `reportSilentFallback` issue on a failed POST and the surviving `schedule:` fallback.
- **Counts drift under a concurrent PR.** The monitor count, route-array count, and ADR ordinals are shared with sibling PRs; re-run the parity suites after any rebase onto `main`.
- **Marginal cost** about $0.78 per month for the new monitor under the existing PAYG cap.

## Non-Goals

- Follow-ups (b) `codeql-to-issues.yml` fail-closed, (c) duplicate push-to-main CI run, (d) pre-enqueue sync skip, and the three operator decisions in #9482.
- Any change to the stall threshold, the position filter, the issue body, labels, or the workflow's `on:`, `permissions:`, `env:` and steps.
- An executor-side Sentry heartbeat in the workflow (deferred, tracked by the Phase 0 issue).
- Routing the new monitor to email (PR 2, two-PR rule).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this plan carries `none` with the sensitive-path scope-out bullet.
- `execution-placement.test.ts` Guard 3's forbidden set is the two host-state verifiers (`workspaces-luks-verify.yml`, `scheduled-prod-version-drift.yml`) plus every `workflowFile` in `WATCHDOG_DISPATCH_TABLE` (`scheduled-inngest-health.yml`, `scheduled-zot-restart-loop.yml`), matched by stem over string literals under `server/inngest/`; `merge-queue-stall-check` collides with none. Run the test to confirm.
- A test that reads OUTSIDE `apps/web-platform` (the on-disk workflow row) must be listed in `apps/web-platform/test/repo-wide-suites.ts`, or `test/repo-wide-containment.test.ts` goes RED and the suite would be silently skipped in the gated project (the app-local precedent test never needed this).
- `postSentryHeartbeat` runs inside its own `step.run`; if it were inside the dispatch step, a heartbeat failure would be reported as a dispatch failure. A green check-in means "dispatched", not "probe executed" (this is the first dispatcher-fed slug; say so in a comment in the `.tf` and the function header so nobody later "fixes" it).
- A report or a heartbeat outside a `step.run` repeats on every Inngest replay; keep side effects inside steps.
- Do not hand-edit `model.likec4.json`; regenerate it (freshness gate is byte-identical).

## References

- Issue #9482 (follow-up (a)); PR #9491; ADR-270 (`### Stall probe`, canary item 10); ADR-033 scope note and anti-circularity corollary; ADR-031 (Sentry as IaC).
- Precedent: `apps/web-platform/server/inngest/functions/cron-actions-queue-health-dispatch.ts`, `cron-bot-pr-reaper.ts` (heartbeat step), PR #9280 (the same file set).
- Gates that must stay green: `sentry-monitor-iac-parity.test.ts`, `sentry-cron-monitor-routing-parity.test.ts`, `execution-placement.test.ts`, `function-registry-count.test.ts`, `c4-count-parity.test.sh`, `c4-model-freshness.test.sh`, `sentry-monitors-audit.test.sh`, `merge-queue-stall-check.test.sh`.
