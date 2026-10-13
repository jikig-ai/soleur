---
title: "fix: ship/postmerge select the deploy arm by what resolve-target deploys, not by head_sha"
date: 2026-09-21
slug: fix-deploy-arm-selection-by-resolve-target
branch: feat-one-shot-8492-deploy-arm-by-resolve-target
issue: 8492
closes: 8492
type: bug
lane: cross-domain
domain: engineering
priority: p2
brand_survival_threshold: aggregate pattern
---

# fix: ship/postmerge select the deploy arm by what resolve-target deploys, not by head_sha

## Enhancement Summary

**Deepened on:** 2026-09-21
**Sections enhanced:** Proposed Solution, Technical Considerations, Files, Architecture Decision
(new), Observability, Guard Contract, Acceptance Criteria, Test Scenarios, Dependencies & Risks
**Agents used:** repo-research-analyst, learnings-researcher, dhh-rails-reviewer,
kieran-rails-reviewer, code-simplicity-reviewer, cto (devex), test-design-reviewer,
spec-flow-analyzer, observability-coverage-reviewer, architecture-strategist, a verify-the-negative
pass, and the Step 4.5 advisor consult.

### Key Improvements

1. `find` now reports the deploy outcome (`DEPLOY=success|failure|pending|skipped|blocked|superseded`)
   and the merge's CI result, so a lock-cancelled or verify-blocked deploy can no longer read as a
   designed skip, and a CI re-run cannot be judged on attempt 1's arm.
2. Postmerge runs `find --wait` and `served` in Phase 3 for every merge, with a table that gives
   every `find` × `served` combination a defined result; ship delegates to the same script and to
   the same polling cap.
3. The script is testable end to end: time and sleep seams, a `gh` stub that runs the script's own
   `--jq` and models pagination and 404s, 31 scenarios, and a scripted mutation driver.

### New Considerations Discovered

- Both skills forbid `$()` in Bash calls; the old Phase 3.7 query violated it, and the first
  drafted replacement would have too.
- The shared `web-1-swap` and `migrate-web-platform` locks cancel queued deploys on a busy `main`,
  which GitHub records as `cancelled`/`skipped` — indistinguishable from a docs-only skip without
  reading the upstream jobs.
- Preflight Check 10 will SKIP this plan's discoverability probe (no sensitive path), so the probe is
  exercised by an `env -i` acceptance criterion instead.

## Overview

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

The postmerge and ship skills find a merge's production deploy run by asking the GitHub API for
`web-platform-release.yml` runs with `event=workflow_run` and `head_sha=<merge>`. For a
`workflow_run`-triggered run, that `head_sha` is the tip of `main` when the run fired, not the commit
the run deploys. The lookup therefore misses the real deploy run on a busy `main`, and can return the
previous merge's run instead. This plan replaces the selection rule with one keyed on the SHA that the
run's `resolve-target` job actually checks out, and relaxes the `/health` `build_sha` check to accept
any later build that contains the merge.

The predicate moves out of SKILL.md prose into one small, tested script
(`plugins/soleur/scripts/deploy-arm.sh`). That is forced, not stylistic: both
SKILL.md files sit just under their `lint-skill-body-budget` ceilings (measured below), so the fix has
to make them *shorter*, and a script is the only form a test can hold to the new rule.

## Problem Statement

Measured on `origin/main` (`plugins/soleur/skills/postmerge/SKILL.md` Phase 3.7, lines 297-373;
`plugins/soleur/skills/ship/SKILL.md` lines 26 and 2467-2469):

- **Primary selector is wrong.** `postmerge/SKILL.md:336` selects
  `actions/runs?head_sha=${MERGE_SHA}&event=workflow_run` and takes `[0]`.
  `ship/SKILL.md:26` and `:2469` prescribe the same query.
