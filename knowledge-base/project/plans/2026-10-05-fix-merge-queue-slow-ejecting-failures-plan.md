---
title: "fix: merge queue is slow because failing candidates eject and force rebuilds"
date: 2026-10-05
slug: merge-queue-slow-ejecting-failures
branch: feat-one-shot-merge-queue-slow-failures
issue: 9482
lane: cross-domain
type: fix
requires_cpo_signoff: false
brand_survival_threshold: none
---

# fix: merge queue is slow because failing candidates eject and force rebuilds

## Enhancement Summary

**Deepened on:** 2026-10-05
**Sections enhanced:** Phases 1 to 4, Guard Contract, Acceptance Criteria, Test Scenarios, Scope Check, Observability
**Agents/checks used:** plan-review panel (DHH, Kieran, code-simplicity, CTO devex), architecture-strategist, test-design-reviewer, learnings-researcher, repo-research-analyst; direct source reads of `playwright-core` `isURLAvailable`, `playwright` `tasks.js`/`failureTracker.js`, Next 16.3.6 local-font loader; live `gh` re-verification of cited PRs and the #9505 timeline; mechanical gates 4.6 to 4.12 (all pass after the Scope Check restructure).

### Key Improvements
1. Phase 2 no longer adds files: `url:` readiness replaces a global-setup probe, helper, unit test and second guard (a `FullConfig.webServer` is `null` for an array config, which would have made the probe vacuous).
2. Guard 1 enumerator now includes untracked files and a fs-walk fixture path; floor raised from 300 to 1,500 (measured 2,304).
3. Otp-login negative control made deterministic (injected status element) after finding the pending island holds only 400 ms.
4. Cold-compile risk handled: webServer timeouts 120 s to 180 s so readiness cannot become a new ejection cause.
5. Corrected: no `adjustFontFallback` needed (Next computes it by default); #9505 timeline updated (87.7 min, merged 11:30:24).

### New Considerations Discovered
- The `lint-bot-statuses` red was an advisory job; PR #9477's 56 min came from an agent push (manual dequeue), not an ejection.
- PR-event workflows are about 61% of window demand (`ci.yml` PR 2,046, `secret-scan` 325, `PR quality guards` 224, `Infra Validation` 104 job-min): the next lever, recorded for #9482, not built.


Ref #9482 (ADR-270, status stays `adopting`). Draft PR #9523. Never `Closes #9482`.

Spec lacks a valid `lane:` (no spec.md exists for this branch): defaulted to `cross-domain` (fail-closed).

## Overview

The operator reported on 2026-10-05 that the merge queue feels slow. A read-only measurement
(gh REST and GraphQL, 2026-10-05, all figures re-pulled during planning) attributes it to two
things, neither of which is main moving:

1. **Candidate failures eject an entry and force every entry behind it to rebuild.** 4 of the 27
   `merge_group` `ci.yml` runs since adoption failed on a *required* check and ejected (3 `e2e`, 1
   `test`); a fifth red run was an advisory job and ejected nothing. Two root causes explain all
   three `e2e` ejections and one explains the `test` ejection candidate (unproven, see Phase 4).
2. **The shared runner pool is saturated in bursts.** At 10:00 to 11:05 UTC demand was 4,435
   job-minutes against 3,900 slot-minutes (60 concurrent jobs x 65 min); the merge queue itself
   was only 22% of it. Rebuilds, PR-run churn and other workflows fill the rest.

The plan fixes the failure causes (highest yield first), makes a dev-server compile failure fail at
server readiness (about 3 min) instead of after 14, and records the contention decision with its numbers. It does
**not** change any ruleset parameter, does not touch ADR-270, and does not redo draft PR #9511
(Sentry route for the stall dispatcher and the ADR canary log; branch
`feat-one-shot-9482-merge-queue-followups`, files listed in Research Insights).

## Research Reconciliation: brief vs measured reality

| Brief claim | Reality (command in Research Insights) | Plan response |
| --- | --- | --- |
| "5 of 25 completed merge_group runs failed (20%)" | 27 `merge_group` runs since adoption (18 distinct PRs); 5 `failure`, 2 in progress. Of the 5, **4 ejected** (e2e x3, test x1); the 5th (`lint-bot-statuses`) is a non-required advisory job: it reddened the run but did **not** eject. PR #9477 left the queue because the agent pushed a fix (`RemovedFromMergeQueueEvent reason=manual`, 15:13:46) | Ejection rate is 4/27 = 15%. No fix for `lint-bot-statuses`; document it (Phase 5) |
| "three e2e failures: one flake or several?" | **Two** causes. `37224723661` and `37295454362`: Turbopack font-resolve cascade (64 red, 14 min). `37216842585`: otp-login strict-mode (1 red, 3 min) | Phase 1 and Phase 3 |
| #9167 "dev-Supabase `Signups not allowed for otp` cascades ~35 reds" | That string is the **mocked payload** in `e2e/otp-login.e2e.ts` (`msg: "Signups not allowed for otp"`); it appears in green e2e logs too (run `37212574590`: count 1, 115 passed). e2e uses a mock Supabase, not dev-Supabase. The 64-red cascade carries the font signature instead | Comment on #9167 with this; fold the cascade into #8785 (Phase 1 step 4) |
| "operator knows the nav-states e2e flake" | The nav-states reds in these runs are *collateral* of the font cascade (authenticated project, `Dev server compile error (5xx on chat route)`), not a nav-states defect | Fix upstream cause; do not touch nav-states specs for this |
| "test-scripts (2/8) in 37293827216" | One suite: `plugins/soleur/skills/git-worktree/test/reap-archive-persistence.test.sh` fixture G, 1 assertion (`plan archive commit missing`). 1 occurrence in 54 failed `test-scripts` jobs; PR run of the same PR passed | Phase 4: reproduce under contention, else make the next occurrence diagnosable; comment on #7376, no new issue |
| "runner contention inferred, not measured at job level" | Measured: job-level queue wait up to 1,342 s, peak 60 concurrent jobs (the Team-plan entitlement) | Phase 5 decision table |
| ADR canary 3 "auto-merge state after removal unmeasured" | On #8820 and #9505 the entry was re-added 2 to 3 min after a `failed_checks` removal with no `AutoMerge*` event in between: auto-merge stays armed and GitHub re-enqueues at the back. A `manual` removal (a push) does not re-add | Record in the #9482 comment; the canary log lives in PR #9511, so do not edit it here |

