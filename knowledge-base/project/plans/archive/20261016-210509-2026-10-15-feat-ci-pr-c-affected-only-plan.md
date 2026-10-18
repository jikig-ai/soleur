---
title: "ci: S4 PR C, affected-only pull_request runs (evidence, go/no-go, readers, lock removal)"
date: 2026-10-15
slug: ci-pr-c-affected-only
branch: feat-one-shot-9729-ci-pr-c-affected-only
issue: 9729
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
amends: [ADR-276]
---

# ci: S4 PR C, affected-only pull_request runs (evidence, go/no-go, readers, lock removal)

## Enhancement Summary

**Deepened on:** 2026-10-15. Sections checked: User-Brand Impact, Observability, Guard Contract, Scope Check, ADR/C4, Implementation Phases, Acceptance Criteria. Agents and gates used: the seven plan-review seats and four CTO rulings recorded below (the review panel is the deepen fan-out for this plan), the Phase 4.6 to 4.12 halts run mechanically, a live verification pass over every cited path, symbol, issue, PR and API shape.

### Key improvements

1. The expensive evidence is preceded by a cheap kill (Phase 1.0), and the go/no-go is a computed verdict with a machine line the gate script reads.
2. The `full-verified` predicate now has an explicit shape table (a skipped `pr-selection` is the normal state), binds to the run that owns the graded `test` check run, uses `CHECK_SHA`, and prints `state=error` outside its closed set.
3. The audit probe separates bypass merges from monitor reverts and carryover chains, records the push-run outcome and assigns the operator.
4. Every guard row names an edit that must fail exactly one row; natural-repair rows (empty stubs, an empty prerequisite-5 heading) are included.

### New considerations discovered

- The unfiltered `actions/runs?head_sha=` endpoint is polluted by unrelated `workflow_dispatch` runs; the workflow-scoped endpoint is the only safe source (verified on `a54c4e315b`, which lists a `push` and a `merge_group` run).
- The org-admin credential is unnecessary: the repo-scoped organization-variables read (200, `total_count` 0) covers every variable that resolves through `vars`.
- No doc-only pull request has been observed after the Q1 merge, so AC9c stays an observation.
- Stage 2 is probably unreachable on the plan's own prior (14% against a 20% bar); the stage 1 evidence tooling is the real deliverable.

## Overview