- **False positive (#8391).** The arm triggered by the *previous* merge's CI completion fires after
  `main` moved to your merge, so GitHub stamps it `head_sha=<your merge>`. The API lists it first. It
  is fully green and deployed someone else's commit.
- **False negative (#8297).** If another PR merges before your CI completes, your real arm is
  stamped with *that* PR's SHA and the `head_sha=<your merge>` query returns nothing.
- **Served-SHA check too strict.** `ship/SKILL.md:26` requires `/health` `build_sha == merge sha`;
  `postmerge/SKILL.md:114` requires "the expected `build_sha`". Once a later merge deploys, the live
  build is a descendant of your merge, which is still a successful delivery of your commit.
- Both failure modes are documented today only as bolt-ons: a paragraph plus bash block
  (`postmerge/SKILL.md:299-316`) and a 1.3 KB fallback sentence inside the `absent` row
  (`:373`). The primary predicate is unchanged.

## Research Insights

**Premise Validation.** #8492 is OPEN, no closing PR. Cited sites confirmed on `origin/main`:
`postmerge/SKILL.md:336` (selector), `ship/SKILL.md:2469` (selector), plus `ship/SKILL.md:26` and
`:2467` and `postmerge/SKILL.md:112-114` (served-SHA equality). Cited mechanism confirmed live against
run `35577957665` (see reconciliation table). ADR corpus: ADR-217 defines the split topology and
already notes `resolve-target` asserts `head_sha` against the event; it does not prescribe how
*consumers* select an arm, so no ADR is contradicted. Incidents #8297 and #8391 are merged fallbacks,
not fixes of the primary predicate — the premise holds.

**Property List.**
1. P1 — Given a merge SHA, the verifier names the deploy-arm run that deployed that merge, or a later
   run whose deployed tree contains it.
2. P2 — The verifier never names a run that deployed an older commit (the #8391 false positive).
3. P3 — The verifier finds the arm even when `main` moved before the merge's CI completed (#8297).
4. P4 — The served-build check passes when production serves the merge or a descendant of it.
5. P5 — "Could not measure" (unreadable log, unfetched SHA, empty `/health`) is reported as such,
   never as a mismatch or a match.
6. P6 — ship and postmerge state one predicate, and a test fails if either drifts back to `head_sha`.

**Cut List.**
- Time-adjacency matching ("created within seconds of CI `updated_at`", `postmerge/SKILL.md:373`) →
  was a proxy for P1/P3 → covered exactly by the resolve-target SHA predicate; cut.
- `gh run view <id> --log | grep -c <merge-sha>` (whole-run log grep, `:373`) → proxy for P1 →
  the resolve-target `depth=1 origin` line is the exact identity; cut (it also matches arms that merely
  *mention* the SHA).
- `head_sha=` query as the selector → P1 fails under it → demoted to a first-guess candidate source,
  per the issue.
- A separate helper for `/health` → P4 needs the same ancestry logic as P1 → folded into the same
  script as the `contains` subcommand (one chokepoint).

**Value measurement.** Not a cost/performance justification; 0.6c does not fire.

**Relevant files.**
- `plugins/soleur/skills/postmerge/SKILL.md:95-125` (Phase 3), `:285-380` (Phase 3.7)
- `plugins/soleur/skills/ship/SKILL.md:26`, `:2467-2469`
- `.github/workflows/web-platform-release.yml:207-264` (resolve-target, pinned checkout)
- `scripts/lint-skill-body-budget.py`, `plugins/soleur/test/skill-body-budget.json`
- `plugins/soleur/test/workflow-run-deploy-invariants.test.sh:853-905` (Guard 8)
- `plugins/soleur/test/lib/git-fixture-env.sh` (throwaway repos with identity; call in the parent
  shell, never through `$( )` — its exported identity dies with the subshell, per the 2026-09-20
  learning)
- `gh` stub patterns: `plugins/soleur/test/issue-flow-measure.test.sh:101-128` (dispatch on `"$*"`,
  `--jq` handling, call log), `plugins/soleur/test/operator-script.test.sh:147-168`
- Script-call convention: `bash "${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/skills/<skill>/scripts/<x>.sh"`
  (`ship/SKILL.md:385`)

**Institutional learnings.**
- `2026-09-20-the-deploy-arm-that-said-success-had-deployed-someone-elses-commit.md` — root cause,
  the resolve-target log recipe, `--allow-escape-sequences` necessity, `app.soleur.ai` host, ship's
  body budget being the reason the #8391 fix landed only in postmerge.
- `2026-09-20-every-defect-in-my-fix-was-a-sentence-i-could-have-run.md` — commands written in prose
  ship unvalidated; hence the script plus test rather than more SKILL.md bash.
- `2026-05-20-test-stubs-env-and-csp-gates-miss-runtime-bugs.md` — a `gh` stub is blind to real API
  shape; hence the live read-only smoke AC against a known run.
- `2026-08-11-the-pr-that-fixed-narrow-guards-shipped-three-narrow-guards.md` — both candidate sources
  must flow through the one classifier (Guard Contract assembly).

**CLI verification.** `gh api --help` lists `--allow-escape-sequences` (verified 2026-09-21, gh
local). `created=>=<ISO>` filter verified against the live API (returned `total_count` 30 for
`>=2026-09-20T00:00:00Z`). `git merge-base --is-ancestor` rc 0/1/128 semantics per git docs and the
`postmerge/SKILL.md:373` note.

**Related issues/PRs.** #8297, #8391, #8265, #8276, #8135 (short-SHA empty set), #8450 (CI
concurrency — explains queued arms), #8490 (open issue whose parallel fix touches `worktree-manager.sh`; out of scope).

## Research Reconciliation — Spec vs. Codebase

| Claim (issue #8492) | Reality on `origin/main` | Plan response |
|---|---|---|
| `resolve-target` logs `depth=1 origin <sha>` | Confirmed live: run `35577957665`, job `106263967678` log contains `depth=1 origin 71e7585e…` once and `resolving deploy target for 71e7585e…` once. The checkout is pinned to `github.event.workflow_run.head_sha` (`web-platform-release.yml:262-264`), i.e. the *triggering CI run's* SHA, which is the commit deployed. The checkout step precedes the resolve step, so the line is present even when resolve-target clean-skips. | Key on the `depth=1 origin` line (first match). |
| `gh api` needs `--allow-escape-sequences` | Confirmed: same job log without the flag exits rc=1 with zero bytes. | Script always passes the flag; the test's `gh` stub reproduces the rc=1/empty behaviour so dropping the flag reds a row. |
| "any test/fixture pinning the old predicate" | `git grep` for `head_sha=${MERGE_SHA}`, `GATE-INDETERMINATE`, `DEPLOY_JOB_STATE`, `build_sha ==`, `Chosen predicate` outside `knowledge-base/` hits only `postmerge/SKILL.md` and `ship/SKILL.md`. `workflow-fidelity.test.ts:298-307` pins only the protocol sentinels, not the predicate. `workflow-run-deploy-invariants.test.sh` Guard 8 pins arm disambiguation (event name present), which the new script satisfies. | No existing fixture to update; the plan ADDS the fixture that pins the new predicate. |
| ship ~line 2469, postmerge ~line 336 | Exact. Also ship line 26 (merge→deploy protocol step 2), ship line 2467 (`/health` "expected `build_sha`"), postmerge line 112/114 (Phase 3 health). | All five sites in scope. |

## Proposed Solution

[Updated 2026-09-21 after plan review and deepen-plan — see `## Plan Review Revisions` and
`## Deepen-Plan Revisions`.]

### 1. New script: `plugins/soleur/scripts/deploy-arm.sh`

**Placement and invocation.** `plugins/soleur/scripts/` is the shared home for shell helpers that
shipped skills call (ADR-178; `sync-pr-behind.sh` is the precedent ship already uses). Both SKILL.md
files call it **repo-relative**, `bash plugins/soleur/scripts/deploy-arm.sh …` — the same form as
`ship/SKILL.md:30` — never through `$(…)`, because both skills forbid command substitution
(`postmerge/SKILL.md:31`, ship's matching rule). Postmerge already runs from a detached
`origin/main` worktree, so the script it runs matches the workflow that deployed. The script never
`cd`s to its own directory.

**Output contract.** stdout carries exactly one verdict line, always, including on errors; every
`git`/`gh` message and one diagnostic line per candidate go to stderr
(`deploy-arm: candidate <id> class=<exact|descendant|reject|pending|unresolved|dropped> sha=<D|-> cause=<…>`).
`set -Eeuo pipefail` with an `ERR` trap that prints `ARM=none REASON=error CAUSE=internal` (or the
subcommand's error token) plus `line=$LINENO cmd=<verb only>` on stderr and exits 2 — so rc 1, 3 and
4 are never produced by a crash. Agents read the stdout line literally and act on its tokens; the
rc is a convenience. **Scope guard:** if `$(git rev-parse --show-toplevel)/.github/workflows/web-platform-release.yml`
does not exist, every subcommand prints `… REASON=not_applicable` and exits 3 (the script is bound to
this repo's pipeline; in any other repo postmerge falls back to its generic health check).

**Test seams.** "Now" is read once from `${DEPLOY_ARM_NOW:-$(date +%s)}` and the `--wait`/retry
sleeps from `${DEPLOY_ARM_SLEEP:-1}` (a multiplier; 0 in tests), so the 10-minute, 3-minute and
polling rules are testable without waiting.

#### `deploy-arm.sh find [--wait [MIN]] <MERGE_SHA>`

| stdout | rc | meaning / caller action |
|---|---|---|
| `ARM=<id> DEPLOYED_SHA=<sha> MATCH=exact\|descendant DEPLOY=<state> CI=<merge CI conclusion>` | 0 | a deploy-arm run is identified and its `deploy` outcome is final |
| same line with `DEPLOY=pending` | 4 | arm identified, `deploy` not concluded — call `find` again (never `gh run view`: a superseded arm must hand off to its descendant) |
| `ARM=none REASON=ci_pending` | 4 | poll: the merge's `ci.yml` push run is not completed, or not created yet |
| `ARM=none REASON=arm_pending` | 4 | poll: a candidate that could still be the answer has not finished `resolve-target`, or its log is inside the 3-min grace |
| `ARM=none REASON=ci_absent` | 3 | stop: no `ci.yml` push run 10+ min after the merge landed, and no descendant arm has delivered it |
| `ARM=none REASON=no_candidate` | 3 | stop: CI completed, every candidate read, none qualifies |
| `ARM=none REASON=unresolved CAUSE=log_read_failed\|log_line_absent\|ancestry_128\|cap_hit` | 3 | stop: could-not-measure, never a mismatch |
| `ARM=none REASON=timeout LAST=<reason>` | 3 | `--wait` cap reached |
| `ARM=none REASON=not_applicable` | 3 | not the soleur repo |
| `ARM=none REASON=error CAUSE=bad_input\|missing_dep:<cmd>\|not_on_main\|gh_failed\|internal` | 2 | error |

`DEPLOY` values:

| `DEPLOY` | derived from the arm's jobs | treated as |
|---|---|---|
| `success` / `failure` | `deploy` conclusion | delivered / real deploy failure |
| `pending` | `deploy` not completed | poll |
| `skipped` | `deploy` skipped AND `resolve-target` concluded `success` AND no job in the run concluded `failure`/`cancelled` — the designed clean skip (docs-only, or `ci_not_green` when `CI=failure`) | nothing deployed by design |
| `blocked` | `deploy` skipped AND `resolve-target` or a job it waits on (`migrate`, `verify-migrations`, `verify-doppler-secrets`) concluded `failure` | real non-delivery |
| `superseded` | `deploy` (or a job it waits on) concluded `cancelled` — the shared `web-1-swap` / `migrate-web-platform` locks keep one pending job, so a busy `main` cancels queued deploys (`web-platform-release.yml:868-870`, `:1115-1117`) | a later arm carries the delivery |

**`--wait [MIN]`** loops inside the script: re-evaluates every 60 s while the verdict is rc 4, prints
one progress line per iteration to stderr, and stops at the first rc 0/2/3 verdict or after `MIN`
minutes (default 120) with `REASON=timeout`. One cadence and one cap for both skills; callers run it
as a background command and act on its single completion. Without `--wait`, one evaluation.

Algorithm (one evaluation):

1. Scope guard; validate `MERGE_SHA` against `^[0-9a-f]{40}$` (a short SHA matches nothing, #8135);
   require `gh`, `git`, `jq`. Default branch `B` = `git symbolic-ref --short refs/remotes/origin/HEAD`
   minus `origin/`, falling back to `main`.
2. **The merge's CI run.** `gh api "repos/{owner}/{repo}/actions/workflows/ci.yml/runs?head_sha=$MERGE_SHA&event=push&per_page=10"`
   (for a push run, `head_sha` *is* the commit). Newest run: keep `status`, `conclusion`,
   `created_at`, `run_started_at`, `run_attempt`. None found → after step 3's fetch, `ci_pending` if
   the merge's committer time is under 10 minutes before "now", else note `ci_absent` and continue
   (a descendant may still deliver it). Window lower bound `T` = the CI run's `created_at`
   (server-stamped; no skew margin), or the merge's committer time via `jq -rn --argjson t <epoch> '$t|todate'`
   when there is no CI run.
3. **Candidates** (the union, de-duplicated by run id):
   - **first guess** — `repos/{owner}/{repo}/actions/runs?head_sha=$MERGE_SHA&event=workflow_run&per_page=100`,
     filtered to `.path == ".github/workflows/web-platform-release.yml"` — today's query, kept as
     the fast path the issue asks for (step 6), never trusted on its own;
   - **window** — `gh api --paginate "repos/{owner}/{repo}/actions/workflows/web-platform-release.yml/runs?event=workflow_run&created=%3E%3D$T&per_page=100"`.
   `--jq` runs per page, so emit one `created_at<TAB>id<TAB>status<TAB>conclusion` line per run and
   `sort` the combined stream afterwards. Cap at 30 candidates (`CAUSE=cap_hit` past it). Then
   `git fetch -q origin "$B"` — **after** listing, so every SHA an already-listed arm checked out is
   local (every arm fires on `branches: [main]`, `web-platform-release.yml:76-79`). A failed fetch is
   not fatal; ancestry then runs on what is local and rc 128 means `unresolved`.
4. **Per candidate** (jobs from `.../runs/<id>/jobs` with `--paginate`, one stream):
   - run concluded `cancelled`/`startup_failure` with no completed `resolve-target` → *dropped*;
   - `resolve-target` not completed → *pending* (it can complete while the run still queues for
     `deploy` — observed on run `35592848323` — so the job decides, not the run);
   - else read `gh api --allow-escape-sequences ".../actions/jobs/<resolve-target id>/logs"` into a
     temp file, up to 3 attempts with 2/4 s backoff, checking `gh`'s rc on its own (a 404 prints its
     JSON error body to stdout and exits 1, so a non-empty file is not success), then
     `grep -m1 -oE 'depth=1 origin [0-9a-f]{40}'` on the file — never `| head -1` under `pipefail`,
     which can SIGPIPE the reader and fake an empty read. Line absent → try the workflow's own
     `resolving deploy target for [0-9a-f]{40}`. Read failed within 3 min of the job's
     `completed_at` → *pending*; later → *unresolved* (`log_read_failed`); read fine but no line →
     *unresolved* (`log_line_absent` — the `actions/checkout` output format changed);
   - classify SHA `D`: `git merge-base --is-ancestor MERGE_SHA D` rc 0 → *exact* if `D == MERGE_SHA`
     else *descendant*; rc 1 → *reject*; rc 128 → *unresolved* (`ancestry_128`);
   - for exact/descendant, derive `DEPLOY` from the jobs already fetched (table above).
5. **Verdict** — the first rule that yields a run wins:
   0. CI run exists and is not completed → `ci_pending` (an exact arm cannot be final before the
      merge's own CI is; this also covers a CI re-run in progress).
   1. **Exact** — the newest exact arm created at or after the CI run's `run_started_at` (so a
      re-run's arm replaces attempt 1's) with `DEPLOY` in `success|failure|blocked|pending`. With
      `run_attempt > 1`, a pending candidate created after it forces `arm_pending`. If CI completed
      but no exact arm exists yet created after `run_started_at` → `arm_pending` (the arm is created
      seconds after CI completes).
   2. **Descendant** — the earliest descendant with `DEPLOY` in `success|failure|blocked|pending`,
      provided no *pending* or *unresolved* candidate was created before it (the merge's own arm
      may be that candidate); otherwise `arm_pending` / `unresolved`.
   3. **Exact, not delivered** — the newest exact arm with `DEPLOY` `skipped` or `superseded`, and
      no later candidate pending (else `arm_pending`).
   4. No run: `arm_pending` if any candidate is pending; `unresolved` if any is unresolved or the
      cap was hit; `ci_absent` if noted in step 2; else `no_candidate`.
6. **Fast path.** When `run_attempt` is 1 and CI is completed, classify first-guess candidates first
   and stop at the first readable exact arm whose `DEPLOY` is not `skipped`/`superseded`: 4 API
   calls (CI run, first guess, jobs, log) on an unbusy `main`.

#### `deploy-arm.sh contains <MERGE_SHA> <BUILD_SHA>`

Pure ancestry, needs only `git`. Input checks first, no network: `BUILD_SHA` empty, `dev` or not
40-hex → `UNRESOLVED` (rc 3); `BUILD_SHA == MERGE_SHA` → `CONTAINS` (rc 0). Then a non-fatal
`git fetch -q origin "$B"`, then ancestry: rc 0 → `CONTAINS` (rc 0), rc 1 → `NOT_CONTAINED` (rc 1),
rc 128 → `UNRESOLVED` (rc 3). Errors → `ERROR CAUSE=…` (rc 2).

#### `deploy-arm.sh served <MERGE_SHA> [URL]`

Probes `URL` (default `https://app.soleur.ai/health` — the canonical host,
`web-platform-release.yml:1288`; the apex returns an empty body, #8391) with
`curl -s --max-time 10`, up to 3 attempts, extracts `.build_sha` with `jq`, and prints the
`contains` verdict followed by ` BUILD_SHA=<sha|->`. An empty or non-JSON body → `UNRESOLVED`.
This keeps the curl-and-parse out of the SKILL.md files, so no caller needs `$(…)`.

### 2. `plugins/soleur/skills/postmerge/SKILL.md`

- **Phase 3 (lines ~95-125):** for this repo, run
  `bash plugins/soleur/scripts/deploy-arm.sh find --wait <merge-sha>` (background, one
  completion), then `bash plugins/soleur/scripts/deploy-arm.sh served <merge-sha>`, and set
  `HEALTH_VERIFIED` from this table (the `supabase == "connected"` requirement stays):

  | `find` | `served` | result |
  |---|---|---|
  | `DEPLOY=success` | `CONTAINS` | verified (`MATCH=descendant` → "delivered by `<D>`") |
  | `DEPLOY=success` | `NOT_CONTAINED` | not verified — deploy reported success but production does not serve the merge (lagging host or a later rollback); report prominently |
  | `DEPLOY=failure\|blocked` | any | not verified — real deploy failure; report the job |
  | `DEPLOY=skipped` | any | not deployed by design (`CI=failure` → CI red, see Phase 2) |
  | `DEPLOY=superseded` or rc 3 `ARM=none` | `CONTAINS` | verified — delivered by a later deploy (covers a manual `workflow_dispatch` redeploy, which `find` does not select) |
  | rc 3 `ARM=none` | `NOT_CONTAINED\|UNRESOLVED` | not verified — report the `REASON`/`CAUSE` |
  | any | `UNRESOLVED` | could-not-measure, never a mismatch |

  Replaces "The `build_sha` field also confirms the merge commit is the live build" and "(and the
  expected `build_sha`)". Other repos keep the generic `curl …/health` check.
- **Phase 2 failure branch (CI red on the merge):** add one sentence — ship already refuses
  post-deploy actions when `CI=failure` (§3), so both skills agree: report CI red, and if `find`
  shows a descendant `DEPLOY=success`, say production carries the merge via `<D>`.
- **Phase 3.7 gate regex (`:283`):** extend to
  `plugins/soleur/skills/(ship|postmerge)/SKILL\.md|plugins/soleur/scripts/deploy-arm\.sh`, so a
  future edit of the predicate alone still opens the watch.
- **Phase 3.7 body:** replace the "Chosen predicate" sentence (`:297`), the false-positive paragraph
  and bash block (`:299-316`), the "Select by the merge SHA, never by recency" paragraph (`:324`),
  the `RELEASE_RUN_ID=$(gh api …)` query block (`:326-337`, which also violated the skill's own
  no-`$()` rule) and the sibling-merge fallback in the `absent` row (`:373`) — measured **5,544
  bytes** of removable text — with:
  - one sentence of rule: identify the arm by what `resolve-target` checks out; a `workflow_run`
    run's `head_sha` is `main`'s tip at trigger time (#8297, #8391, #8492);
  - reuse of Phase 3's `find` line: take the digits after `ARM=` literally into the next call; if
    the line starts `ARM=none`, there is no run — never pass `none` to `gh run view`;
  - `DEPLOY` replaces the `DEPLOY_JOB_STATE` lookup; the rollback-reason grep still reads
    `gh run view <id> --log`;
  - interpretation by match type: `exact` + `success` → `GATE-VALIDATED`; `descendant` + `success`
    → `GATE-VALIDATED (via <D>, run <id>)`; `descendant` + `failure` → `GATE-SUSPECT`, listing
    `git log --oneline <merge>..<D>` beside the PR's gate diff (the failure may be the later
    merge's), without "revert immediately"; `skipped` → `GATE-NOT-EXERCISED`; `superseded`/
    `blocked` → `GATE-INDETERMINATE — <DEPLOY>`; rc 3 → `GATE-INDETERMINATE — <REASON> <CAUSE>`.
  Keep: the push-arm/deploy-arm table, the `live-verify` step-list warning and the `app.soleur.ai`
  host note, the rollback interpretation rows, and one compressed "Why" line (#8265, #8297, #8391).
  If the budget still binds, move the #8391/#8297 narratives to
  `postmerge/references/deploy-status-debugging.md`.
- **Phase 4 note at `:468`** stays (push-event `head_sha` is the commit).

### 3. `plugins/soleur/skills/ship/SKILL.md` — delegate, do not restate

Drafted replacements, measured against `origin/main` (net **−212 bytes**):

| Site | New text | Δ bytes |
|---|---|---|
| line 26, arm selector (replaces ``(`event=workflow_run` on the FULL 40-char merge sha; … #8135)``) | ``(`bash plugins/soleur/scripts/deploy-arm.sh find --wait <full-merge-sha>` — never `head_sha=` alone, #8492; the push arm only builds)`` | −43 |
| line 26, served SHA (replaces ``require `/health` `build_sha == merge sha` ``) | ``require `CI=success` and `deploy-arm.sh served <merge>` → `CONTAINS` `` | +28 |
| line 26, deploy outcomes | append: ``; any other `DEPLOY`/`ARM=none` → step 3 reports it`` | +53 |
| line 2467 (replaces ``​`/health` 200 with the expected `build_sha` ``) | ``​`deploy-arm.sh served` → `CONTAINS` `` | −6 |
| line 2469 bullet | "**Two runs per merge is normal.** `event=workflow_run` is the deploy arm, `event=push` the build. Find the deploy arm with `deploy-arm.sh find <full-merge-sha>`, never a `head_sha=` query or `--limit 1`: a deploy-arm run's `head_sha` is `main`'s tip when it fired, so it misses your arm and returns the previous merge's. See `postmerge/SKILL.md` Phase 3.7." | −244 |

The implementer re-measures with the lint before committing; these deltas were computed against the
current file and are the budget the edit must stay within.

### 4. `knowledge-base/engineering/architecture/decisions/ADR-217-…md` — dated addendum

One short addendum under `## Consequences` (via `soleur:architecture`): Consequence 7's "a consumer
disambiguates the two arms by event" is necessary but not sufficient — *which merge* a deploy-arm run
delivered comes from the SHA its `resolve-target` checked out, never from the run's `head_sha`;
`plugins/soleur/scripts/deploy-arm.sh` is the single place this is decided; it depends on the
`actions/checkout` fetch line and the workflow's `resolving deploy target for` echo (pinned by static
rows in the test).

### 5. New test: `plugins/soleur/test/deploy-arm.test.sh`

Auto-discovered by `scripts/test-all.sh` (`plugins/soleur/test/*.test.sh`, line 78).

**Fixture.** A bare `origin` reached through a `file://` URL plus a clone (a plain-path clone
hard-links the object store, so a "missing" commit is present — measured: rc 0 vs rc 128), rebuilt
per scenario so one row's fetch cannot leak into another. Commits: `A` (previous merge) → `M` (this
merge) → `D` (descendant) on `main`, `X` on an unrelated branch; `M`'s committer date set with
`GIT_COMMITTER_DATE="@$((NOW-900)) +0000"` where a row needs an old merge. `DEPLOY_ARM_NOW` is pinned
and every fixture timestamp is rendered relative to it with `jq todate`. `git_fixture_env`
(`plugins/soleur/test/lib/git-fixture-env.sh`) is called in the parent shell, never inside `$( )`.

**The `gh` stub** (pattern: `plugins/soleur/test/issue-flow-measure.test.sh`): records every argv;
serves job logs only with `--allow-escape-sequences` (otherwise rc 1, zero bytes — the measured
behaviour); serves page 2 of the window only with `--paginate`; applies the script's own `--jq`
expression with real `jq -r` to each page, so the script's filters and field extraction are what is
tested; returns a 404 as real `gh` does (JSON error body on stdout, rc 1); can push a commit to the
bare origin as a side effect of the window call (S8); exits 64 on any unhandled endpoint. Fixture
JSON is pretty-printed and carries no `url` fields: Guard 8 of
`workflow-run-deploy-invariants.test.sh` greps `plugins/` line-by-line for
`workflows/[^ ]*web-platform-release[^ ]*/runs`, so any line of this test or the script that spells
that path must also carry `event=workflow_run`.

**Static rows**, scoped to exactly the named files (never repo-wide — this test contains the
forbidden strings as patterns); each row first asserts the file exists and is non-empty, and the
forbidden-pattern regexes are self-tested against positive and negative strings before use:

- `postmerge/SKILL.md` and `ship/SKILL.md` reference `deploy-arm.sh`;
- neither matches `head_sha=[^&" ]*&event=workflow_run`, `event=workflow_run&head_sha=`, or
  `--event workflow_run` next to `--commit` (does not match the push-run queries at
  `postmerge/SKILL.md:468`, `ship/SKILL.md:2114` — verified);
- neither contains ``expected `build_sha` `` or `build_sha == merge sha`;
- `postmerge/SKILL.md`'s gate regex includes `deploy-arm`;
- in `web-platform-release.yml`: the `resolve-target:` job has no `name:` override, its checkout
  `ref: ${{ github.event.workflow_run.head_sha || github.sha }}` line comes before its
  `id: resolve` step (line numbers compared within the extracted job block, failing if the block is
  not found), and `echo "resolving deploy target for $WR_HEAD_SHA"` still exists.

**Counting.** A `cases` counter bumped at each assertion, a self-test that `pass`/`fail` move their
own counters, `passes + fails == cases`, and a minimum-assertion floor — the
`issue-flow-measure.test.sh:36-60,249-270` pattern. Every `find` row asserts rc, that stdout is
exactly one line matching an anchored regex, and that `DEPLOYED_SHA` equals the fixture's generated
SHA.

**Mutation script.** `plugins/soleur/test/deploy-arm-mutations.sh` (run by hand, not in CI) applies
each Guard Contract row to a scratch copy, checks the mutant text actually changed, runs the suite
against the unmutated script first (must be green), and reports KILLED/SURVIVED per row.
## Technical Considerations

- **Body budget (hard constraint).** `scripts/lint-skill-body-budget.py --base origin/main` measures
  whole-file bytes against `plugins/soleur/test/skill-body-budget.json`: postmerge 47575/48000
  (425 B headroom), ship 273108/274000 (892 B). Raising a ceiling needs a separate budget-only PR.
  Ship: measured −212 B (§Proposed Solution 3). Postmerge: 5,544 B of removable text is measured
  (`:297` 800 B, `:299-316` 1,173 B, `:324` 880 B, `:326-337` 960 B, `:373` 1,731 B); the Phase 3
  table, the Phase 3.7 replacement and the gate-regex widening (+~35 B) must fit in that plus the
  425 B headroom. Run the lint before committing; the fallback is moving the #8391/#8297 narratives
  to `postmerge/references/deploy-status-debugging.md`.
- **No command substitution in SKILL.md.** Both skills forbid `$()` (`postmerge/SKILL.md:31`);
  the new text calls the script with literal arguments and tells the agent to carry the `ARM=` digits
  into the next call by hand. The deleted Phase 3.7 query block was itself a `$()` violation.
- **Guard 8 of `workflow-run-deploy-invariants.test.sh`** currently discovers 9 consumers; the
  script's window query adds a 10th, which carries `event=workflow_run` on the same line and passes.
  The deleted postmerge query never matched its discovery regex, so nothing drops out.
- **Rate cost.** Fast path: 4 calls. Worst case per evaluation: 3 list calls + 2-4 per candidate
  (jobs + up to 3 log attempts), capped at 30 candidates. `--wait` repeats this every 60 s; on a
  busy `main` that is ~10-20 calls a minute, well inside the 5,000/h authenticated budget.
- **Log-format dependency.** The key line is `actions/checkout`'s own fetch output. A change fails
  safe (`CAUSE=log_line_absent` → `GATE-INDETERMINATE`, never a false green); the workflow's
  `resolving deploy target for` echo is the second key; static rows pin the checkout `ref:`, the
  job name and the echo; the live smoke AC re-proves the format.
- **Manual redeploys** (`workflow_dispatch`) are not `workflow_run` runs and are never `find`
  candidates. Postmerge Phase 3 treats `served` → `CONTAINS` as delivery evidence even when `find`
  returns `ARM=none`, so a manual redeploy still verifies.
- **Not in scope:** `scripts/watch-live-verify-pass.sh` (selects recent arms with a live-verify pass,
  not a per-merge arm) and `postmerge/references/deploy-status-debugging.md` (re-runs the latest arm)
  do not key on `head_sha`. `web-platform-release.yml` is not edited (DC-1, DC-3).
  `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` is not touched (the parallel fix
  for issue #8490 edits it).

## Files to Create

- `plugins/soleur/scripts/deploy-arm.sh`
- `plugins/soleur/test/deploy-arm.test.sh`
- `plugins/soleur/test/deploy-arm-mutations.sh` (hand-run mutation driver; not `*.test.sh`, so
  `test-all.sh` does not pick it up)

## Files to Edit

- `plugins/soleur/skills/postmerge/SKILL.md` (Phase 2 failure branch; Phase 3 lines ~95-125; Phase
  3.7 gate regex `:283` and body `:297-373`)
- `plugins/soleur/skills/ship/SKILL.md` (lines ~26, ~2467, ~2469)
- `knowledge-base/engineering/architecture/decisions/ADR-217-the-deploy-fires-on-cis-completion-event-and-the-verdict-never-crosses-as-a-value.md`
  (dated addendum only)

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` bodies reference none of the planned paths
(re-checked after adding the ADR and the mutation driver).

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-217 with a dated addendum (no new ADR): *which merge a deploy-arm run delivered comes from
the SHA its `resolve-target` checked out, never from the run's `head_sha`; `deploy-arm.sh` is the
single place this is decided.* This extends Consequence 7 ("disambiguate the two arms by event"),
which is necessary but not sufficient. Authored through `soleur:architecture` in this PR.

### C4 views

No C4 impact, checked against all three model files. `model.c4` has a `ship` component with a single
`oneshot -> ship "Step 5"` edge, no `postmerge` element, and no edge from the plugin to the GitHub
Actions API or to `/health`; `views.c4` includes only `platform.plugin.ship`; `spec.c4` only defines
element kinds. The change adds no external actor, no external system (the GitHub Actions API and
`app.soleur.ai` are already how ship/postmerge verify deploys, unmodelled at this granularity), no
container or store, and no access relationship. `bash plugins/soleur/test/c4-count-parity.test.sh`
ran green on 2026-09-21 (`ALL TESTS PASSED`).

### Sequencing

Lands with the code in the same PR.

## User-Brand Impact

- **If this lands broken, the user experiences:** a post-merge verification that reports a PR as
  deployed and healthy while production still serves the previous build (or reports a real deploy as
  indeterminate). The operator then fires crons, marks tweets publishable, or closes issues against a
  build that does not contain the change — the #8276 class.
- **If this leaks, the user's workflow is exposed via:** nothing new leaks; the script reads public
  Actions metadata and job logs with the operator's existing `gh` auth and writes nothing.
- **Brand-survival threshold:** `aggregate pattern` — a single wrong verdict is recoverable; repeated
  false-green deploy verifications erode trust in the whole ship pipeline.

## Observability

Layer: `cli-stdout-artifact` (observability layer 7 — the script runs in the operator's agent session
on their machine). `deploy-arm.sh` targets this repo's `web-platform-release.yml` and is not invoked
on the hosted runner; its scope guard returns `REASON=not_applicable` anywhere else. The verdict line
carries only run ids, SHAs, reasons and job states — no customer data.

```yaml
liveness_signal:
  what: "deploy-arm.sh prints exactly one verdict line on every invocation: ARM=<id> DEPLOYED_SHA=<sha> MATCH=<m> DEPLOY=<state> CI=<c>, or ARM=none REASON=<reason> [CAUSE=<cause>], or CONTAINS|NOT_CONTAINED|UNRESOLVED|ERROR for contains/served"
  cadence: "per invocation; --wait re-evaluates every 60 s up to its cap (default 120 min)"
  alert_target: "cli-stdout-artifact: the verdict line in the agent session, reported by postmerge Phase 3 / 3.7 and ship step 2 as GATE-*/HEALTH_VERIFIED outcomes naming REASON and CAUSE"
  configured_in: "plugins/soleur/scripts/deploy-arm.sh"

error_reporting:
  destination: "cli-stdout-artifact: stdout verdict line plus stderr diagnostics (one line per candidate, ERR-trap line with $LINENO and the failing verb); no Sentry path for a local operator tool"
  fail_loud: "rc 2 with ARM=none REASON=error CAUSE=bad_input|missing_dep:<cmd>|not_on_main|gh_failed|internal; rc 3 with REASON=<reason> CAUSE=<cause> when no verdict is possible; rc 4 with REASON=ci_pending|arm_pending or DEPLOY=pending when the caller should poll — never an empty result"

failure_modes:
  - mode: "gh api called without --allow-escape-sequences returns rc 1 and zero bytes"
    detection: "candidate classified unresolved (CAUSE=log_read_failed) after the grace window; test row S1 fails if the flag is dropped"
    alert_route: "cli-stdout-artifact: postmerge reports GATE-INDETERMINATE — unresolved log_read_failed"
  - mode: "actions/checkout output format changes so the depth=1 origin line disappears"
    detection: "fallback to the workflow's own 'resolving deploy target for' line; if neither is present, CAUSE=log_line_absent"
    alert_route: "cli-stdout-artifact: GATE-INDETERMINATE — unresolved log_line_absent (fix the script)"
  - mode: "deployed SHA not local (merge-base exit 128)"
    detection: "script fetches the default branch after listing candidates; a remaining 128 yields CAUSE=ancestry_128"
    alert_route: "cli-stdout-artifact: GATE-INDETERMINATE — unresolved ancestry_128"
  - mode: "more than 30 candidate arms in the window (postmerge run long after the merge)"
    detection: "CAUSE=cap_hit"
    alert_route: "cli-stdout-artifact: GATE-INDETERMINATE — unresolved cap_hit"
  - mode: "deploy skipped because resolve-target, migrate or a verify job failed, or cancelled by lock supersession"
    detection: "DEPLOY=blocked or DEPLOY=superseded, never DEPLOY=skipped"
    alert_route: "cli-stdout-artifact: HEALTH_VERIFIED=false with the job named, or GATE-INDETERMINATE — <DEPLOY>"
  - mode: "/health returns an empty body, non-JSON, or build_sha=dev"
    detection: "served/contains print UNRESOLVED (rc 3), never NOT_CONTAINED"
    alert_route: "cli-stdout-artifact: HEALTH_VERIFIED=false reported as could-not-measure"
  - mode: "gh auth expired or rate limited on a list call"
    detection: "ARM=none REASON=error CAUSE=gh_failed, rc 2"
    alert_route: "cli-stdout-artifact: postmerge reports GATE-INDETERMINATE — error gh_failed"

logs:
  where: "the agent session transcript (stdout verdict + stderr diagnostics); GitHub Actions job logs of the underlying runs"
  retention: "session lifetime; Actions logs per repo retention (90 days)"

discoverability_test:
  command: "bash plugins/soleur/scripts/deploy-arm.sh contains 0000000000000000000000000000000000000000 dev"
  expected_output: "UNRESOLVED"
```

The probe needs no network or credentials: `contains` rejects a non-hex `BUILD_SHA` before any
`git fetch`. Preflight Check 10 is path-gated on `SENSITIVE_PATH_RE` and this diff touches none of
it, so Check 10 will SKIP; the Acceptance Criteria run the probe under `env -i` instead.

## Guard Contract

### Guard 1 — deploy-arm selection (`deploy-arm.sh find`)

**Property.** `find` reports `ARM=<id>` only for a `web-platform-release.yml` `workflow_run` run
whose `resolve-target` job checked out the merge SHA or a descendant of it; it never reports a run
whose checked-out SHA it could not read, never settles while a candidate that could outrank it is
pending, and never labels a non-delivery (`blocked`, `superseded`) as a delivery or a designed skip.

**Assembly.** One chokepoint: the per-candidate classifier (status gate → resolve-target log read →
SHA extraction → ancestry → `DEPLOY` derivation), followed by the single verdict function. Every
candidate source — the `head_sha=` first-guess query, the `created>=` window query, and the
`run_attempt == 1` fast path — feeds that classifier, and every stdout line is printed by the
verdict function or the `ERR` trap; nothing else writes stdout. The consumers are the three
SKILL.md sites (`postmerge/SKILL.md` Phase 3 and 3.7, `ship/SKILL.md` protocol step 2 and the "Two
runs per merge" bullet), none of which may carry its own `head_sha=…&event=workflow_run` selector
(static rows).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Return the first first-guess candidate without reading its log (today's `[0]` behaviour) | RED — S2 selects the previous merge's arm |
| 2 | Drop `--allow-escape-sequences` from the log read | RED — S1 becomes `REASON=unresolved` |
| 3 | Treat an unreadable log as "not ours" instead of unresolved/pending | RED — S7 reports `no_candidate` |
| 4 | Accept `D` when `D` is an ancestor OF the merge (direction reversed) | RED — S6 selects the previous merge's arm |
| 5 | Ignore pending candidates in the verdict | RED — S13 returns `MATCH=descendant` while the merge's own arm is pending |
| 6 | With `run_attempt > 1`, take the oldest exact arm (a second member after a compliant first) | RED — S12 picks attempt 1's clean-skipped arm |
| 7 | Pipe the log into `grep \| head -1` under `pipefail` instead of reading a temp file | RED — S15 (1.5 MB log) becomes `unresolved` |
| 8 | `git fetch` before listing candidates instead of after | RED — S8 (commit pushed during the window call) becomes `unresolved` |
| 9 | Map a `deploy` skipped behind a failed `verify-doppler-secrets` to `DEPLOY=skipped` | RED — S21 expects `DEPLOY=blocked` |
| 10 | Treat a `cancelled` deploy as a candidate for rule 1 | RED — S22 selects the superseded exact arm instead of the delivering descendant |

**Harness rows:**

| # | Suite edit | Expected |
|---|---|---|
| H1 | Scenario runner swallows the script's rc, or runs zero rows | RED — the `passes + fails == cases` check and the assertion floor fail |
| H2 | must-PASS non-canonical input: S1's fixture log also contains an unrelated 40-hex SHA before the `depth=1 origin` line | PASS with the `depth=1 origin` SHA |
| H3 | Stub serves logs without requiring `--allow-escape-sequences` | row 2 SURVIVES — the mutation script reports it, proving the stub is load-bearing |

**Anchor.** No stored value is compared; fixture SHAs and timestamps are generated at run time.

### Guard 2 — served-build containment (`deploy-arm.sh contains` / `served`)

**Property.** The served-SHA check passes exactly when the served `build_sha` equals or descends from
the merge, and an unmeasurable `build_sha` (empty body, `dev`, non-hex, unknown commit) never reads
as a mismatch.

**Assembly.** One ancestry helper shared with Guard 1; `served` only fetches and parses, then calls
`contains`. Consumers: `postmerge/SKILL.md` Phase 3 and `ship/SKILL.md` protocol step 2 and line
~2467, which must call `served`/`contains` rather than compare strings (static rows).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Compare `BUILD_SHA == MERGE_SHA` only | RED — S11 `D` must be `CONTAINS` |
| 2 | Map empty / `dev` / non-hex `BUILD_SHA` to `NOT_CONTAINED` | RED — S11 empty row expects `UNRESOLVED` rc 3 |
| 3 | Reverse the ancestry direction | RED — S11 `A` must be `NOT_CONTAINED` |
| 4 | `served`: treat an empty HTTP body as `NOT_CONTAINED` | RED — S23 expects `UNRESOLVED` |

## Acceptance Criteria

- [ ] `plugins/soleur/scripts/deploy-arm.sh` exists, is executable, passes `shellcheck`, and
      implements `find [--wait]`, `contains` and `served` with the stdout/rc contract in
      §Proposed Solution 1 (exactly one stdout line on every path, including errors).
- [ ] `bash plugins/soleur/test/deploy-arm.test.sh` passes: S1-S31 plus the static rows, with the
      `passes + fails == cases` check and the assertion floor.
- [ ] `bash plugins/soleur/test/deploy-arm-mutations.sh` reports every Guard 1 and Guard 2 row
      KILLED and H3 as described (output pasted in the PR body).
- [ ] `postmerge/SKILL.md` Phase 3 carries the `find`/`served` table, Phase 3.7 reuses the `find`
      line with the literal-digits rule and the match-type interpretation, and the gate regex
      includes `deploy-arm`; `ship/SKILL.md` lines ~26, ~2467, ~2469 carry the §Proposed Solution 3
      text; neither file contains `$(` inside the new text (static rows enforce the rest).
- [ ] `ADR-217-…md` carries the dated addendum in §Proposed Solution 4.
- [ ] `python3 scripts/lint-skill-body-budget.py --base origin/main` prints `OK`, and `wc -c` of
      both SKILL.md files is no larger than on `origin/main`.
- [ ] `bash plugins/soleur/test/workflow-run-deploy-invariants.test.sh`,
      `bash plugins/soleur/test/c4-count-parity.test.sh` and
      `bun test plugins/soleur/test/workflow-fidelity.test.ts` pass.
- [ ] `git diff --name-only origin/main...HEAD` lists neither
      `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` nor
      `.github/workflows/web-platform-release.yml`.
- [ ] The discoverability probe runs clean without network or credentials (preflight Check 10 will
      SKIP it, since no sensitive path is touched):
      `env -i PATH=/usr/bin:/bin HOME=/tmp bash plugins/soleur/scripts/deploy-arm.sh contains 0000000000000000000000000000000000000000 dev`
      prints `UNRESOLVED` (recorded in the PR body).
- [ ] Live smoke (read-only, recorded in the PR body):
      `bash plugins/soleur/scripts/deploy-arm.sh find 71e7585eae756389b815f12b490062db4347be04`
      prints `ARM=35577957665 DEPLOYED_SHA=71e7585eae756389b815f12b490062db4347be04 MATCH=exact DEPLOY=success CI=success`
      (or a newer exact arm if that commit's CI was re-run), and
      `bash plugins/soleur/scripts/deploy-arm.sh served 71e7585eae756389b815f12b490062db4347be04`
      prints `CONTAINS BUILD_SHA=<sha>`.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal tooling change to the ship/postmerge verification
predicate; no user-facing surface, no data, no infrastructure.

## Test Scenarios

`find` rows use a completed, successful `ci.yml` run with `run_attempt: 1` unless stated. "log `X`"
means the arm's `resolve-target` log carries `depth=1 origin <sha of X>`. "Now" is pinned through
`DEPLOY_ARM_NOW`. Every `find` row asserts rc, exactly one stdout line, and the full expected line.

| # | Setup | Expected |
|---|---|---|
| S1 | first guess returns one arm, log `M` (an unrelated 40-hex precedes the key line — H2), `deploy` success | `ARM=<it> DEPLOYED_SHA=M MATCH=exact DEPLOY=success CI=success`, rc 0; the stub's call log shows exactly 4 calls and no window call (fast path) |
| S2 | (#8391) first guess returns arm1 (log `A`) listed before arm2 (log `M`) | selects arm2, exact |
| S3 | (#8297) first guess empty; window has an arm stamped with a later SHA whose log = `M` | selects it, exact |
| S4 | only arm in window has log `D`, `deploy` success | `MATCH=descendant DEPLOYED_SHA=D DEPLOY=success`, rc 0 |
| S5 | ci.yml run for `M` `in_progress`; window has only an arm with log `A` | `ARM=none REASON=ci_pending`, rc 4 |
| S6 | only arm has log `A` | `ARM=none REASON=no_candidate`, rc 3 |
| S7 | only candidate's `resolve-target` completed `NOW-600`; log endpoint returns 404 (JSON body, rc 1) on all 3 attempts | `ARM=none REASON=unresolved CAUSE=log_read_failed`, rc 3 |
| S8 | the stub's window-list handler pushes `L` (child of `M`) to origin as a side effect; only arm has log `L` | fetch-after-listing sees `L` → `MATCH=descendant DEPLOYED_SHA=L` |
| S9 | `MERGE_SHA` is 7 chars | `ARM=none REASON=error CAUSE=bad_input`, rc 2 |
| S10 | only arm has log `X` (unrelated branch) | `ARM=none REASON=no_candidate`, rc 3 |
| S11 | `contains M` with build `M`, `D`, `A`, `""`, `dev`, unknown 40-hex | `CONTAINS`, `CONTAINS`, `NOT_CONTAINED`, `UNRESOLVED`, `UNRESOLVED`, `UNRESOLVED`; also with an unreachable origin URL: unknown → `UNRESOLVED`, `D` → `CONTAINS` |
| S12 | `run_attempt: 2`; attempt-1 arm (created before `run_started_at`) with `deploy` skipped, attempt-2 arm success | selects the attempt-2 arm |
| S13 | a candidate created before a readable descendant arm is pending (`resolve-target` in progress) | `ARM=none REASON=arm_pending`, rc 4 |
| S14 | exact arm `deploy` skipped with `CI=failure` (`ci_not_green`); a later arm with log `D` has `deploy` success | `MATCH=descendant DEPLOY=success CI=failure` |
| S15 | log is 1.5 MB with the `depth=1 origin` line near the top | exact, not `unresolved` (pipefail/SIGPIPE row) |
| S16 | the only candidates are a cancelled run with no `resolve-target` job, then a later arm with log `D` | cancelled run dropped → `MATCH=descendant` (not dropped → rule 2 would give `arm_pending`) |
| S17 | window spans two pages returned newest-first; descendants on both pages, the earliest on page 2 | earliest descendant chosen (a per-page sort goes red) |
| S18 | only candidate's `resolve-target` completed `NOW-60`; log endpoint returns 404 | `ARM=none REASON=arm_pending`, rc 4 (grace); twin rows at `NOW-170` → pending and `NOW-190` → `unresolved` |
| S19 | no ci.yml run; `M` committed `NOW-900`; no candidates | `ARM=none REASON=ci_absent`, rc 3 |
| S20 | no ci.yml run; `M` committed `NOW-60` | `ARM=none REASON=ci_pending`, rc 4 |
| S21 | only arm has log `M`; `verify-doppler-secrets` failure, `deploy` skipped | `MATCH=exact DEPLOY=blocked`, rc 0 |
| S22 | exact arm with `deploy` cancelled (swap-lock supersession); a later arm with log `D`, `deploy` success | `MATCH=descendant DEPLOY=success` |
| S23 | `served M` against a stub HTTP body that is empty, then non-JSON, then `{"build_sha":"<D>"}` (`curl` stubbed on `PATH`) | `UNRESOLVED BUILD_SHA=-`, `UNRESOLVED BUILD_SHA=-`, `CONTAINS BUILD_SHA=<D>` |
| S24 | only arm has log `M`, `deploy` skipped, `resolve-target` success, CI success (docs-only) | `MATCH=exact DEPLOY=skipped CI=success`, rc 0 |
| S25 | log carries only `resolving deploy target for <M>` | exact (fallback line) |
| S26 | log readable but carries neither key line | `ARM=none REASON=unresolved CAUSE=log_line_absent`, rc 3 |
| S27 | 31 candidates, none qualifying | `ARM=none REASON=unresolved CAUSE=cap_hit`, rc 3 |
| S28 | `run_attempt: 2`; readable exact arm and a pending candidate created after it | `ARM=none REASON=arm_pending`, rc 4 |
| S29 | the ci.yml call exits 1 | `ARM=none REASON=error CAUSE=gh_failed`, rc 2, nothing else on stdout |
| S30 | run from a directory with no `.github/workflows/web-platform-release.yml` | `ARM=none REASON=not_applicable`, rc 3 |
| S31 | `--wait 2` with the stub returning `ci_pending` on the first call and S1's data after | final line is S1's, rc 0; one progress line on stderr (sleep stubbed via `DEPLOY_ARM_SLEEP=0`) |
| static | the rows in §Proposed Solution 5 | as listed |

## Dependencies & Risks

- **Log availability lag:** a job's log endpoint can 404 briefly after the job completes. Inside a
  3-minute grace window the script reports `arm_pending` (poll); after it, `unresolved`
  (stop, could-not-measure). Neither is ever converted into a match or a mismatch.
- **Arm log retention:** logs expire with repo retention (90 days); irrelevant for a post-merge check.
- **Descendant acceptance vs. gate validation:** a descendant arm's deploy contains the change, so
  its success exercises the gate (`GATE-VALIDATED (via <D>)`); its failure may be the later merge's
  own fault, so it reports `GATE-SUSPECT` with the `M..D` log rather than recommending a revert.
- **Body budget:** if the rewrite cannot come in under the ceilings, move Phase 3.7's explanatory
  prose into `postmerge/references/` rather than raising a ceiling.

## Plan Review Revisions

Panel: `soleur:engineering:review:dhh-rails-reviewer`, `soleur:engineering:review:kieran-rails-reviewer`,
`soleur:engineering:review:code-simplicity-reviewer` (eng, threshold `aggregate pattern`), plus
`soleur:engineering:cto` (named devex lens, relevance-gated: code/tooling files), and the Step 4.5
advisor consult. Applied (Mechanical):

- **Verdict precedence** (Kieran 1, CTO F1): pending candidates block a verdict they could
  outrank; new `REASON=arm_pending` (rc 4, poll again) kept separate from `unresolved` (rc 3).
- **Status gate before log read** (Kieran 2, advisor 2): cancelled/`startup_failure` runs are dropped;
  job-level (not run-level) `resolve-target` status decides pending.
- **Deploy-skipped ranking** (Kieran 3, advisor 2): a clean-skipped exact arm no longer outranks a
  descendant that really deployed; output gains `DEPLOY=`.
- **Log read into a temp file** (Kieran 4); **sort after `--paginate`** (Kieran 5); **`ci_absent`
  and dependency checks** (Kieran 6); **cap 30 candidates + `run_attempt == 1` fast path**
  (Kieran 10), which also makes the kept `head_sha=` first guess a real fast path.
- **Window bound from the CI run's `created_at`** (simplicity F2): server-stamped, drops the
  10-minute skew margin.
- **No per-SHA fetch-and-retry; fetch `main` after listing** (DHH 2, simplicity F3): every
  deployed or served SHA is on `main`. Fixture `E` replaced by `L` (pushed after the clone).
- **Consumer contract** (CTO F2/F3, Kieran 9): copy-able block with a numeric run-id check, an `ERR`
  trap mapping crashes to rc 2, a REASON→action table with a Monitor polling rule and a 45-min cap,
  and a defined meaning for `NOT_CONTAINED` under a skipped deploy.
- **Ship delegates, measured** (CTO F4, Kieran 8): exact replacements drafted, net −233 B.
- **Script moved to `plugins/soleur/scripts/deploy-arm.sh` with `find`/`contains` subcommands**
  (DHH 5, CTO F5): two skills call it, so it lives in the shared scripts dir under a name for what
  it does.
- **Static assertions as one regex plus stale-phrase rows** (Kieran 7, simplicity F8, DHH 8).
- **Guard matrix trimmed; hand-run mutation AC reduced to four rows** (DHH 3, simplicity F6).
- **Log-format dependency** (CTO F6): fallback to the workflow's own `resolving deploy target for`
  line, plus a static row pinning the `resolve-target` checkout `ref:`.

Not applied, persisted to `knowledge-base/project/specs/feat-one-shot-8492-deploy-arm-by-resolve-target/decision-challenges.md`:

- **DC-1** (advisor): add `run-name: deploy ${{ github.event.workflow_run.head_sha }}` to
  `web-platform-release.yml` so the deployed SHA is in the runs list. Widens scope into the deploy
  workflow; the operator's direction (log-based) stands.
- **DC-2** (DHH 1, simplicity F1): drop the `head_sha=` first-guess source entirely. The issue asks
  to keep it; with the `run_attempt == 1` fast path it now earns its call.
- **DC-3** (CTO F6): move the workflow's `resolving deploy target for` echo above the `clean_skip`
  calls and key on it. Another deploy-workflow edit; the fallback read covers most of the benefit.

Declined with reason: DHH 4 (merge `ci_pending` into `no_candidate`) — the two need different caller
actions (poll vs stop), which the CTO and Kieran reviews showed is the more common failure;
DHH 7 (shrink the Observability block) — the template and deepen-plan Phase 4.7 require the fields.

## Deepen-Plan Revisions

Agents: `soleur:engineering:review:test-design-reviewer`, `soleur:product:spec-flow-analyzer`,
`soleur:engineering:review:observability-coverage-reviewer`,
`soleur:engineering:review:architecture-strategist`, and a verify-the-negative / self-audit pass
(all repo claims confirmed; `web-platform-release.yml` concurrency cite corrected to `:91-93`).
Applied:

- **The postmerge happy path reaches a verdict** (flow F1, F5, F6): `find` moved into Phase 3
  (it ran only in Phase 3.7, which most PRs skip); a `find` × `served` table covers every cell,
  including "deploy success but production does not serve it"; `DEPLOY=pending` is rc 4, so callers
  re-run `find` instead of `gh run view`; `find --wait` gives both skills one cadence and one cap.
- **Non-delivery is never a designed skip** (flow F2, F4): `DEPLOY=blocked` (resolve-target or a
  verify/migrate job failed) and `DEPLOY=superseded` (lock-queue cancellation) split out of
  `skipped`; `CI=` added so a `ci_not_green` skip is distinguishable from docs-only.
- **CI re-runs** (flow F3): no exact verdict before the merge's CI completes; with
  `run_attempt > 1` an exact arm counts only if created after `run_started_at`.
- **Ship and postmerge agree on red CI** (flow F7): ship requires `CI=success` before post-deploy
  actions; postmerge Phase 2 names a descendant delivery when there is one.
- **Gate verdict by match type** (flow F8): descendant failure is `GATE-SUSPECT` with the `M..D`
  log, not "revert immediately"; superseded/blocked are `GATE-INDETERMINATE`.
- **No `$()` in SKILL.md** (flow F10): repo-relative literal calls; `served` subcommand does the
  curl + parse so no caller needs substitution.
- **Placement and scope** (architecture 1, 2, 3, 5, 6, 8): repo-relative calls matching
  `ship/SKILL.md:30`; `not_applicable` scope guard; default branch resolved from `origin/HEAD`;
  postmerge gate regex extended to the script; static rows for the job name and echo; Guard 8
  fixture-line rule; manual redeploys covered by `served`.
- **ADR-217 addendum and a `## Architecture Decision (ADR/C4)` section** (architecture 4).
- **Measured postmerge removable bytes** (architecture 7).
- **Discriminated failure causes** (observability 1, 3, 4, 5): `contains` validates before any
  network call; `CAUSE=` on every `unresolved`/`error`; one stderr line per candidate; a stdout line
  even on rc 2; `set -E`; `gh_failed` and fetch-failure rows; layer citation
  `cli-stdout-artifact`.
- **Deterministic, non-vacuous tests** (test-design P0-1..3, P1-4..6, P2-7, P2-8): `DEPLOY_ARM_NOW`
  and `DEPLOY_ARM_SLEEP` seams; S16 and S8 rebuilt so they can fail; the stub runs the script's own
  `--jq`, models `--paginate`, 404 bodies and unknown endpoints, and records argv; 13 new rows
  (S19-S31); static rows fail on a missing file and self-test their regexes; counting pattern from
  `issue-flow-measure.test.sh`; a scripted mutation driver; fast-path call count pinned.
- **Log-read retry** (flow F9): 3 attempts with backoff before `unresolved`; an unresolved
  candidate created before a descendant blocks the descendant verdict.

Not applied:

- Posting the verdict to the merged PR as a comment (observability 2) — a new write action outside
  the brief; the verdict is reported in the postmerge report and ship output.
- Deriving the `--wait` cap from `DRIFT_SUSTAINED_THRESHOLD_MIN` (flow F5) — couples a plugin
  script to a repo script; a 120-min default with an override covers the measured deploy path.
- `UNRESOLVED_BEFORE=` output field (flow F9) — replaced by the stricter rule that an unresolved
  earlier candidate blocks the descendant verdict.

## References & Research

- Issue #8492; incidents #8297, #8391, #8265, #8276, #8135.
- `knowledge-base/project/learnings/2026-09-20-the-deploy-arm-that-said-success-had-deployed-someone-elses-commit.md`
- `.github/workflows/web-platform-release.yml:207-264` (resolve-target, checkout pin), `:403-420`
- ADR-217 (`knowledge-base/engineering/architecture/decisions/ADR-217-the-deploy-fires-on-cis-completion-event-and-the-verdict-never-crosses-as-a-value.md`) — split topology; receives a dated addendum (§Proposed Solution 4). ADR-178 — shared bash primitives ship in the plugin.
- `scripts/lint-skill-body-budget.py`, `plugins/soleur/test/skill-body-budget.json`
- `plugins/soleur/test/workflow-run-deploy-invariants.test.sh` Guard 8 (lines ~853-905)