## Research Insights

### Premise validation (Phase 0.6)

Cited and checked: #9482 OPEN (decision-challenge tracker, follow-ups a to d), #9512 OPEN (follow-up c,
trigger fired, `deferred-automation`), #9167 OPEN p1, #9170 OPEN p3 (3 comments; a 2026-10-04 occurrence
is run `37216842585`), #9190 OPEN (c4-code-panel, local contention only), #7376 OPEN (68 comments),
PR #9511 OPEN draft (nine files: sentry `alert-reference.json`, `cron-monitor-alerts.tf`,
`cron-monitors.tf`, ADR-270, `runbooks/merge-queue-canary-log.md`, one learning, archived plan/spec),
PR #9523 OPEN draft (this branch). **Found, not cited by the brief: #8785** ("flake: e2e - Turbopack
can't resolve `@vercel/turbopack-next/internal/font/google/font`", OPEN p2, created 2026-09-24). Its own
recurrence watch says "escalate if the signature appears on >= 2 main runs within a week"; it also hit the
release Docker build (run `36067109286`). Mechanism vs ADR corpus: the ADR-270 "Parameters" row for
`max_entries_to_build` says "Raise to 3 only after the canary shows contention is not binding"; the
**Raise checklist** applies to `max_entries_to_merge`, not `max_entries_to_build`. Nothing here proposes
a rejected alternative.

### Property List (Phase 0.6b)

- **P1.** A queue entry is ejected only by a defect in its own change, not by an environmental flake.
- **P2.** When a candidate does fail, the verdict arrives in minutes so the entries behind it rebuild sooner.
- **P3.** Runner capacity is not spent on avoidable work; the contention decision rests on measured numbers.
- **P4.** Every tracker the brief names carries the new evidence (comment or fold), and no duplicate issue is filed.

### Cut List

| Mechanism | Property | Cut because |
| --- | --- | --- |
| `maxFailures` cap (any value) | P2 | Three reviewers disagreed (keep, cut, merge_group only). Phase 1 removes the dominant cascade and `url` readiness catches a compile failure at start; the residual (auth server death) is 2 of 303 runs, PR runs only, and a cap truncates failure reporting on PR runs. Re-add only if a new cascade appears |
| Global-setup probe, extracted helper, unit test | P2 | `url:` readiness in `playwright.config.ts` gives the same early failure with no new file |
| Retry the failing `e2e` job or step | P1 | Playwright already retries once (`retries: 1`); both attempts fail identically on the font error. Retry hides the cause (brief says do not just retry) |
| Lower `max_entries_to_build` 2 to 1 | P3 | The queue is 22% of window minutes; the waste is rebuilds *caused by failures* (11 of 27 runs were not the run that merged). Serial builds would add about 14 min per entry in the healthy case. Re-decide after the fixes land (Phase 5) |
| Skip non-required jobs on `merge_group` | P3 | Non-required jobs (`lint-bot-statuses`, `critical-css-gate`, `harness-discovery`, `lint-webplat`, `test-bun`, `web-platform-build`) total about 8 of 137 median job-minutes (6%), and the `ci.yml` invariant comment forbids event gates on required producers |
| New flake-quarantine registry | P1 | None exists (grep: no `quarantine` or flake-census file); an ad-hoc `test.fixme` hides a cause that is fixable here |
| ADR-270 edit or flipping `adopting` | all | Out of scope by constraint; PR #9511 also edits ADR-270 (merge-conflict surface) |
| A re-measurement script in `scripts/` | P3 | The recipe below is enough for the one re-measure; a script is a mechanism with no second consumer |

### Task 1 data: why each failure happened

All logs pulled with `gh api --allow-escape-sequences repos/jikig-ai/soleur/actions/jobs/<id>/logs`.

