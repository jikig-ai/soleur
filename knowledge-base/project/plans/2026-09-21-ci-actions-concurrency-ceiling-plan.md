---
title: "ci: raise the org-level GitHub Actions concurrency ceiling (issue 8450)"
date: 2026-09-21
slug: ci-actions-concurrency-ceiling
branch: feat-8450-ci-concurrency
issue: 8450
lane: cross-domain
type: chore
priority: P2
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

The org's `free` plan caps concurrent GitHub Actions jobs at 20 while a single PR head
dispatches ~18 runs and `CI` alone is 25 jobs — deploy-critical jobs wait 30–75 min at the
tail even though the pool clears ~250 runs/hr. This plan raises the ceiling via a GitHub
Team upgrade (operator billing step) and ships parallel code trims: three sub-hourly cron
cadence relaxations with paired Sentry-monitor updates, and a fail-closed path gate on the
`e2e` producer inside `ci.yml` so provably-unaffected diffs stop holding a runner slot for the
full suite duration (a green-skip still pays job setup + Playwright container pull, ~1–2 min of
the ~4.2 min run — the residual is stated honestly, and a future "optimization" to job-level
`if:` is explicitly rejected: it would green-skip on detector outage).

## Problem Statement / Motivation

Issue #8450 (measured, not quoted): org plan `free`, 0 self-hosted runners, 79 workflows,
26 `pull_request` producers, 20 real `schedule:` triggers, 24+2 required contexts across
the `CI Required` and `CLA Required` rulesets. Throughput is ~250 runs/hr (corrected
addendum — the body's original ~29/hr figure was a one-page sampling artifact), so the
system is not starved; the defect is **deploy-critical tail latency**: `migrate`/deploy
queued 30–75 min behind a saturated 20-job pool. Every merge during a saturated window
ships with its deploy arm unverified for up to ~75 min.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality on `origin/main` (2026-09-21) | Plan response |
|---|---|---|
| Four sub-hourly crons, ~216 runs/day | Confirmed *requested* cadence; delivered cadence is lower under `schedule:` jitter (`scheduled-prod-version-drift.yml` header measures `*/30` delivering at median ~114 min). | Savings stated honestly as *requested* ~216/day → ~150/day (96 inngest-health kept + 24 + 24 + 6); the capacity recovery is smaller than nominal. |
| `scheduled-inngest-health` `*/15`→`*/30` | Its header (`scheduled-inngest-health.yml:35`) argues `*/15` **because** inngest-down is a brand-survival outage (#5542, 3.5h silent crash-loop) — the same incident class this plan's `single-user incident` threshold covers. CTO + CPO both flag it. | **Kept at `*/15`.** TR2's own escape clause ("tighten less where the header argues otherwise") fires. Sub-hourly file count drops 4→1 (≤2 AC holds). |
| `knowledge-base/**`-only diffs skip heavyweight producers | `knowledge-base/**` is arguably the *worst* skip class: `adr-ordinals`, `markdown-lint`, `gitleaks scan`, `tc-document-sha-guard` verify content living in `knowledge-base/` — skipping them fabricates greens for exactly the gates those diffs exercise. | Filter target is the code-execution producer `e2e` with a **fail-closed allowlist** of provably-safe paths; content gates are untouched. |
| Path filters "where required contexts still report" | Established thrice (#5585 `tenant-integration-required`, #6589 `sentry-destroy-required`, #8203 `vendor-pin-required`): always-run required context over a path-gated producer; detection failure reds, never green-skips. `dorny/paths-filter` was evaluated and rejected (supply chain). | Reuse the doctrine in its simplest form: `e2e`'s own first step runs the classifier — no `needs:` edge, no `outputs:` forwarding; classifier failure reds the job, `pull_request`-only skip on an all-allowlisted diff, context always posts. |
| `apply-inngest-rls` hourly→4h | Header justifies hourly to shrink the cosmetic advisor-recurrence window ≤1h; `cron-monitors.tf` carries a timing-coupling comment ("03:37 UTC is deliberate: 20 minutes after the `17 * * * *` hourly Inngest-RLS") that the cadence change makes stale. | Adopt 4h cadence; rewrite the coupled comment honestly (alignment becomes ≤4h-windowed, not ≤20min). |
| Cadence changes are workflow-only edits | `zot_restart_loop_alarm` and `scheduled_prod_version_drift` `sentry_cron_monitor`s pin `*/30` crontabs (`apps/web-platform/infra/sentry/cron-monitors.tf:1058-1069, 1189-1201`) — applied by the `apply-sentry-infra.yml` IaC path. | Each cadence edit is paired with its monitor edit in the same PR; `apply-inngest-rls` has no monitor (verified — no `sentry_cron_monitor` resource and no `sentry-heartbeat` step). |

## Research Insights

**Premise Validation (Phase 0.6).** Issue #8450 OPEN (verified `gh issue view`); draft PR #8472 OPEN.
All four cited cron files and their `schedule:` expressions confirmed on `origin/main`; rulesets are
IaC (`infra/github/ruleset-*.tf`, ADR-032); `expenses.md` ledger exists with `approved-not-billing`
status convention; the #7931/#5806 prior plan merged (per-SHA `ci.yml` concurrency key + `workflow_run`
deploy gate live). Prior-art check: `2026-09-09-chore-ci-concurrency-and-workflow-run-deploy-plan.md`
already optimized *intra-pipeline* concurrency — #8450 is the orthogonal org-ceiling layer.
Nothing cited was stale.

**Property List (Phase 0.6b).**

1. Raise the org concurrent-job ceiling — only the paid plan tier buys this; no repo mechanism can.
2. Reduce scheduled-run demand on the pool (~4% of load — hygiene, not relief).
3. Stop provably-unaffected PR classes from holding runner slots for required-check compute.
4. Prove the tail moved after the ceiling raises — deploy-arm wait measurement, not fleet p50.

**Cut List (Phase 0.6b).**

| Mechanism considered | Property it would buy | Verdict |
|---|---|---|
| Cron-fleet registry doc | cadence inventory | Per-file header convention already carries it (FR2). Cut. |
| Standing queue-depth monitor | continuous observation | TR3 one-shot sampling + followthrough probe covers the soak; a permanent monitor is a separate build. Cut. |
| New ADR for the plan tier | decision record | Vendor-tier decisions live in `expenses.md` + ADR-032 reopener (iii) flip. Cut. |
| Merge-queue re-enable | ordered merges | Still blocked on CodeQL `merge_group` reporting (#5840, codeql-action#1537); the upgrade only satisfies reopener (iii). Cut — do NOT re-enable. |
| Self-hosted runner | unbounded capacity | NG1: public-repo fork-PR execution policy unsettled; tracked at #3723. Deferred. |
| `dorny/paths-filter` action | change detection | Rejected upstream precedent (supply chain); hand-rolled `git diff --name-only` is the in-repo pattern. Cut. |
| Path filters beyond `e2e` | more saturation relief | Per-producer anchor audits are the cost; scope to one producer, expand only if post-upgrade measurement shows the tail persists. Cut. |
| `[skip ci]` / `paths-ignore:` | skip mechanism | Actively forbidden — `lint-bot-synthetic-statuses.sh` fails on the tokens; `paths-ignore:` can leave required contexts pending forever. Cut. |

**Prior art / files of record:** ADR-032 (+ amendments #5585/#6589/#8149/#8203), ADR-212, ADR-217,
ADR-231 (490 KB workflow byte budget), `scripts/required-checks.txt` SSOT (parity-gated),
`scripts/pr-fanout-ledger.txt` (enforced by `pr-fanout-ledger.test.sh`), aggregator template at
`tenant-integration.yml:482-493` + `merge_group` arm at `:75-84`, detection recipe documented at
`infra-validation.yml:408-425`, expenses gate at `plugins/soleur/skills/ship/SKILL.md` Phase 5.5.

**Value-proposition measurement (Phase 0.6c).** Baseline measured 2026-09-21 (issue addendum):
fleet p50 queue ~7 min, 98 queued at sample, oldest 111 min, deploy-critical `migrate` 30–75 min;
~250 runs/hr completed. Commands: `gh api repos/jikig-ai/soleur/actions/runs?status=queued` and
per-workflow `actions/workflows/<id>/runs` (never the repo-wide `?event=` filter — stale window,
see learnings/2026-09-21).

## Proposed Solution

**Sequencing (CTO-endorsed):** operator billing upgrade first or in parallel (zero code risk,
instant effect), code trims land independently — they do not gate the upgrade, though their
benefit (relieved slot pressure) only materializes once AC-TEAM verifies; if the operator delays
billing, this PR carries the trims without payoff. Path filter
ships in this PR scoped to exactly one producer. The ADR-032 reopener-(iii) flip lands only
after `plan.name == team` verifies (separate follow-up commit/PR, tracked below).

### Phase A — Ledger + operator handoff (docs only)

- **A.1** `knowledge-base/operations/expenses.md` — new recurring row per COO assessment:

  `| GitHub Team (org plan, jikig-ai) | GitHub | dev-tools | 4.00 | approved-not-billing | - | supersedes unbilled Free tier; per-seat pricing — cost scales with org membership (currently 1 seat); public-repo Actions minutes are free — re-evaluate if repo ever goes private; flip to active when `gh api orgs/jikig-ai --jq .plan.name` returns `team`; kill criterion: downgrade to Free next cycle if G2/G3 trims alone prove to clear the tail | <!-- estimate verify_by=2026-10-21 owner=cfo source="GitHub billing receipt / org billing page — first draw may be prorated" -->`

  $4/mo is ~1% of the dev-tools subtotal — no `finance/cost-model.md` refresh needed.
- **A.2** Operator upgrade steps live in a durable artifact —
  `knowledge-base/project/specs/feat-8450-ci-concurrency/operator-upgrade-steps.md` — carrying the
  FR4 steps verbatim (org Settings → Billing → upgrade to Team), the verification command
  (`gh api orgs/jikig-ai --jq .plan.name` → `team`), the ledger-flip instruction, and an
  `action-required` comment on #8450 pointing at it (steps live in the doc, not the comment —
  issue comments are mutable, the doc is the durable artifact). `ship` authors the PR body (and
  `ship-operator-step-gate.sh` denies operator-step tokens there), so the PR body references the
  doc rather than embedding a checklist. **Automation status: UNVERIFIED** — attempted
  2026-09-21: Playwright MCP cannot launch (`Chromium distribution 'chrome' not found at
  /opt/google/chrome/chrome`); `gh`/REST has no plan-tier mutation endpoint (read-only
  `orgs/{org}.plan.name` confirmed); the `github` TF provider has no billing resource. The step
  needs an authenticated github.com session + payment authorization — a named human gate.
  `/work` retries the browser attempt if a runnable browser profile appears; otherwise the
  operator follows `operator-upgrade-steps.md`.
- **A.3** Record the pre-change baseline into
  `knowledge-base/project/specs/feat-8450-ci-concurrency/measurements.md`: fresh queued-age
  sample + deploy-arm (`web-platform-release.yml` + `migrate`) wait times measured as per-job
  `started_at − created_at` from `actions/runs`/`runs/<id>/jobs` (queued-status snapshots only
  see the currently-queued set), with timestamps and the sampling command — the before/after
  pair must be comparable (same event mix).

### Phase B — Cron cadence trims (3 files + 2 monitor pairs + 1 comment fix)

Each edit carries a one-line `schedule:`-site comment naming the protected detection window and
the worst-case added lag (FR2; ADR-231 byte budget — one line, no essays).

- **B.1** `scheduled-prod-version-drift.yml` `*/30`→`0 * * * *`. Window argument: detection is
  `DRIFT_SUSTAINED_THRESHOLD_MIN`-dominated (225 min, `scripts/prod-version-drift-check.sh:128`); delivered `*/30` already medians ~114 min,
  so the nominal request halving loses almost nothing. Paired edit:
  `sentry_cron_monitor.scheduled_prod_version_drift` `schedule.crontab` → `"0 * * * *"`;
  `checkin_margin_minutes` stays 360 (already sized for GHA-fired jitter, the file's own
  convention for this cohort).
- **B.2** `scheduled-zot-restart-loop.yml` `*/30`→`0 * * * *`. Window argument: alarm reads a 3h
  Better Stack window vs 5-min reporter emission — detection is window-bound, not poll-bound
  (header :43-46). Paired edit: `sentry_cron_monitor.zot_restart_loop_alarm` `schedule.crontab`
  → `"0 * * * *"`, `checkin_margin_minutes` 30→120 (NOT the 360 of the other cohort — the 3h
  Better Stack window bounds useful dead-alarm latency; 360 would push a genuinely dead alarm's
  page to ~7h, an unstated regression. 120 covers one dropped hourly tick + GHA jitter).
  Comment fallout, all rewritten in the same commit: `cron-monitors.tf` ~:1051-1054 (the
  "margin == inter-fire gap BY DESIGN" rationale — now false), ~:1152-1153 ("the workflow keeps
  \*/30" claim — now false), and the `checkin_margin_minutes=30` cross-file citation in
  `scheduled-zot-restart-loop.yml` ~:43-46.
- **B.3** `apply-inngest-rls.yml` `17 * * * *`→`17 */4 * * *`. Trade-off stated honestly:
  advisor-recurrence self-heal lag grows ≤1h→≤4h nominal (≤~7h20m worst case under one dropped
  tick), still ≪ the ≤24h cosmetic window the header cites. Rewrite the coupled comment at
  `cron-monitors.tf` (the `scheduled_supabase_advisor_scan` block, ~:1180) — the 03:37 dispatch
  no longer follows an RLS run by 20 min on every tick; state the real bound, not "within the
  4h window" — plus the workflow's own header (`apply-inngest-rls.yml` ~:12-18), which argues
  "hourly … ≤1h" self-heal and goes stale under 4h cadence.
- **B.4** `scheduled-inngest-health.yml` — **untouched at `*/15`** (brand-survival watchdog;
  both domain leaders flagged relaxing it).
- **B.5 (merge→apply gap)** `apply-sentry-infra.yml` auto-applies on merge, but that run queues
  behind the very pool this plan fixes (30–75 min tail): in the gap the workflow already runs
  hourly while the live `zot` monitor still expects `*/30`/margin-30 → one transient
  missed-check-in issue is EXPECTED (the 2026-06-15 false-page class this file documents).
  Mitigation, recorded in `operator-upgrade-steps.md`/PR: immediately post-merge run
  `gh workflow run apply-sentry-infra.yml` (dispatch exists, :112) to shorten the gap, and
  pre-note the expected transient Sentry issue on #8450 — a real subsequent miss must not be
  dismissed under Sentry's repeat-issue silence (#7142).

### Phase C — Path filter on `e2e` (fail-closed allowlist, established pattern)

Staged in two commits per the advisor consult — detector lands report-only first, the gate
flips only after its verdict is observed correct on this PR's own runs.

- **C.1 (commit 1 — report-only)** the allowlist classifier lands as a real script,
  `scripts/ci-e2e-classify.sh` (input: newline-separated changed-file list on stdin + event
  name arg; output: `true`/`false`), invoked by a new first step INSIDE the `e2e` job —
  NOT a `detect-changes` output. In-job detection is strictly simpler and strictly safer than
  the cross-job variant (DHH review): no `needs:` edge (a failed `detect-changes` would
  needs-skip `e2e`, and a skipped required check posts green — the fail-open the file warns
  about at `ci.yml` ~:1419), no job-level `outputs:` forwarding to forget, and a classifier
  failure exits the step → `e2e` reds (the sibling-gate doctrine: detection failure is an
  honest red, never a fabricated skip). The script's header comment carries the allowlist +
  "not in list = run" contract (CTO DX note). Semantics: `applicable=true` UNLESS
  `github.event_name == 'pull_request'` AND the changed-file enumeration succeeds AND returns a
  non-empty list consisting solely of allowlisted paths (`knowledge-base/**` incl.
  plan/spec/learning paths, root `*.md` — **NOT `docs/**`**: repo-root `docs/` is only
  `docs/legal/**`, which IS app-coupled via the pinned SHA-256s in
  `apps/web-platform/lib/legal/legal-doc-shas.ts` — the anchor audit caught it). Enumeration:
  `fetch-depth: 0` on the `e2e` checkout + guarded `if ! CHANGED=$(git diff --name-only
  "origin/${BASE_REF}...HEAD"); then echo true; exit 0; fi` (bare `bash -e` abort would exit
  non-zero before the emit — Kieran finding; enumeration failure must emit `true`, only a
  genuinely broken script exits non-zero). Empty/unresolvable diff and every non-PR event
  (`push`, `merge_group`, `workflow_dispatch`) also emit `true` — fail-closed. Commit 1 wires
  the step + an `::notice::` report only — no gating yet.
- **C.1a (observation gate)** Push commit 1 alone, verify on this PR's own CI run that the
  detector reports `applicable=true` (this PR touches `.github/**` + `apps/**/infra/**` — both
  outside the allowlist), THEN push commit 2 — the gate only fires if the commits land as
  separate pushes. A `false` report on this diff blocks the flip.
- **C.2 (commit 2 — gate flip)** `e2e`'s heavy steps gain
  `if: steps.detect.outputs.applicable == 'true'` — in-job step output, so a missing/unset
  output is impossible while the job runs (the classify step failing reds the job outright);
  a cheap skip-verdict step prints `e2e skipped: no app-affecting paths` to log AND
  `::notice::`/`GITHUB_STEP_SUMMARY` (visible on the checks page). The context reports green
  with a named skip reason — the #5585 "skipped-to-GREEN is an authoritative certification"
  rule makes the anchor audit (C.3) the security contract. A green-skip still pays job setup +
  Playwright container pull (~1–2 min of the ~4.2 min) — stated honestly; a future "optimize to
  job-level `if:`" is explicitly rejected (job-skip green-certifies without the verdict step).
- **C.3** Anchor audit: enumerate every top-level tree that can affect the built app
  (`apps/**`, `supabase/**`, `infra/**`, `scripts/**`, `plugins/**`, `.github/**`,
  lockfiles/manifests, `bunfig.toml`, test configs, Docker assets) and record the accepted
  gap set explicitly in the spec/measurements doc (any path NOT in the safe allowlist runs e2e).
- **C.4** `scripts/pr-fanout-ledger.txt` — update the `consequence` text on `ci.yml`'s row to
  record the step-gate, but DO NOT flip the `paths` flag: the enumerator reads only
  trigger-level `paths:`/`paths-ignore:` keys (`pr-fanout-ledger.test.sh` ~:249), so a step-level
  `if:` leaves the flag `no`, and flipping it to `yes` reds check A4 (`row paths == trigger
  paths`). Job count is unaffected (22 jobs declared).
- **C.5** `scripts/required-checks.txt` + canonical JSON — **unchanged**: the `e2e` context
  still reports on every PR (verify by inspection; parity test stays green).
- No new aggregator context, no ruleset change — `e2e` remains the registered context.

### Phase D — Verification + follow-through (post-merge, post-upgrade)

- **D.1** New soak probe `scripts/followthroughs/actions-queue-tail-8450.sh`: measures
  RUN-level `created_at → run_started_at` on `web-platform-release.yml` runs filtered
  `--event workflow_run` — two traps avoided: per-job `started_at − created_at` on `migrate`/
  `deploy` conflates `needs:`-chain upstream compute with queue wait (Kieran + strategist), and
  every merge produces TWO runs (a `push`-arm run carrying only `release` contaminates the
  sample unless filtered — the file's own text at `scheduled-prod-version-drift.yml:273-276`
  names `--event workflow_run` load-bearing). Before writing the probe, pin `job.created_at`
  semantics empirically on one queued run (`gh api repos/…/runs/<id>/jobs`). Exits 0 when
  deploy-arm p95 wait is <15 min across ≥5 workflow_run runs (fewer in-window is INSUFFICIENT
  evidence, exit non-zero — not a pass). Two preconditions before sampling:
  `gh api orgs/jikig-ai --jq .plan.name` must be `team` — else `SKIP-DECLARED` (exit 0, no alarm
  fatigue while AC-TEAM is pending); and runs must postdate `UPGRADE_NOT_BEFORE` (ISO ts, env
  var populated from the upgrade-verification timestamp in `measurements.md` — `plan.name`
  returns the CURRENT tier, not when it changed). Credential gap (concrete, not "confirm
  wiring"): `scheduled-followthrough-sweeper.yml` declares `contents: read + issues: write` —
  every unspecified scope is `none`, so `GH_TOKEN` has `actions: none` and the probe would 403.
  Fix: add `actions: read` to the sweeper job's permissions (its env comment anticipates new
  declarations). Enrollment: `earliest=` takes a concrete ISO timestamp, so the
  `<!-- soleur:followthrough … -->` directive + `follow-through` label are POSTED BY THE
  OPERATOR-UPGRADE STEP (checklist item in `operator-upgrade-steps.md`), not at merge time.
- **D.2** Post-upgrade verification (TR3 revised per CPO): `gh api orgs/jikig-ai --jq .plan.name`
  == `team` (record the verification timestamp — it is the probe's `UPGRADE_NOT_BEFORE`); then
  measure the **artifact the brand vector names**: merge→`workflow_run` registration lag (the
  one-shot leg, manual) plus a live invocation of the D.1 probe for deploy-arm queue age — the
  probe is the single measurement vehicle, not a duplicated manual method. `measurements.md` is
  the canonical home for all before/after numbers; the PR body links to it (no double-record).
- **D.3** ADR-032 has TWO amendment obligations (strategist review): (a) the `e2e` gate is the
  fourth instance of the required-context-over-gated-producer pattern and the FIRST where the
  registered context and the gated work share a job — record that variant + its accepted
  residual (green-skip still pays container-pull slot time) as an amendment **in this PR**;
  (b) the reopener-(iii) flip lands only after `plan.name == team` verifies — separate commit,
  (a)/(b) reopeners still required (CodeQL `merge_group`, codeql-action#1537; queue stays OFF,
  #5840).
- **D.4** Re-evaluation note on #8450: did the ceiling alone dissolve the tail? If yes, record
  that additional producer path filters are not warranted (the plan's Cut List stays cut).

## Alternative Approaches Considered

| Option | Verdict |
|---|---|
| Thin the whole cron fleet | ~4% of load; kept to the three defensible sub-hourly files; inngest-health stays `*/15`. |
| `paths:`/`paths-ignore:` on required producers | Prohibited by precedent — required context pends forever (ADR-032 escape-hatch; `infra-validation.yml:408-425`). |
| Self-hosted runner | Deferred — public-repo fork-PR execution policy unsettled (#3723). |
| Larger hosted runners (Team-only SKU) | Middle rung between plan ceiling and self-hosted; not needed now — listed for re-evaluation if 60 jobs still tails. |
| Merge queue | Still blocked on CodeQL `merge_group` (#5840); this plan satisfies only reopener (iii). |
| GitHub Support ticket to raise free-tier limit | Zero-cost fallback; unverified whether GitHub grants it — worth one attempt only if the operator declines the $4/mo. |

## Files to Create

- `scripts/followthroughs/actions-queue-tail-8450.sh` — soak probe (D.1)
- `scripts/followthroughs/actions-queue-tail-8450.test.sh` — Guard 2 harness (sibling
  convention: every followthrough probe ships a paired `.test.sh` — `bwrap-probe-selfreport-8016`,
  `ci-deploy-sentry-post-fail-6475`, `inngest-soak-6178`)
- `scripts/ci-e2e-classify.sh` — shipped allowlist classifier the detector calls (C.1);
  Guard 1 tests this artifact, not a YAML mirror
- `plugins/soleur/test/ci-e2e-skip-anchors.test.sh` — Guard 1 (C.1–C.3)
- `knowledge-base/project/specs/feat-8450-ci-concurrency/measurements.md` — before/after record (A.3, D.2)
- `knowledge-base/project/specs/feat-8450-ci-concurrency/operator-upgrade-steps.md` — FR4 steps + verification + ledger flip (A.2)

## Files to Edit

- `.github/workflows/scheduled-prod-version-drift.yml` — `schedule:` + FR2 comment (B.1)
- `.github/workflows/scheduled-zot-restart-loop.yml` — `schedule:` + FR2 comment (B.2)
- `.github/workflows/apply-inngest-rls.yml` — `schedule:` + FR2 comment (B.3)
- `apps/web-platform/infra/sentry/cron-monitors.tf` — `zot_restart_loop_alarm` + `scheduled_prod_version_drift` crontabs/margins; `scheduled_supabase_advisor_scan` comment fix (B.1–B.3)
- `.github/workflows/ci.yml` — `e2e` job: classify step (calls `scripts/ci-e2e-classify.sh`,
  checkout `fetch-depth: 0` so the base ref resolves) + heavy-step `if:` gating + skip-verdict
  step (C.1–C.2). `detect-changes` is NOT touched — in-job detection needs no `needs:` edge.
- `scripts/pr-fanout-ledger.txt` — `ci.yml` row `consequence` text only; `paths` flag stays `no`
  (step-level gating is invisible to the trigger-level enumerator — C.4)
- `.github/workflows/scheduled-followthrough-sweeper.yml` — job `permissions:` gains
  `actions: read` so `GH_TOKEN` reaches the probe's Actions API reads (D.1)
- `knowledge-base/operations/expenses.md` — recurring-vendor row (A.1)

- `knowledge-base/engineering/architecture/decisions/ADR-032-*.md` — amendment recording the
  `e2e` shared-job gate variant + slot-hold residual (D.3a).

Deferred (not this PR): the ADR-032 reopener-(iii) flip — lands when `plan.name == team`
verifies (D.3b).

## User-Brand Impact

- **If this lands broken, the user experiences:** a merge whose deploy arm queued ~75 min —
  a broken deploy goes unverified against the production app (the `web-platform-release`
  `workflow_run` arm is the named artifact).
- **If this leaks, the user's [data / workflow / money] is exposed via:** the deploy-verification
  pipeline for this repo — not a data-leak vector; the exposure is an unverified production deploy.
- **Brand-survival threshold:** `single-user incident`

(Carried forward from the brainstorm's `## User-Brand Impact`; CPO sign-off conditional on
Conditions A–C, all three incorporated: interim window named in Proposed Solution sequencing,
inngest-health kept at `*/15`, TR3 revised to measure the deploy-arm tail.)

## Observability

```yaml
liveness_signal:
  what: "Sentry cron monitors on the three trimmed workflows + followthrough probe verdict"
  cadence: "per-run check-ins; probe evaluated daily by scheduled-followthrough-sweeper"
  alert_target: "Sentry issue (missed check-in) / GitHub issue (probe fail) "
  configured_in: "apps/web-platform/infra/sentry/cron-monitors.tf; scripts/followthroughs/actions-queue-tail-8450.sh"

error_reporting:
  destination: "Sentry web-platform project (existing DSN via sentry-heartbeat composite)"
  fail_loud: "missed cron check-in opens a Sentry issue; probe non-zero exits file via sweeper"

failure_modes:
  - mode: "cadence relax makes a workflow darker than its monitor margin"
    detection: "sentry_cron_monitor missed-check-in (paired TF edit keeps schedule/margin coherent)"
    alert_route: "Sentry issue"
  - mode: "e2e skip allowlist wrongly covers an app-affecting path"
    detection: "ci-e2e-skip-anchors.test.sh (Guard 1) + anchor audit AC; post-merge: a docs-class PR that broke the app would surface via main-push e2e, not the skipped PR"
    alert_route: "CI red / incident"
  - mode: "deploy tail persists post-upgrade"
    detection: "actions-queue-tail-8450.sh soak probe (D.1)"
    alert_route: "follow-through issue stays open"

logs:
  where: "GitHub Actions run logs + Sentry cron check-ins"
  retention: "GitHub 90d / Sentry monitor history"

discoverability_test:
  command: "bash scripts/followthroughs/actions-queue-tail-8450.sh"
  expected_output: "PASS"
  credentials_required: "gh token (Actions read) — the probe's property is live queue state; no unauthenticated substitute reads it. Check 10 records SKIP-DECLARED."
```

## Guard Contract

### Guard 1 — `ci-e2e-skip-anchors.test.sh`: the e2e skip gate cannot certify an app-affecting diff

- **Property.** `e2e` skips heavy steps only when `ci-e2e-classify.sh` emits `false`, which it
  does only on `pull_request` with a non-empty all-allowlisted changed-file list; classifier
  failure exits non-zero → `e2e` reds (never a fabricated green-skip).
- **Assembly.** Two chokepoints: (a) the shipped classifier `scripts/ci-e2e-classify.sh` — the
  test executes the real artifact over fixture file-lists, never a re-implemented mirror; (b)
  grep-anchored assertions on `ci.yml` itself — the classify step precedes the heavy steps, the
  heavy-step `if:` references `steps.<id>.outputs.applicable == 'true'`, and the skip-verdict
  step exists — a dropped wiring line reds even when the classifier is correct.
- **Mutation matrix.**
  - Classifier fed a change-set with one path outside the allowlist (`apps/web-platform/x.ts`) → `true`.
  - Pure `knowledge-base/**` + root `*.md` change-set → `false` (must-PASS the skip arm — proves the gate isn't run-everything vacuous).
  - `docs/legal/foo.md`-only change-set → `true` (the allowlist does NOT cover `docs/**` — pinned-SHA coupling).
  - Mixed allowlist + `apps/` change-set → `true`; deleted-file-only, renamed-file, and empty change-sets → `true` (fail-closed).
  - `push`, `merge_group`, `workflow_dispatch` event args → `true` unconditionally.
  - Simulated diff/enumeration failure → classifier emits `true` (e2e runs — unresolvable is indistinguishable from unsafe); a genuinely broken script exits non-zero → `e2e` reds.
  - Suite row: rename the `applicable` output key / drop the skip-verdict step → guard reds on a stale harness (self-check).
- **Anchor.** The allowlist is the stored set; weakening it (adding `apps/**` or `docs/**`)
  must red the audit assertion that safe-set ∩ app-affecting-set = ∅.

### Guard 2 — `actions-queue-tail-8450.test.sh`: the soak probe cannot pass on stale or empty samples

- **Property.** The probe exits 0 only when `plan.name == team`, ≥5 deploy-arm runs postdate
  `UPGRADE_NOT_BEFORE` in-window, AND their p95 queued age is <15 min; empty or unmeasurable
  samples fail, never pass.
- **Assembly.** `gh api` per-workflow `actions/workflows/<id>/runs` + `actions/runs/<id>/jobs`;
  never the repo-wide `?event=` filter (documented stale-window trap).
- **Mutation matrix.**
  - Fixture API response with zero deploy-arm runs in-window → probe reds (no vacuous pass on empty data).
  - Fixture with p95 ≥15 min → reds.
  - Fixture predating `UPGRADE_NOT_BEFORE` → reds (stale window rejected — same class as the `?event=schedule` trap).
  - Fixture containing `push`-arm `web-platform-release` runs (release-only, no deploy chain) → excluded by the `--event workflow_run` filter; unfiltered fixture reds.
  - Precondition fixture `plan.name == free` → `SKIP-DECLARED`, exit 0 (no alarm fatigue while AC-TEAM is pending).
  - Harness row: point the probe at a synthetic fixture dir with a passing dataset → must PASS (proves the probe isn't fail-everything).

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/sentry/cron-monitors.tf` — edits to two existing
  `sentry_cron_monitor` resources (`zot_restart_loop_alarm`, `scheduled_prod_version_drift`:
  `schedule.crontab` + `checkin_margin_minutes`) and one comment fix in the
  `scheduled_supabase_advisor_scan` block. No new resources, no new providers, no new
  variables — the existing `apply-sentry-infra.yml` apply path covers this root
  (`-target=sentry_cron_monitor.*` scoped since #3811).

### Apply path

(b) — merge-triggered `apply-sentry-infra.yml` applies the monitor edits; no bootstrap script,
no downtime (monitor config only).

### Distinctness / drift safeguards

- Cadence↔monitor pairing is the drift surface — AC-CRON asserts the paired edit; no mechanical
  lint covers it (accepted residual, recorded in Test Scenarios).
- The GitHub org plan tier is **not** Terraform-manageable (the `github` provider has no
  billing/plan resource) and the purchase is a payment-authorized operator step — recorded
  as such in A.2 with the automation-feasibility justification.

### Vendor-tier reality check

GitHub Team raises the hosted concurrent-job ceiling 20→60 (the lever this plan buys);
public-repo Actions minutes remain free on both tiers — recorded as a visibility-flip caveat
in the expenses row.

## Domain Review

**Domains relevant:** Operations, Engineering

### Operations

**Status:** reviewed
**Assessment:** (COO) Ledger row shape is adequate — new row, not an edit to the Copilot row;
status `approved-not-billing` (never `active` before the billing flip — the #6453 defect class);
flip condition and kill criterion written into Notes; `verify_by` ~30 days post-upgrade against
the first invoice; per-seat multiplier and public-repo-minutes caveats recorded; no new
sub-processor/DPA; ~1% of dev-tools subtotal → no cost-model refresh.

### Engineering

**Status:** reviewed
**Assessment:** (CTO) Upgrade-first sequencing endorsed; self-hosted deferral holds (Hetzner/
Inngest precedent is scheduling substrate, not CI execution; fork-PR policy is load-bearing);
aggregator pattern blast radius is manageable per #5585/#6589/#8203 but anchors are the security
contract and `knowledge-base/**` is the wrong skip class; ADR-032 reopener (iii) must flip when
the upgrade lands; Sentry monitor margin/cadence coupling is a real paired edit; larger hosted
runners noted as the unpriced middle rung.

### Product/UX Gate

**Tier:** none (no UI-surface files in the plan's file lists — mechanical override does not fire)
**Decision:** CPO plan-time sign-off (required by `single-user incident` threshold): **conditional
sign-off granted** — conditions (A) interim window, (B) inngest-health carve-out, (C) tail-shaped
metric are all incorporated into the plan above.

**Brainstorm-recommended specialists:** none (brainstorm carried no `## Domain Assessments`; the
leader triad was declined by the operator there and re-run here per plan Phase 2.5).

## Open Code-Review Overlap

None — queried 68 open `code-review`-labeled issues against every path in Files to Edit/Create
(plus `concurrency`/`runner`/`self-hosted`/`schedule:` keyword sweep); no matches.

## Acceptance Criteria

### Pre-merge (PR)

- **AC-CRON** Sub-hourly cron files drop 4→1 (`scheduled-inngest-health` retained at `*/15`);
  each relaxed `schedule:` site carries the FR2 detection-window comment; the paired
  `sentry_cron_monitor` crontab/margin edits land in the same commit.
  Verify: `grep -n 'schedule:' -A2` on each edited workflow + `git show` pairing check.
- **AC-GATE** The `e2e` classifier reports `applicable=true` on this PR's own diff
  (observation gate C.1a); the skip verdict path is exercised by Guard 1's fixture matrix.
  Verified by `bash plugins/soleur/test/ci-e2e-skip-anchors.test.sh` (Guard 1) and
  the C.3 anchor audit recorded in `measurements.md`.
- **AC-PARITY** `pr-fanout-ledger.test.sh`, `required-checks-canonical-parity.test.sh`, and
  `workflow-file-size.test.ts` (byte budget) all stay green; `actionlint` clean on every
  edited workflow.
- **AC-PROBE** Probe + paired harness exist; `bash
  scripts/followthroughs/actions-queue-tail-8450.test.sh` drives the Guard 2 fixture matrix
  (empty window → red, pre-upgrade-timestamp samples → red, free-plan precondition →
  SKIP-DECLARED exit 0, passing dataset → PASS); `bash -n` parses both scripts.
- **AC-REF** The PR body says `Ref #8450` (not `Closes`) — the issue resolves on post-upgrade
  verification, not at merge.

### Post-merge (operator + soak)

- **AC-TEAM** `gh api orgs/jikig-ai --jq .plan.name` returns `team` — operator step per
  `operator-upgrade-steps.md`; the expenses row flips `approved-not-billing → active`
  the same day.
- **AC-TAIL** The deploy-arm tail measurement (D.2: merge→`workflow_run` registration lag +
  probe-measured p95 deploy-workflow job `started_at − created_at`) comes in under the Success
  Metrics threshold (p95 <15 min vs the 30–75 min baseline); recorded in `measurements.md`.
- **AC-ADR** ADR-032 reopener-(iii) amendment lands (in this PR if upgrade verified pre-merge,
  else a sibling chore commit tracked on #8450 — D.3). The upgrade does **not** re-enable
  the merge queue — stated in `operator-upgrade-steps.md`.

## Test Scenarios

| Mutation / scenario | Expected |
|---|---|
| Classifier fed a pure-`knowledge-base/**` changeset | `applicable=false`; e2e heavy steps skip; context posts green skip verdict |
| Same fixture + one `apps/` path | `true`; e2e runs in full |
| `push`/`merge_group`/`workflow_dispatch` event args | `applicable=true` unconditionally |
| Classifier exits non-zero (diff failure) | `e2e` job reds — never a fabricated skip |
| Revert one monitor crontab back to `*/30` while workflow is hourly | Sentry monitor expects more check-ins than arrive → would page; the paired-edit AC (AC-CRON) + review must catch it — there is no drift lint; noted as accepted residual |
| `actionlint .github/workflows/ci.yml` + each edited `scheduled-*.yml` | clean (workflows use actionlint; composite actions do not — none edited) |
| `bash -c` on each new/changed `run:` snippet | parses and exits 0 on dry fixture |
| Probe fixture: zero deploy-arm runs in window | probe exits non-zero |
| Probe fixture: pre-upgrade timestamps only | probe exits non-zero |
| Docs-only PR opened on the branch post-merge | `e2e` green-with-skip; all 24+2 required contexts report; merge unblocked |

## Success Metrics

- Deploy-arm queued p95 < 15 min within the soak window (was 30–75 min).
- Sub-hourly cron files: 1 (was 4); requested cron volume ~216→~150 runs/day.
- Zero pending-forever required contexts introduced (parity + merge-unblocked AC-GATE scenario).

## Dependencies & Risks

- **Operator billing authorization** is the load-bearing external step; the PR ships without it
  but AC-TEAM/AC-TAIL cannot verify until it lands. Interim exposure is named: between merge and upgrade,
  the deploy tail persists — `scheduled-prod-version-drift` remains the deploy-missing backstop.
- **Anchor-set drift**: a future PR adding a new app-affecting top-level dir must extend the
  allowlist's complement — Guard 1's audit assertion covers the enumerated set as of merge;
  residual risk recorded (no machine knows which dirs "affect the app").
- **Merge is not read-only**: this PR edits `apply-inngest-rls.yml`, whose `push:` arm lists
  the workflow file in its own `paths:` trigger — merging fires one extra production SQL apply.
  Idempotent with identity-preflight; noted, not blocked.
- **Billing-cycle assumption**: the ledger row records the $4.00 list price; annual prepay is
  ~$3.67/seat — the `verify_by` invoice check reconciles whichever the operator picks.
- **Delivered-vs-requested cadence**: savings are nominal-request; delivered savings are smaller
  under GHA jitter — metrics above are stated accordingly.
- **ADR-231 byte budget**: all new workflow comments ≤2 lines; no runbook relocation needed.

## References & Research

- Issue: #8450 (+ measurement comment 2026-09-21); brainstorm `2026-09-21-ci-runner-concurrency-brainstorm.md`; spec `specs/feat-8450-ci-concurrency/spec.md`
- Prior shipped work: #7931/#5806 plan (`2026-09-09-chore-ci-concurrency-and-workflow-run-deploy-plan.md`) — intra-pipeline concurrency layer, orthogonal to this org-ceiling change
- ADR-032 (+ amendments #5585/#6589/#8149/#8203), ADR-212, ADR-217, ADR-231
- Tracking: self-hosted runner deferral → #3723; merge queue → #5840; LPT leg-balance → #8006
- Learning: `2026-09-21-gh-actions-runs-event-schedule-filter-returns-stale-window.md` (per-workflow measurement method)
