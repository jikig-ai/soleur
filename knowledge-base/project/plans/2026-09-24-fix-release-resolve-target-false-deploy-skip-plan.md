---
title: "fix(release): resolve-target must not clean-skip a deploy on an empty runs lookup"
date: 2026-09-24
slug: fix-release-resolve-target-false-deploy-skip
branch: feat-one-shot-release-false-deploy-skip
issue: none
closes: none
pr: 8770
type: bug
priority: p1
domain: engineering
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
lane: cross-domain
---

# fix(release): resolve-target must not clean-skip a deploy on an empty runs lookup

## Overview

The deploy arm of the Web Platform Release workflow decides whether a SHA has a release to
deploy by asking the GitHub runs API once. An empty answer is read as "this push touched no
deployable path", and the run ends green without deploying. On 2026-09-24 that answer was empty
for a SHA whose release had been published thirteen minutes earlier, so production stayed on the
previous build until someone re-ran the job. This plan makes an empty answer insufficient on its
own to skip a deploy.

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

This is PR 1 of 4 in a sequence of follow-ups. Scope is the release workflow fix only: the
`resolve-target` job, its two consumers of the skip vocabulary, the two test suites that pin it,
and the ADR-217 amendment that records the changed inference. No issue is filed; the fix lands
directly in draft PR #8770.

## Problem Statement

`.github/workflows/web-platform-release.yml` → job `resolve-target` → step `resolve` (the
`workflow_run` arm, "Step 1: THE VERDICT") does:

```bash
runs_json=$(gh_api \
  "repos/$REPO/actions/workflows/web-platform-release.yml/runs?event=push&head_sha=$WR_HEAD_SHA&per_page=50" \
  --jq '[.workflow_runs[] | {id: .id, status: .status, conclusion: .conclusion}]')
...
if [ -z "$run_id" ] || [ "$run_id" = "null" ]; then
  # STATE 1 — no push-arm run exists for this SHA. ...
  clean_skip "$WR_HEAD_SHA" "no Web Platform Release run exists for this SHA (on.push.paths declined it)" "no_release_run"
fi
```

`no_release_run` is a clean skip: exit 0, `should_deploy=false`, and both alert channels treat it
as "nothing was due" (`notify-gated` excludes it; `release-outcome` puts it in its not-paging arm).
So a transient empty answer produces a green run, no deploy, and no notification.

**Measured incident (verified 2026-09-24 via the API, not taken from the brief):**