| Run (event, PR) | Job | Verdict | Cause |
| --- | --- | --- | --- |
| `37295454362` (merge_group, #9505, 2026-10-05 10:15) | `e2e` 14.5 min | 64 failed / 37 passed / 21 skipped | **Font cascade** (cause A) |
| `37224723661` (merge_group, #9492, 2026-10-04 18:30) | `e2e` 15.1 min | identical 64 / 37 / 21 | **Font cascade** (cause A) |
| `37216842585` (merge_group, #9478, 2026-10-04 16:27) | `e2e` 4.3 min | 1 failed / 114 passed / 7 skipped | `otp-login.e2e.ts:127` strict-mode, `getByRole('status')` resolved to 2 elements (cause B, #9170) |
| `37293827216` (merge_group, #8820, 2026-10-05 10:01) | `test-scripts (2/8)` then `test` aggregate | 80/81 suites; 44 pass, 1 fail in one suite | `reap-archive-persistence.test.sh` fixture G, `plan archive commit missing` (cause C, unproven) |
| `37212108914` (merge_group, #9477, 2026-10-04 15:12) | `lint-bot-statuses` | red, advisory | Real content violation: `lint-infra-no-human-steps.py` flagged `always-on-audit.md:538` (PR's own text). The PR's own `pull_request` run was already red on the same job at 14:58 and was enqueued anyway because the job is in neither `scripts/required-checks.txt` nor the ruleset. Not an ejection cause |

**Cause A (font cascade).** `app/fonts.ts` loads Inter through `next/font/google`. During the first
compile of `app/layout.tsx` on the authenticated dev server (port 3100, distDir `.next/e2e-auth`),
Turbopack fails with `Module not found: Can't resolve '@vercel/turbopack-next/internal/font/google/font'`
plus `next/font/google queries have exactly one entry` (14,7xx log lines per run). Every authenticated
page then 5xx's; `helpers/glyph-box.ts skipLocallyFailInCi` throws in CI, so all 64 `[authenticated]`
tests (cc-soleur-go-routing, nav-states-nav-pending, nav-states-shell, start-fresh-onboarding) go red, each
with a retry at a 60 s timeout, so the job burns 13.3 min of Playwright time against 2.9 min healthy.
It is intermittent (the public server and the same code pass most runs), which fits a transient
fonts.gstatic.com fetch, though the exact failing request is not in the logs. Census over all 303 `e2e`
executions since 2026-10-03: 13 failed (4.3%); 5 font cascade (2 merge_group, 3 pull_request; includes
`37148413395`, `37204806209`, `37235557418`), 4 otp strict-mode, 2 `ERR_CONNECTION_REFUSED` on :3100
(auth server died), 2 `toBeVisible` timeouts on PR-specific changes. #8785 recurrence threshold (>= 2
within a week) is exceeded. The `CSP` is already `font-src 'self'` (`lib/csp.ts`), so the browser never
needed Google; only the build-time fetch does.

**Cause B (otp strict-mode, #9170).** `components/nav/nav-pending-island.tsx` mounts
`<div role="status" class="sr-only">Loading</div>` while a navigation is pending; `otp-login.e2e.ts:174`
and `:177` assert `page.getByRole("status")` on the post-redirect `/signup` banner (the banner has no
`role`/`data-testid` of its own on the signup page). If the login-to-signup pending episode has not
cleared, two elements match. Four occurrences in 3 days (one in merge_group). The four `toHaveCount(0)`
checks (`:181`, `:195`, `:207`, `:219`) have the mirror race.

**Cause C (reap-archive-persistence G).** Fixture G sets `chmod a-w knowledge-base/project/specs`,
runs the reaper, and asserts the tracked plan still produced a `chore(archive-kb)` commit within
`git log -3`. The commit path is `_reap_archive_commit` (`worktree-manager.sh`), which degrades to
`SOLEUR_REAP_ARCHIVE_STAGED` when `git commit` fails; the failure message does not print the markers,
so the log cannot say whether it was STAGED, a hook, or an identity wedge. Not reproduced; not in
#7376's named suites, but the same "passes alone, fails under shard contention" class.

### Task 3 data: runner contention at job level (window 2026-10-05 10:00 to 11:05 UTC)

Command: `gh api "repos/jikig-ai/soleur/actions/runs?created=2026-10-05T08:30:00Z..2026-10-05T11:20:00Z&per_page=100" --paginate`
(955 runs, all workflows), then `gh api repos/jikig-ai/soleur/actions/runs/<id>/jobs?per_page=100 --paginate`
for each (5,548 jobs); queue wait = `started_at - created_at`; running = `started_at <= t < completed_at`.

| Metric | Value |
| --- | --- |
| Peak concurrent running jobs (success or failure only) | 60 (equals the Team-plan entitlement) |
| Demand vs capacity | 4,435 job-min vs 3,900 slot-min (60 x 65) |
| Share of demand | PR `ci.yml` 46% (2,046), other workflows 32% (1,423), `merge_group` `ci.yml` 22% (967) |
| PR `ci.yml` jobs cancelled mid-flight (still billed to the pool) | 430 job-min (10% of demand); 221 cancelled jobs |
| Push-to-main duplicate run (#9512) | 138 job-min (3.1% of demand) |
| Max queue wait of a `merge_group` job, by 5-min bucket | 10:00 115 s, 10:15 239 s, 10:20 520 s, 10:25 698 s, 10:30 924 s, 10:35 1,238 s, 10:40 1,342 s, 10:50 1,012 s |
| Median queue wait of `merge_group` jobs | 3 to 5 s when quiet (08:10 to 10:10); 376 to 1,080 s from 10:20 to 10:50 |
| `merge_group` run wall time | 11 to 17 min quiet (n=19); 23.7 to 35.8 min for the five runs created 10:14 to 10:36 |
| Jobs per `merge_group` run / job-minutes | 34 / about 130 to 149 (median sum 137) |
| Longest healthy jobs | `test-scripts` shards 6.8 to 13.4 min (8 shards, 72 job-min), `test-scripts-heavy` 18, `test-webplat` 11, `shard-totality-mutations` 10, `e2e` 4.2 |
| `merge_group` runs per PR | 27 runs / 18 PRs; 11 of 27 (41%) were not the run that merged the PR (5 failed, 6 superseded by a rebuild); #8820 was built 3 times |

Enqueue-to-merge re-verified from the GraphQL timeline (`ADDED_TO_MERGE_QUEUE_EVENT` /
`REMOVED_FROM_MERGE_QUEUE_EVENT`): #9229 15.0 min, #9491 18.0, #9507 32.6 (behind a 24.5 min contended
run), #8680 33.0, #8820 64.2 (removed `failed_checks` 10:15:45 on the `test-scripts` shard, re-added 10:19:05,
rebuilt again 10:36 when #9505 was ejected, merged 11:05:00), #9505 87.7 min (enqueued 10:02:41, ejected `failed_checks` 10:36:41 on the font-cascade `e2e`,
re-added 10:38:44, merged 11:30:24; verified at deepen time, it was still open at plan time).

Ejection latency: `e2e` for #9505 started 10:21:37 and failed 10:36:12, so the entry behind it learned
at 10:36 rather than about 10:25 had the cascade failed fast.

**Reading.** The contention is real but is a *consequence*: rebuilds triggered by ejections (each about
133 job-min and 14 to 25 min of wall time) land on a pool that PR churn already fills. The queue's own
share is small, so shrinking it (`max_entries_to_build`) buys little and costs speculation. Removing the
ejections removes the rebuilds.

### Institutional learnings applied

- `2026-06-30-github-merge-queue-adoption-wire-all-ruleset-producers.md`: every required producer runs on `merge_group`; `base_ref` is empty there (the lint-bot-statuses step already falls back).
- `2026-10-04-a-queue-candidate-trust-check-premised-on-an-unmeasured-commit-shape.md`: measure the real object, not a mental model (this plan measures real runs).
- `2026-09-22-actions-queue-under-assignment-metrics-and-monitor.md`: job-wait medians survive only on jobs that started; this plan reports max and per-bucket as well as medians.
- `2026-06-03-shared-hook-fetch-coalescing-and-e2e-flake-isolation.md`: a flake with a different failure set per run is a timing or infrastructure defect.
- `2026-02-14-google-fonts-variable-font-deduplication.md`: Inter is a variable font; one woff2 serves all weights. Re-verified 2026-10-05: the Google CSS maps latin 400, 500 and 600 to the single file `.../s/inter/v20/UcC73FwrK3iLTeHuS_nVMrMxCp50SjIa1ZL7.woff2`.
- Unverified claim excluded: the learnings sweep reported an "advisory job must not dequeue" learning; the cited file contains no such text, so it is not relied on.

## Open Code-Review Overlap

- #3564 (Core Web Vitals infrastructure, touches `app/fonts.ts` and `app/layout.tsx`): **Acknowledge.** Different concern (field RUM). The vendored font keeps `display: "swap"` and the same CSS variable, so it does not constrain #3564. Remains open.
- No open code-review issue touches `playwright.config.ts`, `e2e/global-setup.ts`, `e2e/otp-login.e2e.ts`, `e2e/nav-states-nav-pending.e2e.ts`, `reap-archive-persistence.test.sh`, `.github/workflows/ci.yml` or `lib/csp.ts`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Find out WHY each failure happened." [brief task 1] | Research Insights Task 1 table; Phases 3 and 4 diagnostics | mapped |
| 2 | "Fix or quarantine the causes found in step 1 (the e2e flake is the highest-yield one; the operator already knows the nav-states e2e flake exists). Prefer root-cause fixes; do not just retry." [brief task 2] | Phase 1 (font, the e2e flake), Phase 2, Phase 3 (otp), Phase 4 (fixture G) | mapped |
| 3 | "Measure runner contention at JOB level (job started_at minus run created_at, and concurrent run count) for the 10:00 to 11:05 window, then decide whether a lower max_entries_to_build or running fewer jobs per merge_group run helps." [brief task 3] | Research Insights Task 3 table; Phase 6 items 1 to 3 | mapped |
| 4 | "Re-evaluate its trigger with the contention numbers from step 3; it needs its own plan" [brief task 4, #9512] | Phase 6 item 5 | mapped |
| 5 | "Search existing trackers first: #9167 and #9170 (flaky e2e), #9190 (c4-code-panel flake under contention), #7376 (registered infra suites flaky under -P). Comment on or fix those rather than filing duplicates." [brief task 1] | Phase 5 item 2 (consolidated comments), PR body `Closes #8785`, `Closes #9170` | mapped |
| 6 | "PR bodies use `Ref #9482`, never `Closes`." [brief constraints] | Acceptance Criteria (PR body line) | mapped |
| 7 | "ADR-270 stays `adopting`; do not flip it." [brief constraints] | Acceptance Criteria (empty diff on ADR dir); Non-Goals | mapped |
| 8 | "Do NOT act on the three operator decisions on #9482 (deploy hold, brand-survival threshold, `actions`-language alerts); defaults stand." [brief constraints] | Non-Goals | mapped |
| 9 | "Net-issue-flow gate: close or fold into existing trackers before filing new issues." [brief constraints] | Phase 5 (no new issues); Cut List | mapped |
| 10 | "the plan must include the data findings from tasks 1 and 3" [brief planning-phase note] | Research Insights (Task 1 and Task 3 data) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Phase 1: `app/fonts.ts`, `assets/fonts/inter-latin-wght.woff2` | "the e2e flake is the highest-yield one" (ask 2) | asked |
| Phase 1: three `vi.mock("next/font/google")` repoints | - | inferred - justification: the unit tests mock the module the import names; leaving the old mock name makes three suites import the real loader and fail |
| Phase 1: `assets/fonts/README.md` | - | inferred - justification: a vendored binary with no recorded source, version and licence rots; the README is the provenance record |
| Phase 1: `test/no-network-fonts.test.ts` (Guard 1) | "Prefer root-cause fixes; do not just retry." (ask 2) | asked (a root-cause fix that nothing prevents regressing is a retry in waiting) |
| Phase 2: `playwright.config.ts` `url:` readiness | "Prefer root-cause fixes; do not just retry." (ask 2) | inferred - justification: shortens the measured 14 min cascade to the readiness timeout (about 2 min) so entries behind an ejection rebuild sooner; the brief's own evidence is that failures make "every entry behind it rebuild" |
| Phase 3: `e2e/otp-login.e2e.ts` | "#9167 and #9170 (flaky e2e)" (ask 5) | asked |
| Phase 4: `reap-archive-persistence.test.sh` diagnostics | "Fix or quarantine the causes found in step 1" (ask 2) | asked (diagnostics only; cause unproven) |
| Phase 5: `merge-queue-dequeue.md` advisory-red note | "Find out WHY each failure happened." (ask 1) | inferred - justification: the lint-bot-statuses finding (advisory job, manual dequeue costing 56 min) is only useful if the ship skill's dequeue reference records it |
| Phase 5: tracker comments (#9482, #8785, #9167, #9512) | "Comment on or fix those rather than filing duplicates." (ask 5) | asked |
| Phase 6: no-code decision and #9512 numbers | "decide whether a lower max_entries_to_build or running fewer jobs per merge_group run helps" (ask 3) | asked |
| `specs/feat-one-shot-merge-queue-slow-failures/tasks.md` | - | inferred - justification: the plan skill's Save Tasks contract; `soleur:work` executes against it |

### Split Assessment

- Subsystems touched: 3 - `apps/web-platform`, `plugins/soleur`, `knowledge-base`
- Planned files: 12 | Estimated changed lines: about 120 (excluding the 48 KB binary)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Implementation Phases

Order follows the brief: failure diagnosis (done, above) then fixes by yield. Phases 1 to 3 touch
independent files; one PR, `Ref #9482`, plus `Closes #8785` and `Closes #9170` (root-cause fixes that
pass their deterministic AC; the brief's "never Closes" applies to #9482 only).

### Phase 1: remove the build-time Google Fonts dependency (cause A, highest yield)

Files to edit: `apps/web-platform/app/fonts.ts`, `apps/web-platform/test/ready-state.test.tsx`,
`apps/web-platform/test/connect-repo-page.test.tsx`, `apps/web-platform/test/connect-repo-failed-state.test.tsx`
(each does `vi.mock("next/font/google", ...)`; repoint to `next/font/local`, a default-export mock:
`vi.mock("next/font/local", () => ({ default: () => ({ className: "mock-sans", variable: "--font-inter" }) }))`).
Files to create: `apps/web-platform/assets/fonts/inter-latin-wght.woff2` (the single variable latin
file; measured 2026-10-05: 48,256 bytes, sha256 `3100e775e8616cd2611beecfa23a4263d7037586789b43f035236a2e6fbd4c62`),
`apps/web-platform/assets/fonts/README.md` (about 8 lines: source URL, version `v20`, OFL-1.1 licence
pointer, sha256, regenerate command, and the explicit statement "frozen asset, no scheduled refresh:
Inter v20 to a later version changes nothing the app needs"), `apps/web-platform/test/no-network-fonts.test.ts` (Guard 1).

1. Download the woff2 from the URL in Research Insights; record the sha256 in the README only (not in the test: it cannot add integrity, see Guard 1 Anchor).
2. `fonts.ts`: `localFont({ src: "../assets/fonts/inter-latin-wght.woff2", weight: "400 600", style: "normal", variable: "--font-inter", display: "swap" })`, still exporting `sans`. `weight: "400 600"` deliberately mirrors today's `weight: ["400","500","600"]` (a `100 900` range would change how `font-bold` renders). No `adjustFontFallback` option is needed: verified in `node_modules/next/dist/compiled/@next/font/dist/local/loader.js` (Next 16.3.6) that an undefined value computes size-adjusted fallback metrics from the font file (only `false` disables it), so the layout-shift protection the Google loader gives is kept (#3564 territory). `layout.tsx` and `globals.css` are untouched (same variable name).
3. No new dependency (`@fontsource-variable/inter` would need `package-lock.json` and `bun.lock` to move together and trips `lockfile-sync`).
4. Verify (work phase): (a) `grep` shows no `next/font/google` left; (b) the dev server answers `GET /login` 200 inside a network namespace (`unshare -cn` then `-rn`, as `scripts/audit-suite-reads.sh` does), or, if the host forbids user namespaces, assert the compiled CSS served for `/login` contains no `fonts.gstatic.com` URL; (c) the production image path: `next.config.ts` has `output: undefined` (custom server, no standalone tree), so the check is that the hashed woff2 exists under `.next/static/media` after `next build`, and that `.dockerignore` does not exclude `assets/` (the builder stage does `COPY . .`).
5. Visual parity: run the full e2e once locally and in CI (`nav-states-shell` has pixel-sensitive assertions); same typeface and metrics should not move them.

### Phase 2: make a dev-server compile failure fail at readiness, not after 14 minutes (P2)

Files to edit: `apps/web-platform/playwright.config.ts` only.

Today both `webServer` entries use `port:` (TCP readiness), so a server whose first compile 5xx's is
"ready" and 64 tests then fail one by one. Switch each entry to `url: "http://localhost:<port>/login"`:
Playwright's own readiness poll treats a 5xx as not ready (verified in `playwright-core/lib/server/utils/network.js` `isURLAvailable`: ready only for status >= 200 and < 404) and fails at the `timeout` with its standard message. Because the poll request now triggers the first cold compile of `app/layout.tsx` inside that budget, raise both `timeout` values from 120_000 to 180_000 (a slow compile on a saturated runner must not become a new ejection cause); record the measured cold `/login` compile time in the PR body. No new file, helper or unit test. `/login` renders `app/layout.tsx`, so the
font error would surface here.

Work-phase verification: (a) `/login` on :3100 does not depend on the mock Supabase (architecture review read `middleware.ts`: `/login` is in `PUBLIC_PATHS` and returns before any Supabase call, and `app/layout.tsx` resolves an anonymous identity locally with no cookies; confirm with `curl -i http://localhost:3100/login` before the mock exists) (which is started
in `globalSetup`, after `webServer` in Playwright 1.58.2: `runner/tasks.js` runs plugin setup before
global setup); if it does, fall back to an inline probe at the top of `globalSetup` after the mock starts,
reading the two ports from constants exported by the config module (never from `config.webServer`:
Playwright sets `FullConfig.webServer` to `null` when it is an array); (b) a deliberately broken layout
import makes `npx playwright test` fail at readiness within about 3 min locally; (c) `url:` readiness goes through proxy resolution unlike the TCP check: the e2e job sets no proxy env today, so no `NO_PROXY` change is needed. `skipLocallyFailInCi` stays (it
protects the local skip-when-compile-broken behaviour of individual specs).

Not shipped: `maxFailures` (see Cut List; the one remaining whole-environment cascade, auth server
death, was 2 of 303 runs, both PR runs, and a cap would truncate failure reporting on PR runs).

### Phase 3: otp-login strict-mode (cause B, #9170)

Files to edit: `apps/web-platform/e2e/otp-login.e2e.ts`. Read result recorded here:
`nav-states-nav-pending.e2e.ts:17` defines `LIVE = page.getByRole("status")` but its use at `:150` is
already filtered, so that file is not edited.

1. Add `const noAccountBanner = (page) => page.getByRole("status").filter({ hasText: /no Soleur account found/i })` and use it at `:174`, `:177` and `:181` (`:174` and `:177` are the non-retrying strict-mode `toContainText` calls that raced; `:181` is filtered for fidelity to "the banner is gone", not because it flakes: `toHaveCount` auto-retries and the island clears within 400 ms, so do not count it as #9170 flake evidence).
2. Leave `:195`, `:207`, `:219` unfiltered: they run on `/signup` after `page.goto` with no navigation pending, so there is no race, and a text filter would make "no banner" vacuously true.
3. Comment pointing at #9170.

### Phase 4: reap-archive-persistence fixture G (cause C, diagnostics only)

Files to edit: `plugins/soleur/skills/git-worktree/test/reap-archive-persistence.test.sh`.

1. Make the fixture-G failure message inline, flattened onto one line (`$OUT_G` lives under `$TMP` and is deleted by the EXIT trap), `grep SOLEUR_ "$OUT_G"`, `tail -20 "$OUT_G"`, `git -C "$CLONE_G" status --short` and `git -C "$CLONE_G" log --oneline -5 feat-actor` (a STAGED outcome or hook failure shows in stderr lines without a `SOLEUR_` marker). Run `plugins/soleur/test/fixture-relative-assert.test.sh` afterwards: a new `git -C` use can move this file's baseline row (`--write-baseline` in the same commit), so the next occurrence names STAGED vs COMMITTED vs a hook failure. No retry, no repro loop (1 occurrence in 54 failed `test-scripts` jobs; excluded from the expected-ejection arithmetic below).
2. Comment on #7376 (same class: passes alone, fails under shard contention) in the consolidated tracker update; no new issue.

### Phase 5: advisory-red note and tracker updates (P4)

Files to edit: `plugins/soleur/skills/ship/references/merge-queue-dequeue.md` (2 to 3 lines).

1. Add: a red **advisory** job (for example `lint-bot-statuses`) reddens the `merge_group` run but does not eject; pushing to a queued PR removes it with `reason=manual` and costs a full re-queue (#9477: 15:11:45 enqueue, 15:13:46 manual removal, merged 16:07:56).
2. Work-phase tracker actions (read-write, never during planning), kept to what changes a decision: **#9482**, one consolidated comment carrying the Task 1 and Task 3 tables, the corrected ejection rate (4/27), the auto-merge-stays-armed finding for ADR canary 3 (re-added 2 to 3 min after `failed_checks` on #8820 and #9505; a `manual` removal is not re-added), the #9190 and #7376 notes (no `merge_group` run failed on `test-webplat`; fixture G occurrence) and the PR-churn finding below; **#8785** (cause A evidence, recurrence threshold exceeded, `Closes` in the PR body); **#9167** (the string is mock noise present in green runs; recommend closing as duplicate of #8785 only after reading the attempt-1 log of run `36449125669`, which this planning pass could not retrieve because the log returned was the passing re-run); **#9512** (Phase 6 numbers); **#9170** closes via the PR body. No new issues.

### Phase 6: contention decision and #9512 re-evaluation (P3), no code

1. **`max_entries_to_build`: keep 2.** `merge_group` is 22% of demand; the pool saturates because of rebuilds after ejections plus PR churn. Lowering to 1 trades speculation for serial 14 to 17 min merges; ADR-270 says raise only when contention is not binding, and it is binding, so no raise either. No Terraform diff, so the ADR-270 Raise checklist (which governs `max_entries_to_merge`) is not triggered.
2. **Fewer jobs per run: no.** Non-required jobs are about 6% of a run; all `test-scripts` shards feed the required `test` aggregate.
3. **Bigger lever, recorded not built:** PR-event workflows are about 61% of window demand (`ci.yml` PR runs 2,046 job-min; `secret-scan` 325 across 30 runs; `PR quality guards` 224 across 23 runs; `Infra Validation` 104), and 430 job-min (10%) were `ci.yml` jobs cancelled mid-flight. Path-aware early exit on docs-only pushes inside those workflows is the next candidate; it needs its own plan and goes to #9482 as a comment, not a new issue.
4. **Re-measure (a note, not an acceptance criterion):** after Phases 1 to 3 merge, repeat the Task 3 recipe on the next 20 `merge_group` runs. Expected: ejection rate from 15% to about 4%; runs per merged PR from 1.5 toward 1.1. Revisit `max_entries_to_build` only if median `merge_group` job queue wait stays above 60 s with no rebuilds in the sample. The canary log is PR #9511's file; if #9511 has merged by then, append one dated row there instead of a comment-only record.
5. **#9512 (skip the duplicate push-to-main CI run):** the trigger "runner-minute cost becomes binding" is technically met for the pool, but the duplicate is 138 of 4,435 window job-minutes (3.1%; about 19 runs x 134 = 2,550 job-min per day) and carries the deploy-chain risk its body records (`web-platform-release.yml` `workflow_run` arm needs a push-event `CI` run with conclusion `success`; trust-model change; all-jobs-skipped conclusion unmeasured). Decision: stays deferred, p3, numbers added as a comment; it needs its own plan.

## Guard Contract

### Guard 1 - no build-time network font fetch

**Property.** No tracked source file under `apps/web-platform` imports `next/font/google` or references `fonts.googleapis.com` / `fonts.gstatic.com`, and the vendored Inter file exists and is non-empty, so no compile, dev or build step needs the network for fonts.

**Assembly.** Quantifies over every file under `apps/web-platform` with extension `.ts`, `.tsx`, `.js`, `.jsx`, `.mjs`, `.mts`, `.cjs`, `.css` or `.scss`, plus `next.config.*`, enumerated at run time by an injectable enumerator: production uses `git ls-files --cached --others --exclude-standard` (so an untracked new file is swept; tolerate tracked-but-deleted ENOENT), fixtures use a plain directory walk of a synthesized temp tree (a temp dir is not a repo, so the harness rows must not depend on git). Ignored by path SEGMENT (`node_modules`, `.next`), never by substring, and the guard test file itself is excluded (it necessarily contains the forbidden strings). The sweep root is a parameter of the helper. Chokepoint: one vitest suite, `test/no-network-fonts.test.ts`; `app/fonts.ts` is the only declaration site today, and the census exists for a second site. A floor asserts the sweep examined at least 1,500 files (2,304 measured on 2026-10-05 across those extensions under `apps/web-platform`; a pathspec that silently drops most of the tree must fail) and prints `scanned N files`. Resolve paths from the app directory (cwd or `__dirname/..`), never `rev-parse --show-toplevel`, so `test/repo-wide-containment.test.ts` does not reclassify the suite as repo-wide.

**Mutation matrix.**

| # | Edit (must drive RED) | Why it is a distinct row |
| --- | --- | --- |
| 1 | Re-add `import { Inter } from "next/font/google"` in `app/fonts.ts` | The original defect |
| 2 | Keep `fonts.ts` compliant, add `import { Roboto } from "next/font/google"` in a new `components/x.tsx` | Second member after a compliant first |
| 3 | Add `@import url(https://fonts.googleapis.com/...)` to `app/globals.css` | Different file type and syntax |
| 4 | Delete or empty `assets/fonts/inter-latin-wght.woff2` | Vendored file missing |
| 5 | Point the sweep at an empty temp directory | Own dispatch: assert the message text contains "0 files scanned" (not just that it throws), so a git-state error cannot satisfy it |
| 6 | Put the forbidden import in a `.mts` file | The extension set must include `.mts` and `.cjs` |

**Harness rows.** RED: against the synthesized temp tree, weaken the detection regex in the suite (for example drop the `google` alternative) and re-run row 1: the suite must go RED (the row-1 assertion is on the temp tree, so a vacuous regex fails it). Must-PASS non-canonical: a temp tree whose only font import is `import localFont from "next/font/local"` in two files, plus a markdown file mentioning `fonts.gstatic.com` (non-code extensions are out of the sweep), must pass. Rows 2 and 6 run on the fs-walk temp tree (an untracked file is exactly what the production enumerator also covers via `--others`).

**Anchor.** The vendored file's hash lives only in the README, so the guard proves "no network font and not missing", not tamper-resistance or truncation (a truncated file fails `next build` and e2e). Recorded so no reader takes it for integrity.

## Files to Edit

- `apps/web-platform/app/fonts.ts`
- `apps/web-platform/test/ready-state.test.tsx`
- `apps/web-platform/test/connect-repo-page.test.tsx`
- `apps/web-platform/test/connect-repo-failed-state.test.tsx`
- `apps/web-platform/playwright.config.ts`
- `apps/web-platform/e2e/otp-login.e2e.ts`
- `plugins/soleur/skills/git-worktree/test/reap-archive-persistence.test.sh`
- `plugins/soleur/skills/ship/references/merge-queue-dequeue.md`

## Files to Create

- `apps/web-platform/assets/fonts/inter-latin-wght.woff2`
- `apps/web-platform/assets/fonts/README.md`
- `apps/web-platform/test/no-network-fonts.test.ts`
- `knowledge-base/project/specs/feat-one-shot-merge-queue-slow-failures/tasks.md` (the spec directory does not exist yet; created with the file)

Not touched: `infra/github/**`, ADR-270, `merge-queue-canary-log.md` (PR #9511), `.github/workflows/ci.yml`, `apps/web-platform/e2e/global-setup.ts` (unless Phase 2 verification (a) fails), `e2e/nav-states-nav-pending.e2e.ts`.
Path verification: every edited path was confirmed present on this branch; `apps/web-platform/assets/` does not exist yet and is created.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `git grep -n "next/font/google" -- apps/web-platform ':!apps/web-platform/test/no-network-fonts.test.ts' ':!apps/web-platform/assets/fonts/README.md'` returns no hits (the three test mocks now name `next/font/local`); the standing check is the vitest guard, which also sees untracked files.
- [ ] The dev server serves `/login` 200 with no network route (`unshare -cn`/`-rn`), or, on a host without user namespaces, the served CSS contains no `fonts.gstatic.com` URL; after `next build` the hashed woff2 exists under `.next/static/media`; `.dockerignore` does not exclude `assets/`.
- [ ] `no-network-fonts.test.ts`: the unmutated tree is green and prints `scanned N files` with N >= 1,500; mutation rows 1 to 6 each turn it red.
- [ ] `playwright.config.ts` webServer entries use `url:` readiness; with a deliberately broken `app/layout.tsx` import, `npx playwright test` fails at server readiness within about 3 min (not after the suite), recorded in the PR body.
- [ ] CI `e2e`: 0 failed, and the log contains none of `queries have exactly one entry`, `Dev server compile error`, `strict mode violation`.
- [ ] `otp-login.e2e.ts`: no unfiltered `getByRole("status")` at the three assertion sites. Deterministic negative control (not a wall-clock delay: the island holds only `NAV_MIN_VISIBLE_MS` 400 ms after a 150 ms entry delay, so a long route delay lets it unmount before the banner shows and both versions pass): after `waitForURL`, `page.evaluate` appends `<div role="status">Loading</div>`; the pre-change unfiltered assertion then fails with a strict-mode error and the filtered one passes.
- [ ] Fixture G's failure message inlines (flattened with `tr '\n' '|'`, because `$OUT_G` is deleted by the EXIT trap) the SOLEUR markers, `tail -20` of the output, `git status --short` and `git log --oneline -5`; shown once by forcing the assertion to fail locally. This is a one-off diagnostic check, not regression coverage for cause C. `plugins/soleur/test/fixture-relative-assert.test.sh` is run and its baseline regenerated (`--write-baseline`) if the new `git -C` use moves a row.
- [ ] `merge-queue-dequeue.md` carries the advisory-red note.
- [ ] PR body says `Ref #9482` (never `Closes #9482`), `Closes #8785`, `Closes #9170`; ADR-270 `status:` still `adopting`; `git diff origin/main -- infra/github knowledge-base/engineering/architecture` is empty.
- [ ] `python3 scripts/lint-guard-contract.py` passes on this plan; markdown lint passes on the README.

### Post-merge (agent-run, no operator)

- [ ] Tracker comments posted as listed in Phase 5 (#9482, #8785, #9167, #9512); no new issue filed.

## Test Scenarios

- Font file removed from the tree: `no-network-fonts.test.ts` red (row 4); vitest and e2e fail with a missing-file error, not a Turbopack message.
- `fonts.gstatic.com` unreachable (network namespace): dev server still 200 on `/login` and on `/dashboard/chat/<id>` with the mock Supabase.
- Synthetic `role="status"` "Loading" element injected after the signup redirect: the filtered banner assertions pass, the unfiltered ones fail with a strict-mode error (deterministic negative control).
- Broken layout import: Playwright fails at `webServer` readiness (about 3 min), not after the suite.
- Healthy tree: the e2e report shows 0 failed and none of the three log signatures above.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected: CI and test-harness change on an engineering-owned surface (no user-facing page changes, no copy). The one runtime-visible change is the same Inter typeface served from the app origin instead of fetched at build time; no UI surface file (new component, page or layout) is created, so the Product/UX gate does not fire.

## User-Brand Impact

**If this lands broken, the user experiences:** a mis-rendered or fallback system font on every page (the vendored woff2 fails to load) or, worst case, a failed production build blocking a deploy. Mitigation: the e2e job and the production `next build` both load the file, so a broken file fails before merge.

**If this leaks, the user's data is exposed via:** no exposure vector: no credentials, user data or network egress is added; the change removes an outbound build-time fetch.

**Brand-survival threshold:** none. Diff touches no sensitive path (no auth, migration, API route or Doppler config); `apps/web-platform/app/` and `e2e/` are not in the preflight Check 6 sensitive-path regex. threshold: none, reason: CI and font-asset change with no data, auth or billing surface.

## Observability

```yaml
liveness_signal:
  what: e2e job duration and result on every merge_group run (healthy about 3 min, cascade 14 min)
  cadence: every merge_group and pull_request ci.yml run
  alert_target: the existing required check `e2e` (ejects the queue entry on red); merge-queue stall check for entries stuck behind a slow run
  configured_in: .github/workflows/ci.yml (e2e job), .github/workflows/merge-queue-stall-check.yml
error_reporting:
  destination: GitHub Actions job log plus the Playwright report artifact on failure; Playwright's readiness timeout message names the URL that never became ready
  fail_loud: true (Playwright fails at webServer readiness with its standard message; job red)
failure_modes:
  - mode: dev server compile error on either e2e server
    detection: `url:` readiness on both webServer entries fails the job at the webServer timeout (180 s after the Phase 2 raise)
    alert_route: required `e2e` check red, entry ejected, PR author sees the message
  - mode: vendored font missing or corrupt
    detection: no-network-fonts.test.ts and next build
    alert_route: required `test` aggregate red
  - mode: queue runner contention returns
    detection: Task 3 recipe re-run after 20 runs; stall check at 45 min
    alert_route: comment on #9482; merge-queue stall check
logs:
  where: GitHub Actions run logs and test-results artifact
  retention: GitHub default (90 days)
discoverability_test:
  command: curl -s "https://api.github.com/repos/jikig-ai/soleur/actions/workflows/ci.yml/runs?event=merge_group&per_page=20" | jq -r '[.workflow_runs[].conclusion]|unique|join(" ")'
  expected_output: success
```

## Infrastructure, Architecture, Encryption, GDPR gates

- **IaC routing (2.8):** no new infrastructure; no ruleset or Terraform change. Skipped.
- **ADR/C4 (2.10):** no architectural decision made or changed (keeping `max_entries_to_build = 2` is a parameter retained, not a decision reversal). C4 check: external actor GitHub merge queue, system Google Fonts (never modelled: the build-time fetch was an implicit dependency; removing it deletes an undocumented edge, nothing to edit), container web-platform unchanged, no access-relationship change. `c4-count-parity` is unaffected (no cron, monitor or workflow count moves). No ADR edit; ADR-270 remains `adopting`.
- **Encryption posture (2.11):** no persistent store or new connection. Skipped.
- **GDPR (2.7):** no regulated-data surface; removing a third-party font fetch is privacy-neutral to positive (no visitor-IP leak to Google; the build-time fetch never involved visitors). Skipped.
- **Skill description budget (1.8):** no SKILL.md `description:` edit.

## Non-Goals and deferrals

- Acting on the three operator decisions on #9482 (deploy hold, brand-survival threshold, `actions` alerts): defaults stand.
- Accepted gaps, not bugs: a 403 secondary rate limit is not retried; a late run on a congested runner pool is not detected by the dispatcher.
- PR #9511 content (Sentry route, canary log rows 1, 4, 9, 10): not redone.
- #9512: deferred with measured numbers (Phase 6); already tracked.
- #9190 (c4-code-panel) and nav-states timing flake (#9170 data point `37110016731`): not reproduced in any queue run; tracked, comment only.
- `fixture-relative-assert.test.sh` baseline-ratchet reds (19 PR-run failures on `test-scripts (2/8)`, 18 of them "baseline rows differ from live"): a deterministic per-PR gate, not a queue flake and not seen on `merge_group`; noted here only because a PR that raises the site count without regenerating the baseline would eject in the queue. No issue filed (net-issue-flow).
- Raising `max_entries_to_build` to 3 or lowering it to 1: no, see Phase 6.

## Risks and Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6; this one declares threshold `none` with a reason.
- Vendoring replaces `unicode-range` subsetting with one latin file: non-latin glyphs fall back to the system stack (same as today, since `subsets: ["latin"]`).
- Phase 2: `url:` readiness polls `/login` on :3100 before the mock Supabase starts (it starts in `globalSetup`, which runs after `webServer`, verified in `node_modules/playwright/lib/runner/tasks.js`). If `/login` needs the mock, use the inline `globalSetup` fallback documented in Phase 2.
- Playwright sets `FullConfig.webServer` to `null` when `webServer` is an array (`lib/common/config.js`); never read ports from it.
- The cause-A explanation ("transient fonts.gstatic.com fetch") is an inference: the logs show the Turbopack resolve error, not the failing HTTP request. Vendoring is correct under either explanation (the dependency disappears), which is why it is the fix rather than a retry.
- Planning-phase caveat on the contention table: queue wait uses job `created_at`; for `needs`-chained jobs it is the time the job was created, which matched 3 to 5 s medians in quiet periods, so it is a fair queue-wait proxy.
- Before ship, check `knowledge-base/engineering/architecture/principles-register.md` for an entry on third-party egress or vendored assets (not read during planning).
- ADR-270's Parameters row phrases the `max_entries_to_build` gate as "raise to 3 only after the canary shows contention is not binding" and the Raise checklist governs `max_entries_to_merge`; this plan cites each for what it says.
- Frozen figures above are from 2026-10-05 11:20 UTC; the work phase re-pulls any figure it quotes in a PR body.

## Measurement recipe (reproducible, read-only)

```bash
# 1. merge_group run census since adoption (2026-10-04T14:47:24Z), per run jobs
gh api "repos/jikig-ai/soleur/actions/workflows/ci.yml/runs?created=>=2026-10-04T14:47:24Z&per_page=100" --paginate \
  --jq '.workflow_runs[]|select(.event=="merge_group")|[.id,.conclusion,.created_at,.head_branch]|@tsv'
gh api "repos/jikig-ai/soleur/actions/runs/<id>/jobs?per_page=100" --paginate \
  --jq '.jobs[]|[.name,.conclusion,.created_at,.started_at,.completed_at]|@tsv'   # queue wait = started_at - created_at
# 2. pool demand: same jobs call for EVERY workflow run created in the window
gh api "repos/jikig-ai/soleur/actions/runs?created=<start>..<end>&per_page=100" --paginate
# 3. queue timeline per PR
gh api graphql -f query='query($n:Int!){repository(owner:"jikig-ai",name:"soleur"){pullRequest(number:$n){timelineItems(first:30,itemTypes:[ADDED_TO_MERGE_QUEUE_EVENT,REMOVED_FROM_MERGE_QUEUE_EVENT]){nodes{__typename ... on RemovedFromMergeQueueEvent{createdAt reason} ... on AddedToMergeQueueEvent{createdAt}}}}}}' -F n=<pr>
# 4. failing-test names: gh api --allow-escape-sequences repos/jikig-ai/soleur/actions/jobs/<job_id>/logs | sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g' | grep -E '^\s+[0-9]+\) \[|queries have exactly one entry|strict mode violation'
```