Third build PR of stage 4 of the hosted-runner demand plan (#9729, ADR-276). PR B (`2f651e1643`) shipped the dark, locked selection lever; the Q1 follow-up (`269afa3ce4`) made the dark job cost nothing while `CI_PR_AFFECTED` is unset. PR C does three things in order, with a hard decision seam between the first two:

1. **Evidence (stage 1).** A cheap-kill estimate of the mean saving first (a 30-commit local sample), then the escape-rate replay and index-completeness audit, the cold/warm/restored selector timing, the re-measured dark-cost figures, the organization-variable and first-doc-only-PR reads. All of it lands as committed receipts and as read-only scripts. No `ci.yml` edit.
2. **Go/no-go record.** A mechanical verdict computed from the receipts (CTO ruling R3 below). NO-GO ships stage 1 only, keeps the lock and records the NO-GO in ADR-276.
3. **Readers, probe and lock removal (stage 2, GO only).** The jobs-API "full-verified" read wired into the merge authorities, the detective probe with its paging route, the census by-mode split, and the lock removal as the LAST commit behind an executed coupling pin.

Nothing activates in this PR. Flipping the repository variable is a separately authorized step (ADR-276 S4); removing the lock only makes the lever flippable. Every PR text uses `Ref #9729` (never a closing keyword); the issue stays open until the activation lane finishes.

This PR edits `.github/workflows/ci.yml` and `.github/workflows/post-merge-monitor.yml` in stage 2, so it is UNTRUSTED-CI: no agent `--admin` fallback exists. A BEHIND livelock is a request to the user to merge; on a BEHIND PR with auto-merge armed, wait for GitHub to enqueue it and never sync, update-branch or merge by hand.

## Research Reconciliation — Spec vs. Codebase

| Brief / spec claim | Reality (verified 2026-10-15 on `origin/main` e071b828f4) | Plan response |
|---|---|---|
| Vehicle for `sel_s`: "a pull_request run on a doc-only diff on a fresh hosted runner, with the switch set for that run only" | `ci.yml` has `pull_request` with no `branches:` filter, so any PR (stacked or not) starts the full 164-minute battery; `push` is `branches: [main]` in `ci.yml` and in every other workflow with a push trigger (CTO R10, parsed). The selector wall time does not depend on the event type | Phase 1.3: a throwaway branch `canary-sel-9729`, cut from the feature head so the committed scripts exist and carrying ONE extra measurement workflow with `on: push: branches: ['canary-sel-*']`; fresh `ubuntu-latest`, checkout mirrored from `pr-selection`; never merged, not in this PR's diff. The brief's intent (fresh hosted runner, doc-only path, budget raised, switch forced for that run only) is met; the `pull_request` event is not needed to reach `test-all.sh --print-selection --paths=README.md` (CTO R4, consistent with D3: no permanent dispatch-only workflow) |
| Org-level variable check "needs an org-admin credential" | `gh api repos/jikig-ai/soleur/actions/organization-variables` returns HTTP 200 with `total_count` 0 (read at plan time). The org variables SHARED WITH this repository are the only ones that resolve through `vars`; the org-wide list (403) is irrelevant to this repo | Phase 1.1: an automated fail-closed read inside the pre-activation gate script, run now and again at activation. Not an operator item (CTO R7) |
| ADR/issue: "ship's automated `gh run rerun --failed`" | Ship has no automation; `plugins/soleur/skills/ship/SKILL.md` (bullet "The one exception: a failure fetching a third-party artifact") tells the agent to rerun once with `gh run rerun <run-id> --failed`. `gh run rerun` text also appears in `web-platform-release.yml` NEXT messages and `monitor-pr-checks.sh` comments | Phase 3.3: a prose carve-out in ship (when the run's `pr-selection` job shows `active`, rerun ALL jobs or push) plus a pin that the aggregator's remedy line and the carve-out agree (CTO R6) |
| "PR C removes the lock in its LAST commit" | CTO R1 prefers moving the lock removal to PR D, because with no skippable set removal changes nothing observable and only makes the lever flippable | Default stays the brief: lock removed last, on GO only, behind the coupling pin and the gate script. The CTO preference is recorded as an operator (scope) decision challenge; R11 confirms the default is technically safe (cost-only, about 1.3 billed min per PR run, one-line revert) |
| Audit probe is "a step of the existing `post-merge-monitor.yml`" | The workflow's single job `monitor` has `if:` admitting only `workflow_dispatch` or `[bot-fix]` head commits | Phase 3.4: a second job with its own `if:` and job-level permissions; keep `workflow_dispatch` with `commit_sha` as the dry run (CTO R9) |
| Paging "to Better Stack" (ADR-276 named-responder bullet) | No `SOLEUR_*` marker in any workflow is wired to Better Stack; the human-alert pattern for main health is a deduped `ci/main-broken` issue (`main-health-monitor.yml`) | Phase 3.4: deduped `ci/full-battery-escape` issue (GitHub notification email) in PR C; the Better Stack heartbeat becomes a deferral issue; the ADR bullet is amended (CTO R9) |
| Guard 3 goes in `admin-merge-ready.sh` and `ci-head-verdict.sh` | Both read check-runs, not the jobs API; `ci-head-verdict.sh verdict` has a CLOSED state set that consumers whitelist | Phase 3.2: a new subcommand `ci-head-verdict.sh full-verified` (the one resolver) called by `admin-merge-ready.sh` and the audit; the closed `verdict` states are not widened |
| `scripts/ci-battery-gate-replay.sh` is extended with the selector | It is 31 lines and replays ADR-262 relevance arrays by substring over name-status blobs, not the selector | Phase 1.2: new `scripts/ci-pr-affected-replay.sh`; it may copy the first-parent loop, it does not edit that script |
| "census has a by-mode split / escape count" | `scripts/ci-demand-census.sh` (726 lines) has neither (`git grep -c 'affected\|escape'` returns 0) | Phase 3.5 |
| `pr-affected-active`, `ci-full-battery-audit.sh`, the replay receipt | None exists (`git grep` over code returns nothing) | Built in this PR |
| AC9c: "the first doc-only pull request after the Q1 follow-up should show pr-selection skipped" | Merge `269afa3ce4` landed 2026-10-15T17:50:38Z. Every doc-only PR since 08:00Z that day (10346, 10372, 10387) merged BEFORE it. Runs after the merge (e.g. 38789312798 on this draft PR) show `pr-selection` skipped, but a draft run is light by design (`test` red, Option R), so none qualifies | Phase 1.1: the gate script reads the first NON-DRAFT doc-only PR created after the merge (`ac9c=observed\|not-yet`); AC13 records the observation, never gates the merge |
| `gh pr merge --admin` skips the merge queue is "not asserted" | `admin-merge-ready.sh` header already states `--admin` skips the queue like the required-checks rule and that "the adoption canary verifies it" (ADR-270); no API-checkable receipt is cited | Phase 3.6: derive it from history (a main merge commit with no `merge_group` run) and cite the receipt, or omit the sentence |
| Dark-cost figures (1.29 billed min per executed job, 10 of 34, about 300 runs/day) | Re-derived at plan time with the ADR's own method: the 44 `ci.yml` pull_request runs created 2026-10-14T23:24Z to 2026-10-15T09:20:12Z, 42 executed `pr-selection`, 54 billed minutes, 1.29 per executed job | Phase 1.4 repeats the command with a stated window and units before PR C cites any figure |
| 207 web-platform test files mention `knowledge-base` (CTO Q2) | `git grep -l "knowledge-base" -- 'apps/web-platform/**/*.test.*' 'apps/web-platform/test'` returns 238 files today; the figures differ by grep shape | Phase 1.6 states its own command and counts that |

## Research Insights

**Premise Validation.** #9729 OPEN; #10325, #10373, #10333 OPEN; PR B (#10285) and Q1 (#10341) MERGED; draft PR 10412 is this branch; no other open PR names #9729. `CI_PR_AFFECTED` is absent (HTTP 404 on the variable read, variable list 200 with four other names). Cited paths exist on `origin/main`: `scripts/ci-pr-selection.sh` (444 lines, `readonly PR_AFFECTED_LOCKED=1` at line 90), `scripts/ci-pr-selection.test.sh` (1592 lines), `plugins/soleur/scripts/{admin-merge-ready,ci-head-verdict}.sh`, `plugins/soleur/skills/ship/scripts/battery-owed.sh`, `scripts/ci-demand-census.sh`. ADR-276 `status: adopting`, ADR-270 `accepted`, ADR-262 and ADR-183 `active`. The mechanism sits inside ADR-276 Decisions 3 and 5; the `run-name` marker and the base-ref copy are rejected there by amendment (operator 2026-10-12).

**Property List.**

1. The activation evidence exists as committed receipts and the go/no-go is computed from them, not argued.
2. A reduced PR run is never read as full by a merge authority; an unreadable run is never read as full.
3. A merge that reached `main` without a full-battery run is detected and reaches a human.
4. Flipping the variable cannot happen by accident: a read-only gate refuses while any prerequisite is unmet.
5. While the variable is unset (and in a NO-GO), no battery leg changes.
6. Every figure the ADR cites carries its command, window and units, and every sentence the PR falsifies is superseded.

**Cut List.**

- Permanent `sel_s` measurement workflow or job -> property 1 is served by a throwaway branch (D3 ruling stands; the vehicle is not in the diff).
- Better Stack heartbeat Terraform resource and secrets -> property 3 is served by the issue route; deferral issue #10415 (CTO R9).
- Derive-cache restore job, per-suite selection in `test-scripts`, the `needs: pr-selection` edge, bounded `fetch-depth` -> PR D, deferral issue #10414 (CTO R1/R5); PR C measures the restored-cache pass as go/no-go evidence only.
- A `mode` job output and a shared predicate library -> the `pr-affected-active` step plus the existing one resolver (`ci-head-verdict.sh`) serve property 2; the census derives mode from the step.
- Edits to `battery-owed.sh`, `monitor-pr-checks.sh`, `triage-prs.sh` -> classified by the Phase 3.3 sweep; edited only if a reader is a merge authority.
- Soak probe, 20% exit-metric read, Sentry check-in for the audit -> activation lane and PR D (#10414; #9729 itself stays open for the activation).
- Org-admin credential read -> unnecessary (R7).
- A `[full]` run-name marker, a trusted base-ref copy -> already superseded.

**Institutional learnings applied.** `2026-10-15-a-guard-vocabulary-widened-and-its-census-did-not-and-prose-was-scoped-narrower-than-its-claims.md` (widen the census of readers with the guard; supersede by subject; re-derive figures with units; count a mutant only if removing its guard fails exactly its row; a sandbox needs `git init` before a suite that reads git state); `2026-10-14-a-dark-lever-measures-itself-through-its-own-budget-and-my-fix-round-tripped-ratchets-no-file-query-selects.md` (a budget-capped timing is a lower bound; run repo-global ratchets after any test edit); `2026-09-22-the-admin-merge-gate-read-ready-from-an-empty-body.md` (decide readiness positively with a count, `jq -e` every body, never print PR-controlled strings); `2026-09-27-a-carried-over-job-is-relabelled-and-an-undocumented-lock-rule-is-settled-by-a-probe.md` (on a re-run, key job reads on time fields, not `run_attempt`); `2026-10-09-a-cost-lever-must-not-be-able-to-redden-the-run-it-saves.md` (job-level `continue-on-error`; read markers through `scripts/lib/trusted-verdict.sh`, not `author_association`); `2026-10-12-docs-only-ci-skip-premise-is-false-when-tests-read-the-kb.md` (the selector is the single source of truth for what a KB diff reaches; the replay must run in CI or bounded); `2026-08-13-a-benchmark-carries-the-machine-that-produced-it.md` (measure CI timings through the jobs API step times, not locally); `2026-07-17-every-hole-was-a-claim-quantified-over-a-set-sampled-once.md` (run the replay over all 300, not a sample); `best-practices/2026-06-30-github-merge-queue-adoption-wire-all-ruleset-producers.md` (no `pull_request` gate on a required-context producer); `workflow-issues/merge-queue-ejections-two-causes-and-fix-pr-guard-survivors-20261005.md` (decompose ejections per run and step; `TEST_GROUP=affected` is not a merge gate). Gap: no learning covers a "full-verified" read, an escape-rate replay or a restore-only `actions/cache`.

**CTO rulings (spawned for this plan, 2026-10-15; persisted in `knowledge-base/project/specs/feat-one-shot-9729-ci-pr-c-affected-only/decision-challenges.md`).**

- R1: PR C is evidence plus go/no-go plus (on GO) readers, probe and census; per-suite selection is a separate PR D; NO-GO keeps the lock, ships evidence and the NO-GO amendment only, does not revert PR B (dark, costs 0 unset), and files a retire-the-stage issue.
- R2: the gating escape reading is ATTRIBUTABLE: first-parent commits whose full-battery run (`merge_group` or push) has a deterministic failure, not cleared by a retry of the identical tree, in a suite the proposed rule would have skipped for that diff; denominator all 300; not-evaluable commits in a worst-case column; GATE = point estimate with unverified counted as escapes at most 2% AND the one-sided 95% Clopper-Pearson upper bound below 12%; literal, queue-and-push-only and retry-cleared counts are reported, not gating. The replay applies the PROPOSED per-suite rule (today's rule skips nothing, so 0 would be vacuous). The index-completeness audit: every path a registered suite or its sourced libs reference is declared for it or covered by the widened trigger list; zero unexplained gaps; PR 9404 is the mandatory fixture.
- R2 refinement (planner, mechanical): at n=300 a point estimate of 2% (6 escapes) has a one-sided 95% upper bound of about 3.9%, so the 12% clause could never bind; the bound is therefore computed on the WORST-CASE numerator (not-evaluable and unverified commits counted), where it can.
- R3: GO needs all of (a) the R2 gate, (b) zero audit gaps, (c) mean net saving at least 20% of the ONE baseline (99.8, so at least 19.96 job-min per run; net of billed selector minutes, times 8 if selection runs per shard) and no serial edge past the 75-minute declared path (73 today): restored-cache selection wall plus overhead at most 120 s, or selection inside each shard with no `needs:` edge, (d) every knowledge-base-mentioning test file classified, none a real reader inside a skippable suite. A second CTO spawn confirms the verdict, and rules results within 10% of a threshold. Evidence incomplete: ship evidence-only with a follow-through issue due merge plus 7 days. The plan states the honest prior: 23 suite-min of 164.4 is 14%, below the 20% bar, so NO-GO on (c) is a live outcome.
- R4, R5: confirmed with the throwaway push branch; the restored pass uses a cache saved by the canary's first job and restored in a second job on a fresh runner; the production cache design (restore-only `actions/cache/restore`, rolling key `affected-derive-v1-<derive-hash>-<sha>` with prefix `restore-keys`, saved only by a push-to-main job) is PR D's.
- R6: the ship rerun is prose; in-scope sweep is by grep over `plugins/`, `scripts/`, `.github/workflows/` for every `--failed` rerun and every reader of the aggregator `test` check.
- R7, R8: the organization-variable read closes the checklist item without an admin credential; the gate script must refuse unless the prerequisite-5 amendment exists; Guard 3 readers fail closed on an unrecognized job shape; no group is skippable until the amendment answers `test-webplat`'s `tsc --noEmit` and tool installs (the enumerate stream does not cover them); a PR D change to the longest chain must rerun the 75-minute pin.
- R9: the escape route is a deduped `ci/full-battery-escape` issue filed by a second job in `post-merge-monitor.yml` (workflow_run on CI completed on `main`, sweeping the last 24 hours of first-parent commits per run so a missed run is caught by the next); the Better Stack heartbeat is deferred.
- R11: the brief's default (lock removed last in PR C) is safe with two guards: the reader decides on per-job conclusions and the `pr-affected-active` step, never on `active` alone, and the executed coupling pin names the empty-skippable-set driver test with a mutation case. Between PR C and PR D a flip is a cost-only no-op and the gate script refuses it.

**Value measurement (Phase 0.6c).** Command: `gh api --paginate "repos/jikig-ai/soleur/actions/workflows/ci.yml/runs?event=pull_request&created=2026-10-14T23:24:00Z..2026-10-15T09:20:12Z&per_page=100"`, then for each run `gh api "repos/jikig-ai/soleur/actions/runs/<id>/jobs?per_page=100"`, the `pr-selection` job billed as `max(1, ceil(seconds/60))` and skipped as 0. Result at plan time: 44 runs, 42 executed, 54 billed minutes, 1.29 per executed job; it reproduces the ADR figure exactly. The saving a lock removal enables is unmeasured: it is the replay mean (Phase 1.2) and is a hypothesis until then; the only prior is 23 suite-min of 164.4 job-min (14%) from ADR-276 Context.

## User-Brand Impact

**If this lands broken, the user experiences:** a regression that a reduced pull request run waved through reaches `main` and then production (a broken page, an auth or billing path) because a merge authority read a reduced run as a full one; or every pull request wedges because the required `test` context never reports or reports red on a legitimate run (a `--failed` rerun that keeps a cached skip). Because the lever is dark, locked and unset, a broken stage 1 changes nothing a user can see; stage 2 is where the single-user incident can occur.
**If this leaks, the user's [workflow] is exposed via:** `admin-merge-ready.sh`, `ci-head-verdict.sh`, `battery-owed.sh`, `monitor-pr-checks.sh`, `triage-prs.sh`, ship Phase 7 and the push-to-main deploy arm reading a reduced green as full. The deploy arm cannot be reached by a pull_request run (`web-platform-release.yml` re-checks `WR_EVENT == push`), `merge_group` runs the full battery on the candidate tree, and the residual is a bypass (`--admin`) merge, which the detective probe counts and pages.
**Brand-survival threshold:** single-user incident.
**Threshold decision (challengeable):** single-user incident, because the stage's whole purpose is to let a merge authority act on a CI run that did not run every suite; one bypass merge of a reduced green is a user-visible regression, which `aggregate pattern` would understate.

`requires_cpo_signoff: true`. CPO sign-off for PR B was APPROVED-WITH-CONDITIONS (2026-10-14); those conditions are inherited (B and C stay dark and activation locked until C, kill criterion in the ADR, named escape responder, user-impact-reviewer at review). CPO re-reviews this plan at plan review; `soleur:engineering:review:user-impact-reviewer` runs at review time.

| Failure mode (artifact -> vector) | Mitigation / disposition |
|---|---|
| Reduced run read as full by `admin-merge-ready.sh` (run -> READY) | Guard 1: the `full-verified` subcommand; admin-merge-ready calls it before printing READY; unreadable shape means not verified |
| Bypass merge of a reduced green reaches `main` unnoticed | Guard 3: audit job, deduped `ci/full-battery-escape` issue, 24-hour sweep, `workflow_dispatch` dry run |
| Lock removed while a prerequisite artifact is absent | Guard 2: executed coupling pin with mutants; Guard 4: gate script refuses |
| Operator flips the variable with no skippable set (cost only) or before the amendment | Guard 4 refuses (prerequisite 5); flip is a cost-only no-op, rollback is deleting the variable |
| Wrongly RED: `--failed` rerun keeps a cached skip, attempt 2 refuses it, `test` stays red | ship prose carve-out plus remedy-line pin (Phase 3.3) |
| Replay certifies a rule the CI does not run | R2: the replay applies the proposed per-suite rule; receipts carry the rule text; the index audit is mandatory |
| Org variable arms the job unexpectedly | Guard 4 reads the repo-scoped organization-variables endpoint (200, count 0) at gate time |

## Architecture Decision (ADR/C4)

### ADR

No new ADR. Append `## Amendment 2026-10-1x (S4 PR C, #9729)` to ADR-276 (written in this PR; the date is the commit date) and keep its `status: adopting`. It records: the go/no-go verdict with its four criteria and receipt paths; the cold/warm/restored `sel_s` figures with the runner image; the re-measured dark cost with window and units; the resolved organization-variable and AC9c reads; the Guard 3 read and the consumer sweep dispositions; the `--admin` queue-skip receipt or its omission; the escape route (issue plus notification email, Better Stack heartbeat deferred) and the amended "Named responder" bullet; the lock removal (GO) or its retention (NO-GO); a supersession note for every sentence the PR falsifies (grep the SUBJECT: "PR C removes", "deferred to PR C", the `sel_s` commitment, "Further PR C consumers", the named-responder text); and the statement that between PR C and PR D a flip is a cost-only no-op the gate script refuses. ADR-270, ADR-262 and ADR-183 get pointer amendments unconditionally on GO (Guard 1 changes what a green `test` means to the admin-merge gate of ADR-270 and to ADR-262 and ADR-183), and ADR-276 `amends:` gains ADR-270. The amendment also amends activation prerequisite 1 (it names Better Stack and Slack: the interim route is an assigned GitHub issue plus notification email, the heartbeat is #10415, and the gate script lists #10415 as missing until it is closed or the amendment carries an explicit waiver line); records the worst-case detection latency (the audit runs on the next main CI completion and sweeps 24 hours, so a bypass merge is found at the next main merge or after at most a quiet day plus the next push); names PR D (#10414) as the producer of the prerequisite-5 `Skippable set` line (without it the gate cannot reach `ready=true`); states that AC9c is an observation, not proof; and carries the activation-lane runbook (gate command, authorization wording, first-active-run canary, 20% exit read on the by-mode split, rollback by deleting the variable), with #9729 as its owner.

### C4 views

No C4 impact. Read in full: `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`. Checked and already modeled: the external human actor (`founder`, who receives the escape issue by GitHub notification), the external systems (`github` for CI, issues and notification; `betterstack` and Slack stay unchanged because the heartbeat is deferred), the data stores (none added), and the actor-to-surface access relationships (none added). The plan adds no workflow file (the audit is a job in `post-merge-monitor.yml`; the canary workflow lives on a throwaway branch and is never merged) and no Sentry monitor, so `plugins/soleur/test/c4-count-parity.test.sh` must stay green and is run in Phase 5.

### Sequencing

The ADR amendment describes the target state in the same PR. Activation is a separate authorized step in the activation lane; PR D (per-suite selection, derive-cache restore, the `needs:` edge, the chain re-pin) follows only after a GO.

## Open Code-Review Overlap

Open `code-review` issues naming planned files: #8659 and #7942 (`scripts/test-all.sh`), #8800 (`scripts/lib/test-affected-paths.sh`). **Acknowledge** all three (EXIT-trap leaks, two unrun mutation batteries, a census-sandbox hardlink hazard; none shares this PR's concern). Related open issues: #10373 (the `fx_new` fixture copy races git auto-maintenance in `scripts/ci-pr-selection.test.sh` and `scripts/test-all-pr-battery-gate.test.sh`): **Fold in** the two one-line fixture hardenings (`maintenance.auto false`, `gc.auto 0`) as an unconditional stage 1 commit (CTO plan-review ruling: independent of the verdict, two lines, and a flake in the pin suite would redden any later required run); the PR body uses `Ref #10373` (the brief reserves closing keywords; close the issue by hand after the fix is observed green). #10333 (review/work skills prescribe `TEST_GROUP=affected` as the lead gate): **Acknowledge**, separate skills change; this plan applies its lesson by previewing with `bash scripts/test-all.sh --print-selection` and using the bounded default. #10325 (decision-challenge, PR C go/no-go inputs): answered by this plan (Phase 2 and the rulings above); the PR body references it with `Ref #10325` and does not close it.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** two CTO agent spawns at plan time (rulings R1 to R11 above). The brainstorm CTO assessment and the Q1 to Q5 advisory carry forward. Marketing, Sales, Finance, Legal, Support: no implications for an internal CI lever (hosted-runner minutes are tracked in ADR-276 Cost Impacts; no spend decision is taken here). Operations: the escape route is a GitHub issue plus notification email, no vendor change. Product/UX Gate: NONE (no user-facing surface; no new component or page files). CPO sign-off is carried by `requires_cpo_signoff` at plan review.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Cold/warm sel_s measurement." [brief] | Phase 1.3 (throwaway push-branch canary), Research Reconciliation row 1 | mapped |
| 2 | "Escape-rate replay: activation prerequisite 2, under 2% over the last 300 first-parent commits." [brief] | Phase 1.2, Phase 2, R2 | mapped |
| 3 | "Re-measure the dark-cost figures before citing them." [brief] | Phase 1.4, Value measurement | mapped |
| 4 | "Org-level variable check" [brief] | Phase 1.1 (gate script, repo-scoped read), R7 | mapped |
| 5 | "AC9c from the Q1 plan: the first doc-only pull request after the Q1 follow-up should show pr-selection skipped with the full battery green." [brief] | Phase 1.1 (`ac9c`), AC13 | mapped |
| 6 | "PR C removes it in its LAST commit; nothing activates before that." [brief] | Phase 4 (GO only), AC11 | mapped |
| 7 | "Every guard-shaped edit to ci.yml, the driver or its pin suites needs a mutant, and floors must be re-derived from a measured green run, not estimated." [brief] | Guard Contract, Phase 5.1 | mapped |
| 8 | "Run EVERY suite that reads ci.yml, not only the ones that reference the changed files." [brief] | Phase 5.2 (re-run list) | mapped |
| 9 | "The threshold is single-user incident: run user-impact-reviewer." [brief] | Review phase note, AC14 | mapped |
| 10 | "At ship, archive this PR's plan and spec in the PR (Phase 6.45)." [brief] | Ship note in Phase 5.4 | mapped |
| 11 | "count merge-queue ejections from skipped legs in the kill criterion" [issue #9729 CTO Q5 (1)] | Phase 3.5 (census escape count) and the ADR kill-criterion sentence | mapped |
| 12 | "derive-cache restore is restore-only with an exact key from main, never saved from `pull_request` scope" [issue #9729 CTO Q5 (2)] | PR D; the canary measures the restored pass as evidence (R5) | descoped — justification: no permanent cache job exists to restore until per-suite selection puts the selector on the critical path, and R5 rules it into PR D |
| 13 | "bounded fetch of the two parents plus merge-base instead of `fetch-depth: 0`" [issue #9729 CTO Q5 (3)] | PR D | descoped — justification: the 14 s full-history checkout sits inside the 1-billed-minute floor of a job that is skipped while the switch is unset, so a bounded fetch saves nothing until PR D runs the selector on every PR |
| 14 | "judge the 20% exit metric on the by-mode split only" [issue #9729 CTO Q5 (4)] | Phase 3.5 (by-mode split); the 20% read itself is the activation lane | mapped |
| 15 | "sweep every consumer that treats `skipped` as an anomaly (census alerts, flake and health dashboards, ship and auto-merge pollers)" [issue #9729 CTO Q5 (5)] | Phase 3.3 | mapped |
| 16 | "the draft-to-ready transition must still yield a full-verified head" [issue #9729 CTO Q5 (6)] | Guard 1 rows (draft-light run and ready run) | mapped |
| 17 | "pin that empty or garbled outputs never skip once the lock is removed" [issue #9729 CTO Q5 (7)] | Guard 2 rows (unlocked darkequiv rows) | mapped |
| 18 | "Regenerate the shard weight for `scripts/ci-pr-selection`" [issue #9729 PR B follow-ups] | none | descoped — justification: `scripts/suite-durations.tsv` is regenerated from measured runs (ADR-240); a hand edit is overwritten and the weight-drift detector owns the drift |
| 19 | "mode-blind sibling classifiers (`ci-e2e-classify.sh`, `ci-shard-totality-classify.sh`)" [issue #9729 PR B follow-ups] | deferral issue #10416 | descoped — justification: the allowlist does not widen in PR C, so a symlinked or executable `.md` stays doc-only exactly as in PR A; re-evaluate before any allowlist widening |
| 20 | "Check capacity first (`bash scripts/test-all.sh --capacity`)." and the tally caveat [brief] | Phase 0 and Sharp Edges | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `scripts/ci-pr-affected-preactivation.sh` (+ test) | "Check it once with an org-admin credential before activation." and "the first doc-only pull request ... Confirm it on a real doc-only PR." (asks 4, 5) | asked |
| `scripts/ci-pr-affected-replay.sh` (+ test), receipts | "Escape-rate replay" (ask 2) | asked |
| Index-completeness audit inside the replay | "the first-parent commits" replay evidence (ask 2) | inferred — justification: PR 9404 showed the replay alone cannot see a suite whose index entry omits its sourced inputs, and the CTO R2 ruling requires the audit before activation |
| Throwaway canary branch | "Build a vehicle" (ask 1) | asked |
| Go/no-go record | "Set a dated go/no-go" [issue #9729 Q2] | asked |
| `ci-head-verdict.sh full-verified`, `admin-merge-ready.sh` call | "Run EVERY suite that reads ci.yml" and the ADR prerequisite 1 text "the Guard 3 reduced-run read is wired into" (asks 6, 7) | inferred — justification: ADR-276 activation prerequisite 1 makes the read a condition of removing the lock |
| `pr-affected-active` step in `ci.yml` | "PR C removes it in its LAST commit" (ask 6) | inferred — justification: the read and the census need a step that proves a run was reduced, per the archived plan Phase 5.1 |
| Audit job + `ci-full-battery-audit.sh` + `ci/full-battery-escape` label | "Anything that edits .github/workflows/ci.yml is UNTRUSTED-CI" and ADR prerequisite 1 (asks 6, 7) | inferred — justification: prerequisite 1 requires the probe and its route before the lock goes |
| Census by-mode split and escape count | ask 14 | asked |
| Ship prose carve-out + remedy-line pin | none | inferred — justification: the PR B fix-round review (recorded in the ADR checklist) named the wrongly-RED direction (`--failed` rerun keeps a cached skip, `test` stays red) as a PR C consumer decision; ask 15 covers the sweep, not the prose |
| Lock removal, coupling pin | ask 6 | asked |
| `#10373` fixture hardening | none | inferred — justification: stage 2 edits `ci-pr-selection.test.sh`; the documented flake would redden this PR's own required run |
| ADR-276 amendment | "Re-measure the dark-cost figures before citing them" (ask 3) | asked |

### Split Assessment

- Subsystems touched: 5 — `.github`, `scripts`, `plugins/soleur`, `knowledge-base`, (receipts under `knowledge-base`)
- Planned files: about 38 (stage 1 alone about 12) | Estimated changed lines: about 2,400 (more than half are tests and receipts)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split — the seam is the go/no-go record (Phase 2). Stage 1 (evidence, no workflow edit) and stage 2 (readers, probe, lock removal) execute inside this one PR because the operator brief names a single PR C that removes the lock in its last commit, and because stage 2 is built only on a GO: a NO-GO ships stage 1 alone (about 12 files). Five plan-review seats (DHH, code-simplicity, CPO, architecture, and the CTO's own R1) recommended moving stage 2, or at least the lock removal, to PR D; the operator's brief is kept as the default and the choice is recorded as an operator (scope) decision challenge in `decision-challenges.md`, with Phase 4 written to move unchanged. If stage 2 exceeds 25 changed files at work time, the work phase moves the consumers beyond `admin-merge-ready.sh` and `ci-head-verdict.sh` to a follow-up and records the cut.

## Implementation Phases

Order follows `cq-write-failing-tests-before`: for every guard, write the executed test first, watch it go red on the unmodified tree, then edit. Floors are re-derived from a measured green run, never estimated. **Every stage 2 task (Phases 3 and 4) is marked GO only in `tasks.md`: the pipeline must not start them before the Phase 2 record exists and says GO.** Stage 1 is the real deliverable of a NO-GO run (about 12 files).

### Phase 0 — Preflight (work phase start)

1. `bash scripts/test-all.sh --capacity`; the host was `CAPACITY_CONTENDED` (load about 10, sibling suites) at plan time. Under contention CI's full battery is the gate: run only the minimal local set named in Phase 5.2 one suite at a time with exit codes captured (never `| tail`), and never write to the repo while a `test-all.sh` run is in flight.
2. `pipeline-tally.sh` calls run as `cd <worktree> && ...` in one command, never in a parallel batch beside a `cd`.
3. Confirm no competing PR (`gh pr list --state open --search "9729"`), `CI_PR_AFFECTED` absent, organization variables 0 (Phase 1.1 output).
4. Preview the diff's suite scope with `bash scripts/test-all.sh --print-selection`, state `selected N of M`, and use the bounded default as the lead gate, not `TEST_GROUP=affected` (#10333).
5. Baseline: the brief states the Q1 list exits 0 on main; cite the merge commit `269afa3ce4` runs (18 runs settled green per the #9729 status comment) rather than re-running the whole list locally, and re-run only the suites this PR edits to establish their pre-change floors.
6. Probe the vehicle first, before building any replay tooling: push a throwaway branch carrying a trivial workflow file to check that the credential has the `workflow` scope; if the push is refused, stop stage 1 at "evidence incomplete: no hosted-runner vehicle" and ask the user to authorize one (this is the likeliest stall). Runner budget: the vehicle is bounded by a stated cap (canary 2 jobs of at most 15 minutes; replay at most 10 chunks of at most 30 minutes, about 5 runner-hours worst case); record the billed minutes in `go-no-go.md` and weigh them against the saving.

### Phase 1 — Evidence (stage 1; no `ci.yml` or workflow edit in the PR diff)

**1.0 Cheap kill first.** Before any hosted-runner spend, estimate the mean net saving from a stratified local sample: every tenth of the 300 first-parent commits (30 commits), `bash scripts/test-all.sh --print-selection --paths=<files>` with the derive cache primed (19 s warm), skipped suite-minutes from `scripts/suite-durations.tsv` (about 102 suite-min in the light group), counting, where a whole gated job is skipped, that job's billed job-min (suite-min plus its measured non-suite setup and install minutes) as the saving, then subtracting the 1.29 billed selector min per run. Counting setup minutes biases toward GO and the selector subtraction biases toward NO-GO, so the kill fires only when the sample mean plus two standard errors is still under 19.96 on this basis: the kill skips the replay and is irreversible, so it must not fire on an undercount (CTO ruling, 2026-10-15). Reconcile the two denominators in the record: the 14% figure is 23 suite-min against one full run's 164.4 job-min; the R3 bar is 20% of the 99.8 mean PR run (19.96 job-min), and the 23-over-99.8 ceiling (23%) holds only for a run that skips everything skippable, so a realistic mean is lower. If the sample mean plus two standard errors is below 19.96, write criterion (c) as FAIL and the verdict as NO-GO and skip the 300-commit replay, the canary replay chunks and the reader audit (the dark-cost, organization-variable and AC9c reads and the ADR amendment still ship).

**1.1 Pre-activation gate script** `scripts/ci-pr-affected-preactivation.sh` (+ `.test.sh`), read-only, fail-closed, capped at six readers, one line per prerequisite and a final `SOLEUR_PR_AFFECTED_PREACTIVATION ready=<true|false> missing=<list>`; any API failure is `unknown`, never `ok`; `ready=true` needs `ok_count == total > 0`. Readers: (1) `variable`: absent only when the variable read returns HTTP 404 AND the variable list returns 200 (any other failure is "cannot establish"); (2) `org_variables`: `gh api repos/jikig-ai/soleur/actions/organization-variables` returns HTTP 200 with `total_count` 0; (3) `lock`: the driver literal is absent; (4) `artifacts`: the `full-verified` subcommand and the audit script exist and answer their fixtures, the `admin-merge-ready.sh` call site exists (grep), and the newest `full-battery-audit` run on `main` concluded `success`; (5) `verdict`: the receipt's last line `SOLEUR_PR_AFFECTED_VERDICT verdict=GO ruled=confirmed`, read from the receipt path and window dates the ADR amendment records (the spec directory is archived at ship, so the path is read from the ADR, never hard-coded), not older than 60 days (planner default, taste); (6) `prereq5`: the ADR amendment carries a `Skippable set` line naming at least one group or suite, and the escape route's Better Stack follow-up #10415 is closed or the amendment carries an explicit waiver line. `ac9c=observed|not-yet` is printed as information and never gates (the first non-draft pull request created after 2026-10-15T17:50:38Z whose files are all under `knowledge-base/**` or a root `*.md`: `pr-selection` `skipped`; `test-webplat`, `test-bun`, `test-scripts-heavy`, every `test-scripts` shard and `test` `success`). Closed line set: `variable=`, `org_variables=`, `lock=`, `artifacts=`, `verdict=`, `prereq5=`, `ac9c=`. Run it now and record the output; it is run again at pre-merge and in postmerge. The explicit operator authorization is NOT read by the script (a menu acknowledgement is not authorization).

**1.2 Replay and index audit (build, local, no CI)** `scripts/ci-pr-affected-replay.sh` (+ `.test.sh`), R2 semantics. Inputs: `--commits N` (default 300), `--chunk I/K`, `--rule <name>` (the proposed per-suite rule: skip a suite iff its `AFFECTED_SELECTED` row is `0`, its class is not always-on, `AFFECTED_SUMMARY fallback=none`, and the runner-changed trigger list does not match; the receipt stores the rule text and its hash so PR D's selector can be pinned to it), `--out DIR` (no repository path literal in the script: the kb-consumer census). Per commit it records files, selection summary, skipped suites and their `scripts/suite-durations.tsv` minutes, the full-battery run outcome (`merge_group` or push run on that SHA), failing suites from the failed shard jobs' `[FAIL]` lines, and a retry-cleared flag (a later run on the identical tree that went green). Classes: escape (deterministic, uncleared, on a would-skip suite), flake-cleared, unattributable, not-evaluable (expired logs, no run, cancelled, empty-diff bot commit, shard job with no `[FAIL]` line). It is resumable per chunk and writes its receipt incrementally, so a timeout leaves "evidence incomplete" and not nothing. An `aggregate` subcommand merges chunk files and the other receipts into the verdict inputs. Summary: attributable, unverified-as-escape (the gating point estimate), worst-case (adds not-evaluable), the one-sided 95% Clopper-Pearson upper bound computed on the WORST-CASE numerator (so the 12% clause can actually bind; python3 stdlib, bisection on the binomial CDF), literal and queue-and-push-only counts, mean skipped suite-min and mean net saving. The index-completeness audit is a subcommand over `scripts/test-all.sh` registrations and `scripts/lib/test-affected-paths.sh`: for every registered suite, every repo path its file or sourced libs reference must be declared for it or match the widened trigger list; fixture: the PR 9404 shape (a `-mutations` sibling consuming `guard-vacuity-floor.test.sh` and `ci.yml` while the index declares the suite only on its own files) MUST be flagged. Before building the audit, check whether `scripts/test-affected-kb-consumers.*` or the affected-index tests already ratchet declared inputs.

**1.3 Vehicle: cold/warm/restored `sel_s` and the replay chunks** (R4, R5). A throwaway branch `canary-sel-9729` cut from the FEATURE head (so the committed scripts exist; the branch is never merged and is deleted only after the CTO confirmation in Phase 2, in case a within-10% ruling needs a re-measure) carrying ONE extra workflow with `on: push: branches: ['canary-sel-*']`. Job A on a fresh `ubuntu-latest` runs `actions/checkout` with `fetch-depth: 0` (mirrors `pr-selection`), then `time bash scripts/test-all.sh --print-selection --paths=README.md` cold, then warm, then saves the derive cache with `actions/cache/save`; job B (`needs: A`, a second fresh runner) restores it and runs the pass a third time. Each pass is its own step so the durations come from the jobs API step times, not from logs; record `nproc`, `uname -r` and the runner image version. The same workflow hosts the replay chunks as matrix jobs (artifact per chunk, `gh run download`, `aggregate`); poll with Monitor, never a background poll. The driver's `CI_PR_AFFECTED` and 90 s budget are not involved.

**1.4 Re-measure the dark cost.** Re-run the Value-measurement command with a stated window (the ADR sample, 2026-10-14T23:24Z to 2026-10-15T09:20:12Z, reproduces 42 executed, 54 billed, 1.29 per executed job; add a second window after the Q1 merge for the skipped-job state) and the pull-request run counts for 10-09 to 10-14 (354, 183, 383, 387, 251, 264). State units (billed vs raw minutes, per executed job vs per run) in every sentence the ADR keeps, and the oldest run still listed.

**1.5 Reader audit for the go/no-go.** `git grep -l "knowledge-base" -- 'apps/web-platform/**/*.test.*' 'apps/web-platform/test'` (238 files at plan time; state the command and the count) plus `scripts/test-affected-kb-consumers.baseline.txt` (274 rows). The replay script emits the candidate list (file, suite, group, skippable under the rule); the work phase classifies each as fixture-string only or a real reader of the tree.

**1.6 Fixture hardening (#10373).** `git -C "$FX_BASE" config maintenance.auto false` and `gc.auto 0` in the `fx_new` fixtures of `scripts/ci-pr-selection.test.sh` and `scripts/test-all-pr-battery-gate.test.sh`: an unconditional stage 1 commit (two one-line changes, independent of the verdict). The PR body uses `Ref #10373`.

### Phase 2 — Go/no-go record (the seam)

Write `receipts/go-no-go.md` from the Phase 1 numbers, one row per R3 criterion with the measured value, the threshold, the arithmetic and a status in `pass`, `fail`, `within-10%` or `unmeasured`. The verdict function (in the replay script; a test pins it with synthetic receipts for every status combination) is: GO iff every criterion passes; NO-GO iff any criterion fails outside the 10% band; UNDECIDED otherwise (a `within-10%` goes to the CTO; an `unmeasured` criterion is the evidence-incomplete path). The receipt records `computed=` and `ruled=`; the gate reads `ruled`, and a CTO ruling can only move a computed verdict toward NO-GO (a CTO GO over a computed NO-GO is a decision for the operator). Spawn `soleur:engineering:cto` once on the measured numbers to confirm (mandatory) and record `Ruled by CTO agent, <date>: ...` in `decision-challenges.md`; then write the receipt's last line `SOLEUR_PR_AFFECTED_VERDICT verdict=<GO|NO-GO|UNDECIDED> ruled=<confirmed|pending>` and record the oldest run still listed. Commit and push the receipts, then delete the canary branch, before any stage 2 commit.

- **GO:** continue with Phases 3 and 4.
- **NO-GO:** keep the lock; write the ADR amendment recording the NO-GO, the figures and that PR B stays dark at zero cost; file a retire-the-stage issue with a due date of merge plus 7 days and a closing step for #9729 once the operator decides; ship stage 1. No workflow edit, so normal merge rules apply (the no-`--admin` rule binds only a PR that edits `.github/workflows/`). Do not revert PR B.
- **Evidence incomplete** (any criterion `unmeasured` after the vehicle ran): ship stage 1 as evidence-only and file a follow-through issue due merge plus 7 days.

### Phase 3 — Readers, probe, census (stage 2, GO only)

**3.1 `pr-affected-active` step** in the `pr-selection` job of `.github/workflows/ci.yml`: a step named exactly `pr-affected-active`, `if: steps.select.outputs.active == 'true'`, which only prints a notice. Update every pin that reads the job (`scripts/ci-push-dedupe.test.sh` `P-JOB-TEXT`, `PRSEL_IF`, the `C-VARS` census; `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh`), with the step name held in one constant that the reader and the census also pin (Guard 2); the census of readers of the step widens in the same commit (case-insensitive, whitespace-tolerant around `.` and `[`, whole document, whole-context forms).

**3.2 Full-verified read.** `plugins/soleur/scripts/ci-head-verdict.sh full-verified <pr|sha> [--repo OWNER/REPO]` prints one last line `SOLEUR_CI_FULL_VERIFIED state=<yes|no> sha=<H> run=<id|none> reason=<token>` and exits 0 (a decision was made). When it cannot answer it prints `state=error` (a state OUTSIDE the closed `yes|no` set, so no consumer can read an outage as a verdict) and exits 3; consumer tests stub that real error output. A head is `yes` iff (a) the argument is a main SHA and a `merge_group` run on that SHA concluded `success` (a `merge_group` run's `head_sha` is the queue commit, which becomes the main commit and never equals a PR head SHA; mirror the `push-dedupe` pins `.path`, `head_repository` and `head_branch` prefix `gh-readonly-queue/main/`), or (b) the argument is a PR head SHA and the pull_request `ci.yml` run that OWNS the graded `test` check run (check suite to run id, not "newest by created_at", which can diverge across re-runs and concurrent runs; runs filtered by `pull_requests[].number`, base and `head_repository` so a stacked PR sharing a head SHA cannot satisfy or defeat it) concluded `success` AND none of `test-webplat`, `test-bun`, `test-scripts-heavy` has conclusion `skipped` (any skipped gated job means `no`; a draft-light run is red by design, so the run-level `success` already excludes it and no light-draft qualifier exists) AND the `pr-affected-active` step did not conclude `success`. Job and step shape table: a `pr-selection` job concluded `skipped` (the normal state with the variable unset) has no steps and its step is NOT consulted, so a run where every gated job executed is `yes`; a `pr-selection` job that ran must carry the step with a conclusion of `success` or `skipped`; a missing `pr-selection` job is `error` only when a gated job is skipped (runs older than PR B have none and every gated job executed); an empty or garbled jobs list, a missing gated job or an unrecognized step shape is `error`. The jobs API is paginated and `total_count` asserted; reads use job and step names and conclusions, head SHA and event (never a title, never a check name), job time fields not `run_attempt` labels, and `jq -e` checks every body. `plugins/soleur/scripts/admin-merge-ready.sh` calls it on `CHECK_SHA` (the graded SHA, which is `--green-sha G` on the update-branch carryover flow, not necessarily the merge head `$SHA`) only after every required context counts GREEN, and prints READY only on `yes` (a positive decision, never "no culprit named"); `no` is NOT-READY `reason=reduced-run` with the remedy printed (enqueue through the merge queue, or unset the variable and push; rerunning or pushing re-evaluates the selector and can reduce again), `error` is exit 3. A repo whose default-branch `ci.yml` has no `pr-selection` job (a customer repo) answers `yes` with `reason=not-applicable`, mirroring the existing applicability rule. A moved base is covered by the strict-up-to-date policy and the queue, not by the predicate. Data sources, verified live at plan time: `gh api "repos/jikig-ai/soleur/actions/workflows/ci.yml/runs?head_sha=<sha>"` (a queue-merged commit such as `a54c4e315b` lists both a `push` and a `merge_group` run; the unfiltered `actions/runs?head_sha=` endpoint is polluted by unrelated `workflow_dispatch` runs at that SHA and truncates at `per_page`, so it is never used). Tests: new rows in `plugins/soleur/test/ci-head-verdict.test.sh` and `plugins/soleur/scripts/admin-merge-ready.test.sh`; extend the reader census row L1 so a new reader of the aggregator `test` is listed.

**3.3 Consumer sweep.** A closed regex set, not an open-ended grep, with a census test (extend row L1 of `ci-head-verdict.test.sh`) that fails when a reader of the aggregator `test` check, of `ci.yml` run conclusions, or a `gh run rerun` site is unclassified: `plugins/soleur/scripts/{admin-merge-ready,ci-head-verdict,monitor-pr-checks,check-red-on-main,deploy-arm}.sh`, `plugins/soleur/skills/ship/scripts/battery-owed.sh`, `plugins/soleur/skills/drain-prs/scripts/triage-prs.sh`, `plugins/soleur/lib/pr-merge-poll.ts`, `scripts/ci-demand-census.sh`, `scripts/ci-draft-push-census.sh`, the followthrough probes (`scripts/followthroughs/{pr-battery-gate-saving-9323,ci-push-dedupe-soak-9512,ci-draft-light-soak-9728}.sh`: the first counts pull_request successes as qualifying and will count reduced runs once active), `.github/workflows/{post-merge-monitor,web-platform-release}.yml`, `plugins/soleur/skills/ship/{SKILL.md,references/{settle-then-admin-merge,merge-queue-dequeue,red-on-main-quarantine}.md}`, `merge-pr`. Table in the PR body: reader, what it does with a green `test`, class (merge authority, reporter, deploy arm, unaffected), disposition. Only a merge authority is edited. Expected: `battery-owed.sh`, `monitor-pr-checks.sh` and the push-only `deploy-arm.sh` stay unchanged with a one-line rationale each (a green `test` under the queue is followed by the `merge_group` full battery); the `full-decided` token name drifting from its meaning is noted in the ADR; the follow-through probe is a disposition row, edited only if it would count reduced runs. Ship prose: in the rerun exception of `plugins/soleur/skills/ship/SKILL.md`, when the run's `pr-selection` job shows `active`, rerun all jobs (`gh run rerun <run-id>`) or push, never `--failed`; the aggregator's remedy line in `ci.yml` and this sentence use the same wording, pinned by one test. Keep the Q1 wording rule: no `gh run rerun` beside the release workflow file name on one line.

**3.4 Detective probe and route.** `plugins/soleur/scripts/ci-full-battery-audit.sh` (+ `.test.sh`) and a second job `full-battery-audit` in `.github/workflows/post-merge-monitor.yml`. The workflow already triggers on `workflow_run` for CI completed on `main` (the `monitor` job filters bot-fix commits), so the new job needs only its own `if:`: `github.event.workflow_run.event == 'push'` and head branch `main` (a fork branch named `main` can fire the trigger), or `workflow_dispatch` with `commit_sha`; job-level permissions derived per endpoint from the vendor's permission table (`actions: read` for the runs and jobs reads, `contents: read` for `commits/{sha}/pulls`, `issues: write` for the label and the filing; confirm each against the table and by the dry-run dispatch), its own `concurrency` with `cancel-in-progress: false`, and no `continue-on-error` on the probe step. It sweeps the last 24 hours of first-parent commits on `main` every run. For each SHA: a `merge_group` run on that SHA with conclusion `success` and every gated leg executed is a queue merge (silent); otherwise select the PR whose `merge_commit_sha` equals the SHA (`commits/{sha}/pulls` can return several) and call `full-verified` on the PR's earlier graded head (the update-branch parent chain proves a carryover merge); `yes` is silent. Classify separately and do not flag as escapes: a direct revert pushed by the `monitor` job (no PR by design) and a merge whose verified carryover chain holds. A `no`, or a PR-less commit that is not a monitor revert, is a bypass: emit `::error::SOLEUR_FULL_BATTERY_ESCAPE sha=<sha> pr=<n>` and file one deduped `ci/full-battery-escape` issue keyed by SHA that ASSIGNS the operator and records the main push-run outcome in its body (a bypass merge still gets a full push run on `main`, because `push-dedupe` elides it only after a successful `merge_group` run: a green push run lowers the severity, it does not clear the finding). The filer follows `main-health-monitor.yml` (label created idempotently, list-then-file, an unreadable list means "do not file", no PR-controlled string in the title). A sweep that examines zero commits because of an API error exits non-zero. The `workflow_dispatch` dry run on the PR branch is a receipt: its run id, the label existing, a test issue filed and closed, and the notification email arriving (assignment, not a mention alone, is what generates it).

**3.5 Census.** `scripts/ci-demand-census.sh`: PR `CI` job-minutes by mode (`full` unless the run's `pr-affected-active` step concluded `success`, then `affected`) and the escape count, read as the number of `ci/full-battery-escape` issues created in the window (the annotation is not a readable source); extend its test; update the schema header lines. Scheduling the census is the activation lane's.

**3.6 `--admin` and the queue.** Derive from history whether a bypass merge reaches `main` with no `merge_group` run: list recent main first-parent commits, find one merged by `gh pr merge --admin` per the corpus, and check `actions/workflows/ci.yml/runs?head_sha=<sha>&event=merge_group`. Cite the SHA in the ADR amendment, or omit the sentence (the stated fallback is "omitted", so the work phase cannot stall on it).

### Phase 4 — Lock removal (last commit of the work phase, GO only)

Self-contained on purpose: if the operator rules that PR D owns the lock removal (decision challenge in `decision-challenges.md`), this whole phase moves unchanged.

1. Write first, red on the unmodified tree: in `scripts/ci-pr-selection.test.sh` a `row_lock_coupling` run against the UNLOCKED sandbox copy (the `UNLOCKED` pattern, whose `sed` derivation is re-wired in step 3; with the lock present in the real tree it would pass, so it must not run against the real tree): the lock may be absent only while the `full-verified` subcommand (executed against a shared fixture helper: prints its marker, answers `no` for a reduced fixture) and `ci-full-battery-audit.sh` (executed: flags a bypass fixture) answer correctly, the `admin-merge-ready.sh` call site exists (grep; that script's own suite carries G1-6 and G1-8), the `full-battery-audit` job and the `pr-affected-active` step exist (parsed `ci.yml` and `post-merge-monitor.yml`). Add a `row_empty_skippable` (a diff whose would-skip set is empty emits `active=false`, empty `skip_legs`, with the switch `on` and the lock absent).
2. Run `bash scripts/ci-pr-affected-preactivation.sh` and put its `variable=absent` line in the PR body; with the lock still present it correctly prints `ready=false lock=present` at this point, so the PR body asserts only the variable state. It is re-run at pre-merge and in postmerge; AC14 is the PR-ready check.
3. Remove `readonly PR_AFFECTED_LOCKED=1` (line 90) and the dead read (`GUARD:G2-13-LOCK-READ`, line 154); keep the `locked=` field on the notice and step summary as a constant `false` (the notice schema is pinned and consumers whitelist it); update the header comments that describe the lock; invert `row_lock`, `row_must_pass`, the `on/true` assertions, the lock-count and one-diff-line pins, `UNLOCKED`/`UNLOCKED_ROWS` (re-wire the `sed` that derives the unlocked copy, which matches the lock line verbatim) and the two lock mutants; add the "unlocked, empty or garbled outputs never skip" rows to the `darkequiv` evaluator in `scripts/ci-push-dedupe.test.sh`.
4. Re-derive the floors of the suites this commit edits (`BASE_ROWS` and `MIN_MUTANTS` in `ci-pr-selection.test.sh`; `_FLOOR` and the `MUT_RUN` minimum in `ci-push-dedupe.test.sh`) from a full green run, and record the measured numbers. The floors of `ci-test-aggregator-diagnosis.test.sh` move in the Phase 3.1 and 3.3 commits, not in this one.
5. The ADR amendment is finalized in this commit or the one before it; this commit touches only the driver, its suite, `ci-push-dedupe.test.sh` rows and ADR text.

### Phase 5 — Verify and ship

5.1 Mutants: scripted as ONE apply/revert/expect table per suite (not hand-run): for every row of the Guard Contract, apply the edit to a sandbox copy that has had `git init -q && git add -A` run, confirm it LANDED and that removing the guard fails exactly the named row; drop any mutant that kills nothing and say so.
5.2 CI is the authority for the full re-run list (every suite that reads `ci.yml`: `git grep -l 'ci\.yml' -- '*.test.sh'` returns 46 files at plan time, plus the vitest readers under `apps/web-platform/test`, the Q1 list, the ratchets file-referencing selection missed in PR B, the release-budget awk with the declared path staying 73 of 75). The minimal LOCAL set, run one suite at a time: the suites this PR edits (`scripts/ci-pr-selection.test.sh`, `scripts/ci-push-dedupe.test.sh`, `scripts/ci-draft-light.test.sh`, `plugins/soleur/test/{ci-test-aggregator-diagnosis,ci-head-verdict,ship-battery-owed,c4-count-parity,guard-vacuity-floor,fixture-relative-assert,fixture-dir-operand-assert,fixture-cd-containment,fixture-env-adoption,lint-orphan-test-suites}.test.sh`, `plugins/soleur/scripts/admin-merge-ready.test.sh` and its wiring suite `admin-merge-ready-wiring.test.sh` (it walks the admin-merge-ready corpus), the new suites), `scripts/test-affected-kb-consumers.test.sh`, `python3 scripts/lint-guard-contract.py` over this plan, `lint-shell-capture-exit`, shellcheck, the markdown sweep, and `apps/web-platform/test/git-lock-marker-telemetry.test.ts` (vitest, from `apps/web-platform`: the new `SOLEUR_*` markers are emitted outside the `skills/*/scripts/*.sh` walk, but run it once to prove no registration is owed). `scripts/test-all-affected.test.sh` timed out under load 12 to 24 in Q1: leave it to CI. Run bash suites under the CI bash (5.2.x) where the workstation differs. New suites are registered (the orphan lint reports it once the file is tracked; edit the registration files only as the orphan lint and the shard-totality suite report) and the affected gate degrading to full is expected and stated. Extend the declared inputs of `scripts/ci-pr-selection.test.sh` in `scripts/lib/test-affected-paths.sh` (it now executes files under `plugins/soleur/scripts/`, `ci.yml` and `post-merge-monitor.yml`; the audit must flag its absence: the PR 9404 shape).
5.3 Push, then read this PR's own run: with the variable unset `pr-selection` is `skipped` and every battery leg and `test` concludes `success` on the ready run; record run id and job conclusions in the PR body.
5.4 Review: the 11-seat review plus `soleur:engineering:review:user-impact-reviewer` (single-user threshold). Ship: archive this plan and spec in the PR (Phase 6.45); PR body carries `Ref #9729` only, plus `Ref #10373`, `Ref #10325`.

## Files to Edit

Stage 1 (always):

- `scripts/ci-pr-selection.test.sh` and `scripts/test-all-pr-battery-gate.test.sh` (`fx_new` hardening only)
- `scripts/lib/test-affected-paths.sh` and the shard manifests (registration of the new suites and the declared inputs, only as the orphan lint and shard-totality report)
- `knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md` (amendment; `amends:` gains ADR-270), with unconditional pointer amendments in ADR-270, ADR-262 and ADR-183 on GO

Stage 2 (GO only):

- `.github/workflows/ci.yml` (`pr-affected-active` step, aggregator remedy wording)
- `.github/workflows/post-merge-monitor.yml` (`full-battery-audit` job)
- `scripts/ci-pr-selection.sh` (lock removal, header) — last commit
- `scripts/ci-pr-selection.test.sh` (coupling and empty-skippable rows, inverted lock rows, floors)
- `scripts/ci-push-dedupe.test.sh` (step pins, `darkequiv` unlocked rows, floors)
- `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh` (remedy-line pin, floors)
- `plugins/soleur/scripts/ci-head-verdict.sh` and `plugins/soleur/test/ci-head-verdict.test.sh` (`full-verified`, reader census)
- `plugins/soleur/scripts/admin-merge-ready.sh` and `plugins/soleur/scripts/admin-merge-ready.test.sh`
- `plugins/soleur/skills/ship/SKILL.md` (rerun carve-out)
- `scripts/ci-demand-census.sh` and `scripts/ci-demand-census.test.sh`
- `scripts/followthroughs/pr-battery-gate-saving-9323.sh` only if the sweep shows it would count reduced runs

## Files to Create

- `scripts/ci-pr-affected-preactivation.sh` (+ `.test.sh`)
- `scripts/ci-pr-affected-replay.sh` (+ `.test.sh`)
- `plugins/soleur/scripts/ci-full-battery-audit.sh` (+ `.test.sh`) — GO only
- `knowledge-base/project/specs/feat-one-shot-9729-ci-pr-c-affected-only/{tasks.md,decision-challenges.md}` and `receipts/{replay-summary.md,replay-commits.tsv,sel-s-canary.md,go-no-go.md,dark-cost.md,reader-audit.md}`
- Never in the diff: the `canary-sel-9729` branch workflow (deleted after the Phase 2 confirmation)

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC1 Stage 1: receipts are committed under the spec directory: the replay summary with attributable, unverified-as-escape, worst-case, the 95% Clopper-Pearson upper bound (on the worst-case numerator), the literal and queue-and-push-only counts and the retry-cleared count, each with numerator and denominator; the rule text and its hash; the 300-commit window dates; the oldest run still listed. If Phase 1.0 killed criterion (c), the sample figures and the arithmetic replace the replay summary and `go-no-go.md` says so.
- [x] AC2 The index-completeness audit flags the PR 9404 fixture and reports zero unexplained gaps on the current tree (or lists each gap, and the verdict records it as a NO-GO input).
- [x] AC3 `receipts/sel-s-canary.md` holds cold, warm and restored wall times read from the jobs API step times, `nproc`, the runner image version and the run ids; `git ls-remote --heads origin canary-sel-9729` is empty after the Phase 2 confirmation; `git diff --name-only origin/main...HEAD` lists no file of the canary workflow (the merge-base form, so a sibling merge cannot redden it).
- [x] AC4 The dark-cost figures in the ADR amendment carry the command, window, units and the plan-time reproduction (42 executed, 54 billed, 1.29 per executed job); every sentence PR C falsifies is superseded by a dated note (grep of the SUBJECT lists each hit, including negative claims: "is NOT asserted", "inert in PR B", "deferred to PR C", "no reader can read a reduced green yet", "PR C removes the lock").
- [x] AC5 `bash scripts/ci-pr-affected-preactivation.sh` runs read-only and prints exactly the closed line set (`variable=`, `org_variables=`, `lock=`, `artifacts=`, `verdict=`, `prereq5=`, `ac9c=`) and the final line; its test rows (Guard 4) pass; the recorded output states `variable=absent`, `org_variables=0` and the `ac9c` state.
- [x] AC6 `receipts/go-no-go.md` records each R3 criterion with measured value, threshold, arithmetic and status, `computed=` and `ruled=`, the CTO confirmation row and the machine line; committed before any stage 2 commit (`git log` order).
- [x] (N/A: verdict NO-GO, stage 2 not built) AC7 (GO) The `full-verified` subcommand and its `admin-merge-ready.sh` call pass Guard 1 rows including the draft-light run, the ready run, the skipped-`pr-selection` ready run (must be `yes`), an empty jobs list, a carryover on `--green-sha`, and the stacked-PR shared head SHA.
- [x] (N/A: verdict NO-GO, stage 2 not built) AC8 (GO) `ci-full-battery-audit.sh` passes Guard 3 rows; the `workflow_dispatch` dry-run receipt (run id, label, test issue, notification email) is recorded in the PR body.
- [x] (N/A: verdict NO-GO, stage 2 not built) AC9 (GO) The Phase 3.3 sweep table is in the PR body and the census test is green; the ship carve-out and the aggregator remedy line agree (pinned).
- [x] AC10 `git diff --quiet origin/main...HEAD -- scripts/required-checks.txt` exits 0 and no ruleset context name changed; `plugins/soleur/test/c4-count-parity.test.sh` is green.
- [x] (N/A: verdict NO-GO, stage 2 not built) AC11 (GO) The lock removal is the last commit of the WORK phase: `git log --format=%s` shows it after every other implementation commit, and `git show --stat <that commit>` touches only the driver, its suite, `ci-push-dedupe.test.sh` and ADR text. Commits after it are limited to review fixes (each re-runs `row_lock_coupling`) and files the pipeline writes (`knowledge-base/INDEX.md`, `specs/<branch>/session-state.md`, `tasks.md`, and the ship-time archive moves of this plan and spec). The PR body records the gate-script `variable=absent` line; `grep -c '^readonly PR_AFFECTED_LOCKED=' scripts/ci-pr-selection.sh` is 0 and `row_lock_coupling` is green.
- [ ] AC12 The CI full battery is green on the PR; the minimal local set of Phase 5.2 exits 0 with exit codes captured; floors are the measured numbers listed in the PR body with the run they came from; `python3 scripts/lint-guard-contract.py` passes on this plan.
- [ ] AC13 (observation) This PR's own ready-run CI shows `pr-selection` `skipped` and all battery legs and `test` `success` (record the run id); the AC9c gate-script state is recorded (`observed` or `not-yet`), and a `not-yet` is an observation, not a failure.
- [ ] AC14 (observation) `soleur:engineering:review:user-impact-reviewer` ran at review; no activation command was run: `gh api repos/jikig-ai/soleur/actions/variables/CI_PR_AFFECTED` still returns HTTP 404 at PR-ready time (it depends on the variable staying unset, so it is an observation at that moment, not a property of the diff).

### Post-merge (observations; not gates)

- [ ] AC15 The activation lane (a separately authorized step, outside this PR; #9729 owns it and stays open) starts only after the gate script prints `ready=true`; the ADR amendment carries the lane's runbook: the gate command, the authorization wording, the first-active-run canary, the 20% exit read on the by-mode split, and rollback by deleting the variable.

## Observability

```yaml
liveness_signal:
  what: the SOLEUR_PR_AFFECTED_PREACTIVATION line of the gate script, the full-battery-audit job conclusion in the jobs API, and the ci/full-battery-escape issue list
  cadence: per main CI completion (audit job); on demand (gate script)
  alert_target: a deduped ci/full-battery-escape issue assigned to the operator (GitHub notification email); the Better Stack heartbeat is deferred (#10415) and is a gate prerequisite
  configured_in: .github/workflows/post-merge-monitor.yml (full-battery-audit job), plugins/soleur/scripts/ci-full-battery-audit.sh, scripts/ci-pr-affected-preactivation.sh
error_reporting:
  destination: workflow run annotations (::error::SOLEUR_FULL_BATTERY_ESCAPE) and the filed issue; the gate script prints one line per unmet prerequisite
  fail_loud: yes (a zero-commit sweep or an unreadable API exits non-zero; unknown is never ok)
failure_modes:
  - mode: a bypass merge of a reduced run reaches main
    detection: the audit job on the next main CI completion, sweeping the last 24 hours
    alert_route: ci/full-battery-escape issue and notification email
  - mode: the audit job itself does not run or errors
    detection: the gate script's artifacts reader requires the newest full-battery-audit run on main to have concluded success; a missed run is caught by the next run's 24-hour sweep
    alert_route: the gate refuses activation; a red job on a main CI completion
  - mode: a reader reads a reduced run as full
    detection: Guard 1 fixture rows; live, the audit's escape issue
    alert_route: ci/full-battery-escape issue
logs:
  where: GitHub Actions run logs and annotations; receipts under the spec directory and the receipt path recorded in the ADR
  retention: 90 days for runs (the replay receipts are committed because the logs expire)
discoverability_test:
  command: bash scripts/ci-pr-selection.sh
  expected_output: reason=not_pr
```

## Guard Contract

### Guard 1 — full-verified read (`ci-head-verdict.sh full-verified` and the `admin-merge-ready.sh` call)

**Property.** A merge authority treats a head as full-battery-verified only when a `merge_group` run on that main SHA succeeded, or the pull_request `ci.yml` run owning the graded `test` check run succeeded with no gated job skipped and no successful `pr-affected-active` step; any unreadable or unrecognized shape is not verified.

**Assembly.** The chokepoint is the single `full-verified` subcommand in `ci-head-verdict.sh` (the one resolver). Its callers: `admin-merge-ready.sh` (blocking, on `CHECK_SHA`), `ci-full-battery-audit.sh` (detective), and any reader the Phase 3.3 sweep classifies as a merge authority; reporters (`monitor-pr-checks.sh`, `triage-prs.sh`, `battery-owed.sh`) are listed with a disposition, not edited. The closed `verdict` state set is not widened. The gated set is the three jobs `test-webplat`, `test-bun`, `test-scripts-heavy`.

**Mutation matrix.**

| # | Mutation (must drive the guard RED) | Expect |
|---|---|---|
| G1-1 | green `test`, run shows `test-bun` `skipped` | state=no |
| G1-2 | `pr-affected-active` step `success`, no job skipped | state=no |
| G1-3 | a full-looking run on a different head SHA | state=no |
| G1-3b | the same run still in progress | state=error |
| G1-3c | the same run with conclusion `failure` | state=no |
| G1-4 | the jobs API returns an empty or non-JSON body | state=error, exit 3 (outside the closed set) |
| G1-5 | a gated job skipped and the `pr-selection` job absent from the run | state=error |
| G1-6 | dispatch: `admin-merge-ready.sh` with the subcommand call deleted still prints READY for the G1-1 fixture | admin-merge-ready suite RED |
| G1-7 | second consumer (`ci-full-battery-audit.sh`) replaces the call with its own check that misses G1-2 | audit suite RED |
| G1-8 | reorder: the call moved after the READY line is printed | admin-merge-ready suite RED (READY printed for a reduced run) |
| G1-9 | draft-light run (`test-webplat` skipped by light, `test` red) read as verified | state=no for the draft run, yes for the ready run after it |
| G1-10 | carryover: `--green-sha G` graded, the call made on the merge head `$SHA` instead of `CHECK_SHA`, and a reduced run on G | admin-merge-ready suite RED |
| G1-11 | a stacked PR sharing the head SHA has a full run while this PR's run is reduced | state=no |

Harness rows: H1 mutate the suite (delete the G1-2 fixture arm) and require RED; H2 a stub `gh` returning an empty jobs list must be `error`, and the consumer stubs replay the producer's real error line (`state=error`, exit 3), so a consumer that whitelists only `yes|no` is exercised. Must-PASS non-canonical inputs: a ready run where `push-dedupe` and `draft-light` are `skipped` (normal) and `pr-selection` is `skipped` with no steps is `yes`; a main SHA whose only success is a `merge_group` run is `yes`. Anchor: the predicate lives in a script a PR can edit, so the guard proves consistency; the outside anchors are `merge_group` (the full battery on the candidate tree) and the UNTRUSTED-CI rule (a PR editing `.github/workflows/` has no agent admin-merge path).

### Guard 2 — lock removal coupling pin, empty skippable set and the `pr-affected-active` step

**Property.** The activation lock can be absent only while the `full-verified` subcommand, its `admin-merge-ready.sh` call site, the audit script, the `full-battery-audit` job and the `pr-affected-active` step all exist and work; a diff whose would-skip set is empty emits `active=false` and an empty `skip_legs` whatever the switch; exactly one step named `pr-affected-active` exists, in the `pr-selection` job, guarded by `steps.select.outputs.active == 'true'`.

**Assembly.** The lock literal and its read in `scripts/ci-pr-selection.sh`, the arm (`GUARD:G2-13-ARM`), the coupling and empty-skippable rows in `scripts/ci-pr-selection.test.sh` (the chokepoint, run against the unlocked sandbox copy), the real files they check, the `darkequiv` rows in `scripts/ci-push-dedupe.test.sh`, and `ci.yml` parsed whole (case-insensitive, whitespace-tolerant around `.` and `[`) for the step and its readers (the reader constant in `ci-head-verdict.sh` and the census constant in `ci-demand-census.sh` must equal the step name).

**Mutation matrix.**

| # | Mutation | Expect |
|---|---|---|
| G2-1 | lock absent in the sandbox copy and the `full-verified` subcommand deleted | `row_lock_coupling` RED |
| G2-2 | lock absent and the `full-battery-audit` job deleted from `post-merge-monitor.yml` | RED |
| G2-3 | lock absent and the `pr-affected-active` step deleted, renamed or moved to another job in `ci.yml` | RED (name coupling) |
| G2-4 | the coupling row runs zero checks (the artifact list empty) | anti-vacuity floor RED |
| G2-5 | the `admin-merge-ready.sh` call site removed but the other four artifacts kept | RED (second member after a compliant first) |
| G2-6 | the arm drops the `would_skip != none` term with the switch `on` and an empty set | `row_empty_skippable` RED |
| G2-7 | a gated job's `if:` edited so an empty or garbled `skip_legs` or `head_sha` no longer evaluates to run | the `darkequiv` evaluator RED |
| G2-8 | the natural repair of a red coupling row: the subcommand or the audit replaced by an empty executable stub | RED: both are EXECUTED against the shared fixture and must answer correctly |
| G2-9 | the step `if:` made unconditional (`always()`) | RED |
| G2-10 | a second step with the same name added after a compliant first | RED |

Harness rows: H3 break the coupling row's own artifact list and require RED; H6 delete each census regex arm in turn and require a red row (no arm is redundant). Must-PASS non-canonical: the real tree with the lock present and every artifact present; the step name quoted in single and in double quotes. Anchor: the pin and the lock are in one diff, so a weakening PR can edit both; the outside anchors are Guard 4 (reads the live variable, the receipt and prerequisite 5) and `merge_group`. Order: the commit order (lock last) is checked by AC11 with `git log`, not by a suite, because a suite sees only the final tree.

### Guard 3 — audit probe

**Property.** Every commit on `main`'s first-parent history in the sweep window that has neither a successful `merge_group` run nor a full-verified PR head run (nor a verified carryover chain, nor a monitor revert) produces exactly one deduped escape issue; a queue merge produces none; a sweep that examined no commit is an error.

**Assembly.** `ci-full-battery-audit.sh` is the chokepoint; the workflow job only invokes it and passes the window; the issue filer is one function.

**Mutation matrix.**

| # | Mutation | Expect |
|---|---|---|
| G3-1 | a bypass merge (no `merge_group` run, reduced PR run, full push run green) | one issue filed, push outcome in the body |
| G3-2 | a queue merge (`merge_group` success, every gated leg executed) | no issue |
| G3-3 | the sweep stops after the first commit; a second bypass follows a compliant first | second still filed (stop-early mutant RED) |
| G3-4 | the commit list is empty because the API call failed | exit non-zero |
| G3-5 | run twice on the same SHA | still one issue (dedupe) |
| G3-6 | more than 100 runs for a SHA (pagination) | verdict unchanged |
| G3-7 | a direct revert pushed by the `monitor` job (no PR); a PR-less non-monitor commit | revert silent, other filed |
| G3-8 | the event is a `workflow_run` from a fork branch named `main` (`workflow_run.event` not `push`) | job skipped, no issue |

Harness rows: H4 delete the dedupe lookup in the suite's stub and require G3-5 RED; must-PASS non-canonical: a squash-merged commit whose PR is found through `commits/{sha}/pulls` selecting the entry whose `merge_commit_sha` matches. Anchor: GitHub's runs API is the outside source of truth; the label and issue are the only write.

### Guard 4 — pre-activation gate script

**Property.** The script prints `ready=true` only when every prerequisite is positively read as met; any API failure, any unreadable answer and any missing prerequisite is listed in `missing=` and yields `ready=false`.

**Assembly.** One list of at most six prerequisites iterated by one loop; each reader returns `ok`, `unmet` or `unknown`; the final line is computed from the list, never from the first failure, and `ready=true` requires `ok_count == total > 0`.

**Mutation matrix.**

| # | Mutation | Expect |
|---|---|---|
| G4-1 | the organization-variables endpoint returns 403, then `total_count` 1 | `ready=false`, named in `missing=` |
| G4-2 | the ADR has no prerequisite-5 amendment (empty skippable set) | `ready=false` |
| G4-3 | the receipt's machine line says NO-GO, UNDECIDED, `ruled=pending`, is absent or is older than 60 days | `ready=false` |
| G4-4 | the lock is present, or the newest `full-battery-audit` run on `main` did not conclude `success` | `ready=false` |
| G4-5 | two prerequisites unmet after a met one | both listed |
| G4-6 | the prerequisite list is empty (dispatch) | exit non-zero (anti-vacuity) |
| G4-7 | the variable read returns a non-404 error | `unknown`, `ready=false` |
| G4-8 | the natural repair of G4-2: the amendment heading is added with an empty or `none` skippable set | `ready=false` |

Harness rows: H5 remove one reader from the loop in the suite and require RED; must-PASS non-canonical: every prerequisite `ok` with the variable absent returns `ready=true`. Anchor: the gate reads live state (GitHub variable, organization variables, run conclusions) and the receipt path recorded in the ADR; explicit operator authorization stays a human step the script cannot satisfy.

## Test Scenarios

- Variable unset, doc-only or code diff: `pr-selection` skipped, every battery leg runs, `test` green; `scripts/required-checks.txt` unchanged.
- Variable `on`, lock absent, empty skippable set: `active=false`, empty `skip_legs`, every leg runs.
- Reduced run (a gated job skipped): `full-verified` is `no`; `admin-merge-ready.sh` is NOT-READY `reduced-run`; the audit files one issue for a bypass merge of it.
- Queue merge: the audit is silent.
- Draft run then ready run: the draft run is never verified; the ready run is.
- `gh run rerun <id> --failed` on an attempt that cached a skip: the aggregator names the all-jobs remedy; ship's carve-out uses the same words.
- Gate script with the organization endpoint returning 403: `ready=false`, `unknown`.
- Replay fixture set: an escape on a would-skip suite, a retry-cleared flake, a not-evaluable commit, the PR 9404 shape.

## Sharp Edges

- **This PR is UNTRUSTED-CI in stage 2.** No agent `--admin`. BEHIND livelock: ask the user to merge. Auto-merge armed and BEHIND: wait for the queue to enqueue; never sync, update-branch or merge by hand (a push restarts CI and dequeues it).
- **Draft PRs are red by design** (Option R, `draft-light`): this draft's `test` failure and skipped `test-webplat` are not evidence about stage 2; read the ready run.
- **Do not add `knowledge-base/` path literals** to the replay, gate script or their suites (the kb-consumer census, `scripts/test-affected-kb-consumers.baseline.txt`); pass receipt paths by argument.
- **A mutant that kills nothing is not a kill.** Remove the guard and require the named row to fail; record equivalent mutants as equivalent. A sandbox is not a git repo: `git init -q && git add -A` first.
- **Floors are measured, not estimated**, from a full green run of each edited suite, and listed with the run.
- **Local `test-all.sh --affected` degrades to full** here (the runner, index and `ci.yml` are edited) and under load times out; CI's battery is the merge authority; capacity first.
- **A budget-capped timing is a lower bound.** The canary passes are separate steps with no driver budget; read times from the jobs API.
- **Run records have a lifetime.** The replay and the audit decide from run and job records (90-day retention, step lists strip at about 170 days, manual deletion possible): state the OLDEST listed run live in the receipt, never infer it from a setting, and keep the receipts committed because the logs expire. The audit window (24 hours) and the replay window (300 first-parent commits, about two weeks) are inside retention today; a replay re-run later is not.
- **Never query `actions/runs?head_sha=` for a CI verdict.** Use `actions/workflows/ci.yml/runs?head_sha=`; the unfiltered endpoint returns unrelated `workflow_dispatch` runs at that SHA and truncates at `per_page`.
- **Units in every figure:** billed minutes versus raw job-minutes, per executed job versus per run, and the sample window.
- **The replay runs against today's index** for older diffs (a recorded limit); a replay that cannot measure a commit classes it not-evaluable, counted in the worst case.
- **`activation` text:** this plan never writes a command that sets the variable; the gate script prints readiness, authorization is a human act.
- A plan whose `## User-Brand Impact` is empty or omits the threshold fails `deepen-plan` Phase 4.6; this plan carries the section and `requires_cpo_signoff: true`.

## Plan Review Log

Seven seats reviewed this plan on 2026-10-15: DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer, the CPO and the CTO (devex lens). Mechanical findings were applied: the cheap-kill sample first (Phase 1.0), the worst-case-numerator bound, the `full-verified` shape table (a skipped `pr-selection` is the normal state, no light-draft qualifier, `CHECK_SHA`, check-suite binding, clause (a) for main SHAs and (b) for PR heads), the audit's push-run, revert, carryover and fork-trigger handling, the vehicle ordering and transport, the AC11 and Phase 4 contradictions, the unlocked-sandbox coupling row, the declared-inputs entry, Guard 5 folded into Guard 2, the closed sweep regex and census test, the gate script's machine verdict line and six readers, ADR-270 amendments, and the activation-lane runbook. Taste and user-challenge items are in `knowledge-base/project/specs/feat-one-shot-9729-ci-pr-c-affected-only/decision-challenges.md`; the main one is whether stage 2 or the lock removal belongs to PR D (five seats said yes; the operator's brief is the default). CPO: APPROVED-WITH-CONDITIONS, conditions 1 to 3 folded, condition 4 recorded as that challenge.
