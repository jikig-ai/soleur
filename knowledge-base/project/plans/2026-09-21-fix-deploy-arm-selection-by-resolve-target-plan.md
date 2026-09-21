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
concurrency — explains queued arms), #8490 (parallel, touches `worktree-manager.sh`; out of scope).

## Research Reconciliation — Spec vs. Codebase

| Claim (issue #8492) | Reality on `origin/main` | Plan response |
|---|---|---|
| `resolve-target` logs `depth=1 origin <sha>` | Confirmed live: run `35577957665`, job `106263967678` log contains `depth=1 origin 71e7585e…` once and `resolving deploy target for 71e7585e…` once. The checkout is pinned to `github.event.workflow_run.head_sha` (`web-platform-release.yml:262-264`), i.e. the *triggering CI run's* SHA, which is the commit deployed. The checkout step precedes the resolve step, so the line is present even when resolve-target clean-skips. | Key on the `depth=1 origin` line (first match). |
| `gh api` needs `--allow-escape-sequences` | Confirmed: same job log without the flag exits rc=1 with zero bytes. | Script always passes the flag; the test's `gh` stub reproduces the rc=1/empty behaviour so dropping the flag reds a row. |
| "any test/fixture pinning the old predicate" | `git grep` for `head_sha=${MERGE_SHA}`, `GATE-INDETERMINATE`, `DEPLOY_JOB_STATE`, `build_sha ==`, `Chosen predicate` outside `knowledge-base/` hits only `postmerge/SKILL.md` and `ship/SKILL.md`. `workflow-fidelity.test.ts:298-307` pins only the protocol sentinels, not the predicate. `workflow-run-deploy-invariants.test.sh` Guard 8 pins arm disambiguation (event name present), which the new script satisfies. | No existing fixture to update; the plan ADDS the fixture that pins the new predicate. |
| ship ~line 2469, postmerge ~line 336 | Exact. Also ship line 26 (merge→deploy protocol step 2), ship line 2467 (`/health` "expected `build_sha`"), postmerge line 112/114 (Phase 3 health). | All five sites in scope. |

## Proposed Solution

[Updated 2026-09-21 after plan review — see `## Plan Review Revisions`.]

### 1. New script: `plugins/soleur/scripts/deploy-arm.sh`

A plugin-level script (not under one skill's folder), because both `ship` and `postmerge` call it —
`plugins/soleur/scripts/` is the shared home and its call convention is
`bash "${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/scripts/deploy-arm.sh" …`. It must be run from inside a
soleur checkout (it resolves `{owner}/{repo}` through `gh` and runs `git` against the caller's CWD);
it never `cd`s to its own directory, so it also works from a cached plugin install. All `git`/`gh`
noise goes to stderr; stdout carries exactly one verdict line, even under a `2>&1` capture. An `ERR`
trap turns any unplanned failure into rc 2, so rc 1 and rc 3 are never produced by a crash. Callers
decide on the stdout token; the rc is a hint.

Two subcommands share one ancestry helper (the single chokepoint for "does X contain the merge").

#### `deploy-arm.sh find <MERGE_SHA>`

| stdout | rc | caller action |
|---|---|---|
| `ARM=<id> DEPLOYED_SHA=<sha> MATCH=exact\|descendant DEPLOY=<deploy job state>` | 0 | use run `<id>` |
| `ARM=none REASON=ci_pending` | 4 | poll again: the merge's `ci.yml` push run is not completed (or not created yet) |
| `ARM=none REASON=arm_pending` | 4 | poll again: a candidate that could still be the answer has not finished `resolve-target` |
| `ARM=none REASON=ci_absent` | 3 | stop: no `ci.yml` push run exists for the merge 10+ min after it landed (e.g. `[skip ci]`), and no descendant arm has deployed yet |
| `ARM=none REASON=no_candidate` | 3 | stop: CI completed, every candidate was read, none qualifies |
| `ARM=none REASON=unresolved` | 3 | stop: a finished candidate's SHA could not be read (log unreadable, ancestry rc 128 after fetch), or the 30-candidate scan cap was hit — could-not-measure, never a mismatch |
| error on stderr | 2 | bad input (not 40-hex), `gh`/`git`/`jq` missing, merge SHA not on `origin/main`, unplanned failure |

`DEPLOY` is the selected run's `deploy` job state: its `conclusion` when completed, else `pending`.

Algorithm:

1. Validate `MERGE_SHA` against `^[0-9a-f]{40}$` (a short SHA silently matches nothing, #8135);
   require `gh`, `git`, `jq`.
2. **The merge's CI run.** `gh api "repos/{owner}/{repo}/actions/workflows/ci.yml/runs?head_sha=$MERGE_SHA&event=push&per_page=10"`
   (for a push run, `head_sha` *is* the commit). Take the newest; keep its `status`, `created_at`
   and `run_attempt`. None found: `ci_pending` if the merge's committer time (`git show -s
   --format=%ct`, after step 3's fetch) is under 10 minutes old, else remember `ci_absent`.
   Window lower bound `T` = that CI run's `created_at` — server-stamped, no clock-skew margin; when
   there is no CI run, `T` = the merge's committer time rendered with `jq -rn --argjson t <epoch>
   '$t|todate'` (portable; no GNU/BSD `date` flags).
3. **Candidates** (the union, de-duplicated by run id):
   - **first guess** — `repos/{owner}/{repo}/actions/runs?head_sha=$MERGE_SHA&event=workflow_run&per_page=100`,
     filtered to `.path == ".github/workflows/web-platform-release.yml"` — today's query, kept as the
     fast path the issue asks for (see step 6), never trusted on its own;
   - **window** — `gh api --paginate "repos/{owner}/{repo}/actions/workflows/web-platform-release.yml/runs?event=workflow_run&created=%3E%3D$T&per_page=100"`.
   `--jq` runs per page, so emit one `created_at<TAB>id<TAB>status<TAB>conclusion` line per run and
   `sort` the combined stream afterwards; never `sort_by` inside `--jq`. Cap at 30 candidates.
   Then `git fetch -q origin main` — **after** listing, so every SHA an already-listed arm checked
   out is on `main` locally (every arm fires on `branches: [main]`, `web-platform-release.yml:76-79`).
4. **Per candidate**, cheapest first:
   - run concluded `cancelled`/`startup_failure` with no completed `resolve-target` → drop (it
     deployed nothing; a CI re-run cancels the arm waiting in the concurrency group,
     `web-platform-release.yml:89-92`);
   - `resolve-target` not completed → *pending* (`resolve-target` can complete while the run is
     still queued for `deploy`, observed on run `35592848323`, so check the job, not the run);
   - else read `gh api --allow-escape-sequences ".../actions/jobs/<resolve-target id>/logs"` **into a
     temp file**, check `gh`'s rc on its own, then `grep -m1 -oE 'depth=1 origin [0-9a-f]{40}'` on
     the file (piping into `head -1` under `pipefail` can SIGPIPE the reader and fake an empty
     read). If absent, fall back to `resolving deploy target for [0-9a-f]{40}`. Neither present, or
     the read failed → *unresolved* — except that a failed read on a `resolve-target` job that
     completed under 3 minutes ago counts as *pending* (the log endpoint lags job completion).
   - classify SHA `D`: `D == MERGE_SHA` → exact; `git merge-base --is-ancestor MERGE_SHA D` rc 0
     → descendant, rc 1 → reject, rc 128 → *unresolved* (no per-SHA retry: `D` is on `main`, and
     step 3 fetched `main` after listing it).
   - For exact/descendant candidates, read the `deploy` job state from the jobs list already fetched.
5. **Verdict** — rank, first rule that yields a run wins:
   1. newest exact whose `deploy` is not `skipped`, **provided — when the CI run's `run_attempt`
      is above 1 — no pending candidate was created after it** (a re-run's arm may still be
      coming); otherwise → `arm_pending`;
   2. earliest descendant whose `deploy` is not `skipped`, **provided no pending candidate was
      created before it** (the merge's own arm may still be coming); otherwise → `arm_pending`;
   3. newest exact with `deploy` `skipped` (a docs-only or `ci_not_green` clean skip — reported as
      such, `DEPLOY=skipped`);
   4. no run: `ci_pending` if the CI run is not completed; `arm_pending` if any candidate is pending;
      `unresolved` if any candidate is unresolved or the cap was hit; `ci_absent` if remembered in
      step 2; else `no_candidate`.
6. **Fast path.** When the CI run's `run_attempt` is 1, only one exact arm can exist, so the script
   classifies first-guess candidates first and stops at the first readable exact arm whose
   `deploy` is not `skipped`. On an unbusy `main` that costs 4 API calls (CI run, first guess,
   jobs, log).

#### `deploy-arm.sh contains <MERGE_SHA> <BUILD_SHA>`

`git fetch -q origin main`, then: `CONTAINS` (rc 0) when `BUILD_SHA == MERGE_SHA` or the merge is an
ancestor of it; `NOT_CONTAINED` (rc 1) when ancestry says no; `UNRESOLVED` (rc 3) when `BUILD_SHA` is
empty, `dev`, not 40-hex, or ancestry exits 128. An empty `/health` body (the apex returns rc 0 with
an empty body, #8391) lands in `UNRESOLVED`, never `NOT_CONTAINED`.

### 2. `plugins/soleur/skills/postmerge/SKILL.md`

- **Phase 3 (lines ~112, ~114):** replace "The `build_sha` field also confirms the merge commit is
  the live build" and "(and the expected `build_sha`)" with the `contains` check: `CONTAINS` passes
  (a later merge's build contains yours); `UNRESOLVED` is could-not-measure (`HEALTH_VERIFIED=false`,
  reported as such); `NOT_CONTAINED` while the deploy arm's `DEPLOY` is not concluded means keep
  polling, and with `DEPLOY=skipped` means "not deployed", not "unhealthy".
- **Phase 3.7:** replace the "Chosen predicate" sentence (`:297`), the false-positive paragraph and
  bash block (`:299-316`), the "Select by the merge SHA, never by recency" paragraph (`:324`), the
  `RELEASE_RUN_ID=$(gh api …head_sha=…)` query and its comment (`:326-337`), and the sibling-merge
  fallback inside the `absent` row (`:373`) with:
  - one sentence of rule: identify the arm by what `resolve-target` checks out; a `workflow_run`
    run's `head_sha` is `main`'s tip at trigger time (#8297, #8391, #8492);
  - one exact block to copy, which captures stdout and rc separately and extracts the id
    numerically — `ARM=none` must never reach `gh run view`:
    ```bash
    OUT=$(bash "${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/scripts/deploy-arm.sh" find "$MERGE_SHA"); RC=$?
    RELEASE_RUN_ID=$(printf '%s\n' "$OUT" | sed -n 's/^ARM=\([0-9][0-9]*\) .*/\1/p')
    [[ "$RELEASE_RUN_ID" =~ ^[0-9]+$ ]] || RELEASE_RUN_ID=""   # never eval $OUT
    ```
    and the existing `DEPLOY_JOB_STATE` guard changes from `!= "null"` to the same numeric test;
  - one REASON table: rc 4 (`ci_pending`, `arm_pending`) → re-check through the Monitor tool every
    60 s, giving up after 45 min (CI p95 plus the deploy arm's queue behind the release job) with
    `GATE-INDETERMINATE — timed out (<reason>)`; rc 3 (`ci_absent`, `no_candidate`, `unresolved`)
    → `GATE-INDETERMINATE — <reason>`, naming the run ids examined; `MATCH=descendant` → say the
    gate was exercised by a later merge's deploy.
  Keep: the push-arm/deploy-arm table, the `live-verify` step-list warning and the `app.soleur.ai`
  host note (true and not about selection), the `DEPLOY_JOB_STATE` classification block and its
  interpretation rows, and the incidents, compressed into one "Why" line (#8265, #8297, #8391).
  If the rewrite still needs bytes, the #8391/#8297 narratives are the first thing to move to
  `postmerge/references/deploy-status-debugging.md`.
- **Phase 4 note at `:468`** (full 40-char SHA for `actions/runs?head_sha=`) stays: it governs
  push-event runs, whose `head_sha` *is* the commit.

### 3. `plugins/soleur/skills/ship/SKILL.md` — delegate, do not restate

Exact replacements, drafted and measured at plan time (net **−233 bytes** against `origin/main`):

| Site | Old | New | Δ bytes |
|---|---|---|---|
| line 26, arm selector | ``(`event=workflow_run` on the FULL 40-char merge sha; the push-arm `Web Platform Release` is build+publish only, and a short sha returns an EMPTY set that reads as drained, #8135)`` | ``(`bash "${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/scripts/deploy-arm.sh" find <full-merge-sha>` — never `head_sha=` alone, #8492; the push arm only builds)`` | −25 |
| line 26, served SHA | ``require `/health` `build_sha == merge sha` `` | ``require `deploy-arm.sh contains <merge> <build_sha>` → `CONTAINS` `` | +25 |
| line 2467 | ``​`/health` 200 with the expected `build_sha` `` | ``​`/health` 200, `deploy-arm.sh contains` → `CONTAINS` `` | +11 |
| line 2469 bullet | whole "Two runs per merge is normal." bullet | "**Two runs per merge is normal.** `event=workflow_run` is the deploy arm, `event=push` the build. Find the deploy arm with `deploy-arm.sh find <full-merge-sha>`, never a `head_sha=` query or `--limit 1`: a deploy-arm run's `head_sha` is `main`'s tip when it fired, so it misses your arm and returns the previous merge's. See `postmerge/SKILL.md` Phase 3.7." | −244 |

The #8135 short-SHA point survives in the script's input validation and in postmerge Phase 4. The
waiting rule lives only in postmerge Phase 3.7; ship points at it.

### 4. New test: `plugins/soleur/test/deploy-arm.test.sh`

Auto-discovered by `scripts/test-all.sh` (`plugins/soleur/test/*.test.sh`, line 78). Builds a
throwaway bare `origin` (reached through a `file://` URL) plus a clone, with `A` (previous merge) →
`M` (this merge) → `D` (descendant) on `main`, `X` on an unrelated branch, and `L` pushed to origin
`main` **after** the clone (exercises the fetch-after-listing order). A fake `gh` on `PATH` serves
fixture JSON per endpoint and serves job logs **only when `--allow-escape-sequences` is present**
(otherwise rc 1, zero bytes — the measured behaviour). Scenarios are listed under Test Scenarios.

Static assertions, scoped to exactly `postmerge/SKILL.md` and `ship/SKILL.md` — never a repo-wide
grep, because this test contains the forbidden strings as its own patterns:

- both reference `deploy-arm.sh`;
- neither matches `head_sha=[^&" ]*&event=workflow_run` (catches `${MERGE_SHA}`, `$MERGE_SHA` and
  `<full-40-char-merge-sha>` spellings; does not match the push-run queries at
  `postmerge/SKILL.md:468` and `ship/SKILL.md:2114`);
- neither contains ``expected `build_sha` `` or `build_sha == merge sha`;
- `postmerge/SKILL.md` contains the `=~ ^[0-9]+$` run-id check;
- `web-platform-release.yml`'s `resolve-target` job still checks out
  `ref: ${{ github.event.workflow_run.head_sha || github.sha }}` before its resolve step — the log
  line this script keys on exists only because of that ordering.

Harness constraints found at plan time:

- **Use a `file://` origin URL.** A plain-path `git clone` hard-links the whole object store, so a
  commit that should be missing is already present (measured 2026-09-21: rc 0 with a path clone,
  rc 128 with `file://`).
- **Call `git_fixture_env` (`plugins/soleur/test/lib/git-fixture-env.sh`) in the parent shell**,
  never inside `$( )` — its exported identity dies with the subshell and `git commit` fails on CI
  runners with no global identity (2026-09-20 learning).
- **Guard 8 of `workflow-run-deploy-invariants.test.sh` scans `plugins/`, this test included.** Any
  stub `case` pattern that spells `workflows/web-platform-release.yml/runs` must carry
  `event=workflow_run` on the same pattern line.
- **Non-vacuity:** the suite ends by asserting `passed == <expected row count>`; a zero-row run fails.

## Technical Considerations

- **Body budget (hard constraint).** `scripts/lint-skill-body-budget.py --base origin/main` measures
  whole-file bytes against `plugins/soleur/test/skill-body-budget.json`: postmerge 47575/48000
  (425 B headroom), ship 273108/274000 (892 B). Raising a ceiling needs a separate budget-only PR.
  Ship is measured at −233 B above. Postmerge deletes ~3 KB of bolt-on prose and adds the block,
  the REASON table and the Phase 3 `contains` rule; run the lint before committing.
- **Guard 8 of `workflow-run-deploy-invariants.test.sh`** discovers the script's window query
  (`workflows/[^ ]*web-platform-release[^ ]*/runs`); the URL itself carries `event=workflow_run`,
  so it passes and raises the consumer count above the ≥5 floor with no edit to that test.
- **Rate cost.** Fast path: 4 calls. Worst case: 3 list calls + 2 per candidate, capped at 30
  candidates (~63 calls) — reached only when postmerge runs long after the merge.
- **Log-format dependency.** The key line is `actions/checkout`'s own `git fetch` output, so a bump
  of the pinned checkout action could change it. That fails safe (every candidate `unresolved` →
  `GATE-INDETERMINATE`, never a false green), the fallback line `resolving deploy target for` is
  tried second, and the live smoke AC re-proves the format on every change to the script.
- **Not in scope:** `scripts/watch-live-verify-pass.sh` (selects recent arms with a live-verify pass,
  not a per-merge arm) and `postmerge/references/deploy-status-debugging.md` (re-runs the latest arm)
  do not key on `head_sha`. `web-platform-release.yml` is not edited (see `## Plan Review
  Revisions`, DC-1/DC-3). `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` is not
  touched (parallel PR #8490).

## Files to Create

- `plugins/soleur/scripts/deploy-arm.sh`
- `plugins/soleur/test/deploy-arm.test.sh`

## Files to Edit

- `plugins/soleur/skills/postmerge/SKILL.md` (Phase 3 lines ~112-114; Phase 3.7 lines ~297-373)
- `plugins/soleur/skills/ship/SKILL.md` (lines ~26, ~2467, ~2469)

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` bodies reference none of the planned paths.

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

```yaml
liveness_signal:
  what: "deploy-arm.sh prints exactly one verdict line (ARM=<id> ... MATCH=exact|descendant DEPLOY=<state>, or ARM=none REASON=<reason>) on every invocation"
  cadence: "per invocation (postmerge Phase 3.7 and ship's merge-deploy protocol, once per merge)"
  alert_target: "the running agent's postmerge Phase 7 report (GATE-INDETERMINATE names the REASON)"
  configured_in: "plugins/soleur/scripts/deploy-arm.sh"

error_reporting:
  destination: "stderr of the invoking agent session plus the postmerge Phase 7 report; no Sentry path (local operator tool)"
  fail_loud: "rc 2 with 'MERGE_SHA must be the full 40-char sha' on bad input or any unplanned failure (ERR trap); rc 3 with ARM=none REASON=<reason> when no verdict is possible; rc 4 with REASON=ci_pending|arm_pending when the caller should poll — never a silent empty result"

failure_modes:
  - mode: "gh api called without --allow-escape-sequences returns rc 1 and zero bytes"
    detection: "candidate classified unresolved, verdict ARM=none REASON=unresolved; test row pins the flag"
    alert_route: "postmerge reports GATE-INDETERMINATE with REASON=unresolved"
  - mode: "deployed SHA not fetched locally (merge-base exit 128)"
    detection: "script fetches main after listing candidates; a remaining 128 yields REASON=unresolved"
    alert_route: "postmerge reports GATE-INDETERMINATE with REASON=unresolved"
  - mode: "/health returns an empty body or build_sha=dev"
    detection: "contains prints UNRESOLVED (rc 3), not NOT_CONTAINED"
    alert_route: "postmerge sets HEALTH_VERIFIED=false and reports could-not-measure"

logs:
  where: "the agent session transcript (stdout/stderr of the script); GitHub Actions job logs for the underlying runs"
  retention: "session lifetime; Actions logs per repo retention (90 days)"

discoverability_test:
  command: "bash plugins/soleur/scripts/deploy-arm.sh contains 0000000000000000000000000000000000000000 dev"
  expected_output: "UNRESOLVED"
```

## Guard Contract

### Guard 1 — deploy-arm selection (`deploy-arm.sh find`)

**Property.** `find` reports `ARM=<id>` only for a `web-platform-release.yml` `workflow_run` run
whose `resolve-target` job checked out the merge SHA or a descendant of it. It never reports a run
whose checked-out SHA it could not read, and never settles on a verdict while a candidate that could
outrank it is still pending.

**Assembly.** One chokepoint: the per-candidate classifier (status gate → resolve-target log read →
SHA extraction → exact / ancestry). Both candidate sources (the `head_sha=` first-guess query and the
`created>=` window query) feed it, and so does the `run_attempt == 1` fast path; none may produce a
verdict without passing through it. Three SKILL.md call sites consume the verdict
(`postmerge/SKILL.md` Phase 3.7, `ship/SKILL.md` protocol step 2 and the "Two runs per merge"
bullet); none may carry its own `head_sha=…&event=workflow_run` selector (static row).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Return the first first-guess candidate without reading its log (today's `[0]` behaviour) | RED — S2 selects the previous merge's arm |
| 2 | Drop `--allow-escape-sequences` from the log read | RED — S1 becomes `REASON=unresolved` |
| 3 | Treat an unreadable log as "not ours" instead of unresolved | RED — S7 reports `no_candidate` |
| 4 | Accept `D` when `D` is an ancestor OF the merge (direction reversed) | RED — S6 selects the previous merge's arm |
| 5 | Ignore pending candidates in the verdict | RED — S13 returns `MATCH=descendant` while the merge's own arm is pending |
| 6 | Stop at the first exact arm when `run_attempt > 1` (second member after a compliant first) | RED — S12 picks the older, clean-skipped arm |
| 7 | Pipe the log into `grep \| head -1` under `pipefail` instead of reading a temp file | RED — S15 (1.5 MB log) becomes `unresolved` |

**Harness rows:**

| # | Suite edit | Expected |
|---|---|---|
| H1 | Scenario runner swallows the script's rc, or runs zero rows | RED — every row asserts rc and stdout; the final `passed == expected` check fails on zero rows |
| H2 | must-PASS non-canonical input: S1's fixture log also contains an unrelated 40-hex SHA before the `depth=1 origin` line | PASS with the `depth=1 origin` SHA |

**Anchor.** No stored value is compared; fixture SHAs are generated by the test's own git repo at run
time.

### Guard 2 — served-build containment (`deploy-arm.sh contains`)

**Property.** `contains` passes exactly when the served `build_sha` equals or descends from the
merge, and an unmeasurable `build_sha` never reads as a mismatch.

**Assembly.** The same ancestry helper as Guard 1; consumers are `postmerge/SKILL.md` Phase 3 and
`ship/SKILL.md` protocol step 2 and line ~2467, which must call `contains` rather than compare
strings (static row).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Compare `BUILD_SHA == MERGE_SHA` only | RED — S11 `D` must be `CONTAINS` |
| 2 | Map empty / `dev` / non-hex `BUILD_SHA` to `NOT_CONTAINED` | RED — S11 empty row expects `UNRESOLVED` rc 3 |
| 3 | Reverse the ancestry direction | RED — S11 `A` must be `NOT_CONTAINED` |

## Acceptance Criteria

- [ ] `plugins/soleur/scripts/deploy-arm.sh` exists, is executable, passes `shellcheck`, and
      implements `find` and `contains` with the stdout/rc contract in §Proposed Solution 1.
- [ ] `bash plugins/soleur/test/deploy-arm.test.sh` passes, runs S1-S18 plus the static rows, and
      ends with a `passed == expected` check that fails on zero rows.
- [ ] Guard 1 rows 1, 2 and 5 and Guard 2 row 1, applied to a scratch copy of the script, each turn
      the suite red (one line each in the PR body).
- [ ] `postmerge/SKILL.md` Phase 3.7 contains the copy-able `deploy-arm.sh find` block with the
      `=~ ^[0-9]+$` run-id check and the REASON table; `ship/SKILL.md` lines ~26, ~2467 and ~2469
      carry the replacements in §Proposed Solution 3 (static rows in the test enforce both).
- [ ] `python3 scripts/lint-skill-body-budget.py --base origin/main` prints `OK`, and
      `wc -c` of both SKILL.md files is no larger than on `origin/main`.
- [ ] `bash plugins/soleur/test/workflow-run-deploy-invariants.test.sh` passes.
- [ ] `bun test plugins/soleur/test/workflow-fidelity.test.ts` passes (protocol sentinels intact).
- [ ] `git diff --name-only origin/main...HEAD` does not list
      `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` or
      `.github/workflows/web-platform-release.yml`.
- [ ] Live smoke (read-only, recorded in the PR body):
      `bash plugins/soleur/scripts/deploy-arm.sh find 71e7585eae756389b815f12b490062db4347be04`
      prints `ARM=35577957665 DEPLOYED_SHA=71e7585e… MATCH=exact DEPLOY=success` (or a newer
      non-skipped exact arm, if CI for that commit was re-run), and
      `bash plugins/soleur/scripts/deploy-arm.sh contains 71e7585eae756389b815f12b490062db4347be04 "$(curl -s --max-time 10 https://app.soleur.ai/health | jq -r .build_sha)"`
      prints `CONTAINS`.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal tooling change to the ship/postmerge verification
predicate; no user-facing surface, no data, no infrastructure.

## Test Scenarios

`find` rows use `run_attempt: 1` unless stated. "log `X`" means the arm's `resolve-target` log carries
`depth=1 origin <sha of X>`.

| # | Setup | Expected |
|---|---|---|
| S1 | first guess returns one completed arm, log `M`, `deploy` success (log also has an unrelated 40-hex earlier — H2) | `ARM=<it> DEPLOYED_SHA=M MATCH=exact DEPLOY=success`, rc 0 |
| S2 | (#8391) first guess returns arm1 (log `A`) listed before arm2 (log `M`) | selects arm2, exact |
| S3 | (#8297) first guess empty; window has an arm stamped with a later SHA whose log = `M` | selects it, exact |
| S4 | only arm in window has log `D`, `deploy` success | `MATCH=descendant`, `DEPLOYED_SHA=D` |
| S5 | ci.yml run for `M` `in_progress`; window has only an arm with log `A` | `ARM=none REASON=ci_pending`, rc 4 |
| S6 | ci.yml run for `M` completed; only arm has log `A` | `ARM=none REASON=no_candidate`, rc 3 |
| S7 | ci.yml completed; only candidate's `resolve-target` completed 10 minutes ago but its log endpoint returns 404 | `ARM=none REASON=unresolved`, rc 3 |
| S8 | only arm has log `L` (pushed to origin `main` after the clone) | fetched after listing → `MATCH=descendant` |
| S9 | `MERGE_SHA` is 7 chars | rc 2, stderr names the 40-char requirement |
| S10 | only arm has log `X` (unrelated branch) | `ARM=none REASON=no_candidate`, rc 3 |
| S11 | `contains M` with build `M`, `D`, `A`, `""`, `dev`, unknown 40-hex | `CONTAINS`, `CONTAINS`, `NOT_CONTAINED`, `UNRESOLVED`, `UNRESOLVED`, `UNRESOLVED` |
| S12 | `run_attempt: 2`; two exact arms, the older with `deploy` skipped (`ci_not_green`), the newer success | selects the newer |
| S13 | a candidate created before a readable descendant arm is still pending (`resolve-target` in progress) | `ARM=none REASON=arm_pending`, rc 4 |
| S14 | exact arm `deploy` skipped (`ci_not_green`); a later arm with log `D` has `deploy` success | selects the descendant (`MATCH=descendant`) |
| S15 | log is 1.5 MB with the `depth=1 origin` line near the top | exact, not `unresolved` (pipefail/SIGPIPE row) |
| S16 | a cancelled run with no `resolve-target` job sits beside the real exact arm | cancelled run dropped; exact selected |
| S17 | window spans two pages returned newest-first | earliest descendant chosen across pages |
| S18 | only candidate's `resolve-target` completed 1 minute ago; log endpoint returns 404 | `ARM=none REASON=arm_pending`, rc 4 (grace window) |
| static | the rows in §Proposed Solution 4 | as listed |

## Dependencies & Risks

- **Log availability lag:** a job's log endpoint can 404 briefly after the job completes. Inside a
  3-minute grace window the script reports `arm_pending` (poll); after it, `unresolved`
  (stop, could-not-measure). Neither is ever converted into a match or a mismatch.
- **Arm log retention:** logs expire with repo retention (90 days); irrelevant for a post-merge check.
- **Descendant acceptance vs. gate validation:** for Phase 3.7 (did a deploy gate change survive a
  real deploy?) a descendant arm deploying a tree that contains the change still exercises the gate,
  so accepting it is correct. The script reports `MATCH=descendant` so the report can say so.
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

## References & Research

- Issue #8492; incidents #8297, #8391, #8265, #8276, #8135.
- `knowledge-base/project/learnings/2026-09-20-the-deploy-arm-that-said-success-had-deployed-someone-elses-commit.md`
- `.github/workflows/web-platform-release.yml:207-264` (resolve-target, checkout pin), `:403-420`
- ADR-217 (`knowledge-base/engineering/architecture/decisions/ADR-217-the-deploy-fires-on-cis-completion-event-and-the-verdict-never-crosses-as-a-value.md`) — split topology; not changed by this plan.
- `scripts/lint-skill-body-budget.py`, `plugins/soleur/test/skill-body-budget.json`
- `plugins/soleur/test/workflow-run-deploy-invariants.test.sh` Guard 8 (lines ~853-905)