| fact | value |
|---|---|
| SHA | `ee9f2c94241f0093728e880bd4f591e88bdd64db` (PR #8732, C4 render sandbox + stale banner) |
| push-arm run | `36047804812`, created 19:23:22Z, completed `success` 19:31:21Z |
| deploy-arm run | `36050118687` attempt 1, `resolve-target` 19:44:48Z → 19:45:04Z |
| attempt-1 annotation | `deploy skipped — no Web Platform Release run exists for this SHA (on.push.paths declined it)` |
| same query now | returns `36047804812` |
| recovery | attempt 2, started 19:49:09Z |

The filtered query was stale for **at least 13 minutes after the run completed** (21 minutes after
it was created). A 60-second retry alone would not have recovered this incident.

## Research Reconciliation — Spec vs. Codebase

| Claim (brief / ADR / in-file comment) | Reality (measured) | Plan response |
|---|---|---|
| Empty answer = "on.push.paths declined" (ADR-217 §3 row 1, in-file STATE 1 comment) | 1 of 10 attempt-1 `no_release_run` verdicts in the last 200 runs of this workflow was false (ee9f2c9, 20 deployable files). The other 9 were correct (0 deployable files each). | Empty is no longer sufficient; a diff check discriminates the two. |
| "The same query returned that run minutes later, so the empty answer was transient API lag" (brief) | Confirmed. Also measured today: `?event=push&per_page=5` returns a newest run dated 2026-09-10 while many 2026-09-24 push runs exist; the unfiltered list is current. GitHub documents these params as "search" params (up to 1,000 results per search). | Add a second lookup via the unfiltered list, filtered client-side. |
| "retry the lookup with backoff (e.g. 3 x 20 s)" (brief) | Lag in the incident was ≥13 min, so retry alone would have turned a silent skip into a loud fail, not a deploy. | Keep the retry (it covers short lag) AND add the unfiltered fallback (it covers long lag). |
| `HEAD~1..HEAD` touching the release pathspec implies a push-arm run exists | Holds for single-commit pushes. For a multi-commit push GitHub diffs `before..after`, a superset, so "head commit matches" still implies "push matched". The reverse can fail (an earlier commit matched, the head did not), and it is **reachable**: the repo allows rebase-merge and merge-commit merges (`gh api repos/jikig-ai/soleur` → `allow_rebase_merge: true, allow_merge_commit: true`), so a rebase-merged PR ending in a docs-only commit pushes a range whose head diff is empty. GitHub's documented 3,000-file cap is the only case where a match might not produce a run. | The diff check only decides how to read an empty answer. It never overrides a run that was found, and it never runs before the lookup. The reverse gap is a residual risk, covered in practice by the fallback lookup and the retries, which run whatever the diff says. |
| Discriminator validated? | Run against the 10 observed SHAs: ee9f2c9 → 20 deployable files; the 9 true docs-only SHAs → 0 each (one of them a 2-parent merge commit). | Clean separation on real data. |

## Proposed Solution

Three changes to step `resolve`, all on the `workflow_run` arm, plus consumers and tests.
[Revised 2026-09-24 after plan review; see `## Plan Review Revisions`.]

### 1. Two independently served reads, retried

Replace the single query with a lookup loop in the main shell:

1. **Primary read, unchanged:** the existing filtered query
   (`?event=push&head_sha=$WR_HEAD_SHA&per_page=50`), with its existing projection and own-run
   select. It stays byte-compatible with G7's `runs\?[^"]*event=push` regex, and existing row X1
   still covers it.
2. **Fallback read, only if the primary is empty:** the unfiltered list
   `repos/$REPO/actions/workflows/web-platform-release.yml/runs?per_page=100`, which takes no search
   params. Select client-side with
   `[.workflow_runs[] | select(.event == "push" and .head_sha == $sha) | .id] | sort_by(.) | last // ""`.
   There is no own-run conjunct: this run is always `event: workflow_run`, so `.event == "push"`
   already excludes it, and a conjunct no test can kill is noise.
   **Coverage:** measured at about 70 runs a day (200 runs from 2026-09-22T00:11Z to
   2026-09-24T20:09Z), so page 1 covers about 1.4 days. The push run is created at push time,
   one CI duration (about 20 min) before this job runs. A months-later operator re-run falls
   outside page 1, but the primary search is reliable at that age.

**Retry, as the brief asks:** up to **4 lookups** (the initial one plus 3 retries), with
`sleep 20` between them. `RELEASE_LOOKUP_ATTEMPTS=4` and `RELEASE_LOOKUP_BACKOFF_S=20` are
literal local constants. Each retry logs `no push-arm run found for <sha> (lookup N/4) —
retrying in 20s`. A found run breaks the loop at once, so the normal deploy path pays no
latency. The retry always runs on an empty result, including for docs-only SHAs. That costs up
to 60 s on runs that deploy nothing, and it keeps the retry independent of the diff check, which
can miss one case (Reconciliation row 4). Two reviewers (DHH, simplicity) argued for cutting the
retry, because the fallback is what would have fixed the incident. It is kept because the
operator specified it, and it is recorded as a challenge in
`knowledge-base/project/specs/feat-one-shot-release-false-deploy-skip/decision-challenges.md`.

**ERREXIT: make the sharp edge structurally impossible.** At the top of the step body:

```bash
set -euo pipefail
shopt -s inherit_errexit   # a gh_api fail_closed inside ANY $( ) now kills the caller too
exec 3>&1                  # annotations go to the job's real stdout, never into a capture
```

`fail_closed` and `clean_skip` send their `::error::`/`::notice::` lines to `>&3`. Today, a
`gh_api` failure inside `x=$(gh_api …)` prints its `::error::` into the capture and loses the
annotation (Kieran P1-1; this already happens today on every `github_api_unavailable`). The loop
itself is still written as plain statements in the main shell (`_j=$(gh_api …)` simple
assignments, no `$( )` around a function that performs reads). `inherit_errexit` is the
backstop, not a licence to capture it.

### 2. The diff check that reads an empty result

Only when the run id is still empty after all lookups:

```bash
set -f
_drc=0
# shellcheck disable=SC2086  # deliberate word-split into git pathspecs (same as check_changed)
_changed=$(git diff --no-renames --name-only "${WR_HEAD_SHA}~1" "$WR_HEAD_SHA" -- $RELEASE_PATH_FILTER) || _drc=$?
set +f
if [ "$_drc" -ne 0 ]; then
  fail_closed "no push-arm release run was found for $WR_HEAD_SHA after $RELEASE_LOOKUP_ATTEMPTS lookups, and its diff could not be computed (git rc=$_drc), so on.push.paths declining it cannot be proven — refusing to treat this as a docs-only push" "release_run_missing"
fi
if [ -n "$_changed" ]; then
  fail_closed "no push-arm release run was found for $WR_HEAD_SHA after $RELEASE_LOOKUP_ATTEMPTS lookups (filtered + unfiltered), but its diff touches deployable paths ($(printf '%s' "$_changed" | head -3 | tr '\n' ' ')) — a release was due and GitHub run search is most likely lagging" "release_run_missing"
fi
clean_skip "$WR_HEAD_SHA" "no Web Platform Release run exists for this SHA and its diff touches no deployable path (on.push.paths declined it)" "no_release_run"
```

- **The explicit SHA, not `HEAD`.** `git diff` names `$WR_HEAD_SHA` and its first parent, so the
  answer is about the commit the event carried.
- **`--no-renames`.** By default `git diff` reports a rename by its destination only, so a file
  moved OUT of `apps/web-platform/` would read as "no deployable path". Listing both sides errs
  toward the loud failure (Kieran P2).
- **Pathspec source.** A new step env `RELEASE_PATH_FILTER`, byte-identical to
  `jobs.release.with.path_filter`, which is the git-dialect mirror of `on.push.paths` that
  `check_changed` already uses with the same `git diff` shape. A job cannot read another job's
  `with:`, and `env` is not available in a reusable-workflow `with:`, so the string is copied.
  Invariants row P1 pins the copy, and B8 separately binds `path_filter` to the drift checker's
  `PATHSPEC`. An empty value lists every file and fails loud. An unset value exits red under
  `set -u`. No extra guard is needed.
- **Checkout depth.** `resolve-target`'s `actions/checkout` gains `fetch-depth: 2`. Its `ref:`
  pin to the event SHA is unchanged. `check_changed` uses depth 2 with no `ref:`; with a SHA ref,
  checkout v4 fetches that commit at depth 2, and Kieran's review confirmed this works. Without
  depth 2, `~1` fails (rc 128, measured). Every docs-only SHA would then fail closed and Slack
  would fire on every docs push, which is loud and safe but noisy. Row L6 and invariants row P2
  pin it.
- **Fail closed, not `should_deploy=true`.** The brief allows either. With no run id there is no
  artifact, version or image, and `migrate`/`deploy` gate on those. The fallback read is what
  turns most of these into real deploys.

### 3. Vocabulary: one new fault reason, `release_run_missing`

- `notify-gated` `if:` gains `needs.resolve-target.outputs.skip_reason == 'release_run_missing' ||`.
- `notify-gated` `case` gains:
  `release_run_missing) CAUSE='no release run could be found for this SHA although its changes touch the web platform — GitHub run search is most likely lagging. Use "Re-run failed jobs" on THIS run; if resolve-target fails the same way again, wait about 15 minutes and retry. Do not re-run the push-arm release, which already published' ;;`
- The shared `MESSAGE` trailer ("re-run the release once CI is green for this SHA") contradicts
  that CAUSE (CTO P1). Make the trailer depend on the reason: for `release_run_missing` and
  `github_api_unavailable`, the trailer says "re-run the failed jobs on this run". Every other
  reason keeps the current wording.
- `release-outcome` needs **no edit**. The new reason is not in its not-paging arm, so it falls
  through to `classify resolve-target failure`: an email plus the Sentry event. A dedicated
  email arm was considered and deferred (see decision-challenges). G9's extractor counts any
  `release-outcome` case arm that names a produced reason as a clean skip, so adding one would
  red the disjointness check.
- `plugins/soleur/skills/ship/references/settle-then-admin-merge.md` lists the deploy-arm states
  for the post-merge reader. Add `release_run_missing`: the job goes red, Slack and email fire,
  and recovery is "Re-run failed jobs" on the deploy-arm run (Kieran P2).

### 4. Prose that states the old inference

Rewrite every place that says "empty → on.push.paths declined":

- the `THE FIVE STATES` comment table above `resolve-target`, row 1, plus a new row for
  `release_run_missing`;
- the in-step `STATE 1` comment. It should also state the assumption the fallback relies on: the
  push run is created at push time, before CI completes, so it exists before this arm starts;
- the liveness-poll comment ("a docs-only push creates no push-arm run at all, and takes the
  no_release_run clean skip before reaching here"), which should now say the skip comes after the
  diff check;
- the `timeout-minutes: 15` sizing comment, which should note that docs-only runs now take up to
  about 60 s longer (at least 14x headroom remains; the declared ceiling and B9 are unchanged);
- ADR-217 §3 (see Architecture Decision).

## Research Insights

**Premise Validation.** Every cited reference was checked. Run `36050118687` attempt 1's
`resolve-target` annotation reads `deploy skipped — no Web Platform Release run exists for this SHA
(on.push.paths declined it)` at 19:44:48Z. Push run `36047804812` for the same SHA completed
`success` at 19:31:21Z. The same query today returns it. `ee9f2c9` is on `main` (#8732). Nothing
cited was stale. The brief's "3 x 20 s" figure is **insufficient on its own**: the measured lag
was ≥13 min, so this plan adds a fallback read.

**Property List.**

- P1: A SHA whose push-arm release run exists is never clean-skipped because a runs lookup
  answered empty.
- P2: A SHA with no push-arm run (the diff touches no deployable path) still clean-skips GREEN,
  with no Slack and no email.
- P3: When an expected release run cannot be found, the run fails LOUD with a distinct reason, so
  Slack, email and Sentry all fire and name the cause.
- P4: A GitHub API failure on any lookup read fails closed (`github_api_unavailable`). It never
  degrades to "no run".

**Cut List.**

- Mechanism: "keep `should_deploy=true` on an empty result" → P1 → cut. There is no run id, so
  there is no artifact, version or image, and the deploy chain gates on those. P3's fail-loud
  covers it.
- Mechanism: a new `check-suites`/`check-runs` lookup → P1 → cut. The unfiltered workflow list is
  already a non-search read, and the research agent found both checks endpoints equally
  undocumented on consistency.
- Mechanism: a derived wait constant tied to CI duration → cut, per ADR-217's existing rejection
  ("a derived constant is one more thing that can drift"). The retry uses literals.
- Plan-review cuts (see Plan Review Revisions): the client-side select on the primary read (it
  buys no property: the defect was an empty answer, not a wrong one); the own-run conjunct in the
  fallback (already excluded by `.event == "push"`); the empty-pathspec guard (P1 parity makes the
  state unshippable, and an empty pathspec already fails loud); the standing sed-mutant battery
  and static line-order row (L1/L7 cover them behaviourally).

**Measured data (commands in this session):**

- `gh api …/runs?per_page=100&page={1,2}`: 200 runs back to 2026-09-22T00:11Z. Recovered the SHA
  each attempt-1 `no_release_run` actually resolved, from the `resolve-target` log line
  `resolving deploy target for <sha>`. Only ee9f2c9 had a push run.
- Pairing deploy arms to SHAs by the **run object's** `head_sha` is wrong. That field is main's
  tip at trigger time, not the commit deployed (learning
  `2026-09-20-the-deploy-arm-that-said-success-had-deployed-someone-elses-commit.md`). The first
  pass of this analysis made that mistake and found "10 false skips" and a phantom
  concurrency-group violation. Recovering the SHA from the log corrected both.
- `git diff --name-only <sha>~1 <sha> -- <path_filter>` on the 10 SHAs: 20 files for ee9f2c9, 0 for
  each of the other 9.

**External (best-practices-researcher):**

- GitHub REST "List workflow runs for a workflow": *"This endpoint will return up to 1,000 results
  for each search when using the following parameters: actor, branch, check_suite_id, created,
  event, head_sha, status."* <https://docs.github.com/en/rest/actions/workflow-runs>. GitHub does
  not document consistency; community reports of filtered-query lag:
  <https://github.com/orgs/community/discussions/21980>.
- `on.push.paths`: pushes to an existing branch use a two-dot `before..after` diff. If the diff
  exceeds **3,000** files and the matching file is not among the first 3,000, the workflow does
  not run. Pushes of more than 1,000 commits, or a diff timeout, always run.
  <https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions#onpushpathspaths-ignore>
- `[skip ci]` suppresses push/pull_request workflows only. It suppresses both CI and this
  workflow's push arm, so with no CI completion there is no deploy-arm event to misread.

**Relevant files:**

- `.github/workflows/web-platform-release.yml`: `resolve-target` (checkout, step `resolve`,
  `gh_api`, `clean_skip`/`fail_closed`); `notify-gated` (`if:` + `case`); `release-outcome` (the
  not-paging `case`, unchanged).
- `.github/workflows/reusable-release.yml` `check_changed`: the same `git diff --name-only HEAD~1
  -- $PATH_FILTER` shape under `set -f`, checkout `fetch-depth: 2`.
- `plugins/soleur/test/resolve-target-decision.test.sh`: executes the extracted step body with a
  `gh` stub. Floor 24.
- `plugins/soleur/test/workflow-run-deploy-invariants.test.sh`: static G3/G7/G9/G12 plus a
  structural mutation battery. Floor 70. G9 enforces the skip_reason partition.
- `scripts/prod-version-drift-check.sh` `PATHSPEC` and `scripts/prod-version-drift-check.test.sh`
  B8/B9: B8 pins `path_filter` parity, and B9 reads `resolve-target`'s declared `timeout-minutes`
  (unchanged).
- `scripts/lint-workflow-errexit-capture.py` (ADR-170): the `x=$(…) || _rc=$?` idiom is the
  sanctioned capture.
- `scripts/guard-vacuity-floor.test.sh`: keep `TOTAL=` and `MIN_ROWS=` adjacent to the floor `if`.
- Wiring: `scripts/lib/test-affected-paths.sh` and `scripts/suite-shard-legs.tsv` (decision suite
  on shard 1, about 16.7 s; invariants on shard 3, about 4 s).

**Institutional learnings applied:**

- `2026-09-20-the-deploy-arm-that-said-success-had-deployed-someone-elses-commit.md` and
  `2026-09-23-a-green-deploy-arm-had-deployed-the-parent-commit.md`: identify a deploy arm by what
  it resolves, not by its label. The analysis above and post-merge verification follow this.
- `2026-06-08-ci-gate-fail-open-traps-skip-token-grep-and-buildkit-cache-mode.md` and
  `2026-04-27-preflight-security-gates-skip-vs-fail-defaults.md`: a three-state gate hides
  fail-open when "transient/unknown" collapses into SKIP. This plan separates them.
- `2026-03-20-ci-deploy-reliability-and-mock-trace-testing.md`: drive stub ordering with trace
  markers (here a call-counter file per URL class plus a `sleep` stub log), not ad-hoc temp state.

**Baselines (this session):** `resolve-target-decision.test.sh` 24/24,
`workflow-run-deploy-invariants.test.sh` 70/70 (mutation battery 5/5),
`c4-count-parity.test.sh` all passed.

**Related open issues:** #8498 (publish the deployed SHA via run-name). This is adjacent: it
concerns identifying the deploy arm, not resolving the release run. Acknowledged, not folded in.
#8007 (release announcement not gated on deploy success) is unrelated to the lookup.

## Files to Edit

- `.github/workflows/web-platform-release.yml`
  - `resolve-target` → `actions/checkout`: add `fetch-depth: 2`.
  - `resolve-target` → step `resolve` → `env:`: add `RELEASE_PATH_FILTER` (byte-identical to
    `jobs.release.with.path_filter`).
  - Step `resolve` body:
    - add `shopt -s inherit_errexit` and `exec 3>&1`;
    - send the `fail_closed`/`clean_skip` annotations to `>&3`;
    - add the 4×20 s lookup loop (the primary read unchanged, plus the unfiltered fallback);
    - add the diff check, with the `release_run_missing` fail-closed before the
      `no_release_run` clean skip.
  - Comments: the FIVE STATES table, STATE 1 (including the push-run-exists-first assumption), the
    liveness-poll note, the `timeout-minutes` sizing note.
  - `notify-gated`: the `if:` conjunct, the `case` arm for `release_run_missing`, and the trailer
    that depends on the reason.
- `plugins/soleur/test/resolve-target-decision.test.sh`: see Test Scenarios.
- `plugins/soleur/test/workflow-run-deploy-invariants.test.sh`:
  - add row P1 (pathspec parity) and row P2 (checkout `fetch-depth` ≥ 2 or `0`);
  - G8's accepted-token `case` gains the code form `.event == "push"`, because the fallback URL
    `…/web-platform-release.yml/runs?per_page=100` matches G8's consumer regex and its window
    carries no `event=push` (Kieran P1-2);
  - add a must-PASS row for that token and a must-RED row: the same window with the select
    removed must still be flagged;
  - raise the floor.
- `plugins/soleur/skills/ship/references/settle-then-admin-merge.md`: add the
  `release_run_missing` state to the deploy-arm state list.
- `knowledge-base/engineering/architecture/decisions/ADR-217-the-deploy-fires-on-cis-completion-event-and-the-verdict-never-crosses-as-a-value.md`:
  add a `## Amendment — 2026-09-24` section and fix the §3 table row 1.

## Files to Create

None.

## Open Code-Review Overlap

None. 79 open `code-review` issues were checked against all four planned paths plus the tokens
`resolve-target`, `no_release_run` and `ADR-217`; there were zero matches.

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-217** (no new ADR). §3's table row 1 ("no push-arm run for this SHA → `on.push.paths`
declined → clean skip, green") encodes the inference this incident falsified. The amendment:

- An empty lookup is read as "`on.push.paths` declined" **only after** 4 lookups over two
  independently served reads (filtered search plus unfiltered list) **and** a diff check
  (`git diff <sha>~1 <sha> -- path_filter`) shows no deployable path.
- An empty lookup for a SHA whose diff touches deployable paths, or whose diff cannot be
  computed, is a seventh state: `release_run_missing`, **fail closed, loud**.
- Rationale: incident run `36050118687` (≥13 min of filtered-search staleness). Alternatives
  rejected: retry-only (measured lag exceeds any reasonable in-job wait), `should_deploy=true` on
  empty (nothing deployable without the artifact), and a check-suites lookup (no better
  documented consistency).
- Status stays `Accepted`. Follow the existing amendment convention
  (`## Amendment — <date> (<ref>)`, as in ADR-006).

### C4 views

**No C4 impact.** All three model files were checked (`model.c4` 861 lines, `views.c4`, `spec.c4`):

- (a) External human actors: the notified operator is `founder`, and the Slack/email/Sentry
  channels are existing edges. None is added.
- (b) External systems: `github` (Actions + REST API), `resend`, `sentry`. All are already
  modeled. The new read is GitHub's own API from inside a GitHub-hosted job, an internal
  `github` behaviour and not a new edge (the model states that no `github -> github` edge can
  exist).
- (c) Containers/data stores: none touched.
- (d) Access relationships: unchanged.

`model.c4` names `web-platform-release.yml` only in the Sentry-store edge prose (line ~769), which
this change does not affect. Required backing: `bash plugins/soleur/test/c4-count-parity.test.sh`
green. The baseline passes; re-run it at work time.

### Sequencing

The amendment ships in this PR, describing the state as it stands after the PR.

## Guard Contract

The guards here are the behavioural rows of the decision suite and invariants rows P1/P2. The
mutation matrices below are **design** (written before the code). They are executed **once at work
time**, each as a `sed` on a scratch copy with a `cmp -s` landing check. The kill evidence (the
mutation, the row that went red, the rc) goes into the PR body. They are **not** kept as a
standing sed battery inside the suite. Three reviewers (DHH, simplicity, CTO) agreed that
text-coupled mutants would break on every later rewording of step `resolve`; see Plan Review
Revisions.

### Guard 1 — empty-lookup discriminator

**Property.** No execution of `resolve-target` on the `workflow_run` arm emits
`skip_reason=no_release_run` for a SHA whose `<sha>~1..<sha>` diff (with `--no-renames`) touches
the release pathspec, or whose diff cannot be computed.

**Assembly.** The single chokepoint is the one `clean_skip … "no_release_run"` call site in step
`resolve` of job `resolve-target`. Every path that reaches it must first pass (a) the lookup loop
ending empty, then (b) the diff check returning rc 0 with empty output. The pathspec flows
through one env var, `RELEASE_PATH_FILTER`, which the harness reads out of the workflow YAML (it
does not restate it) and which invariants row P1 binds to `jobs.release.with.path_filter`. A
second `no_release_run` emitter placed before the diff is a second member. L1 catches it
behaviourally (row 3 below).

**Mutation matrix:** run once at work time; evidence in the PR body.

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the diff check, so empty → `clean_skip no_release_run` unconditionally (the pre-fix code) | RED — L1 |
| 2 | Guard's own dispatch: `_changed=$(git diff …) \|\| true`, so a diff failure reads as "no deployable path" | RED — L6 |
| 3 | Second member: add a second `clean_skip "$WR_HEAD_SHA" "…" "no_release_run"` right after the first empty lookup (before the retries and the diff) | RED — L1 |
| 4 | Reorder: move the diff check BEFORE the lookup and clean-skip on no-match without looking | RED — L7 (docs-only head commit, but the push run exists → must deploy) |
| 5 | Workflow copy: `RELEASE_PATH_FILTER` drifts from `path_filter` (drop `apps/web-platform/`) | RED — invariants P1, and L1 (the harness reads the env from the YAML copy) |
| 6 | Workflow copy: remove `fetch-depth: 2` from the resolve-target checkout | RED — invariants P2 |
| 7 | Drop `--no-renames` | RED — L8 (a rename out of `apps/web-platform/` + empty lookups → must be `release_run_missing`) |

Rows 5 and 6 are standalone checks run on a sed-mutated copy of the workflow, not entries in the
invariants `mutate()` battery. `MUTPRED` scores only `sha`, `before`, `lv-push`, `branches`,
`workflows` and `wf-name`, so it would report these as SURVIVED (Kieran P1-3).

**Harness rows:**

- H1 (a suite edit that must go RED): hardcode `RELEASE_PATH_FILTER` in `run_resolve` instead of
  reading it from the YAML. Then mutation 5 no longer reddens L1. This is run once at work time,
  and it demonstrates that the YAML read is what couples the suite to the shipped pathspec.
- H2 (must-PASS, non-canonical): the `pdocs` commit (touches only `plugins/soleur/docs/x.md`)
  plus empty lookups → `no_release_run`, rc 0. This proves the `:(exclude)` members are honoured
  and that the guard does not reject everything.

**Anchor.** `RELEASE_PATH_FILTER` and `path_filter` live in the same file, so one diff can weaken
both. P1 proves consistency, not integrity. The external anchor is B8 in
`scripts/prod-version-drift-check.test.sh`, which also binds `path_filter` to
`scripts/prod-version-drift-check.sh` `PATHSPEC`, a separate file that a reviewer sees move.

### Guard 2 — lookup completeness

**Property.** If a push-arm run for the SHA exists in either read (filtered or unfiltered) on any
of the 4 lookups, `resolve-target` resolves it and never reaches the empty branch. A failed read
fails closed and never counts as "empty".

**Assembly.** The lookup loop is the only producer of the run id on the `workflow_run` arm. Its
two reads both go through `gh_api`, whose fail-closed propagates through `inherit_errexit` plus
the plain-statement shape (Proposed Solution §1). The fallback's jq select is its own.

**Mutation matrix:** run once at work time; evidence in the PR body.

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the retry (a single lookup) | RED — L2 (filtered empty on lookups 1–2, found on 3 → must deploy) |
| 2 | Remove the unfiltered fallback | RED — L3 (filtered always empty, unfiltered has the run → must deploy) |
| 3 | Guard's own dispatch: remove `shopt -s inherit_errexit` AND wrap the loop as `run_id=$(lookup_fn)` | RED — A2 (exact `rc -eq 1`, exactly one `skip_reason=` line equal to `github_api_unavailable`) |
| 4 | Second member: drop `.event == "push"` from the fallback select | RED — X2 (the list offers this SHA's `workflow_run` run, id 1000 > 777 → must pick 777) |
| 5 | Second member: drop `.head_sha == $sha` from the fallback select | RED — X2 (a NEWER push run 778 for another SHA is offered → picking it trips identity_mismatch) |

**Harness rows:**

- H3 (a suite edit that must go RED): revert `get()` from `tail -1` to `head -1`. Then, against
  mutation 3, A2's skip_reason assertion reads the subshell's first emit
  (`github_api_unavailable`) and only the rc check remains. The added "exactly one
  `skip_reason=` line" assertion is what keeps A2 killing it (Kieran P1-1). Run once at work time.
- H4 (must-PASS): L7, a docs-only diff whose push run is found, deploys. A lookup guard that
  rejects everything cannot pass it.

## User-Brand Impact

- **If this lands broken, the user experiences:** either (a) a merged fix that never reaches
  production. The app keeps serving the previous build with no alert, which is exactly the
  2026-09-24 incident. Or (b) a false "deploy GATED — prod NOT updated" Slack/email on every
  docs-only push, if the diff check misfires (for example, with the checkout depth missing).
- **If this leaks, the user's data / workflow / money is exposed via:** no exposure vector. The
  change reads public Actions metadata and a git diff with the job's existing `actions: read` /
  `contents: read` token. No new secret, permission or egress.
- **Brand-survival threshold:** `aggregate pattern`. Silent staleness compounds across merges
  (users see fixed bugs persist), but no single-user data incident is possible here.

## Observability

```yaml
liveness_signal:
  what: "resolve-target's per-run verdict annotation — ::notice::deploy skipped — <reason> or ::error::deploy blocked — <reason> — plus the skip_reason job output"
  cadence: "per main CI completion (every workflow_run arm run)"
  alert_target: "Slack releases channel (notify-gated), operator email ops@jikigai.com via Resend (release-outcome), Sentry event (release-outcome)"
  configured_in: ".github/workflows/web-platform-release.yml (jobs resolve-target, notify-gated, release-outcome)"

error_reporting:
  destination: "Sentry via release-outcome's store-API POST using secrets.NEXT_PUBLIC_SENTRY_DSN; email via secrets.RESEND_API_KEY"
  fail_loud: "resolve-target exits 1 with ::error::deploy blocked — no push-arm release run was found for <sha> after 4 lookups … (skip_reason=release_run_missing); notify-gated posts CAUSE 'no release run could be found for this SHA although its changes touch the web platform …'"

failure_modes:
  - mode: "runs search lag outlasts all 4 lookups AND the unfiltered page misses the run, for a SHA with deployable changes"
    detection: "resolve-target fails closed with skip_reason=release_run_missing (red job)"
    alert_route: "Slack (notify-gated) + email + Sentry (release-outcome)"
  - mode: "a GitHub API read in either lookup fails 3 times"
    detection: "gh_api fail_closed → skip_reason=github_api_unavailable (unchanged path; row A2 pins that the fallback read is covered)"
    alert_route: "Slack + email + Sentry"
  - mode: "diff cannot be computed (checkout depth regressed, parent unfetchable)"
    detection: "fail_closed release_run_missing with 'its diff could not be computed (git rc=N)'"
    alert_route: "Slack + email + Sentry"
  - mode: "docs-only SHA (expected)"
    detection: "clean skip no_release_run after 4 lookups, green, log shows 'lookup N/4' lines"
    alert_route: "none by design (nothing was due)"

logs:
  where: "GitHub Actions job log + check-run annotations for resolve-target (public repo: readable unauthenticated via the REST API)"
  retention: "GitHub Actions log retention for the repo (90 days default)"

discoverability_test:
  command: "curl -s --max-time 10 \"https://api.github.com/repos/jikig-ai/soleur/actions/workflows/web-platform-release.yml/runs?per_page=1\""
  expected_output: "workflow_runs"
```

(The probe reads the public repo's run list without authentication. It contains no `|`, `;`, `&`,
`<`, `>`, `$` or backtick, so it passes preflight Check 10's shell-active reject. The verdict
annotation for a given run is at `…/check-runs/<resolve-target job id>/annotations`, which is also
public.)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected. This is an infrastructure/tooling change confined to one
CI workflow's decision logic and its tests. There is no UI surface (the mechanical UI-surface
override was checked, and no Files-to-Edit path matches), no regulated data, no new
infrastructure, and no new store or connection (Phases 2.7, 2.8 and 2.11 skip).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `bash plugins/soleur/test/resolve-target-decision.test.sh` exits 0, with the floor
  raised to the derived total stated in its derivation comment. `TOTAL=` and `MIN_ROWS=` stay
  directly above the floor `if`.
- [ ] AC2: **The requested row (L1).** The fixture commit touches `apps/web-platform/x.ts`, and
  both runs reads return `[]` on all 4 lookups. Expected: `rc=1`, `should_deploy=false`, exactly
  one `skip_reason=` line in `$GITHUB_OUTPUT`, and its value is `release_run_missing` (so it is
  not `no_release_run`).
- [ ] AC3: `bash plugins/soleur/test/workflow-run-deploy-invariants.test.sh` exits 0. G9 reports
  no orphan or phantom for `release_run_missing`; P1, P2 and the G8 token rows pass; the floor is
  raised.
- [ ] AC4: the PR body carries a mutation-evidence table covering every Guard 1/Guard 2 mutation
  and harness rows H1/H3: the mutation, the `cmp -s` landing check, the row that went RED, and the
  observed rc. A mutation whose sed did not land is recorded as a failure and redone, never as a
  kill.
- [ ] AC5: `bash scripts/prod-version-drift-check.test.sh` stays green (B8 path_filter parity; B9
  unchanged because `timeout-minutes: 15` is unchanged).
- [ ] AC6: `python3 scripts/lint-workflow-errexit-capture.py` (no args; it scans every workflow)
  prints `lint-workflow-errexit-capture: clean` (baseline: clean, 83 workflows).
- [ ] AC7: `bash plugins/soleur/test/c4-count-parity.test.sh` green (backs "no C4 impact").
- [ ] AC8: the ADR-217 amendment exists, and §3 row 1 no longer states that an empty lookup alone
  means `on.push.paths` declined.
- [ ] AC9: anchored, not bare-token (`cq-assert-anchor-not-bare-token`):
  - `grep -cF "skip_reason == 'release_run_missing'" .github/workflows/web-platform-release.yml` returns 1 (the `notify-gated` `if:`);
  - `grep -cE '^\s*release_run_missing\)' .github/workflows/web-platform-release.yml` returns 1 (the `case` arm);
  - `grep -cE 'fail_closed .*"release_run_missing"$' .github/workflows/web-platform-release.yml` returns 2 (the two diff-arm producers).

### Post-merge (automated verification, no operator step)

- [ ] AC10: this PR's merge commit touches `plugins/soleur/skills/ship/references/`, a deployable
  path under `on.push.paths`, so its push arm publishes a release. The deploy-arm run for the
  merge SHA must reach `deploy: success`. Identify that run by the SHA in `resolve-target`'s log
  line `resolving deploy target for <sha>`, not by the run's `head_sha` label (learning
  2026-09-20). Its log shows either `release run: <id>` on lookup 1, or `lookup N/4` lines
  followed by a found run, and never a `no_release_run` notice.

(An earlier AC11, "the next app-touching deploy-arm run deploys", was cut by the plan-review
standing check `cq-ac-must-not-depend-on-concurrent-sessions`. Whether it holds depends on other
PRs' merges and not on this diff. The found-run path is pinned deterministically by the CONTROL
row plus L2, L3 and L7.)

## Test Scenarios

Harness changes in `plugins/soleur/test/resolve-target-decision.test.sh`:

- **`get()` reads the LAST emit** (`grep … | tail -1`). Every row that expects a skip or a
  failure also asserts exactly one `^skip_reason=` line. A swallowed failure emits twice (once
  inside the subshell, once from the caller), and GitHub keeps the last value for a repeated
  output key. Reading the first value hid that case (Kieran P1-1).
- **`gh` stub:** route `*/runs\?*head_sha=*` → `runs.json`, which may be a sequence
  `runs.json.1`, `runs.json.2`, … served by one counter file `$FIX/.n_filtered` (needed only for
  L2). Route any other `*/runs\?*` → `runs_all.json`. Put the `head_sha` route FIRST. Fixtures
  carry the real list shape
  (`{"total_count":N,"workflow_runs":[{"id","event","head_sha","status","conclusion"}]}`,
  verified live in this session). `--jq` delegates to real `jq -r`, as it does today.
- **`mkfix`** also writes `runs_all.json` (default `{"total_count":0,"workflow_runs":[]}`).
  Existing rows are otherwise untouched: the primary read and its projection are unchanged, and
  X1 keeps killing removal of the own-run exclusion.
- **`sleep` stub** on `$W/bin`: it appends to `$W/sleep.log` and returns at once. The retry is
  kept, so without the stub each empty-lookup row would pay 60 s. It also speeds up A1's
  existing 5+10 s.
- **One real git fixture repo**, linear, built after
  `source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"` (which arms the #7833 tripwire) with
  `git_fixture_env "$W" || exit 1` (`plugins/soleur/AGENTS.md` §Test Fixture Conventions;
  `plugins/soleur/test/fixture-env-adoption.test.sh` reddens on a mutating `git` spawn that
  bypasses it). The existing `trap 'rm -rf "$W"' EXIT` stays ABOVE the `source` line. Commits
  in order:
  - `root` (seeds `apps/web-platform/moved.ts`);
  - `docs` (`knowledge-base/x.md`);
  - `app` (`apps/web-platform/x.ts`);
  - `pdocs` (`plugins/soleur/docs/x.md`);
  - `ptest` (`plugins/soleur/test/x.sh`);
  - `mvout` (`git mv apps/web-platform/moved.ts other/moved.ts`).

  Each row that reaches the diff sets `WR_HEAD_SHA` to its commit and runs the body with
  `CWD=$W/repo`. Kieran confirmed that `root~1` fails with rc 128, `docs` gives rc 0 and empty
  output, and `app` lists the file.
- **`set -e` from `test-helpers.sh`:** sourcing it turns on `set -e` in the harness, so the
  CONTROL row's bare `( … )` would abort before the VOID message. Rewrite it as
  `if ( … ); then pass; else …; fi`.
- **`RELEASE_PATH_FILTER` comes from the workflow, not from the harness.** The PyYAML extractor
  also reads the step's `env.RELEASE_PATH_FILTER`, and `run_resolve` passes it through.

Rows (existing rows keep their labels, `SHA_OK` and artifacts; S1 moves onto the fixture repo):

| id | setup | expected |
|---|---|---|
| S1 | `docs` commit, both reads `[]` | `no_release_run`, rc 0, one `skip_reason` line; `sleep.log` has exactly 3 entries |
| **L1** | `app` commit, both reads `[]` | `release_run_missing`, rc 1, one `skip_reason` line (the requested row) |
| L2 | `SHA_OK`, filtered `[]`, `[]`, then the run; unfiltered `[]` | deploys; `sleep.log` has 2 entries |
| L3 | `SHA_OK`, filtered always `[]`, unfiltered has the push run | deploys; 0 sleeps |
| L5 | `pdocs` commit, both `[]` | `no_release_run`, rc 0 (H2 must-PASS) |
| L6 | `root` commit, both `[]` | `release_run_missing`, rc 1 (diff uncomputable) |
| L7 | `docs` commit, filtered has the push run (artifact built with the `docs` SHA) | deploys (a found run is never overridden by the diff) |
| L8 | `mvout` commit, both `[]` | `release_run_missing`, rc 1 (a rename out of the pathspec is deployable) |
| A2 | `docs` commit (so a swallowed failure WOULD read as a clean skip), filtered `[]`, unfiltered fixture missing (stub exits 23) | rc exactly 1, one `skip_reason` line = `github_api_unavailable` |
| X2 | `SHA_OK`; filtered `[]`; unfiltered lists `{1000, workflow_run, SHA_OK}`, `{778, push, OTHER}`, `{777, push, SHA_OK}` | selects 777 (`release run: 777` in stdout), deploys |

The `ptest` commit is not given its own row. It sits between `pdocs` and `mvout` so that `mvout~1`
is a normal commit, and the `test/` exclusion has the same shape as `docs/`, which L5 covers.

Invariants suite (`plugins/soleur/test/workflow-run-deploy-invariants.test.sh`) new rows:

- P1: `resolve-target` step `resolve` env `RELEASE_PATH_FILTER` == `jobs.release.with.path_filter`
  (PyYAML, byte-identical).
- P2: the `resolve-target` checkout declares `fetch-depth` of 0 or ≥ 2.
- G8: the `.event == "push"` token is accepted, with a must-PASS row (the real fallback window)
  and a must-RED row (the same window with the select removed is still flagged).
- G9 needs no edit; it picks up the new reason automatically.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Retry only (the brief's minimum) | Measured lag ≥13 min, so it would not have deployed the incident SHA. Kept as a layer, as specified, not as the fix. |
| Cut the retry entirely (DHH, simplicity review) | The operator specified it. Recorded as a User-Challenge in `decision-challenges.md`; the operator's direction stands. |
| `should_deploy=true` on empty-with-deployable-diff | No run id means no artifact, version or image; `migrate`/`deploy` gate on those. It would run a deploy chain against nothing. |
| Diff FIRST: an empty diff clean-skips at once with no lookup, and a non-empty diff polls (scoped advisor consult, Step 4.5) | It would regress rebase-merged PRs whose last commit is docs-only. Today the lookup finds their push run and deploys; diff-first would skip them every time, not only under lag. Rebase-merge is enabled on this repo. This is Guard 1 mutation 4, and L7 kills it. The advisor's other point, that the default outcome under any slip must be red and not green, is adopted through `inherit_errexit` and row A2. |
| Unfiltered list FIRST, filtered search as the fallback (DHH P2) | It is equally correct. It is not adopted, because it touches the primary read that X1 and G7 pin, for no property gain. Taste; recorded in `decision-challenges.md`. |
| Stub `git` in the body harness instead of a fixture repo (advisor) | A stub would replay the harness author's reading of `:(exclude)` and rename semantics, the fake-agrees-with-writer class. One linear repo serves every row that reaches the diff, and the existing 24 rows keep `SHA_OK`, which was the advisor's actual concern. |
| A standing sed-mutant battery inside the decision suite | Text-coupled mutants break on every later rewording of step `resolve` (DHH, simplicity, CTO). The matrix runs once at work time, with its evidence in the PR body. |
| A static "single `no_release_run` producer, after the diff" row | A brittle line-order check for something L1 and L7 cover behaviourally (DHH, simplicity). Cut. |
| YAML anchor (`&release_paths` / `*release_paths`) instead of copying the pathspec (CTO P2) | GitHub Actions accepts anchors, but whether actionlint and every PyYAML extractor in the repo accept them was not verified at plan time. Copy plus P1 parity is the verified path. Taste; recorded. |
| A dedicated `release-outcome` email arm for `release_run_missing` (CTO P1) | G9's extractor classifies any `release-outcome` case arm that names a produced reason as a clean skip, so adding one reds the disjointness check. It needs a G9 extractor change first. Deferred to decision-challenges; the email still fires through the generic resolve-target failure arm. |
| Retry only when the diff matches (saves up to 60 s on docs-only runs) | Makes the retry depend on the diff check, which misses one case (multi-commit pushes). Runner seconds on non-deploying runs are cheap. |
| Diff via the REST `commits/{sha}` files list instead of git | Adds a third path-filter dialect (a bash `case` over the GitHub glob) and a 300-files-per-page pagination edge. The git pathspec reuses `check_changed`'s exact semantics. |
| Look up via `commits/{sha}/check-suites` → `?check_suite_id=` | `check_suite_id` is itself a documented *search* param on the runs list, and the consistency of both is undocumented. |

## Dependencies & Risks

- **Residual risk:** a multi-commit push (a rebase-merge or merge-commit merge, both enabled here)
  whose head commit is docs-only, but where an earlier commit touched deployable paths, *and*
  filtered-search lag outlasts 60 s, *and* the push run is not on the unfiltered page 1. The
  result is the old silent skip. That takes three coincident conditions. Page 1 covers about 1.4
  days of this workflow's runs (measured at about 70 a day), and the push run is created about 20
  minutes before this job, so the third is implausible. The production drift alerter
  (`scripts/prod-version-drift-check.sh`, `*/30`, same `PATHSPEC`) is the independent backstop. It
  pages when prod is missing any commit that matches the pathspec, whatever the push shape.
- **Risk:** GitHub docs do not guarantee the unfiltered list's ordering. Mitigation: the select
  is order-independent (`sort_by(.) | last`), and only page-1 *membership* is relied on.
- **Risk:** `fetch-depth: 2` on a checkout pinned to a SHA ref. `check_changed` uses depth 2 with
  no `ref:`. With a SHA ref, checkout v4 fetches that commit at depth 2. Kieran confirmed this
  works; row L6 and P2 pin the failure mode.
- **Risk:** `shopt -s inherit_errexit` changes how every existing `$( )` in the step behaves.
  Every existing capture is either a `gh_api` read (which already exits the subshell through
  `fail_closed`'s explicit `exit 1`) or a `jq`/`printf` pipeline. The existing 24 rows are the
  regression net and must stay green unchanged.

## Plan Review Revisions

The panel was DHH, Kieran, code-simplicity and the CTO (devex lens), plus the Step 4.5 advisor
consult. Two panels fired on the same scope:

- The simplification panel (DHH + simplicity) fired on the harness battery, the static
  line-order row, the primary-read select, the own-run conjunct and the empty-var guard.
- The correctness panel (Kieran) fired on the same harness battery (G1-M5/M6 unkillable) and on
  A2's kill mechanism.

Deleting the machinery dissolved the correctness findings (see the plan-review rule "prefer
delete over fix").

**Applied as Mechanical:**

- Kieran P1-1: `get()` reads the last emit; rows assert exactly one `skip_reason` line; A2
  asserts rc exactly 1. `inherit_errexit` plus `exec 3>&1` make the errexit edge structural and
  keep annotations out of captures.
- Kieran P1-2: G8 accepts `.event == "push"`, with must-PASS and must-RED rows.
- Kieran P1-3: G1-M5/M6 become standalone sed-copy checks run at work time, not `mutate()`
  entries.
- Kieran P2s:
  - corrected the run rate (about 70 a day; page 1 covers about 1.4 days);
  - added `--no-renames` and row L8;
  - rewrote CONTROL as `if ( … )`;
  - P2 also accepts `fetch-depth: 0`;
  - corrected the checkout claim;
  - added the ship reference doc consumer.
- Cuts (DHH + simplicity): the standing sed battery (the matrix now runs once, with evidence in
  the PR); static row P3; the client-side select on the primary read; the own-run conjunct in the
  fallback; the empty `RELEASE_PATH_FILTER` guard; the per-route counters (one counter remains,
  for L2's sequence); five fixture repos collapsed to one linear repo.
- Simplicity: AC9 is anchored instead of counting bare tokens, and the STATE 1 comment states the
  push-run-exists-first assumption.
- CTO P1 (Slack): the CAUSE names "Re-run failed jobs" on THIS run plus the ~15-minute wait
  advice, and the trailer depends on the reason. This is a factual fix to a message that
  contradicted itself.

**Not applied (persisted to `specs/feat-one-shot-release-false-deploy-skip/decision-challenges.md`):**

- User-Challenge: cut the retry (DHH, simplicity). The operator specified it, so it stays.
- Taste: read the unfiltered list first (DHH).
- Taste: YAML anchor for the pathspec (CTO).
- Taste/deferred: a dedicated release-outcome email arm (CTO; blocked on G9's extractor).
- Deferred to PRs 2–4 (CTO): automatic re-run on `release_run_missing`; de-duplicating the drift
  alerter's page against this alert.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits
  the threshold will fail `deepen-plan` Phase 4.6.
- **Errexit in command substitution.** Keep the lookup loop as plain statements in the main shell
  even with `inherit_errexit` on. Never wrap a function that performs `gh_api` reads in `$( )` or
  `if`/`||`/`&&`, where bash suspends `-e` regardless of `inherit_errexit`. A2 is the behavioural
  pin.
- **Pairing deploy arms to SHAs.** In post-merge verification, recover the deployed SHA from
  `resolve-target`'s log (`resolving deploy target for <sha>`). The run object's `head_sha` is
  main's tip at trigger time.
- **`set -f` around the pathspec word-split.** Without it, `:(exclude)` tokens and any glob
  characters reach the shell's globbing. The `|| _drc=$?` capture keeps execution linear, so one
  `set +f` after it restores globbing on both arms.
- **G7 regex** `runs\?[^"]*event=push` must keep matching the primary query literal. Do not
  reformat that line into a variable.
- **The floor adjacency** (`TOTAL=` then `MIN_ROWS=` then the `if`) must stay contiguous, or
  `scripts/guard-vacuity-floor.test.sh` counts the floor as unconstructible.
- **A repeated `$GITHUB_OUTPUT` key keeps its last value.** Any test that reads outputs must read
  the last one and assert the count. Reading the first is how a swallowed failure passes.
- **This PR's own merge deploys** (it touches `plugins/soleur/skills/ship/references/`). That is
  expected (AC10), and not a sign the diff check misfired.
