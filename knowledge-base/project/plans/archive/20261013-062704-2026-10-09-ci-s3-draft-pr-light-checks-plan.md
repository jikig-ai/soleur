---
title: "ci: S3 draft-PR light checks, full set on ready_for_review (#9721 stage 3)"
date: 2026-10-09
slug: ci-s3-draft-pr-light-checks
branch: feat-one-shot-9728-ci-draft-light
issue: 9728
type: chore
lane: cross-domain
priority: p2-medium
domain: engineering
brand_survival_threshold: aggregate pattern
---

## Enhancement Summary

**Deepened on:** 2026-10-09. **Agents used:** architecture-strategist, spec-flow-analyzer (deepen pass); CTO, DHH, Kieran, code-simplicity (plan review); learnings-researcher. **Gates run:** user-brand impact (present, `aggregate pattern`), observability (5 fields; command `python3 scripts/lint-guard-contract.py <this plan>` returns `3 guard entries`), PAT-shape grep (no hits), UI wireframe (no UI surface), encryption posture (no store or connection), guard contract (lint green, assembly structural, rows derived from the design), scope check (one unfenced section, no `unmapped` or blocked rows), ADR ordinal (no new ADR), cited PRs and issues resolved live (#9772, #9808, #9409, #9400, #9306, #9818, #9876), `gh pr ready --undo`, `gh pr checks --required` and the `last: 1` ready-event timeline query verified, GitHub's `GITHUB_TOKEN` no-new-workflow-run rule fetched from docs.github.com (workflow_dispatch and repository_dispatch are the exceptions).

1. The planning-time census says gate 6 will pass (8.24 draft pushes per draft PR against the parent plan's windowed 2.6), so the expected branch is the full implementation; the stop branch is kept as a real deliverable.
2. The resolver is time-based with a closed state set (`n/a`, `full-decided`, `pending-full`, `no-run`, `stalled`, `awaiting-approval`); the deepen pass added the never-draft and bot-PR short-circuits, the green-`test` short-circuit for PRs readied before S3, the stale-row rule for manual re-runs, read-after-write lag handling and the clock-skew allowance.
3. Gate 5b is read early (Phase 1) and blocks both the canary and activation: the web-platform webhook route would raise an `engineering.ci_failed` card for every red draft run.
4. The probe runs from merge + 1 day (not + 8 days) and checks the live invariants, so the dark-window deadline and the stall signal are not blind in the riskiest week.
5. Entry-gate STOPs close the stage (`Closes #9728`); Branch C is a hold with S4 and S5 still parked, and that deadlock is surfaced to the operator.

### New considerations discovered

- A manual re-run of a pre-ready draft run reuses the cached `draft-light` output, can cancel the in-flight ready run through the per-ref concurrency group, and leaves a newer red `test` row; the plan forbids it as a recovery and gives `gh pr ready --undo` then `gh pr ready` instead (gate 1 sub-probe (i) measures it).
- Bot PRs opened `--draft` with `GITHUB_TOKEN` gain a real full run on the human ready click; this is a behavior change recorded in the amendment, not only a cost line.
- `draft-light` adds one runner queue hop in front of every heavy job on saturated runners; the canary records it.

## Overview

Stage 3 of the hosted-runner demand plan: draft pull requests would run only a light check set, and the
full required set would run when a PR is marked ready and again in the merge queue. This plan sequences
the stage as a measure-first decision: the cheaper-alternative census runs before anything else and may
close the stage with no workflow change.

Builds on `knowledge-base/project/plans/2026-10-07-ci-reduce-hosted-runner-demand-plan.md` (the parent
plan, read-only here), `knowledge-base/project/specs/feat-one-shot-ci-hosted-runner-demand/issues/s3-draft-light-checks.md`
and ADR-276 (status `adopting`; it stays `adopting`, see the Architecture section). Option R is decided
(ADR-276 Decision 4): the draft `test` aggregator concludes red. The kill-switch is the repository
variable `CI_DRAFT_LIGHT`, accepted value exactly `on`.

Spec note: no `spec.md` exists for this branch, so `lane:` defaults to `cross-domain` (fail-closed). `closes:` is deliberately absent from the frontmatter: `Closes #9728` belongs in the PR body only for Branch A (the stage closes by its stop rule); Branches B and C use `Refs #9728`.

## Research Reconciliation: brief and parent plan vs. this tree

| Claim | Reality (checked 2026-10-09 on this branch / `origin/main` 79482dab59) | Plan response |
|---|---|---|
| `ci.yml` is at its declared ceiling of 24 jobs | `yaml.safe_load(ci.yml)['jobs']` is 25 and `scripts/pr-fanout-ledger.txt` says 25: S2 added `push-dedupe` (#9808) | Any job S3 adds is 26: the ledger row is bumped with a dated note, as S2 did |
| S1 is "merged and live" | Merged (PR #9772). The post-merge census exists as a comment on #9727 (2026-10-09T15:52Z, 85.2% reduction, criterion of 80% met). ADR-276's Stage status list has NO `S1 live` line yet; the S2 amendment says a docs-only follow-up appends it | S3's amendment commit appends the `S1 live` line (both outcomes) |
| Pre-policy mean of 2.6 draft pushes per draft PR | 2.6 is 18 runs over 7 PRs inside one 6-hour window: it counts only the pushes that fell inside the window, not the PR's draft lifetime. A full-lifecycle pilot over the last 30 days gives 8.24 (n=425, median 8, see Research Insights) | Gate 6 is re-measured by a committed script on a closed-cohort definition; the pilot says the gate will probably pass, but it is not authoritative |
| "post-policy" mean pushes per draft PR is measurable | The policy "no draft push before a local `--affected` run passes" is enforced nowhere: `lefthook.yml` `pre-push` carries only the PII, questionnaire and rejected-register mirrors and the affected-ratchets lane (#9409, ratchets only); `pre-commit` runs `--affected` per commit, not per push; ship Phase 4 runs it before the Phase 6 push but the pipeline pushes drafts earlier (plan checkpoints, work commits). No post-policy population exists | Gate 6 uses a monotone short-circuit and a policy-ceiling bound (Phase 1), plus a third verdict, INDETERMINATE, for the case neither settles |
| `battery-owed.sh` "must not read a light `test` as full" needs a code change | It judges the newest row per name by `started_at` and demands `completed` + `success`; a draft `test` that concludes red is NOT-GREEN, so it already returns OWED | Expect no logic change; add the two mutation rows to its suite and prove they can go RED by mutating the script |
| The test aggregator needs a new arm | Its loop already sets `fail=1` on any `skipped` leg (message `SKIPPED — the leg did not run`), so skipped heavy legs already conclude red | Add an explicit draft arm anyway (message `draft: full battery owed at ready`, exit 1, `pull_request` only) so a later "tolerate skipped" edit cannot turn a draft green |
| Consumers are `monitor-pr-checks.sh`, ship Phase 7, `drain-prs` triage, `gh pr checks` readers, `admin-merge-ready.sh --wait` | Confirmed, plus: `plugins/soleur/skills/merge-pr/SKILL.md` carries a verbatim copy of the Phase 7 `required_failed` poll; `triage-prs.sh` counts `fails` from `statusCheckRollup`, so a ready PR with a ready run in flight would be tiered `needs-review`; `admin-merge-ready.sh --wait` treats a FAILED context as terminal, so a red draft row would end the wait at once | Phase 7 builds one shared resolver and points every reader at it instead of patching six copies |
| `gh pr ready` must use a non-`GITHUB_TOKEN` identity | No `gh pr ready` or `markPullRequestReadyForReview` exists in tracked code under `.github/`, `apps/` or `scripts/` (the plugin hits are skill prose and test fixtures); callers are agent sessions (ship Phase 6) and humans. Bot PRs are opened `--draft` by `bot-pr-with-synthetic-checks` and `fix-constraints-stage-b.yml` with `GITHUB_TOKEN` (no CI at open) and readied by a human click | Gate 2 verifies the user-token path; the census of callers is part of its record |
| The agent `--admin` path is a fallback for this PR | `admin-merge-ready.sh` exits 1 (`UNTRUSTED-CI`) for any PR editing `.github/workflows/` or `.github/actions/`, so the S3 PR itself (it edits `ci.yml`) has no agent admin merge; the operator merges it by hand if the queue livelocks | Recorded as a Risk; Branch A (no `ci.yml` edit) does not have this limit |
| Dark launch costs nothing | The `ready_for_review` entry in `types` is ungated: every drafted-then-readied PR gets one extra full run while the variable is unset (406 ready transitions in the last 30 days, about 13.5 a day at roughly 96 job-minutes a run, about 1,300 job-minutes a day) | Phase 9 arms the merge only when activation can follow at once; an authorized dark merge is bounded to 1 day by the probe |

## Research Insights

### Premise validation (Phase 0.6)

Checked with `gh issue view` / `gh pr view` on 2026-10-09: #9728 open (no comments); #9721 closed (parent);
#9727 (S1) closed 2026-10-09 with a post-merge census comment; #9512 (S2) closed, merged dark
(#9808); #9818 (S2 soak tracker) open; #9729 (S4) and #9730 (S5) open; #9876 (ADR-270 accepted, ADR-276
to `adopting`) merged; draft PR #9885 open. ADR-270 `status: accepted`. Repository variables list shows
only `GIT_DATA_ROOT_STATE_MIGRATED` and `WATCHDOG_ARMED`: `CI_DRAFT_LIGHT` and `CI_PUSH_DEDUPE` are
both unset. ADR corpus: the mechanism (draft light set, Option R/T) is ADR-276 Decision 4 itself; no ADR
rejected it. One stale premise corrected: the job ceiling (24 vs 25) and the pre-policy mean (windowed
2.6 vs full-lifecycle 8.24).

### Property List (Phase 0.6b)

1. A draft PR push consumes far fewer hosted-runner minutes than a ready PR push.
2. A PR cannot enter the merge queue, or be merged by any route this repo controls, on the strength of a light run.
3. Every required context still reports on every event; none is left pending or skipped-green; no reader treats a light result as a full one.
4. The reduction has a kill-switch, fails closed to full CI whenever state is unknown, and its non-switchable parts are named.
5. The stage's saving and its entry decision rest on one committed, self-checking measurement.
6. A PR that is readied reaches a full run, and a PR for which that did not happen is visible to an owner.

### Cut List (Phase 0.6b)

| Mechanism | Property | What already covers it or why cut |
|---|---|---|
| A skip arm on the ready run (reuse the draft run's full-mode green) | 1 | Cut: skipping the ready run's heavy legs needs a tolerance arm in `test` (Option T in disguise) or a skipped required row (the #8450 pattern). The ready run is always full; the dark-window cost is bounded instead (Phase 9) |
| A success marker or a new required context | 2, 3 | Option T, rejected by ADR-276 Decision 4 (`bot-pr-with-synthetic-checks` would post it green) |
| A new "light CI" workflow file | 1 | Parent plan Cut List: job-level gating inside `ci.yml` keeps required names stable |
| A run-name or check-name marker, or a jobs-API "this run was light" detector | 6 | Derivable from time: only runs created at or after the latest ready event speak for a non-draft head, and those can never be light by construction. No marker, no new ABI, no coupling to what else may skip `test-scripts` |
| Patching each of six consumer copies | 3 | One shared resolver script (Phase 7) |
| A live-fork probe for gate 3 | 4 | Design-invariant: forks run full whether or not `vars` reach them (see gate 3) |
| Re-doing superseded-run cancellation, path-gating Infra Validation, the five ADR-262 batteries | 1 | Parent plan Cut List |

### Pilot census for gate 6 (value-proposition measurement, Phase 0.6c)

Produced during planning, read-only, NOT authoritative (the committed script in Phase 1 is). Method:
`gh pr list --state all --search "created:>=2026-09-09" --limit 1000` (741 PRs); per-PR GraphQL
`timelineItems(itemTypes: [READY_FOR_REVIEW_EVENT, CONVERT_TO_DRAFT_EVENT])` to rebuild draft windows (a PR whose first event
is a ready event was draft at open; 430 of 741 had one); `gh api --paginate
"repos/jikig-ai/soleur/actions/workflows/ci.yml/runs?event=pull_request&created=<day>..<day+1>&per_page=100"` for 30
daily slices (6,008 runs), joined to PRs by `head_branch` (the run's `pull_requests[]` array is EMPTY for about 92% of runs, so
joining on it silently drops most of the population, a measurement trap the script must self-check); a draft push is a distinct
`head_sha` whose first run was created inside a draft window. Cohort: PRs created on or after 2026-09-11 (full draft
lifetime observed), at least one draft push.

| Quantity | Value |
|---|---|
| Draft PRs in cohort / draft pushes | 425 / 3,501 |
| Mean / median draft pushes per draft PR (distinct head SHA) | 8.24 / 8 |
| Runs per draft PR (same, no re-run double counting seen) | 8.24 |
| Draft pushes whose run concluded `failure` | 448 (12.8%) |
| Policy-floor bound `(P - F) / N` (policy removes every failed push) | 7.18 |
| By PR creation date: before 09-24 / 09-24 to 10-02 / 10-03 on | 6.92 / 8.52 / 9.40 (no drop after the #9409 pre-push lane) |
| Draft PRs later readied | 406 of 425 |

Reading: against the 2.75 criterion the pilot passes on both the raw mean and the policy-floor bound, so the expected
branch is the full implementation. Break-even changes too: at 8.2 draft pushes a PR the saving per drafted-then-readied PR
is roughly `8.2 x (draft run minus light run) - one ready run`, an order of magnitude above the parent plan's marginal
2.6-push case. Caveats the script must close: a first listing attempt returned several daily slices of exactly 100 runs (one page, an
interrupted or partial fetch) that a second attempt filled in (the final set has 20 to 406 runs a day, none at 100), so every
slice must be reconciled to the API's `total_count` and the script must fail on a mismatch; head-branch reuse across PRs;
still-open drafts are right-censored (the Phase 1 cohort excludes them); and `--paginate` output is written to a file, never
aggregated with `--jq`.

### Consumer census (grepped on this tree)

Readers of the `test` context or of PR-event `CI` conclusions: `scripts/required-checks.txt`, `infra/github/ruleset-ci-required.tf`;
`.github/workflows/web-platform-release.yml` and `post-merge-monitor.yml` (`workflow_run` on `CI`; they filter to the push
arm, confirm at implementation that a failed `pull_request` run is ignored); `plugins/soleur/skills/ship/scripts/battery-owed.sh`;
`plugins/soleur/scripts/admin-merge-ready.sh` + `plugins/soleur/test/admin-merge-ready-wiring.test.sh`;
`plugins/soleur/scripts/monitor-pr-checks.sh`; `plugins/soleur/skills/ship/SKILL.md` (Phase 6 ready/arm, Phase 7 poll);
`plugins/soleur/skills/merge-pr/SKILL.md` (duplicate poll); `plugins/soleur/skills/drain-prs/` (`SKILL.md`, `scripts/triage-prs.sh`);
`plugins/soleur/skills/ship/references/settle-then-admin-merge.md`; `scripts/followthroughs/pr-battery-gate-saving-9323.sh`
(its baseline averages successful `pull_request` runs; a light run concludes `failure`, so it drops out, verify rather than assume);
`.github/actions/bot-pr-with-synthetic-checks` and `apps/web-platform/server/inngest/functions/_cron-safe-commit.ts`
(`SYNTHETIC_CHECK_NAMES`; neither may receive a draft marker). NEW finding not in the parent plan:
`apps/web-platform/app/api/webhooks/github/route.ts` routes every `workflow_run` with `conclusion == failure` to the
`engineering.ci_failed` Inngest event ("Spawn fix agent" card). If the Soleur GitHub App is subscribed to `workflow_run` for
`jikig-ai/soleur` itself, Option R turns each draft push into a `ci_failed` event. Gate 5b below checks this before activation.

### Institutional learnings applied

- `2026-10-09-a-cost-lever-must-not-be-able-to-redden-the-run-it-saves.md`: the `draft-light` job carries job-level `continue-on-error`
  (a failed lever runs full CI); the sweeper token cannot read Actions variables, so activation is recorded as a tracker comment.
  The draft aggregator is the one place a red is the intended output, so that inversion is explicit in the Guard.
- `2026-09-22-the-admin-merge-gate-read-ready-from-an-empty-body.md`: readiness is decided positively (green count equals required
  count); a skipped or neutral required context is PENDING while a same-name sibling re-runs.
- `2026-09-24-8611-merge-tail-six-frictions-and-a-stale-reaper.md`: `UNTRUSTED-CI` for workflow-editing PRs; a draft-to-ready time must be
  measured from the ready event, never from draft creation.
- `2026-06-29-admin-merge-skips-deploy-via-await-ci-gate.md`: `web-platform-release` `await-ci` polls `test` on the merge SHA.
- `2026-06-30-github-merge-queue-adoption-wire-all-ruleset-producers.md`: no event gate on a required job; enumerate producers.
- `2026-09-21-gh-actions-runs-event-schedule-filter-returns-stale-window.md`: query each workflow's own runs endpoint, not the repo-wide filter.
- `2026-09-25-path-gating-exit-status-not-emptiness.md`, `2026-07-27-instrument-misreports-own-coverage-and-subagent-counts-are-claims.md`:
  the census reports its own coverage and fails on a mismatch.
- `2026-09-25-gh-stub-must-mirror-real-cli-flags.md`: stubs of `gh` in the new suites must accept only real flags.
- Nothing in the learnings covers fork access to `vars`, `GITHUB_TOKEN` ready events, or the arm-after-ready race: they stay entry gates.

## Open Code-Review Overlap

Open `code-review` issues whose bodies name a file this plan edits: #8659 (`scripts/test-all.sh`, test-helpers EXIT trap) and #7942
(`scripts/test-all.sh`, two unregistered mutation batteries). **Acknowledge** both: S3 only adds `run_suite` rows to
`scripts/test-all.sh`, a different concern from either, and neither sits on the lines S3 touches. No overlap on `ci.yml`,
`battery-owed.sh`, `admin-merge-ready.sh`, `monitor-pr-checks.sh`, the ship, merge-pr and drain-prs skills, or the ledger.

## Decisions fixed by this plan

These are the choices the issue said "fixed in S3's plan"; the work phase does not reopen them without a recorded reason.

| Decision | Value | Why |
|---|---|---|
| Stall-signal threshold N | 75 minutes after the PR's ready event | Above the observed maxima (about 38 min success, 51 min failed, measured as created-to-completed) plus the p90 PR queue wait of about 14 min (855 s); re-derived from gate 4's samples before the probe is written, and widened (never narrowed) if they exceed it |
| Dark window | The PR is armed for merge only once the activation preconditions hold (CTO confirmation or a recorded operator statement, the operator's go, gate 5b resolved). If the operator instead authorizes a dark merge, the probe FAILS 1 day after merge with no activation recorded | The ungated `ready_for_review` type costs about 13.5 extra full runs a day (about 1,300 job-minutes) while the variable is unset (Phase 9); the CTO review called a 3-day window too generous |
| Jobs gated on the draft output | `test-webplat`, `test-scripts`, `test-scripts-heavy`, `shard-totality-mutations` (the four measured heavy families) | `test-bun`, `web-platform-build`, `encryption-posture`, `lint-webplat` and the cheap guards are the light set; `e2e` is untouched by S3: it keeps its step-level applicability gating and S2's existing `needs: [push-dedupe]` plus job-level `if:` (pinned by `ci-e2e-skip-anchors.test.sh`), and gains no `draft-light` term (#8450). Phase 1 re-checks `test-bun`'s per-run minutes and adds it only if it exceeds 3 |
| New job | `draft-light` (API only, no checkout, `pull-requests: read`, job-level `continue-on-error: true`, `timeout-minutes: 3` alone on its line) | A step shell is mandatory (the Actions `==` operator is case-insensitive, so `ON` would match). Folding the read into `detect-changes` would put a full-depth checkout in front of every heavy job; folding it into `push-dedupe` is a poor fit (that job is push-only, carries its own switch, is under the S2 soak probe and is pinned by its own suite). `draft-light` and `push-dedupe` are parallel roots, so the longest declared `needs:` path (the release workflow's 73 of 75 minute budget, slack 2) does not lengthen |
| Ready run | Always full. No skip arm | See the Cut List |
| Which run speaks for a non-draft head | Only a `ci.yml` `pull_request` run at the head created at or after the PR's latest server-side `ReadyForReviewEvent`; any `test` row from before it is draft-era | The ready run, and every later push's run, can never be light by construction (`ACTION != ready_for_review`, and a live read of a ready PR says not draft), so no light-run detector, jobs-API shape test or skip-source pin is needed, and S4's later decline cannot break it |
| Verdict resolver | One script, `plugins/soleur/scripts/ci-head-verdict.sh`, called by every reader | Six copies of one predicate is how the parent plan's consumer list went stale |
| Follow-through tracker | #9728 itself (label `follow-through` plus the directive comment) | Net issue flow stays at 0 new issues; the sweeper closes it when the soak passes |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "Implement S3 = #9728 (ci: draft-PR light checks, full set on ready_for_review; stage 3 of the hosted-runner demand plan)" | Phases 1 to 10 | mapped |
| 2 | "Variable CI_DRAFT_LIGHT, accepted value exactly \"on\" (anything else = full CI)" | Phase 6 `draft-light` step, Guard 1 | mapped |
| 3 | "Option R is decided (ADR-276 Decision 4): the draft aggregator concludes red" | Phase 6 aggregator draft arm, Guard 1 | mapped |
| 4 | "This stage's PR must append its own dated Amendment to ADR-276 BEFORE the stage takes effect, and also fold in an \"S1 live\" line" | Phase 2 (both branches) / Phase 4 | mapped |
| 5 | "treat the flip as unconfirmed and do NOT move ADR-276 beyond \"adopting\"" | Architecture Decision section; AC | mapped |
| 6 | "(a) resolve the six entry gates ... on a throwaway PR BEFORE any ci.yml edit" | Phase 3 | mapped |
| 7 | "Do gate 6 FIRST ... it may legitimately fail, in which case S3 closes by its stop rule ... NO ci.yml change ... a valid deliverable; the plan must have a branch for that outcome and one for the full implementation" | Phase 1 verdict table, Phase 2 (Branch A), Phases 3 to 10 (Branch B) | mapped |
| 8 | "(b) Only if gate 6 passes and the other gates clear: implement per the issue's Scope/Files list" | Phases 4 to 8, Files to Edit | mapped |
| 9 | "net-issue-flow must stay <= 0; include \"Closes #9728\" only if the stage fully ships or closes by stop rule" | Phase 10, AC (tracker is #9728, no new issue) | mapped |
| 10 | "commit trailer ...; PR body ends with ...; poll with the Monitor tool never Bash run_in_background; no git stash; no force-push; provision nothing for lever 5" | Phase 10 | mapped |
| 11 | "Before pushing run directly: scripts/test-affected-kb-consumers.test.sh, .claude/hooks/grep-q-pipe-guard.test.sh, scripts/guard-vacuity-floor.test.sh, plus the stage's own suites; do NOT use test-all.sh --affected" | Phase 10 | mapped |
| 12 | "Do not touch the main checkout ... Post-merge checks run from a detached origin/main worktree" | Phase 10, Post-merge AC | mapped |
| 13 | "Only modify files under knowledge-base/project/{plans,specs}/ for this branch" (planning phase) | This run writes only the plan, tasks.md, decision-challenges.md | mapped |

### Plan-Item Provenance

| Plan item | User words cited | Verdict |
|---|---|---|
| Gate 6 census script `scripts/ci-draft-push-census.sh` | "measure pre-policy and post-policy mean pushes per draft PR over a 30-day census" | asked; the script is inferred because ADR-276 Decision 7 makes a committed script the single authority for any number, and the pilot showed `pull_requests[]` joins silently drop 92% of runs |
| Shared resolver `ci-head-verdict.sh` | "Consumers (...) must ... resolve the verdict from the newest non-draft run at HEAD" (issue body) | asked; one script instead of six copies is inferred |
| Ready-run wait step | "Ship Phase 6 must wait for a non-draft CI run on HEAD created after the ready call and fail closed (same in drain-prs and merge-pr)" | asked |
| Follow-through probe | "A follow-through probe in scripts/followthroughs/ raises an owner-visible signal" | asked; soak exit and dark-window deadline are inferred from the S2 precedent (ADR-276 S2 amendment) |
| INDETERMINATE verdict (Branch C) | "it may legitimately fail" | inferred: the brief gives pass and fail; a policy that is enforced nowhere can leave the criterion undecidable, and silently picking a side would be a decision the ADR reserves |

### Split Assessment

- Subsystems touched: 4 roots (`.github`, `plugins/soleur`, `scripts`, `knowledge-base`). Planned files: about 30 (Branch B). Estimated lines: about 1,500 including suites. Over the 4-root threshold.
- Recommendation: single PR, because the issue sizes the stage as one (`Fix-Size: 450 lines / 12 files`, which already undercounts the suites), the parts are not independently shippable (a `ci.yml` that lights drafts without the readers is the stall the ADR warns about), and S2 shipped at 27 files. The measure-first split IS the sequencing: Branch A is a PR of 5 docs and one script.

## Implementation Phases

Sequence is load-bearing: Phase 1 (gate 6) before everything; Phases 3 and 4 (other gates, ADR amendment) before the first `.github/workflows/ci.yml` edit; tests before code in every phase (`cq-write-failing-tests-before`). Evidence goes to
`knowledge-base/project/specs/feat-one-shot-9728-ci-draft-light/measurements/` (tracked paths, so the filing gate sees them).

### Phase 0 - Preflight (no edits to shared files)

1. Work only in `.worktrees/feat-one-shot-9728-ci-draft-light`; the main checkout (uncommitted `.mcp.json`, staged `scripts/followthroughs/watchdog-debounce-soak-9686.sh`) is never read for edits, staged or cleaned.
2. Re-read `gh variable list --repo jikig-ai/soleur` (expect no `CI_DRAFT_LIGHT`), ADR-276 head-of-file `status:` (expect `adopting`), `yaml.safe_load(ci.yml)['jobs']` length and the ledger row (expect 25 and 25). A different value means a sibling PR moved: rebase first (merge, never force-push).
3. Sync `origin/main`; if S2 follow-ups touched `ci.yml` or `scripts/ci-push-dedupe.test.sh`, read them before Phase 6.
4. Look for an ENFORCED "no draft push before a local `--affected` run passes" policy and its effective date (`git grep -n "pre-push" lefthook.yml`, the work and ship skills, `AGENTS.rules.md`). None is expected (see the Reconciliation table); record the result, because an enforcement date with at least 30 days behind it turns the Phase 1 floor into a measured post-policy mean.

### Phase 1 - Gate 6 FIRST: the cheaper-alternative census (read-only, no `ci.yml` edit)

1. **Test first.** `scripts/ci-draft-push-census.test.sh` with a synthesized fixture dir (runs, PR timelines, heads; no real PR data, `cq-test-fixtures-synthesized-only`) and the script `scripts/ci-draft-push-census.sh`, shaped like `scripts/ci-demand-census.sh` (fixture mode runs anywhere; live mode refuses under `GITHUB_ACTIONS`). Guard 3 below is its contract. Register: `scripts/test-all.sh` `run_suite`, `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv`, `scripts/lib/test-affected-paths.sh` if it needs a declared edge, `scripts/test-affected-kb-consumers.baseline.txt` if the registrar demands it; run `bash scripts/lint-orphan-test-suites.sh`. (`.github/CODEOWNERS` is NOT touched on Branch A: it is under `.github/`, which Branch A leaves alone; the CODEOWNERS lines for the census files are added in Branch B only.)
2. **Definitions (fixed here).** A *draft PR* is one with at least one closed draft window (opened draft then readied, or converted to draft then readied, or closed while draft). A *draft window* is rebuilt from `ReadyForReviewEvent` / `ConvertToDraftEvent` (first event ready means draft at open). A *draft push* is a distinct `head_sha` whose first `ci.yml` `pull_request` run was created inside a draft window; runs are joined to PRs by `head_branch` against the PR's `headRefName` (never by `pull_requests[]`), and a branch name claimed by more than one PR in the window is excluded and counted. The cohort is PRs whose draft window CLOSED inside the 30-day window and whose window opened inside it (no right-censored open drafts, no windows clipped at the start). The 30 days end at a closed UTC day boundary.
3. **Run it live** from a developer shell with `gh auth` (`env -u GITHUB_ACTIONS bash scripts/ci-draft-push-census.sh --end <UTC-day> --days 30 --summary`), output to `measurements/draft-push-census-<date>.tsv` plus the summary. Required output lines: `COHORT_PRS`, `DRAFT_PUSHES`, `MEAN_PUSHES_DISTINCT_SHA`, `MEAN_RUNS`, `MEDIAN`, `FAILED_PUSH_SHARE`, `POLICY_FLOOR_MEAN` (= (pushes - failed pushes) / PRs: the lowest mean the unenforced policy could leave if it removed EVERY CI-failed push, an assumption stated on the line, distinct-SHA basis only), `READY_TRANSITIONS` and `BOT_READY_TRANSITIONS` (the dark-window cost input; bot-authored PRs counted apart because they run no CI today and would gain one full run per human ready click), `UNMAPPED_RUNS`, `EXCLUDED_BRANCH_COLLISIONS`, `SLICES_RECONCILED` (every daily slice equals the API `total_count`), and the per-cohort split by PR creation date. Also record the saving inputs with `scripts/ci-demand-census.sh --workflow ci.yml` over consecutive 12-hour `--start`/`--end` windows (its hard limit; sum `TOTAL_JOB_SECONDS` and recompute per-run minutes, as the S1 amendment documents): per-run minutes of the four gated families, of the light set, of `test-bun` (added to the gated set only if above 3) and of `e2e`, and the gated families' share of a run, so the estimated saving `draft pushes x (draft run - light run) - one ready run` is computed from measured inputs rather than the parent plan's 73 and 10.
4. **Verdict table (applied mechanically, on the distinct-SHA basis; the runs basis is reported next to it and the LOWER of the two decides; the 2.75 comparison is integer cross-multiplication, `pushes * 4 >= 11 * PRs`, so the 2.75 boundary rows are exact):**

| Verdict | Condition | Branch |
|---|---|---|
| FAIL | `MEAN_PUSHES_DISTINCT_SHA` below 2.75. Monotone: the policy only removes pushes, so no post-policy mean can exceed this | A: stop rule, no `ci.yml` change |
| PASS | mean at or above 2.75 AND `POLICY_FLOOR_MEAN` at or above 2.75 (the policy could remove every failed push and the criterion still holds) | B: full implementation |
| INDETERMINATE | mean at or above 2.75 but `POLICY_FLOOR_MEAN` below 2.75 | C: hold. Only an enforced policy plus a 30-day post-policy census can decide |
| REFUSED | any self-check failure (slice mismatch, unmapped share above 5%, zero cohort) | none: fix the instrument, never decide on it |

   The operator's criterion is a measured POST-policy mean. No post-policy population exists unless Phase 0 finds an enforcement date with at least 30 days behind it, in which case that measured mean replaces the floor in the PASS row. Otherwise the floor is a stated substitute for a measurement that cannot be taken. Reviewers asked to drop it (call PASS on the raw mean alone); that would loosen the operator's pass rule, so it is kept and recorded as a challenge in `decision-challenges.md`. The planning pilot (Research Insights) reads PASS with wide margin (8.24 and 7.18); that is a prior, not a verdict.
6. **Gate 5b, read-only, now (not after the verdict).** Check whether the Soleur GitHub App is installed with `workflow_run` delivery on `jikig-ai/soleur` (`gh api repos/jikig-ai/soleur/installation` or the app's delivery log), so the possible `apps/web-platform` route-filter scope is known before Branch B is chosen. Record it in the census comment.
5. Informational line, not a verdict input: the minutes break-even from the measured inputs, `mean draft pushes x (draft run minutes - light run minutes) > (readied share x ready run minutes) + bot ready runs`. The operator's 2.75 criterion is a push count; a PASS on pushes that is net-negative in minutes (an expensive light run) is raised to the operator before Branch B proceeds rather than decided here, and recorded in `decision-challenges.md`.
5b. Attach the census to #9728 as a comment (the S1 and S2 pattern) with the command and the verdict line.

### Phase 2 - Branch A (verdict FAIL) and Branch C (INDETERMINATE): no `ci.yml` change

**Branch A, S3 closes by its stop rule.** Deliverable (a valid, complete outcome): the census script, suite and measurement files; the ADR-276 amendment (below); the `#9728` closure comment; a note on #9729 and #9730 that S3 has closed by entry gate 6 so their "parked until S3 has a post-merge census or closes by gate or stop rule" condition is met (the notes re-decide nothing). The PR body says `Closes #9728`. Nothing else is edited: no `.github/`, no plugin script, no skill. Then jump to Phase 10 (suites, ship) and stop.
**Branch C, hold.** Same artifacts, but the amendment records `S3 held at entry gate 6 (indeterminate)` and the operator decision it needs (enforce the policy, then re-run the census over 30 post-policy days); #9728 stays open with a dated re-measure comment and the operator-decision request (it gets the `follow-through` label and an `earliest=` directive at the policy-enforcement date plus 30 days only if the operator chooses to enforce the policy; otherwise it waits on the operator's decision, which the comment states); the PR body says `Refs #9728`. S4 (#9729) and S5 (#9730) stay parked under Branch C, because C is a hold and not a closure; that parking rule is the operator's, so the deadlock it creates if the policy is never enforced is surfaced in `decision-challenges.md`. No `ci.yml` change.

**ADR-276 amendment (both branches, committed before anything else changes behavior).** Append `## Amendment <work date> (S3, #9728)`: status stays `adopting`; the CTO review-comment confirmation of the 2026-10-09 flip (owed on merged PR #9876) is still outstanding and is stated as such, so the flip is not treated as stronger than the operator's direction; S3's decision (A: closed by gate 6 with the numbers; B: see Phase 4); the census link; and the append-only Stage status lines `- <date> S1 live (#9727: post-merge census 85.2% against the 80% criterion, <comment url>)` and the S3 line. Do not edit any earlier line of the file.

### Phase 3 - Branch B only: entry gates 1 to 5 on a throwaway PR (before any `ci.yml` edit)

A scratch branch `scratch/9728-entry-gates` from `origin/main`, a draft PR titled `DO NOT MERGE: scratch entry-gate probe` (no `do-not-merge` label exists in this repository), armed only in the guarded gate 1 sub-scenario (iii), never merged, closed and its branch deleted at the end. The scratch branch DELETES the repository's pull_request-triggered workflows (`ci.yml` and the rest; a PR runs the workflows of its own merge ref) and adds ONE probe workflow `.github/workflows/zz-s3-probe.yml` on `pull_request` types `[opened, synchronize, reopened, ready_for_review]` with a job named exactly `test`, so the cost is a few minutes of runner time, no S3 code is needed and the only `test` rows on the SHA are the probe's. Because the real required contexts are absent, `mergeStateStatus` is BLOCKED throughout and says nothing about `test`; read `gh pr checks --required --json name,bucket,state`, the `statusCheckRollup` contexts and the raw `commits/<sha>/check-runs?filter=all` rows instead. `admin-merge-ready.sh` returns `UNTRUSTED-CI` for this PR (it edits workflows), so its readiness logic is NOT probed live. Record each answer in `knowledge-base/project/specs/feat-one-shot-9728-ci-draft-light/measurements/gate-results.md` (question, command, observed output, decision).

| Gate | Probe | Decision rule |
|---|---|---|
| 1 Rollup with two same-name rows | The single probe workflow reproduces the production topology: the `synchronize` run on the draft head concludes red; `gh pr ready` then starts a `ready_for_review` run of the SAME workflow on the SAME SHA whose `test` job needs a `sleep` job of a few minutes (the real aggregator only gets a row after the shards end, 38 to 51 minutes). Read the required-check view, the rollup and the raw rows at three points: before the second `test` row exists, while it is pending, after it is green. Sub-scenarios on the same PR: (i) `gh run rerun --failed` of the pre-ready run while the ready run is in flight (does the per-ref concurrency group cancel the ready run, and is the draft-light output reused); (ii) a same-name `test` check run posted through the API as the bot synthetic checks do, then the real workflow row (the human ready click on a bot-opened draft PR); (iii) with the throwaway still BLOCKED (required contexts absent, verify `mergeStateStatus` first), `gh pr merge --auto` while the newest `test` row is red and a newer one pending, then `gh pr merge --disable-auto` at once: does GitHub accept it and keep it enabled | Expected: the newest row per name decides (red blocks while pending, clears when the newer row is green). If an older red row keeps blocking after a newer green: Option R is unusable, **STOP, Branch A-style closure by gate 1**, no `ci.yml` edit |
| 2 `gh pr ready` token identity | (a) ready the throwaway with the operator's `gh` token: a `ready_for_review` run must appear; (b) a probe step on `opened` readies its own PR with `GITHUB_TOKEN`: no run may appear (documented GitHub behaviour, confirmed once). Record the caller census from the Reconciliation table | If (a) fails: STOP (closure by gate 2). (b) confirms the rule the plan already assumes; the wait step fails closed on its absence |
| 3 Variables on fork runs | Design-invariant: `draft-light` requires `head.repo.full_name == repository` before it can emit `light=true`, so forks run full whether or not `vars` reach them. Probe live only if a second GitHub identity is available; otherwise record "answered by design" and assert it in Guard 1 | Either outcome leaves forks on full CI; no stop condition |
| 4 Arm-then-register window | Sample 3 `gh pr ready` calls: seconds from the server-side ready event to the first run's `created_at` (the minimum must be at least minus 5, else the skew allowance is widened), and how long the timeline takes to show the new `ReadyForReviewEvent` after `gh pr ready` returns. `gh pr merge` is run on the throwaway only in sub-scenario (iii) of gate 1 under its guard | Wait timeout fixed at 300 s (the wait fails closed, so a wider number only delays a refusal); the samples are recorded as evidence and N (stall threshold) is widened, never narrowed, if they argue for it. The wait step ships regardless (the issue demands it) |
| 5 `--admin` path and consumers | Drive `admin-merge-ready.sh` through its stubbed fixtures (`admin-merge-ready.test.sh` feeds check-run rows directly): a draft-red newest `test` row, then a pending newer one, then a green newer one, reading `ready=`/`reason=`; the live throwaway cannot be used here (`UNTRUSTED-CI` refuses first). 5b (read in Phase 1 step 6): the Soleur GitHub App `workflow_run` delivery check | `--wait` today ends at once on FAILED (known), which Phase 7 fixes. 5b is a HARD activation precondition: `apps/web-platform/app/api/webhooks/github/route.ts` gates `workflow_run` on `conclusion == failure` only (no event or branch filter; dedup key is the run id), so Option R would turn every draft push (about 100% red, against 12.8% failed today, about 7x the cards) into an `engineering.ci_failed` "Spawn fix agent" card. If the app delivers for this repo, the default remedy is a route filter that drops `workflow_run` events with `event == pull_request` whose PR head is a draft (resolved by an explicit head-SHA lookup, never `pull_requests[]`, which is empty for most runs), with tests, shipped before activation (Files to Edit, conditional); otherwise change the app subscription. Recorded in the amendment, never silently accepted |

If every gate clears (or is answered by design), continue. Any STOP outcome is a closure by that entry gate (ADR-276 uses "closed by its entry gate or stop rule" for exactly this): amendment + closure comment + census, no `ci.yml` edit, PR body `Closes #9728`. A gate 1 STOP means Option R (an ADR decision) is unusable; an alternative is a new ADR decision for the operator, stated in the amendment and not improvised here (Option T stays rejected).

### Phase 4 - Branch B: ADR-276 amendment (first behavior-bearing commit; precedes every file below)

Append `## Amendment <work date> (S3, #9728)` containing: status stays `adopting` (flip unconfirmed, as in Phase 2); the kill-switch (`CI_DRAFT_LIGHT`, exactly `on`, compared in the step shell, entering through `env:`), the Decision 3(a) to (h) checklist answered for S3, the exit criterion (draft `CI` minutes per draft push down at least 80%; zero queue stalls; zero PRs in the queue with a heavy family unrun on a non-draft head; net minutes on drafted-then-readied PRs down at least 25%; stop rule 2.75), the census link and the gate results, the numeric target per Decision 3(e) with the dark-window cost (Phase 9), how to measure, how to roll back (variable off restores full draft CI; the `types` entry, the ship/merge-pr/drain-prs wait step and the consumer changes need a revert), the named residual (a light run reading as full is only possible through a consumer that bypasses the resolver), the `S1 live` line, and the `- <date> S3 amended` line. Insertion sites: the Stage status lines go under the Stage status table (after the existing dated lines, ADR lines 53 to 55 today), the `## Amendment` heading at the end of the file. A supersession block, in the style of the S1 note under Status, records the two wordings of Decision 4 this stage replaces: "newest non-draft run at HEAD" becomes "runs created at or after the latest ready event, closed state set in `ci-head-verdict.sh`", and the stall signal "newest `test` draft-mode red for more than N minutes" becomes "no deciding run N minutes after the ready event". It also states that the `DRAFT_LIGHT` arm is an intra-run, red-only, `pull_request`-only value, so ADR-217's "the verdict never crosses as a value" is untouched and no ADR-217 amendment is needed, that bot PRs opened as drafts gain a real PR-level full run on the human ready click (accepted; their ready runs are subtracted from the net-minutes criterion), and adds a pointer line to ADR-032 (the required `test` aggregator is red by design on one event class; S2 left one for `e2e`). The commit order (amendment before the first `ci.yml` commit) is checked once at ship time with `git log --reverse --format=%h -- <ADR>` against `-- .github/workflows/ci.yml`; it is NOT a registered suite (branch history does not survive a squash merge, so a suite would be vacuous on `main`). A stateless check is registered instead: `ci.yml` mentioning `draft-light` requires the ADR to contain the S3 amendment heading. The amendment's rollback section states the footprint plainly: reverting S3 is a code revert across about 30 files, not a variable flip, and Option T (a marker plus a tolerance arm) was rejected because `bot-pr-with-synthetic-checks` would post the marker green for bot PRs.

### Phase 5 - Branch B: tests first (RED), one suite at a time

1. `scripts/ci-draft-light.test.sh` (new, modelled on `scripts/ci-push-dedupe.test.sh`): extracts the `draft-light` step body and each gated condition from the parsed YAML and EXECUTES them over event fixtures under the shell Actions uses (`bash --noprofile --norc -eo pipefail`); gated-set parity in both directions; Guard 1's rows.
2. `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh`: add the draft arm rows (the file already extracts and executes the aggregator body over result triples).
3. `scripts/ci-push-dedupe.test.sh`: its pinned gated-condition tail and gated set change with the new clause; update the pins in the same commit as `ci.yml` and keep its own mutation rows green.
4. `plugins/soleur/test/ci-head-verdict.test.sh` (new) for the resolver, Guard 2's rows; `plugins/soleur/scripts/admin-merge-ready.test.sh` and `plugins/soleur/test/admin-merge-ready-wiring.test.sh`; `plugins/soleur/test/monitor-pr-checks.test.sh`; `plugins/soleur/test/drain-prs.test.sh`; `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`; `plugins/soleur/test/ship-battery-owed.test.sh` (the two mutation rows; they are expected to PASS against today's script because Option R already makes a light `test` NOT-GREEN, so prove they can fail by temporarily mutating the script and recording the red).
5. `scripts/followthroughs/ci-draft-light-soak-9728.test.sh` for the probe (Phase 8).
6. Each new suite is registered (Phase 1 step 1 list) and `bash scripts/lint-orphan-test-suites.sh` is run.

### Phase 6 - Branch B: `ci.yml`

1. `on.pull_request.types: [opened, synchronize, reopened, ready_for_review]` (the full list; naming only the new type drops the defaults). Check `plugins/soleur/test/pr-fanout-ledger.test.sh` and `plugins/soleur/test/ci-concurrency-key.test.sh` stay green.
2. New job `draft-light` (Decisions table) with `if: github.event_name == 'pull_request'` (it takes no runner on `push` or `merge_group`; the gated jobs keep `!cancelled()` and compare `!= 'true'`, so a skipped `draft-light` is full CI). One `run:` step, every input through `env:` (`GH_TOKEN`, `GH_REPO`, `PR_NUMBER`, `ACTION`, `HEAD_REPO`, `SWITCH: ${{ vars.CI_DRAFT_LIGHT }}`), `set +x`, literals only in outputs, same shape as `push-dedupe`. It emits `light=true` LAST and only when ALL hold: `SWITCH` is exactly `on` (shell `[ "$SWITCH" = on ]`); `ACTION` is not `ready_for_review`; `HEAD_REPO` equals `GH_REPO` and is non-empty; a bounded (`timeout 20`) live read of `repos/$GH_REPO/pulls/$PR_NUMBER` returns the JSON boolean `draft == true` (the event payload's draft flag is deliberately NOT an input: a re-run reuses a stale payload, so only the live read can speak for the current state, and the `ready_for_review` run is excluded by `ACTION`). Every other path (unset, empty, `ON`, whitespace, error, null, non-boolean, timeout) leaves `light` empty, which means full. It annotates `would_light` the same way `push-dedupe` annotates `would_elide`, so the dark phase is observable.
3. Add `draft-light` to the `needs:` of the four gated jobs and append `&& needs.draft-light.outputs.light != 'true'` to their `if:` (keeping `!cancelled()` and S2's clause). Add `draft-light` to the `test` aggregator's `needs:`, an `env:` string `DRAFT_LIGHT`, and, after the loop and BEFORE the final `if [[ $fail -ne 0 ]]` check, an arm that runs only when `EVENT_NAME == pull_request` and `DRAFT_LIGHT == true`: print `draft: full battery owed at ready` (in addition to the loop's per-leg SKIPPED lines) and `exit 1` unconditionally (placed after the final check it would be unreachable, because the skipped legs already set `fail=1`; the arm makes the verdict independent of how skips are classified). The aggregator's `if:` stays `always() && ...`.
4. `scripts/pr-fanout-ledger.txt`: ci.yml 25 to 26 with a dated note naming `draft-light` and the gated set rule (a new heavy job must join it, enforced by `scripts/ci-draft-light.test.sh`).
5. Header comment in `ci.yml` (the merge_group invariant block) gains one sentence naming S3, the variable and Option R. Run `actionlint` via the repo's pinned path (the `lint-bot-statuses` job installs it) and the C4 count parity test (`plugins/soleur/test/c4-count-parity.test.sh`; it gates job counts quoted in `model.c4`).

### Phase 7 - Branch B: readers, the resolver, the wait step

1. `plugins/soleur/scripts/ci-head-verdict.sh` with two subcommands and a CLOSED state set. `verdict <pr>` reads the PR's timeline (GraphQL `timelineItems(last: 1, itemTypes: [READY_FOR_REVIEW_EVENT])`, verified to return the event on a real PR) and prints one `SOLEUR_CI_HEAD_VERDICT state=<n/a|full-decided|pending-full|no-run|stalled|awaiting-approval> pr=<N> sha=<H> run=<id|none> reason=<token>` line. Order of evaluation: (1) a PR with NO ready event was never a draft, so it cannot carry a light run: `n/a`, readers fall through to today's row logic (this keeps never-draft and bot-opened PRs, which have synthetic rows and no `pull_request` run, from reading as stalled); (2) the newest `test` check run at H is a completed `success`: `full-decided` regardless of T, because under Option R a green `test` is never a light result (this also covers a PR readied before S3 merged or while the variable was unset, whose draft-era run was a full run); (3) otherwise list `repos/$R/actions/workflows/ci.yml/runs?event=pull_request&head_sha=H` (never the run's `pull_requests[]`, empty for most runs) and keep runs created at or after T minus 5 seconds (clock-skew allowance: the timeline and the runs API are separate services; a draft-era run inside that window is cancelled by the ready run's concurrency group anyway); (4) map the newest kept run: not completed means `pending-full`; completed with `success`, `failure` or `timed_out` means `full-decided` (its own rows are authoritative; `timed_out` is a real failure and is never hidden as PENDING); `action_required` (a fork run awaiting approval) means `awaiting-approval`; `cancelled`, `skipped`, `stale`, `neutral`, `startup_failure` or any unknown value means `no-run` (fail closed); no kept run means `no-run`; (5) `stalled` overrides `pending-full` and `no-run` when no kept run has decided and more than N=75 minutes have passed since T (a ready run stuck queued on starved runners is the case ADR-276 Decision 4 names, and 75 exceeds the 73-minute declared CI path, so a healthy run cannot trip it). The reported `run` is the deciding run: a reader judging `test` must use that run's rows, and a newer `test` row that belongs to a different run (for example a manual re-run of a pre-T run) yields `not ready, reason=stale-row`, never READY. `wait-ready-run <pr> --before-count K [--timeout S]` (default 300): the caller read K, the PR's `ReadyForReviewEvent` count, BEFORE `gh pr ready`; the wait polls until the count exceeds K AND a live read says the PR is not a draft (guards timeline read-after-write lag), takes that new event's server time as T, then polls for a `pull_request` run at H created at or after T minus 5 seconds; exit 0 on success, non-zero (fail closed, with a named reason: `no-ready-event`, `no-run`, `awaiting-approval`) otherwise. Both times come from the server, never the local clock. Recovery for a `no-run` or `stalled` ready PR: `gh pr ready --undo <pr>` then `gh pr ready <pr>` with a user token (verified: `gh pr ready --undo` exists; this creates a new ready event and so a new ready run); a manual re-run of a pre-T run is NOT a recovery (it reuses the cached `draft-light` output, can cancel the in-flight ready run through the per-ref concurrency group, and its rows are stale by the rule above).
2. Readers call it: `monitor-pr-checks.sh` (a `pending-full` verdict reports PENDING, not FAILED, for a red `test`); `admin-merge-ready.sh` (`--wait` does not treat the draft row's FAILED as terminal while the verdict is `pending-full`; `no-run` and `stalled` return ABSENT or PENDING, never READY; `UNTRUSTED-CI` behaviour unchanged); `plugins/soleur/skills/drain-prs/scripts/triage-prs.sh` and its `SKILL.md` (a ready PR with `pending-full` is not counted failing); ship Phase 7 `required_failed` poll and the verbatim copy in `merge-pr/SKILL.md` (a required failure on `test` is ignored while the verdict is `pending-full`; the existing `ship-phase-7-poll-fixtures.test.sh` fixtures grow rows for it). Per-state action for every reader: `n/a` today's logic; `full-decided` the deciding run's rows; `pending-full` wait (PENDING, never FAILED); `no-run` and `stalled` not ready, print the recovery command above and never start a fix loop on the draft-red row; `awaiting-approval` not ready, name the approval it needs. `drain-prs` triage gains a `ready-unarmed` tier for `no-run` and `stalled` ready PRs, with the recovery command. Each reader edit is driven by a failing fixture row first: a reader that already behaves correctly on the fixtures (gate 1 and gate 5 decide this) is not edited, only pinned.
3. Ship Phase 6 (`plugins/soleur/skills/ship/SKILL.md`, step "If the PR is a draft, mark it ready"): after `gh pr ready`, read the server-side ready time, run `wait-ready-run`; on non-zero do NOT run `gh pr merge --squash --auto`, report the PR as readied but unarmed with the reason. The same step goes into `drain-prs` arming and `merge-pr`. Document that every `gh pr ready` caller must use a non-`GITHUB_TOKEN` identity. `plugins/soleur/skills/ship/references/settle-then-admin-merge.md` gets a pointer line, since the admin route's `--wait` now consults the resolver. Mind the skill budgets: `plugins/soleur/test/components.test.ts` word budget and the lifecycle `SKILL.md` byte ratchet (`rule-body-lint`, ADR-229) — run both before committing the skill edits and trim a sibling sentence rather than raise a cap.
4. `plugins/soleur/skills/ship/scripts/battery-owed.sh`: expected no logic change (Reconciliation); if the new rows expose one, fix it.
5. `scripts/followthroughs/pr-battery-gate-saving-9323.sh`: confirm by its fixtures that a failed light `pull_request` run does not enter its baseline or its escape count; add a fixture row either way.

### Phase 8 - Branch B: the follow-through probe

`scripts/followthroughs/ci-draft-light-soak-9728.sh` (+ `.test.sh`, registered, CODEOWNERS), exit codes per the sweeper contract (0 pass, 1 fail, 2 not yet, 3 cannot establish, 78 refuses xtrace with a token set). Checks on every sweep: (a) STALL: any open PR with a ready event whose verdict is `stalled` (N=75) is a FAIL naming the PR; `n/a` and `full-decided` PRs are never flagged; (b) DARK DEADLINE: more than 1 day after the merge with no `S3-ACTIVATED: <UTC ISO>` marker comment on #9728 (trusted authors only: owner, member, collaborator) is a FAIL; (c) DETECTIVE ACTIVATION CHECK: a light run observed with no activation on record, or with no `S3-CONFIRMED: <url>` marker (the CTO review comment on #9876, or the operator's recorded statement that activation proceeds without it) is a FAIL, because the variable is a repository setting and no code path can refuse a `gh variable set`; (d) LIVE INVARIANTS on every sweep once activated: every observed light run (a `pull_request` run whose four gated jobs were skipped) has a failing `test`, and no run created at or after its PR's latest ready event has a skipped gated family; (e) exit (exit 2 NOT YET until activation + 7 days, so the early checks run from merge + 1 day while the exit gating stays inside the script): 7 days since activation, at least 20 draft pushes observed light (a soak with no draft pushes proves nothing), zero stalled PRs, zero PRs whose `merge_group` entry followed a head whose newest `pull_request` run was a draft run (the issue's heavy-family-unrun count, defined by that join), and an `S3-EXIT-CENSUS: <url>` comment on #9728 holding the before/after minutes (Decision 3(e)). The tracker is #9728 (`follow-through` label plus the `<!-- soleur:followthrough script=scripts/followthroughs/ci-draft-light-soak-9728.sh earliest=<merge+1d> secrets=... -->` directive); any new `secrets=` is wired into `.github/workflows/scheduled-followthrough-sweeper.yml`.

### Phase 9 - Branch B: canary, dark merge, activation

1. **Canary (needs the operator's explicit go; a repository variable is a production write, `hr-menu-option-ack-not-prod-write-auth`).** The S3 PR's own `pull_request` runs use its own `ci.yml`. Precondition: gate 5b answered "no `workflow_run` delivery for this repository" (otherwise the deliberately red canary run would raise the very `engineering.ci_failed` card gate 5b exists to prevent, and the canary is skipped as below). With the go: `gh variable set CI_DRAFT_LIGHT --body on --repo jikig-ai/soleur`, push a trivial change to the still-draft PR, and record: a light run (four heavy families skipped, `draft-light` `light=true`, `test` red with the draft message), `ci-head-verdict.sh` reading it, then `gh pr ready` (user token) producing a full run, `wait-ready-run` exit 0, the queue entering, `merge_group` full. IMMEDIATELY after, `gh variable delete CI_DRAFT_LIGHT` and confirm with `gh variable list`. Other PRs do not have the new `ci.yml` until they merge `main`, so the pre-merge window affects only this PR. Without the go: skip the canary, say so in the amendment, and let the first activation draft be the canary (the S2 pattern).
2. **Merge only when activation can follow.** Dark cost, stated in the amendment: the `ready_for_review` type adds about 13.5 full runs a day (406 ready transitions in 30 days) at roughly 96 job-minutes, about 1,300 job-minutes a day of added demand (about 4% of a day's demand: 8,414 job-minutes in the parent plan's 6-hour window is roughly 33,700 a day), until the variable is on. So the PR is readied and left green but NOT armed until step 3's preconditions hold. If the operator explicitly authorizes a dark merge instead, the amendment records it and the probe's 1-day deadline bounds it. A readied-but-unarmed PR rebases on every main advance (strict up-to-date policy) and pays a full run each time, so if the preconditions do not hold within 3 days the PR is converted back to draft (`gh pr ready --undo`) and the tracker says why. During the canary record the queue wait of the `draft-light` job itself: it is a hosted-runner root in front of every heavy job and adds a queue hop on saturated runners.
3. **Activation** needs BOTH the CTO review-comment confirmation of the `adopting` flip on #9876 (or an explicit operator statement that the activation proceeds without it, recorded verbatim) AND the operator's explicit go. Order: post `S3-CONFIRMED: <comment url or quoted statement>` on #9728, then `gh variable set CI_DRAFT_LIGHT --body on`, then the activating agent comments `S3-ACTIVATED: <variable updated_at>` on #9728. The probe checks that order after the fact (Phase 8 (c)). 5b (Phase 3) must be resolved first. This flip does not happen in the PR.

### Phase 10 - Ship (both branches)

1. Run directly (not through `test-all.sh --affected`): `bash scripts/test-affected-kb-consumers.test.sh`, `bash .claude/hooks/grep-q-pipe-guard.test.sh`, `bash scripts/guard-vacuity-floor.test.sh`, then the stage's suites: Branch A `bash scripts/ci-draft-push-census.test.sh`; Branch B additionally `scripts/ci-draft-light.test.sh`, `scripts/ci-push-dedupe.test.sh`, `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh`, `ci-head-verdict.test.sh`, `ship-battery-owed.test.sh`, `admin-merge-ready.test.sh`, `admin-merge-ready-wiring.test.sh`, `monitor-pr-checks.test.sh`, `drain-prs.test.sh`, `ship-phase-7-poll-fixtures.test.sh`, `pr-fanout-ledger.test.sh`, `ci-concurrency-key.test.sh`, `ci-e2e-skip-anchors.test.sh`, `c4-count-parity.test.sh`, the probe's test, `python3 scripts/lint-guard-contract.py`, `bash scripts/check-adr-ordinals.sh`.
2. Commit trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; PR body ends with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. No `git stash`, no force-push (sync by merge), polling through the Monitor tool only.
3. PR body: Branch A and any entry-gate STOP closure `Closes #9728`; Branch C and Branch B `Refs #9728` (B: the stage ships dark and the tracker carries the soak; the sweeper closes it). `bash plugins/soleur/skills/ship/scripts/net-issue-flow.sh` must report a net of 0 or less: no issue is filed by this stage, and Branch A closes one.
4. This PR edits workflows (Branch B), so it has no agent `--admin` fallback (`UNTRUSTED-CI`); ship Phase 6 tells the operator so, as it already does.

## Guard Contract

Three guards are deliverables. Guard 1 and Guard 2 are Branch B; Guard 3 (the census instrument that decides Branch A or B) is on every branch. The matrices are derived from the design, before any code. Guard 1 refines the parent plan's Guard 1 (ready run always full, no skip arm; payload and live draft read conjoined).

### Guard 1 - Draft-light gating and the red draft aggregator (S3, the `test` context)

**Property.** On a `pull_request` run for which a live read says the PR is a draft, from the same repository, for an action other than `ready_for_review`, with `CI_DRAFT_LIGHT` exactly `on`, the four gated heavy jobs are skipped and the `test` context concludes failure with the message `draft: full battery owed at ready`; on every other event, state, value or error the heavy jobs run and `test` reflects the real results; no code path lets a draft `test` conclude success or lets a heavy job be skipped on a ready head.

**Assembly.** The chokepoints are two, and a guard on either alone is the defect. (1) The producer of the decision: the `draft-light` job's step body in `.github/workflows/ci.yml` (its inputs are the variable, the event action, the head repository, and one live read; its single output is `light`). (2) The consumers of that output inside the workflow: the `if:` of EVERY job that can be skipped by it (derived from the parsed YAML as "every job whose `needs` contains `draft-light`", not a remembered list of four) and the `test` aggregator's `needs:`, `env:` and loop/arm body, which `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh` already extracts and executes over synthetic result triples. Outside the workflow the property quantifies over the readers listed in Guard 2, over `scripts/required-checks.txt` / `infra/github/ruleset-ci-required.tf` / the canonical JSON (no name added, none renamed), and over `.github/actions/bot-pr-with-synthetic-checks` plus `_cron-safe-commit.ts` `SYNTHETIC_CHECK_NAMES`, neither of which may be handed a draft marker. `e2e` is a required context; since S2 it already carries `needs: [push-dedupe]` and a job-level `if:` (pinned by `ci-e2e-skip-anchors.test.sh`) and S3 adds NO `draft-light` term to it, so it runs on drafts. Event shapes: `pull_request` (draft, ready, `ready_for_review`, reopened, a re-run whose payload still says draft, fork, deleted fork), `merge_group`, `push`, `workflow_dispatch`.

**Mutation matrix.**

| Mutation (must go RED) | Targets |
|---|---|
| Make the draft aggregator arm exit 0, or classify `skipped` as tolerated | Option R: a draft `test` stays red |
| Feed the aggregator `EVENT_NAME=merge_group` or `push` with `DRAFT_LIGHT=true` and a skipped leg | the draft input is honoured only on `pull_request`; elsewhere a skipped leg still fails and the draft message never prints |
| Add a fifth heavy job that needs `draft-light` but leave it out of its `if:`, or add a heavy job to the gated set but not to `needs:` | the gated-set parity check, in both directions, derived from the parsed YAML |
| Set the variable to unset, empty, `ON`, `On`, ` on`, `on ` (whitespace), `true`, `1`, or `"on"` with quotes | only the exact string `on` enables light mode |
| Feed the `draft-light` body an empty or all-absent environment (0 inputs resolved) | it must emit nothing (full) and exit 0, never `light=true`; and the suite refuses a run that executed 0 fixture rows |
| Event payload draft `true` while the live read says `false` (a re-run after ready) | a stale payload never skips heavy jobs on a ready head: the live read alone decides |
| `ACTION=ready_for_review` with the live read saying draft `true` (a lagging read right after `gh pr ready`) | the ready run is never light, whatever the variable and the reads say |
| Live read errors, times out, returns non-JSON, `null`, a string `"true"`, or a missing `draft` key | an unresolved or malformed read is full |
| Head repository differs from the base repository, is empty, or is `null` (deleted fork) with the variable on | forks run full |
| Remove `continue-on-error: true` from `draft-light`, or give it a `needs:` on a heavy job | a failing lever must never redden the run it saves, and must not be able to deadlock the heavy jobs (they keep `!cancelled()`) |
| Add a `draft-light` term to `e2e`'s `needs:` or `if:` | the required `e2e` context keeps reporting on drafts (#8450); the existing anchors suite pins S2's pair, this row pins the S3 absence |
| Remove the `if: github.event_name == 'pull_request'` from `draft-light` | the lever must not take a runner on `push` or `merge_group` |
| Rename a required context, or add `draft-light` to `scripts/required-checks.txt` | no required name moves; the new job is not a required context |

**Harness rows.** (a) Replace the extracted aggregator body with a stub that prints success: the suite must fail. (b) Replace the extracted `draft-light` body with `echo light=true` and with `exit 0`: the suite must fail both. (c) Must-PASS inputs that are not the canonical fixture: a draft run with the variable on where the light legs succeed and the four heavy jobs are `skipped`, listed in a different order and with an extra unrelated leg name, producing the Option R verdict exactly (exit 1, the draft message on stderr, nothing on stdout); and a `workflow_dispatch` run with the variable on, which must run full and produce an ordinary green `test`. (d) A fixture whose `0 passed, 0 failed` ledger must fail the suite.

**Anchor.** The aggregator compares results, not a stored value, so no stored-value anchor applies. The independent anchor for "the full battery still ran before merge" is the `merge_group` run for queue merges, which S3 does not alter; it is NOT an anchor for the agent `--admin` path (that skips the queue; `admin-merge-ready.sh` is its only gate, Guard 2) nor for contexts the queue trusts the PR run for (`rename-guard`, `allowlist-diff`, vendor-pin, tenant), which live in other workflows that S3 leaves unchanged.

### Guard 2 - Verdict resolution and the ready-run wait (every reader of a PR head's CI state)

**Property.** For a non-draft PR head, no reader (monitor, poll, triage, admin readiness, battery decision) reports FAILED, READY or SKIPPABLE from a `test` row that predates the PR's latest ready event: while the newest `pull_request` run created at or after that event is in flight the answer is PENDING, a ready head with no such run is not ready and becomes `stalled` after N=75 minutes, and auto-merge is armed only after such a run exists.

**Assembly.** The chokepoint is `plugins/soleur/scripts/ci-head-verdict.sh` (`verdict`, `wait-ready-run`); every reader must reach it. The reader census (grepped on this tree, re-run at implementation with `git grep -n "gh pr checks\|statusCheckRollup\|check-runs\|required_failed\|gh pr ready\|gh pr merge" -- plugins .github scripts`): `plugins/soleur/scripts/monitor-pr-checks.sh`; `plugins/soleur/scripts/admin-merge-ready.sh` (and `--wait`); `plugins/soleur/skills/ship/SKILL.md` Phase 6 (ready then arm) and Phase 7 (`required_failed` poll, plus the `gh pr checks` reads at the later settle steps); `plugins/soleur/skills/merge-pr/SKILL.md` (a verbatim copy of that poll, and its arm step); `plugins/soleur/skills/drain-prs/` (`SKILL.md` arming, `scripts/triage-prs.sh` `fails`); `plugins/soleur/skills/ship/references/settle-then-admin-merge.md`; `plugins/soleur/skills/ship/scripts/battery-owed.sh` (reads rows directly; Option R keeps it correct, so it is covered by rows, not by the resolver); `scripts/followthroughs/pr-battery-gate-saving-9323.sh`. The resolver's rule is time-based (runs created at or after the latest ready event), so it needs no light-run detector and no pin on what else may skip a gated job.

**Mutation matrix.**

| Mutation (must go RED) | Targets |
|---|---|
| Non-draft head, red `test`, newest `CI` `pull_request` run in progress: feed `monitor-pr-checks.sh`, the Phase 7 poll fixtures, `triage-prs.sh` and `admin-merge-ready.sh --wait` | each reports PENDING / not failing from the newest run, not FAILED from the row |
| Non-draft head whose only runs and `test` rows predate the ready event (the ready run was never created) | `verdict` says `no-run`; after N=75 minutes since the ready event it says `stalled`; `admin-merge-ready.sh` returns ABSENT or PENDING, never READY; the probe FAILs |
| Non-draft head with NO `pull_request` run created after the ready event | `wait-ready-run` exits non-zero and the ship step does not run `gh pr merge --squash --auto` |
| Two PRs, the second with a second non-draft run: confirm `verdict` reads the NEWEST run at THIS head only | a check that stops at the first run or at another PR's head |
| `battery-owed.sh` fed a draft-era red `test` row on a ready head whose full run never started, then one that was cancelled | OWED, not SKIPPABLE |
| Feed `admin-merge-ready.sh` a draft-run `test` row and no ready-run row; then a draft row plus a pending ready row; then a draft row plus a green ready row | ABSENT or PENDING; PENDING; READY (the third must PASS, the guard cannot be a reject-everything stub) |
| Resolver given a completed run created after the ready event whose `test` row is red | `full-decided`: the row is authoritative and FAILED is reported (a reader must not hide a real failure behind PENDING) |
| Newest run after the ready event was cancelled (a manual `gh run cancel`, or a superseded run whose successor is missing) | `no-run`, not `full-decided` and not PENDING-forever |
| Never-draft PR (no ready event) with synthetic rows and no `pull_request` run; a PR readied before S3 merged with a green full draft-era `test`; both read after 80 minutes | `n/a` and `full-decided`, never `stalled` (the probe must not FAIL healthy PRs) |
| Ready run `queued` or `in_progress` for 80 minutes; ready run `action_required`; ready run `timed_out`; unknown conclusion | `stalled`; `awaiting-approval`; `full-decided` and reported failed; `no-run` (fail closed) |
| A run created 1 second before the timeline's ready time, and one created 6 seconds before | the first is kept (skew allowance), the second is not |
| Read-after-write lag: `ReadyForReviewEvent` count not yet above the caller's `--before-count`, or live `draft` still true | `wait-ready-run` keeps waiting and then fails closed; it never takes the previous ready event as T |
| A manual re-run of a pre-T draft run completes red after the ready run completed green | the newest `test` row belongs to another run: `not ready, reason=stale-row` for `admin-merge-ready.sh`, never silently ignored; the recovery text says `gh pr ready --undo` then `gh pr ready` |
| Resolve runs through each run's `pull_requests[]` instead of `workflows/ci.yml/runs?head_sha=` | the lookup row: a fixture whose runs have an empty `pull_requests[]` (92% of real runs) must still resolve |
| Resolver given an API error, an unparseable body, or an empty run list | exit non-zero / `no-run`, never `full-decided` or PENDING-forever |
| Reader bypass: add a `gh pr checks` read with a `required_failed` verdict to any skill or script without calling the resolver | a lint row (the suite greps the census patterns over `plugins/`) |

**Harness rows.** (a) Stub `gh` so every call returns an empty body: the resolver suite must fail, not pass. (b) `gh` stubs accept only real flags (`2026-09-25-gh-stub-must-mirror-real-cli-flags.md`). (c) Must-PASS non-canonical inputs: a PR whose ready run finished green 3 minutes after a light draft run on the same SHA (`full-decided`, rows authoritative), and a draft PR (`verdict` returns n/a and no reader changes behaviour). (d) The wiring test's decoy admin-merge call site, which exists to prove a lint can see call sites, must still be found after the edit.

**Anchor.** The resolver compares live API state at call time; no stored value. The independent control for the agent `--admin` route is `UNTRUSTED-CI` for workflow-editing PRs (unchanged) and the queue for every other merge.

### Guard 3 - The gate 6 census instrument

**Property.** The census prints a verdict-bearing mean only if its population is complete and non-vacuous: every daily slice reconciles to the API `total_count`, the cohort is non-empty, unmapped runs and branch-name collisions are below their bounds, and the mean is computed over closed draft windows opened inside the window; otherwise it prints no mean and exits non-zero.

**Assembly.** The script `scripts/ci-draft-push-census.sh` end to end: the runs fetch (30 daily slices, written to a file, never aggregated with `--jq`), the PR list and timeline fetch (paginated; a PR with more than 50 timeline events is flagged, not truncated), the join (`head_branch` to `headRefName`, never `pull_requests[]`), the window rebuild, the cohort filter, the arithmetic, and the output lines. Every fetch site is enumerated in the suite, not a sample.

**Mutation matrix.**

| Mutation (must go RED) | Targets |
|---|---|
| Truncate one daily fixture slice to 100 rows while its `total_count` says more | the reconcile check: exit non-zero, no mean printed |
| Join on `pull_requests[]` instead of `head_branch` (92% of real runs have it empty) | the unmapped-run bound |
| Include an open (right-censored) draft in the cohort, or clip a window at the start of the period | the closed-cohort rule |
| Count runs instead of distinct SHAs when a SHA has re-runs, or count a force-push to the same tree as two pushes | the unit definition and the "lower of the two bases decides" rule |
| Feed an empty cohort (0 PRs) | the dispatch floor: refuse, never print `MEAN 0` |
| Feed two PRs that reuse one branch name | collision exclusion is counted and printed |
| Fixture with 11 pushes over 4 PRs (exactly 2.75) and 10 pushes over 4 PRs (2.5) | boundary by integer cross-multiplication: 2.75 passes, below fails (a float compare cannot express 2.7499 on a small cohort) |
| Fixture where the mean passes but `POLICY_FLOOR_MEAN` is below 2.75 | the INDETERMINATE verdict, not PASS |

**Harness rows.** (a) Replace the script's arithmetic with `echo 9.99`: the suite must fail. (b) Must-PASS non-canonical fixture: a cohort listed in reverse order, with one PR converted to draft twice and one opened ready then converted, whose expected mean is hand-computed in the fixture. (c) `0 passed, 0 failed` fails the suite.

**Anchor.** The verdict compares a measured mean to the 2.75 constant from ADR-276; the independent anchor is the committed census output on the tracker issue (a reviewer can re-run the same command for the same closed window), and the amendment quotes the command so a weakened script cannot pass unnoticed behind an unchanged number.

## Architecture Decision (ADR/C4)

### ADR

No new ADR. The decision is ADR-276 Decision 4, already written. The deliverable is an **amendment to ADR-276** (`## Amendment <work date> (S3, #9728)`), written by hand under `soleur:architecture` conventions, committed BEFORE any behavior-bearing change (Decision 3(g)), in both branches: Branch A records the closure by gate 6 and the census; Branch B records the switch, the exit criterion, the gate results, the dark-window cost and the activation preconditions. Both append the Stage status lines `S1 live` and the S3 line. **ADR-276's `status:` stays `adopting`**: the CTO review-comment confirmation of the 2026-10-09 flip is still owed on merged PR #9876 (nothing had arrived as of 2026-10-09), so the amendment says the flip is unconfirmed, does not call it stronger than the operator's direction, and moves nothing toward `accepted` (that needs S5). Decision 3(h) (ADR-270 `accepted`) is met. If gate 5b forces a route filter in `apps/web-platform`, the amendment names it as a precondition of activation, not a hidden dependency. A pointer line to ADR-032 is added only if the work phase finds S3 changes what that ADR says about the `test` aggregator (S2 added one for `e2e`; decide by reading it, do not assume).

### C4 views

Read in full this session's relevant surface: `model.c4` (934 lines), `views.c4`, `spec.c4`. Checked against the rubric: external human actors (`founder`, `contributor`: the contributor's fork PR path is unchanged, forks run full), external systems (`github` "Source control, CI/CD...", `sentry`, `doppler`, `hetzner`: no new edge; the optional `apps/web-platform` webhook route filter touches an existing internal container, not an actor or system), data stores (none added), actor-to-surface access relationships (none changed), and the hosted runners (not modeled as an element; S3 adds no runner). `plugins/soleur/test/c4-count-parity.test.sh` was run on this branch: `ALL TESTS PASSED`, `Failed: 0`. **No C4 edit.** Branch B re-runs the parity test after the `ci.yml` job count moves (it gates job counts quoted in edge prose).

### Sequencing

Amendment first (Phase 2 or Phase 4), then tests, then `ci.yml`, readers, probe; activation last and outside the PR.

## Observability

The stage adds `ci.yml` logic and `plugins/soleur/scripts/*` readers, so the 5-field contract applies (Branch A adds only a census script and docs).

```yaml
liveness_signal:
  what: the S3 follow-through probe (stall signal for a readied PR with no run created after its ready event for more than 75 minutes, dark-window deadline, detective activation check, soak exit), plus the `ci-draft-light` annotation (`would_light`, `light`, reason) that `draft-light` writes on every pull_request run
  cadence: daily follow-through sweep; the annotation on every pull_request run
  alert_target: tracker issue #9728 (follow-through label) and the sweeper issue comment
  configured_in: scripts/followthroughs/ci-draft-light-soak-9728.sh and .github/workflows/ci.yml (job draft-light)
error_reporting:
  destination: workflow run annotations (::warning on a lever error) and the follow-through sweeper comment
  fail_loud: true
failure_modes:
  - mode: draft aggregator reads green, or a heavy job is skipped on a ready head
    detection: Guard 1 mutation suite in the required test context (executed bodies, gated-set parity), the canary run, and the probe's light-run-while-not-activated check
    alert_route: red test context, then probe failure on #9728
  - mode: ready run never created or ran light (wrong token identity, dropped event, lagging read)
    detection: ci-head-verdict.sh stalled state (N=75 minutes from the server-side ready event) read by the probe; Phase 6 wait step refuses to arm
    alert_route: probe failure naming the PR on #9728; the ship step reports readied-but-unarmed to the operator
  - mode: red draft runs flood engineering.ci_failed
    detection: gate 5b before activation; the route filter's test; after activation, count of ci_failed events per draft push in the Inngest event log
    alert_route: activation blocked; otherwise the probe's exit census records the count
  - mode: dark window overruns (merge without activation)
    detection: probe deadline check, 1 day after merge with no S3-ACTIVATED marker
    alert_route: probe failure on #9728
  - mode: census silently undercounts (truncated slice, unmapped runs)
    detection: Guard 3 reconcile and bounds; REFUSED verdict
    alert_route: the script exits non-zero and prints no mean
logs:
  where: GitHub Actions run logs and annotations; census and gate results committed under knowledge-base/project/specs/feat-one-shot-9728-ci-draft-light/measurements/ and attached to #9728
  retention: GitHub default run retention; committed files are permanent
discoverability_test:
  command: python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-10-09-ci-s3-draft-pr-light-checks-plan.md
  expected_output: 3 guard entries
```

The command checks the one machine-checkable artifact of the plan phase (the Guard Contract). The stage's own `discoverability_test` is `bash scripts/ci-draft-light.test.sh` (a short, executed-body suite) for Branch B and `bash scripts/ci-draft-push-census.test.sh --fixture` for Branch A.

### Soak follow-through enrollment (post-deploy time-gated close criterion)

The exit criterion holds for 7 days after activation and the variable carries a 30-day removal trigger, so closure is automated, not remembered: probe `scripts/followthroughs/ci-draft-light-soak-9728.sh` (Phase 8), tracker #9728 with the `follow-through` label and the `<!-- soleur:followthrough script=scripts/followthroughs/ci-draft-light-soak-9728.sh earliest=<merge+1d> secrets=... -->` directive; any new `secrets=` wired into `.github/workflows/scheduled-followthrough-sweeper.yml`; the 30-day variable removal is the probe's last stage after the exit census. The sweeper's token cannot read Actions variables, so activation is read from the `S3-ACTIVATED` tracker comment, as in S2.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The CTO agent reviewed this plan on 2026-10-09 and found the design sound: the API-only `draft-light` job, four gated jobs, an always-full ready run and one resolver is the smallest design that keeps Option R. Changes asked for and applied: (1) pin the light-run identification (the CTO's suggestion was a `draft-light`-succeeded requirement plus a skip-source invariant test; plan review replaced it with a time-based rule, runs created at or after the latest ready event, which removes the coupling), (2) make gate 5b a HARD activation precondition after reading `apps/web-platform/app/api/webhooks/github/route.ts` (`workflow_run` failure is the only gate, no event or branch filter, dedup by run id, so Option R would raise `engineering.ci_failed` cards about 7x), with a draft-head route filter as the default remedy, (3) shrink the dark window (arm the merge only when activation can follow; an authorized dark merge is bounded to 1 day, not 3), (4) the ledger bump to 26 with a dated note, and keep `draft-light` off the release budget path (it is a parallel root with `push-dedupe`). The ADR handling was confirmed correct: keep `adopting`, do not claim the CTO confirmation, require it plus the operator's go for activation, and plan a manual operator merge because a workflow-editing PR has no agent `--admin` path.

No product, UX, marketing, legal, finance or sales surface is touched (no user-facing page or copy); no GDPR surface (no personal data, no schema, no auth route; the optional webhook route filter reads a workflow-run payload that is already processed today) and no encryption posture surface (no store, no new cross-component connection). No new infrastructure: the repository variable is set with `gh variable set`, the accepted AP-001 carve-out in ADR-276 Principle Alignment.

## User-Brand Impact

- **If this lands broken, the user experiences:** a regression that a skipped heavy family should have caught reaches `main` and the deployed web app, or a ready PR is stuck on a red `test` that no one is told about; the merge-queue full battery and the stall probe bound both.
- **If this leaks, the user's workflow is exposed via:** no data surface; the only exposure vector is a mis-set repository variable, which fails closed to full CI.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** carried forward from the parent plan: S3 changes when checks run, not who can read what, and `merge_group` keeps the full battery; a single-user incident needs a data or credential surface, which this stage does not touch.

## Test Scenarios

1. Gate 6: a synthesized fixture of 6 PRs (reverse-ordered, one converted to draft twice, one opened ready then converted, one open draft excluded, two sharing a branch name) prints the hand-computed mean and cohort; a truncated slice prints no mean and exits non-zero.
2. Draft, variable `on`, payload and live draft: heavy jobs skipped, `test` red with `draft: full battery owed at ready`, `battery-owed.sh` OWED.
3. Same head marked ready (`ready_for_review`): full run, `test` green when the suites are, the wait step passes, queue entry, `merge_group` full regardless of the variable.
4. A re-run of a draft run after the PR went ready: live read says ready, so full. The variable flipped between the draft push and the ready: the ready run is full either way.
5. A fork PR with the variable on: full. `workflow_dispatch`, `merge_group`, `push` with the variable on: full, ordinary `test`.
6. Non-draft head, red draft `test`, ready run in flight: monitor, poll, triage and `admin-merge-ready.sh --wait` all say PENDING; ready run never created: `wait-ready-run` fails closed and nothing is armed; after 75 minutes from the ready event the resolver says `stalled` and the probe names the PR.
7. The `draft-light` job errors (lost runner, API failure): the run is NOT reddened and the heavy jobs run.
8. `ci.yml` job count 26, ledger row 26, `pr-fanout-ledger.test.sh` and `c4-count-parity.test.sh` green; no required context added or renamed.

## Files to Create

Branch A and B:
- `knowledge-base/project/specs/feat-one-shot-9728-ci-draft-light/tasks.md`, `decision-challenges.md`, `session-state.md`
- `knowledge-base/project/specs/feat-one-shot-9728-ci-draft-light/measurements/draft-push-census-<date>.tsv` (+ summary)
- `scripts/ci-draft-push-census.sh`, `scripts/ci-draft-push-census.test.sh`

Branch B only:
- `knowledge-base/project/specs/feat-one-shot-9728-ci-draft-light/measurements/gate-results.md`
- `scripts/ci-draft-light.test.sh`
- `plugins/soleur/scripts/ci-head-verdict.sh`, `plugins/soleur/test/ci-head-verdict.test.sh`
- `scripts/followthroughs/ci-draft-light-soak-9728.sh`, `scripts/followthroughs/ci-draft-light-soak-9728.test.sh`

## Files to Edit

Branch A and B:
- `knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md` (append only: the amendment and Stage status lines; `status:` unchanged)
- `scripts/test-all.sh`, `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv`, and, if a registrar demands it, `scripts/lib/test-affected-paths.sh` and `scripts/test-affected-kb-consumers.baseline.txt` (suite registration)

Branch B only:
- `.github/workflows/ci.yml`; `scripts/pr-fanout-ledger.txt` (25 to 26); `.github/CODEOWNERS` (lines for the census, `ci-draft-light` and probe files, as S2 did)
- `scripts/ci-push-dedupe.test.sh`, `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh`, and, only if their pins move, `plugins/soleur/test/ci-concurrency-key.test.sh`, `plugins/soleur/test/ci-e2e-skip-anchors.test.sh`
- `plugins/soleur/skills/ship/scripts/battery-owed.sh` (only if a row exposes a defect) and `plugins/soleur/test/ship-battery-owed.test.sh`
- `plugins/soleur/scripts/admin-merge-ready.sh`, `plugins/soleur/scripts/admin-merge-ready.test.sh`, `plugins/soleur/test/admin-merge-ready-wiring.test.sh`
- `plugins/soleur/scripts/monitor-pr-checks.sh`, `plugins/soleur/test/monitor-pr-checks.test.sh`
- `plugins/soleur/skills/ship/SKILL.md` (Phase 6, Phase 7), `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`, `plugins/soleur/skills/merge-pr/SKILL.md`, `plugins/soleur/skills/drain-prs/SKILL.md`, `plugins/soleur/skills/drain-prs/scripts/triage-prs.sh`, `plugins/soleur/test/drain-prs.test.sh`, `plugins/soleur/skills/ship/references/settle-then-admin-merge.md`
- `scripts/followthroughs/pr-battery-gate-saving-9323.sh` and its test (a fixture row; edited only if the check shows a light run enters its baseline)
- Conditional on gate 5b: `apps/web-platform/app/api/webhooks/github/route.ts` and `apps/web-platform/test/server/webhooks/github-route.test.ts`

Verify before editing: every path above exists on `origin/main` (`git ls-files <path>`); the work phase runs that check for the whole list, because a plan-time path that does not exist is a build, not an edit.

## Acceptance Criteria

### Pre-merge (PR)

Both branches:
- [ ] `scripts/ci-draft-push-census.test.sh` passes; the live census output is committed under `measurements/` and attached to #9728 with its command; `SLICES_RECONCILED` is true and the verdict line is one of PASS, FAIL, INDETERMINATE (never REFUSED).
- [ ] ADR-276 has a new `## Amendment` for S3 and the Stage status lines `S1 live` and the S3 line; `git diff origin/main...HEAD -- <ADR>` shows only appended lines and the `status:` line still reads `adopting`.
- [ ] `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-10-09-ci-s3-draft-pr-light-checks-plan.md` reports 3 guard entries; `bash scripts/check-adr-ordinals.sh` passes.
- [ ] The three directly-run suites pass: `scripts/test-affected-kb-consumers.test.sh`, `.claude/hooks/grep-q-pipe-guard.test.sh`, `scripts/guard-vacuity-floor.test.sh`.
- [ ] `net-issue-flow.sh` reports net <= 0; the commit trailer and PR-body ending are present.

Branch A (FAIL) additionally:
- [ ] `git diff --name-only origin/main...HEAD` (merge-base diff) lists nothing under `.github/`, `plugins/`, `apps/`; `Closes #9728` in the PR body; the closure comment on #9728 states the verdict numbers; a note exists on #9729 and #9730.

Branch C (INDETERMINATE) additionally: as A, but `Refs #9728`, no closure, the dated re-measure comment exists.

Branch B additionally:
- [ ] `measurements/gate-results.md` records gates 1 to 5b with the commands and outputs, and every gate cleared or was answered by design; the throwaway PR is closed and its branch deleted; no `ci.yml` edit precedes the S3 amendment commit (`git log` order).
- [ ] `yaml.safe_load(ci.yml)['jobs']` has 26 entries and the ledger row says 26; `types` is `[opened, synchronize, reopened, ready_for_review]`; `draft-light` is `continue-on-error`, `timeout-minutes: 3`, has no `needs:`; the four gated jobs and the `test` aggregator carry `draft-light` in `needs:`; `e2e` has no new condition.
- [ ] `scripts/ci-draft-light.test.sh`, `scripts/ci-push-dedupe.test.sh`, `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh`, `ci-head-verdict.test.sh`, `ship-battery-owed.test.sh`, `admin-merge-ready.test.sh`, `admin-merge-ready-wiring.test.sh`, `monitor-pr-checks.test.sh`, `drain-prs.test.sh`, `ship-phase-7-poll-fixtures.test.sh`, `pr-fanout-ledger.test.sh`, `c4-count-parity.test.sh` and the probe's test pass; each Guard's mutation rows were run RED once and recorded.
- [ ] `grep -n "gh pr ready" plugins/soleur/skills/{ship,merge-pr,drain-prs}/SKILL.md` shows each followed by the `wait-ready-run` step before any `gh pr merge`; the lint row proves no reader bypasses the resolver.
- [ ] The probe test passes; #9728 carries the `follow-through` label and the directive (`earliest=` merge + 1 day); PR body says `Refs #9728`.
- [ ] The dark phase is observable before any flip: at least one real draft push after merge shows the `would_light=true` annotation (real Actions engine, variable still unset), recorded on #9728.
- [ ] If gate 5b found delivery for this repo: the route filter and its test are in the PR, or the app subscription change is recorded, before the activation step.

### Post-merge (operator-visible follow-through)

- [ ] After activation, the first activated PR's runs are recorded on #9728: the light run (four gated jobs skipped, `test` red with the draft message), the ready run (full, `test` green), the `wait-ready-run` exit, the queue entry and the `merge_group` run. This is the live check the extracted-body suites cannot give for `needs`, `!cancelled()` and `continue-on-error` semantics.

- [ ] Run from a detached `origin/main` worktree (never the main checkout): `git ls-files` shows the new suites registered in `scripts/test-all.sh`; `yaml.safe_load` job count 26; ADR-276 `status: adopting`.
- [ ] Activation (outside the PR, needs the operator's go and the CTO confirmation or the recorded statement): `S3-CONFIRMED`, then `gh variable set CI_DRAFT_LIGHT --body on`, then `S3-ACTIVATED` on #9728; the probe passes after 7 days with the exit census (draft `CI` minutes per draft push down at least 80%, zero stalls, zero heavy-unrun queue entries, net minutes down at least 25%).
- [ ] Stop rule: if the live pushes per draft PR fall below 2.75 the variable is deleted and the stage closed. Removal trigger: 30 days with zero escapes, delete the variable and keep only the draft-input arm.
- [ ] S4 (#9729) and S5 (#9730) are re-decided only after the S3 post-merge census exists (or Branch A's closure, which unparks them).

## Risks and Sharp Edges

- **The pilot is not the verdict.** 8.24 and 7.18 came from a planning-time script that was not self-checking; the committed census decides. If it disagrees, Branch A or C is the correct outcome, not a failure.
- **Red draft CI is a behavior change for people and bots**, not only for the aggregator: GitHub shows a failing `CI` on every draft push, Actions failure notifications go to authors, and the `engineering.ci_failed` route may fire (gate 5b). Option R is decided; the plan lists the side effects so activation is informed.
- **Time-based resolver.** The resolver keys on the latest ready event, so a PR that is converted to draft and readied again resets T; a head pushed while draft after the last ready event cannot occur (a draft head has no ready event after it). The ready event is read from the GraphQL timeline with `last: 1` of `READY_FOR_REVIEW_EVENT`, never from local time.
- **The `types` entry cannot be switched off.** Rolling the variable back does not remove the extra ready run; only a revert does (Rollback column of the issue).
- **Ready-draft-ready with no new push** reruns full on a head that may already be green (accepted cost under Option R). Converting a queued PR to draft dequeues it (ship Phase 7 already reads that). A light run cancelled by the per-ref concurrency group leaves `cancelled` rows that pollers must ignore in favor of the newest row per name. `fix-constraints-stage-b.yml` opens drafts with `github.token` (no CI), so the human ready click is that PR's first run.
- **Release budget.** `draft-light` must stay a parallel root next to `push-dedupe`; if the implementation gives it a `needs:` or raises its timeout, re-derive the release workflow's CI path (73 of 75 minutes today, slack 2; check B9).
- **Workflow-editing PR.** `UNTRUSTED-CI` means no agent admin merge; if the queue livelocks the operator merges by hand.
- **Skill budgets.** The Phase 6/7 edits are in lifecycle skills under a byte ratchet (ADR-229) and the description word budget; trim a sibling sentence, never raise a cap.
- A plan whose `## User-Brand Impact` section is empty, omits the threshold, or holds only placeholder text fails `deepen-plan`; this one carries all three lines.
- **Do not edit the parent plan, the parent spec directory or the earlier ADR-276 text**; the amendment is append-only.

## Plan Review Outcome

Panel (headless, brand-survival threshold `aggregate pattern`): DHH, Kieran, code-simplicity, plus the CTO agent under the Domain Review gate. Findings are classified; mechanical ones are applied, taste and user-challenge ones are recorded in `knowledge-base/project/specs/feat-one-shot-9728-ci-draft-light/decision-challenges.md`.

| Finding | Source | Class | Disposition |
|---|---|---|---|
| Gate 5 live probe is vacuous (`UNTRUSTED-CI` refuses before reading rows); Gate 1 must mirror one workflow with two runs and a delayed aggregator row | Kieran, simplicity | mechanical | Applied (Phase 3: stubbed fixtures for gate 5, single probe workflow for gate 1, real workflows deleted on the scratch branch) |
| Branch A must not touch `.github/CODEOWNERS`; the draft arm must sit before the final `fail` check; `draft-light` needs `if: event_name == pull_request`; e2e wording; resolver must not use `pull_requests[]` | Kieran | mechanical | Applied (Phases 1, 6, 7; Guard 1 and 2 rows) |
| A registered "amendment precedes ci.yml" suite cannot survive a squash merge | DHH, Kieran | mechanical | Applied (ship-time check plus a stateless ADR-heading check) |
| Phase 1 never measures the light-run cost, e2e or bot ready transitions; the census needs explicit 12-hour windows | DHH, Kieran | mechanical | Applied (Phase 1 step 3 output lines) |
| Read gate 5b early; gate it before the canary | DHH, CTO | mechanical | Applied (Phase 1 step 6, Phase 9 step 1) |
| Detect lightness by ready-event time, not jobs-API shape | DHH | taste | Applied: removes the skip-source coupling to S4 and the light-owed state |
| Drop the event payload input; keep the live read | DHH (drop payload) vs simplicity (drop the live read) | taste | Applied DHH's half. The live read stays because ADR-276 Decision 4 and the issue require resolving draft state live; simplicity's `RUN_ATTEMPT` substitute is recorded as declined |
| Drop INDETERMINATE / Branch C and the floor | DHH, simplicity | taste (Kieran: user-challenge) | Not applied: the operator's rule is a measured post-policy mean; collapsing to the raw mean loosens it. Renamed `POLICY_FLOOR_MEAN`, stated as an assumption, boundary by integer cross-multiplication |
| Shrink Phase 7 to the wait step unless gate 1 or 5 shows readers misread | simplicity | taste (conflicts with the operator's listed consumers) | Partly applied: each reader edit starts from a failing fixture and an already-correct reader is only pinned |
| Trim probe checks (registration check, `proposed` check); keep markers | DHH, simplicity | taste | Applied for the registration and `proposed` checks; the dark deadline and `S3-CONFIRMED` are kept (CTO) |
| Guard matrices wider than the unique risk | DHH | taste | Declined: the matrices are the Guard Contract gate's required shape; duplicated rows are annotated |
| Reconciliation of the footprint in the ADR rollback section | DHH | user-challenge (informational) | Applied (Phase 4) |

## Review amendments (2026-10-10, PR #9885)

Appended; the sections above are left as written. Superseded by review: the stall threshold is 120 minutes (was 75: 73 declared + 14 p90 queue wait = 87), the resolver has no clock-skew allowance (a draft push's light run created just before the ready call must never be adopted as the ready run), and the API-error marker is `state=error`, outside the closed state set. The resolver also answers n/a / ok when the repo's default-branch ci.yml has no `draft-light` job, and the webhook filter is scoped to `jikig-ai/soleur`.

### User-Brand Impact (amended; this supersedes the section above for review purposes)

- **If this lands broken, the user experiences:** (1) a Soleur user in a CUSTOMER repository whose ship/merge flow now calls `ci-head-verdict.sh`: without the applicability probe, `wait-ready-run` would wait 300 s for a ready run that never comes and tell them not to arm (`plugins/soleur/scripts/ci-head-verdict.sh`, `plugins/soleur/skills/ship/SKILL.md` step 6); (2) a genuinely failing `test` on a ready PR read as pending during an API outage (the old `state=no-run reason=api-error` marker), so no one is told; (3) a founder's `engineering.ci_failed` card for a failing draft run silently dropped (`apps/web-platform/server/webhook-draft-ci-run.ts`, in force from deploy whether or not `CI_DRAFT_LIGHT` is set; a customer installation's own `CI` workflow is out of scope of the filter); (4) a regression a skipped heavy family should have caught reaching `main`: bounded by `merge_group` running the full battery, the red `test` on a light draft, and the ruleset.
- **If this leaks, the user's workflow is exposed via:** no data, credential, billing or user-table surface is touched. The exposure vectors are the variable `CI_DRAFT_LIGHT` (a mis-set value fails closed to full CI), the resolver's read-only `gh api` calls, and the webhook lookup (installation token, 5 s deadline, fail-open).
- **Brand-survival threshold:** `aggregate pattern` (unchanged: nothing here is a single-user incident without a data or credential surface; the merge line is held by `test` + `e2e` + the queue, not by the readers).
- **Rollback completeness:** deleting the variable restores full draft CI; the webhook filter, the `ready_for_review` type, the wait step and the readers need a revert (ADR-276 S3 amendment, "How to roll back").
