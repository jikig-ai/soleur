---
title: "fix: the S4 observation-window probe must resolve the PR of a merged-PR run"
date: 2026-10-28
slug: observation-window-probe-merged-pr-resolution
branch: feat-one-shot-observation-window-probe-merged-pr-resolution
issue: 10865
type: fix
priority: p2
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

Spec lacks valid lane: no `spec.md` exists for this branch, so `lane` defaulted to `cross-domain` (TR2 fail-closed). PR text uses `Ref #10865`, `Ref #11306`, `Ref #10861`, `Ref #10448` only; this plan has no `closes:` key on purpose.

## Enhancement Summary

**Deepened on:** 2026-10-28
**Sections enhanced:** 6 (Observability added, precedent diff added, Guard 1 row 6 made coherent, exit-code claims verified, shared literals reconciled, tasks.md propagated)
**Research agents used:** CTO (rulings F1-F5, re-ruling R1-R6), learnings-researcher, plan-review panel (DHH, Kieran, code-simplicity); deepen-plan ran its halt gates 4.6-4.13 inline and live read-only probes instead of a 40-agent fan-out (the change is one bash file plus its stub suite).

### Key Improvements
1. `## Observability` section with the 5-field schema and a sandbox-safe `discoverability_test` (the unauthenticated probe run prints `CANNOT ESTABLISH`), replacing the earlier "not triggered" paragraph.
2. Precedent diff against `scripts/registry-delivery-change.sh` `resolve_pr_for_sha` (same endpoint, stricter acceptance rule, reason stated).
3. Verified live: gh's own exit codes are 0, 1, 2, 4 (`gh help exit-codes`; 8 for pending checks), so the probe's return codes 44/45 cannot collide; `timeout` uses 124-127 and 137.

### New Considerations Discovered
- A mutation row cannot say "must stay green" inside a must-go-RED matrix; Guard 1 row 6 is now a per-PR-vs-per-run counting mutant killed by a second run on the same PR in `ow_u_resolved`.
- `phase=facts-done` carries the live gate's denominator on stderr only, so `row_ow_progress`'s token ban and 500-byte cap stay valid (the line grows by about 20 bytes).

## Overview

The follow-through probe `scripts/followthroughs/ratchet-observation-window-10865.sh` (tracker #10865, series #10861, epic #10448) reads each pull_request run's PR from the run's own
`pull_requests[0].number` and drops runs where it is empty as "a fork run". GitHub empties that field once the PR merges, so the oldest-250 prefix the probe reads (all merged PRs)
yields a distinct-green-PR count of 0 by construction and the window can never certify. This plan (1) resolves the PR of such a run from its head commit, (2) re-derives the
planned-reads accounting and the facts-phase allowance for the real PR count, (3) adds the CTO-ruled bounded retry, (4) fixes the cosmetic `set -u` abort, and (5) corrects the header
and runbook wording that claim an unmoving "earliest prefix". All five are implemented in the probe, its stub-gh rows in `plugins/soleur/test/ci-pr-affected-replay.test.sh`, and the
runbook. Nothing about what the window certifies changes except that merged PRs can now be counted.

## Research Insights

**Premise Validation (Phase 0.6).** Checked: #10865, #11306 and #10861 are all OPEN (`gh issue view`); no open PR names #10865 or the probe; the collision pre-check reported only two
`test-all.sh` processes owned by an unrelated worktree (`feat-one-shot-8628-inngest-4-upgrade`), no PR and no overlap with the files of this plan. The probe, the replay suite section
(`ratchet observation window (#10865)`) and the runbook section `The observation log` exist on this branch. The brief's measurements were re-taken read-only on 2026-10-28 (11 listing
pages, 25 spot lookups, 2 error-shape lookups, ~45 requests on the user token): of 1000 listed pull_request runs 551 are cancelled, 298 failure, 151 success, 0 are fork runs; the
oldest listed run is 2026-10-24T21:23:16Z (the window opened 2026-10-23T15:41:52Z), so the 1,000-result cap already moved the prefix; of the oldest 250 non-cancelled runs 245 have an
empty `pull_requests`, 249 distinct head SHAs, 81 distinct head branches (88 are run-conclusion success on 88 shas / 64 branches; 162 are run-conclusion failure, and a failure run can still carry a
green ratchet job because that job is `continue-on-error`). `GET commits/<sha>/pulls` returned exactly one PR (closed/merged, same repo, `head.ref` equal to the run's branch)
for 23 of 25 sampled runs and `[]` for 2; an unknown sha answers HTTP 422 `No commit found for SHA`; the returned PR's `head.sha` is usually a LATER push than the run's sha
(sampled: run sha `649f619d...` -> PR 11016 head `a4273d9f...`), so a `head.sha` equality check would wrongly drop resolvable runs. ADR-corpus check: no ADR decides the resolution mechanism;
`scripts/registry-delivery-change.sh` already uses `commits/<sha>/pulls` (comment: measured on #6326 that it resolves a merge-commit PR to the branch's PR) so the endpoint has repo precedent.
The runbook and the replay suite are NOT oracle inputs: the probe's `ORACLE` array is `.github/workflows/ci.yml`, `scripts/ci-pr-affected-replay.py`, `plugins/soleur/scripts/lint-ratchet.py`,
`scripts/ci-pr-affected-audit.accept.tsv`, `scripts/lib/test-affected-paths.sh`, `scripts/test-all.sh` and the baseline; this plan edits none of them and no row of
`scripts/ci-pr-affected-audit.baseline.tsv`.

**Property List (Phase 0.6b).**
- P1. A green pull_request unit whose run names no PR counts toward the distinct-PR count iff its head commit identifies exactly one PR of this repository that belongs to that run's branch and existed when the run was created.
- P2. A run that cannot be so identified is excluded from every count and never aborts the sweep.
- P3. Fork runs, canary branches and non-green units spend no resolution request.
- P4. The planned-reads guard still fails closed (exit 3 before any read, never a smaller plan) and now models the real request classes; the facts phase has an allowance that fits the real PR count inside the sweeper's 15 minute job limit.
- P5. One transient 5xx or timeout does not cost a whole night; a 403/429 still stops all reads.
- P6. A sweep with zero PR units prints its phase line and exits with its verdict, never aborting.
- P7. The probe header and the runbook no longer claim that the earliest prefix latches or that an empty `pull_requests` means a fork run.

**Cut List (Phase 0.6b).**
- Server-side `status=` filtered listing (stop 551 cancelled runs filling the cap) -> buys window coverage, not P1-P7; cancelled runs are already skipped before any jobs read -> CTO F4: OUT, tracked as a deferral on #11306.
- Per-branch lookup (`pulls?head=`), merge_group branch-name derivation, resolving every prn==0 run, early-stop of the facts loop -> each rejected by the CTO (F1, F2) with the rationale in `decision-challenges.md`.
- A resolver cache of any kind (per-sha file cache, persisted cache) -> 249 distinct shas in 250 runs means about zero hits and nothing persists between sweeps -> CTO R1.
- A 12th unit column, a second counter, a production retry-sleep seam, a `created_at` identity clause and a second retry call site -> each cut at plan review for buying no property of P1-P7 -> CTO R2, R3, R5, R6.

**Institutional learnings applied.** `2026-09-25-gh-stub-must-mirror-real-cli-flags.md` (the new stub handlers answer only real `gh api` argv); `2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md` (every new function gets a mutation hitting it); `2026-09-08-both-my-anti-vacuity-gates-ran-through-the-line-that-voided-them.md` (path operands must be provably absolute: `fixture-relative-assert`); `2026-09-07-every-instrument-i-built-to-check-my-own-work-could-not-tell-clean-from-never-ran.md` (xtrace refusal needs a must-PASS arm; the lint takes positional paths); `2026-10-25-draining-an-index-by-declaring-edges-reveals-pairs...md` (a literal tracked path in a suite becomes an audit pair - the new fixtures use synthetic names and 40-hex shas only); `2026-06-05-followthrough-pr-body-prose-closes-keyword-autocloses-tracker.md` (`Ref` only, in the PR title, body and commit bodies); `2026-03-24-gh-api-paginate-concatenated-arrays.md` (one page only on the resolver: `per_page=2`, no `--paginate`); `2026-07-23-gh-run-list-truncation-reports-false-all-settled.md` (a listing at its cap is an incomplete read, reported as `truncated`).

## Research Reconciliation - Spec vs. Codebase

| Claim in the brief | Reality (measured / read) | Plan response |
|---|---|---|
| "commit `commits/<head_sha>/pulls` resolves a merged PR" | True for 23 of 25; `[]` for 2; HTTP 422 for an unknown sha; PR `head.sha` is often a later push | Resolve with the identity checks of CTO F1; never compare `head.sha`; `[]`, 422 and 404 are "unresolved" |
| "the existing planned-reads accounting `2 per run, 5 per PR, 200 reserve` must be updated" | At ~80 PRs the old formula is ~1,125 > the ~1,000/h sweeper token: a permanent exit 3. The live run spent 267 for 214 units (~1.25 per run) | New pre-read feasibility formula (CTO F2), prints `planned=` beside `used_delta` |
| "line ~353 `${#PR_EXCLUDED[@]}` aborts" | Confirmed by the 2026-10-28 live run (bash 5.3); older bash versions may not abort, so a mutant restoring it can survive there | Plain integer `facts_prs`; behavioural row plus a static no-`${#PR_EXCLUDED` row; mutation row on the counter (version independent) |
| "earliest prefix latches" in the header and runbook | Wrong since the listing hit its 1,000-result cap: the prefix moves forward | Wording corrected in both (CTO F4) |
| Brief item 3 "optional retry only if the CTO rules it in scope" | CTO F3: IN scope; plan review (R3, R6) removed the planned test seam and the second retry site | Implemented as one fixed-`sleep 2` retry in `gh_get`; the baseline read is routed through it |

## Files to Edit

- `scripts/followthroughs/ratchet-observation-window-10865.sh` - resolver, `gh_get` return codes 44/45 and the one retry, `raw_baseline` through `gh_get`, quota formula, facts default, `facts_prs`, `pr_unattributed_runs`, header.
- `plugins/soleur/test/ci-pr-affected-replay.test.sh` - stub `gh` handlers (`ERR422_`, `ERR_ONCE_`), `ow_write` cleanup glob, new rows and mutants, updated `row_ow_quota`, `row_ow_argv`, `row_ow_static`, `env -u` lists.
- `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` - `The observation log`: criteria bullet for composition stays; "Reads are bounded" and "Forgery bound" bullets rewritten; a dated observation-log entry.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-observation-window-probe-merged-pr-resolution/decision-challenges.md` (created by this plan: the five CTO rulings).
- `knowledge-base/project/specs/feat-one-shot-observation-window-probe-merged-pr-resolution/tasks.md` (derived from this plan).

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (200) was searched for each of the three edited paths with `jq --arg path ... contains($path)`: no open code-review issue names any of them. Related non-code-review trackers: #11306 (the deferred-items tracker; this PR resolves its items 1-2 of the 2026-10-28 comments and adds the F4 deferral as a comment), acknowledged, not closed.

## Proposed Solution (as ruled)

Rulings F1-F5 and the plan-review re-ruling R1-R6 are in `knowledge-base/project/specs/feat-one-shot-observation-window-probe-merged-pr-resolution/decision-challenges.md` (all `Ruled by CTO agent, 2026-10-28`). Implementation shape, after the re-ruling:

1. **Resolver in `read_unit`** (parallel worker, no cache, no new unit column). After the rerun classification, when `ev=pull_request`, `prn=0`, `fork!=1`, `branch` does not start with `canary-`, `ex=0`, `cls=plain` and `sha` matches `^[0-9a-f]{40}$`: call `api "repos/$REPO/commits/$sha/pulls?per_page=2"`. Return code 44 (HTTP 404) or 45 (HTTP 422) from `gh_get` is unresolved; any other failure is `fail_api "run $id commit pulls"`; a payload that is not a JSON array is `fail_api "run $id commit pulls (parse)"`. A jq program reading the payload on stdin yields `.[0].number` iff `length == 1`, `.[0].head.repo.full_name == $repo`, `.[0].base.repo.full_name == $repo`, `.[0].head.ref == $branch` and the number is a positive integer; otherwise 0. The result replaces column 6 of the unit row (the row keeps its 11 columns). No `created_at` clause (R5).
2. **`gh_get` return codes and the one retry site (R6, F3).** `gh_get` returns 44 for HTTP 404 and 45 for HTTP 422 (never gh's own 1, 2, 4, 8 or timeout's 124-127, 137), decided from `$errf` before it is removed. One helper `transient_err <rc> <errfile>` (rc 124, or stderr matching `HTTP 5[0-9][0-9]`, `EOF`, `connection reset`, `TLS handshake timeout`, `i/o timeout`, `dial tcp`, `Client.Timeout`) drives exactly one retry after a fixed `sleep 2`; the retry is skipped when `$RL_FLAG` exists and never fires for 44, 45, 403, 429, other 4xx or a parse failure. `raw_baseline` is rewritten to call `gh_get -H 'Accept: application/vnd.github.raw' "repos/$REPO/contents/$BASELINE?ref=$1"` (path last) and keeps its contract: 0 read, 4 absent only on rc 44, any other failure (including 45) `fail_api`. `sleep` joins the required-tools loop; there is no new env seam.
3. **Status line and notes (R2).** Append ONE field at the END of the existing status line: `pr_unattributed_runs=N`, counted after the reads by awk over `$GREEN` (pull_request rows whose column 6 is still 0, column 11 `fork` != 1, column 4 branch not `canary-*`). When `distinct == 0` and N > 0 the "only 0 distinct" NOT YET text gains `(N runs could not be attributed to a PR)`. The stderr note becomes `phase=facts-done prs=$facts_prs green_pr_rows=$G` where `G` counts green pull_request rows that are non-fork and non-canary (the live gate's denominator); stderr only, so the status line and the existing `row_ow_progress` token ban stay valid.
4. **Quota guard (R4).** Replace `need=$(( 2*to_read + 5*need_prs + 200 ))` with `need = ceil(1.5*to_read) + ceil(res_cands/2) + 3*pr_est + 100`, in bash `$(( (3*to_read + 1)/2 + (res_cands + 1)/2 + 3*pr_est + 100 ))`, where `res_cands` = pull_request rows in `dispatch.tsv` with `$8==0`, `$10==0` and `$5 !~ /^canary-/`, and `pr_est` = distinct non-zero `$8` among pull_request rows + distinct `$5` among `res_cands` (kind-prefixed columns: `$3`=ev, `$5`=branch, `$8`=prn, `$10`=fork). Print `planned=$need` at the end of the `quota:` line. Fail-closed text and exit 3 unchanged. Worked: live shape (about 260 rows, 245 `res_cands`, 81 PRs) = 390 + 123 + 243 + 100 = 856; base fixture = 12 + 0 + 15 + 100 = 127; resolved fixture = 12 + 2 + 12 + 100 = 126.
5. **Facts phase (F2 X, F5).** `FACTS_BUDGET` default 180 (cap 300 unchanged); `facts_prs=0` initialised before the facts loop and incremented once per PR whose facts are read (inside the main-shell loop, after the cache early-return of `pr_facts`); `${#PR_EXCLUDED[@]}` removed.
6. **Wording.** Probe header: criterion (a) "a PR run that names no PR" -> "a run whose PR cannot be resolved"; "WHAT A PASS CERTIFIES" and the final PASS echo ("certifies the earliest prefix of the window") -> the earliest prefix of the LISTED runs, with the 1,000-result cap stated, no latching, and a pointer to the runbook for the time arithmetic (stated once, in the runbook); the comments at the old `prn != 0` skip and at the quota guard ("oldest 250 runs belong to 4 PRs"). The runbook mirrors them.

Time arithmetic for the runbook only (F2): listing about 25 s, reads typically about 205 s with a hard cut at 300 s, facts at most 180 s checked before each PR (each PR makes up to 3 serial reads, and a hung read can now cost 2 x 60 s + 2 s), baseline about 3 s: typical about 345 s, worst about 520 s plus that tail, against the 900 s sweeper limit (`timeout-minutes: 15`, shared by every tracker; the worst recent whole-sweep run was 231 s).

## Implementation Phases

### Phase 1 - failing tests first (`cq-write-failing-tests-before`)

1. Stub `gh` (heredoc `GHSTUB`): add `ERR422_<key>` (stderr `gh: No commit found for SHA (HTTP 422)`, rc 1) and `ERR_ONCE_<key>` (first call: remove the marker, print `gh: HTTP 502`, rc 1; later calls serve the fixture); change the stub's own two `sleep` calls to `command -p sleep` so the no-op `sleep` stub below cannot swallow `SLOW_`/`HANG_`. Both new handlers answer only real `gh api` argv.
2. A no-op logging `sleep` stub in a dedicated directory (`$BIN/nosleep/sleep`, appends its argv to `$GHLOG.sleeps`), prepended to PATH inside `ow_probe` and `ow_probe_split` only (not `row_ow_trap`, not `row_ow_xtrace`).
3. `ow_write`: extend the cleanup glob with `"$GHFIX"/*_commits_*_pulls_*`, `"$GHFIX"/ERR422_*`, `"$GHFIX"/ERR_ONCE_*`; helpers `ow_commit_pulls <sha> <json>` (`fx "repos/$R/commits/$1/pulls?per_page=2"`) and `ow_pr_obj <n> <branch> [head repo] [base repo]`.
4. Add the rows and mutants of **Test Scenarios**; run `bash plugins/soleur/test/ci-pr-affected-replay.test.sh` and record that the new rows are RED against the unmodified probe.

### Phase 2 - the probe

Implement items 1-6 of **Proposed Solution** in `scripts/followthroughs/ratchet-observation-window-10865.sh`. Constraints that bit the last change: the xtrace refusal `case "$-" ... esac` stays DIRECTLY below `set -uo pipefail` (`lint-shell-trace-credential-refusal` Rule A); every new path operand is rooted at the literal `"$WORK/..."` (`fixture-relative-assert`; fix the code, never the baseline); no API payload on a jq argv (the resolver jq reads stdin; only the small scalars `repo` and `branch` ride on argv and `row_ow_argv` is updated); the new identity check is spelled `.head.repo.full_name == $repo and .base.repo.full_name == $repo` so the existing mutant `fork-head-repo-ignored` (which matches the `pr_facts` `elif` text) still lands exactly once; no new tracked-path literal (audit pair); exit 1 stays unreachable.

### Phase 3 - runbook and header

Rewrite the two runbook bullets (and the criteria/exit-code bullets only where they mention the fork or latch claims) and add a dated observation-log entry.

### Phase 4 - local gates, then one live verification

Run, in this order: the replay suite; `bash plugins/soleur/test/fixture-relative-assert.test.sh`; `python3 scripts/lint-shell-trace-credential-refusal.py scripts/followthroughs/ratchet-observation-window-10865.sh` (positional path); `bash scripts/lint-shell-trace-credential-refusal.test.sh`; `python3 scripts/lint-guard-contract.py <this plan>`; `python3 -I scripts/ci-pr-affected-replay.py ratchet` (no new pair, no baseline growth); `bash -n` and `shellcheck` if installed. Then ONE live read-only run on the user token (about 600 requests, planned budget about 856): put the token in the environment without command substitution (`umask 077`; `gh auth token > <scratch file>`; `read -r GH_TOKEN < <scratch file>`; `export GH_TOKEN`; `rm -f <scratch file>`), run `SOAK_PROGRESS=1 bash scripts/followthroughs/ratchet-observation-window-10865.sh`, and record in the PR body: exit code, `green_pr_units_distinct_prs`, `pr_unattributed_runs`, `green_pr_rows` (from the stderr note), `units_read`/`truncated`, `quota: used_delta` against `planned`, and which criteria are unmet if the exit is 2. **Gate (CTO R-ruling):** exit 0 or 2 (never 3) AND `green_pr_units_distinct_prs > 0` AND `green_pr_rows > 0` AND `pr_unattributed_runs * 4 < green_pr_rows`, else stop and re-weigh; if the gate fails do NOT loosen the identity checks, re-measure on the 25-sample first. A `used_delta` above `planned` or within 10% of it is a stop-and-reweigh finding. Never run collect, ejections, aggregate or verdict.

### Phase 5 - ship (not part of this planning run)

PR title and body use `Ref #10865` only. Comment on #11306 (never #10865) the F4 deferral. Merge-queue mode: BEHIND is expected, never hand-sync. There is no deploy artifact (the sweeper runs the probe from `main`), so served-SHA verification is not applicable; the next nightly sweeper comment on the tracker is the post-merge evidence.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `bash plugins/soleur/test/ci-pr-affected-replay.test.sh` exits 0 with every `window probe:` row and `probe mutant` row green, and the new rows were RED on the unmodified probe (recorded in the PR body).
- [ ] `bash plugins/soleur/test/fixture-relative-assert.test.sh` and `python3 scripts/lint-shell-trace-credential-refusal.py scripts/followthroughs/ratchet-observation-window-10865.sh` pass without any baseline edit; `git diff --stat origin/main...HEAD -- 'scripts/*.baseline.txt' scripts/ci-pr-affected-audit.baseline.tsv scripts/ci-pr-affected-audit.accept.tsv` is empty (three-dot: merge-queue mode leaves the branch BEHIND).
- [ ] `git diff origin/main...HEAD --name-only` lists no ORACLE input (`.github/workflows/ci.yml`, `scripts/ci-pr-affected-replay.py`, `plugins/soleur/scripts/lint-ratchet.py`, `scripts/ci-pr-affected-audit.accept.tsv`, `scripts/lib/test-affected-paths.sh`, `scripts/test-all.sh`, the baseline).
- [ ] `grep -A1 '^set -uo pipefail$' scripts/followthroughs/ratchet-observation-window-10865.sh` shows the `case "$-" in` xtrace refusal on the next line.
- [ ] The probe contains no `${#PR_EXCLUDED` text; `phase=facts-done prs=` is printed from `facts_prs`.
- [ ] `grep -n 'latches\|never change\|names no PR' scripts/followthroughs/ratchet-observation-window-10865.sh knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` returns no stale claim (the criterion-(a) phrase, the "evidence latches only because the oldest runs never change" sentence and the final PASS echo are rewritten).
- [ ] The Phase 4 live run is recorded in the PR body with the gate fields, exactly one live run, and the gate holds.
- [ ] `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-10-28-fix-observation-window-probe-merged-pr-resolution-plan.md` exits 0.
- [ ] PR title/body/commits contain no closing keyword before an issue number; `gh pr view --json closingIssuesReferences` is empty.

### Post-merge (operator-free)

- [ ] The first nightly sweeper comment on #10865 after merge shows `green_pr_units_distinct_prs` above 0 and no `CANNOT ESTABLISH: API quota`; its `quota:` line is appended to the runbook observation log by a later docs PR (not part of this one).

## Test Scenarios

All rows live in `plugins/soleur/test/ci-pr-affected-replay.test.sh` section `ratchet observation window (#10865)`; fixtures use synthetic names and 40-hex shas (`OW_H13=cccc...`), never a tracked path. Helper `ow_u_resolved` turns the five base pull_request units into prn-0 runs with 40-hex shas (plus a sixth run on PR 11's branch with a second sha, which must not raise the distinct count) whose `commits/<sha>/pulls?per_page=2` fixtures return the matching PR object (`head.ref` = the unit's branch, base and head repo `jikig-ai/soleur`); one of them is a bot PR created 4 seconds before its run (the measured live shape) and must resolve.

| Row | Scenario | Expected |
|---|---|---|
| `row_ow_resolve_merged` | `ow_u_resolved`: four prn-0 runs resolve, the canary run does not call | exit 0 PASS, `green_pr_units_distinct_prs=4`, `pr_unattributed_runs=0`, four commit lookups in GHLOG and none for the canary sha |
| `row_ow_resolve_unresolvable` (table loop) | PR 13's run answers `[]`; two PRs; head repo elsewhere; base repo elsewhere; `head.ref` differs; HTTP 404; HTTP 422 | each exit 2 with `no green DRAFT PR run`, `pr_unattributed_runs=1`, distinct 3; 404 and 422 are requested exactly once (no retry, empty sleep-stub log); none aborts |
| `row_ow_resolve_errors` | persistent 502; 403; 429; a JSON object instead of an array; a stub `gh` exiting 4 with a 401 message (gh's own auth code) | exit 3, one fixed line `CANNOT ESTABLISH: GitHub API read failed (run 5003 commit pulls...)` with no branch name or payload text; 403/429 stop further launches; exit 4 is NOT read as unresolved |
| `row_ow_resolve_scope` | prn-0 runs that must NOT call: a non-green unit (exit 1), an incident, a fork run (`OW_RUNFORK`), a `canary-` branch, a merge_group run, a run whose `pull_requests` is already set, a non-hex sha | no `commits_..._pulls` request for any of them in GHLOG |
| `row_ow_zero_pr_units` | `ow_probe_split` with only merge_group units; and with every PR run unresolved; and the base fixture | zero-unit: exit 2 `only 0 distinct`, stderr has no `unbound variable` and contains `phase=facts-done prs=0`; all-unresolved also prints `(N runs could not be attributed to a PR)`; base: stderr `prs=5` |
| `row_ow_quota` (updated) | base `need=127` (remaining 129 passes, 128 fails with `need=127`); `ow_u_resolved` `need=126`; 403/429 rows unchanged | `quota:` line ends `planned=127` on a pass |
| `row_ow_retry` | fail-once 502 on a jobs read; persistent 502; 403; 429; 404 on a non-resolver read; 502 then 403 on the retry; fail-once 502 on the baseline contents read; with `SOAK_PARALLEL=2`, one read answers 403 at once and a second (`SLOW_`) answers 502 | fail-once: normal verdict, path requested twice, one sleep-stub line; persistent: exit 3 after exactly 2 requests; 403/429/404: exactly 1 request and an empty sleep log; 502-then-403: exactly 2 requests, flag set; baseline fail-once recovers; the flagged-run case requests the 502 path exactly once (the `$RL_FLAG` skip) |
| `row_ow_static` / `row_ow_argv` (updated) | header and argv scan | `SOAK_FACTS_BUDGET_S:-180`, no `${#PR_EXCLUDED`, header names the 1,000-result cap; `found` count and allowed list gain `repo=$REPO branch=$branch` |

Mutants (`ow_mutate`, each old-string unique after the single retry site): identity clause set (one table-driven kill row each for `length == 1` -> `>= 1`, the head-ref clause, the head-repo clause, the base-repo clause); resolver dispatch condition -> `false`; the 404/45 mapping -> `fail_api`; each pre-call scope test (fork, canary, green, sha shape) separately; `facts_prs` increment -> `:`; quota `res` term dropped and the exact-boundary pair; `transient_err` without the `HTTP 5[0-9][0-9]` alternative; the `$RL_FLAG` skip dropped; `-eq 0` -> `-le 1` (two retries); the baseline path not routed through `gh_get`. Existing rows that count requests on a persistently failing path (`row_ow_worker_fail`, `row_ow_stop_after_fail`, `row_ow_api_failure`, `row_ow_quota`) are re-read, not just re-run, because a 5xx now costs two requests.

## Guard Contract

### Guard 1 - resolver identity (the PR a merged run is attributed to)

**Property.** A pull_request unit enters the distinct-PR count only through a PR number taken from the run's own `pull_requests` or resolved from a commit lookup that returned exactly one PR of this repository whose head ref equals the run's branch.

**Assembly.** The single chokepoint is column 6 (`prn`) of the unit rows written by `read_unit` (the only writer of `$UD/*.out`), consumed by the facts loop over `pr_units` and by nothing else; its inputs are exactly three: the listing projection (`pull_requests[0].number`, no call), the resolver result, and the literal `0`. Three guard sites must all hold: the pre-call scope test (event, prn, fork, branch, ex, cls, sha shape), the response identity jq program (length, two repositories, head ref, number), and the downstream `pr_facts` exclusions (canary, fork, oracle) that re-fetch the PR independently of the resolver. `pr_unattributed_runs` is derived from the same rows. A fourth writer of column 6 would be the defect.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `length == 1` loosened to `length >= 1` in the identity program (takes the first of two PRs) | RED (`row_ow_resolve_unresolvable`) |
| 2 | drop the `head.ref == $branch` check | RED (`row_ow_resolve_unresolvable`) |
| 3 | drop the head-repository or the base-repository equality (two mutants) | RED (`row_ow_resolve_unresolvable`) |
| 4 | drop each pre-call fork / canary / green / sha-shape test, separately | RED (`row_ow_resolve_scope`) |
| 5 | the dispatch of the resolver itself: replace the call condition with `false` (a resolver that reports 0 attributed and exits 0 is vacuous) | RED (`row_ow_resolve_merged`: distinct 4 and `pr_unattributed_runs=0` fail) |
| 6 | add a SECOND unit after a compliant first on the same PR (same branch, different sha; `ow_u_resolved` carries it): a mutant that counts distinct per resolved run instead of per PR (drop the `SEEN_KEY` test) | RED (`row_ow_resolve_merged`: distinct must stay 4) |
| 7 | HTTP 404/422 mapped to `fail_api` instead of unresolved; and gh's exit 4 mapped to unresolved | RED (`row_ow_resolve_unresolvable`, `row_ow_resolve_errors`) |

Harness row: the stub's `commits_..._pulls` fixtures are per path, so a stub that answered one PR for every sha cannot exist; the harness edit that must go RED is removing the 4-second bot-PR fixture's `head.ref` (the unit must then be unattributed), and the must-PASS non-canonical input is that bot PR.

Anchor: the guard compares no stored value (nothing persists between sweeps), so the integrity anchor is the downstream `pr_facts` read of `pulls/<n>`, independent of the resolver.

### Guard 2 - the planned-reads guard

**Property.** No read of runs starts when the planned request count does not fit the remaining quota, and a shortfall is exit 3, never a smaller plan.

**Assembly.** The estimate is computed from `dispatch.tsv` alone, before the first worker launches, in one expression; the check `RL_REM - LISTCALLS < need` is the single chokepoint; the runtime backstops (`RL_FLAG` on 403/429, `FAILED_FLAG`) are separate and unchanged.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | drop the `res_cands` term from `need` | RED (`row_ow_quota`, resolved-fixture boundary 126) |
| 2 | drop the `3*pr_est` term | RED (`row_ow_quota`, base boundary 129/128) |
| 3 | count `LISTCALLS` out | RED (`row_ow_quota` exact-boundary pair) |

### Guard 3 - the bounded retry

**Property.** A failed read is retried at most once, and only when it is a timeout or a 5xx/network-class failure with the rate flag unset; a 403, 429, 404, 422, other 4xx or parse failure is never retried.

**Assembly.** `gh_get` (so `api`, `log_api` and the baseline read) is the only `gh` call site in the probe; it goes through the one `transient_err` predicate and one retry counter.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | remove the `HTTP 5[0-9][0-9]` alternative from `transient_err` | RED (`row_ow_retry` fail-once) |
| 2 | ignore `$RL_FLAG` before retrying | RED (`row_ow_retry`, the `SOAK_PARALLEL=2` flagged-run case) |
| 3 | allow a second retry (`-eq 0` -> `-le 1`) | RED (`row_ow_retry` persistent: 2 requests, not 3) |
| 4 | add `HTTP 403` to the predicate | RED (`row_ow_retry` 403: 1 request) |

## User-Brand Impact

- **If this lands broken, the user experiences:** the nightly sweeper comment on tracker #10865 reports a wrong verdict: either a permanent `NOT YET` / `CANNOT ESTABLISH` (the window never certifies - the status quo) or, if the resolver over-attributes, a premature PASS that lets the tracker be closed. Closing #10865 authorizes nothing (PR3b #10859 stays held for the budget owner), and no customer-facing surface is touched.
- **If this leaks, the user's data is exposed via:** nothing new: the probe is read-only on a public repository, holds only `GH_TOKEN` (already declared by the directive), writes nothing, keeps its xtrace refusal and its fixed-line failure messages (no payload text in a public comment).
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** an internal CI follow-through probe with no user data path and no write authority; the worst outcome is an early close of a soak tracker that PR3b separately gates.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Resolve the PR for runs whose `pull_requests` is empty (head_sha -> commits/<sha>/pulls, or another method)." [brief] | Phase 2 item 1; Guard 1; Files to Edit probe | mapped |
| 2 | "The METHOD is a technical fork: spawn soleur:engineering:cto to rule it" [brief] | `decision-challenges.md` F1-F5 | mapped |
| 3 | "the existing planned-reads accounting \"2 per run, 5 per PR, 200 reserve\" must be updated" [brief] | Phase 2 item 3; Guard 2; `row_ow_quota` | mapped |
| 4 | "Cosmetic defect around line 353: `${#PR_EXCLUDED[@]}` on an empty associative array aborts under `set -u` on bash 5.3. Count with a plain integer set in the loop; add a test row with zero PR units." [brief] | Phase 2 item 4; `row_ow_zero_pr_units`, `row_ow_facts_prs` | mapped |
| 5 | "Optional companion, only if the CTO rules it in scope: bounded one-retry on 5xx and timeouts only, never 403/429." [brief] | CTO F3 (IN); Phase 2 item 5; Guard 3; `row_ow_retry` | mapped |
| 6 | "Add test rows in plugins/soleur/test/ci-pr-affected-replay.test.sh (stub gh) covering: merged-PR run with empty pull_requests resolved to its PR and counted; truly unresolvable run still excluded; zero-PR-unit run." [brief] | Test Scenarios rows 1, 2, 7 | mapped |
| 7 | "Update the probe header comment and the runbook ... observation-log wording where they describe the fork/prn=0 rule and the \"earliest prefix latches\" assumption" [brief] | Phase 2 item 6; Phase 3; Files to Edit runbook | mapped |
| 8 | "Run the new probe tests locally and the relevant lints before pushing." [brief] | Phase 4 | mapped |
| 9 | "Do not touch ORACLE inputs or the audit baseline" [brief] | Acceptance Criteria 2-3 | mapped |
| 10 | "Post NOTHING to #10865." [brief] | Phase 5 (deferral comment goes to #11306 only) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| probe file edit | "Resolve the PR for runs whose `pull_requests` is empty" (ask 1) | asked |
| replay suite edit | "Add test rows in plugins/soleur/test/ci-pr-affected-replay.test.sh (stub gh)" (ask 6) | asked |
| runbook edit | "Update the probe header comment and the runbook" (ask 7) | asked |
| `decision-challenges.md` | "Persist every decision as a row of the `| Item | Class | Ruling |` table in knowledge-base/project/specs/<branch>/decision-challenges.md" [brief] | asked |
| new facts-phase default 180 s | "note the existing planned-reads accounting ... must be updated" (ask 3) | inferred - justification: with ~70 PRs the serial facts phase needs ~140 s against 120 s, and a deterministic oldest-first cut repeats nightly, which recreates the never-certifies defect (CTO F2) |
| `planned=` on the `quota:` line | "must be updated" (ask 3) | inferred - justification: the F2 weights are two days of measurements; without the printed figure nothing can show them wrong |
| `pr_unattributed_runs=N` status field and `green_pr_rows` stderr note | "truly unresolvable run still excluded" (ask 6) | inferred - justification: the test must observe exclusion, a systemic resolver failure must be visible in the public comment instead of reading as "only 0 distinct", and the live gate needs a denominator (CTO R2) |
| no-op logging `sleep` stub and the stub `gh` `ERR422_` / `ERR_ONCE_` handlers | "bounded one-retry on 5xx and timeouts only" (ask 5) | inferred - justification: a 2 s sleep in every failing-path row would slow the suite and the retry needs a fail-once fixture; the test layer, not a production seam, carries the cost (CTO R3) |
| `tasks.md` | — | inferred - justification: the plan skill's Save Tasks step derives it from this plan |

### Split Assessment

- Subsystems touched: 3 - `scripts`, `plugins`, `knowledge-base`
- Planned files: 5 | Estimated changed lines: ~450 (probe ~130, replay suite ~280, runbook ~25, plan artifacts excluded from the code estimate)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Domain Review

**Domains relevant:** none

No cross-domain implications detected - internal CI follow-through tooling and its runbook (engineering-only, no user-facing surface, no spend change beyond reads on an already-allocated token).

## Observability

The probe is itself the observability artifact for tracker #10865; this section declares how a broken probe is noticed without host access (layer: the CI follow-through sweeper, `hr-observability-layer-citation` - the sweeper job log and the tracker comment).

```yaml
liveness_signal:
  what: the nightly sweeper comment on #10865 (a verdict line starting NOT YET, PASS or CANNOT ESTABLISH plus the status line with pr_unattributed_runs and the quota line with planned and used_delta)
  cadence: daily
  alert_target: the #10865 tracker comment stream and the sweeper job log
  configured_in: .github/workflows/scheduled-followthrough-sweeper.yml

error_reporting:
  destination: the sweeper's tracker comment (stdout and exit code of the probe); stderr carries only counts
  fail_loud: exit 3 with a first token CANNOT ESTABLISH (quota shortfall, failed read, resolver non-array payload), exit 78 under xtrace, exit 2 with NOT YET; exit 1 is unreachable by design

failure_modes:
  - mode: planned reads exceed the hourly token quota
    detection: the first stdout line CANNOT ESTABLISH API quota with remaining, need and the reset time
    alert_route: the tracker comment
  - mode: the resolver attributes most green runs to no PR (a head-ref or repository mismatch, or GitHub changing the endpoint)
    detection: pr_unattributed_runs on the status line and, at zero distinct PRs, the NOT YET text naming the count of runs that could not be attributed
    alert_route: the tracker comment
  - mode: one transient 5xx or timeout on a read
    detection: one retry; a second failure ends the sweep with the single fixed line CANNOT ESTABLISH naming the run and the read
    alert_route: the tracker comment
  - mode: the facts phase is cut by its 180 s allowance
    detection: NOT YET read budget ended in the PR-facts phase, and truncated=1 on the status line
    alert_route: the tracker comment

logs:
  where: the sweeper workflow job log and the tracker comments
  retention: GitHub Actions log retention for the job log; the comments are permanent

discoverability_test:
  command: bash scripts/followthroughs/ratchet-observation-window-10865.sh
  expected_output: CANNOT ESTABLISH
```

The `discoverability_test` runs the probe with no `GH_TOKEN` (the sandbox holds no credential), so it refuses at once with `CANNOT ESTABLISH: GH_TOKEN is not set ...` (or, when a tool is absent from the sandbox, `CANNOT ESTABLISH: <tool> is not installed`); it finishes in well under the 15 s cap, uses the allowlisted verb `bash` on a committed repo-relative script, contains no `ssh`, and declares no `credentials_required`, so no declared-probe ratchet moves.

## Gates not triggered

Task Design (no new autonomous task: the sweeper and the tracker directive already exist), Encryption Posture (no store or connection), ADR/C4 (no architectural decision: the C4 views model no probe element, and `plugins/soleur/test/c4-count-parity.test.sh` is unaffected because no count in `model.c4` derives from this file), GDPR (no regulated-data surface), Infrastructure-as-Code (none), Downtime & Cutover (none: a nightly read-only probe), PAT-shaped variables (none: the probe holds the sweeper-provided `GH_TOKEN` only).

## Risks and Sharp Edges

- **Precedent diff (deepen Phase 4.4).** `scripts/registry-delivery-change.sh` `resolve_pr_for_sha` already resolves a sha through `commits/<sha>/pulls`, takes `[.[] | select(.merged_at != null)][0].number` and falls back to the commit subject suffix `(#N)`. Ours differs on purpose: that helper produces a WRITE target, so it prefers a merged entry and tolerates a first-of-many; this probe is read-only and must not guess, so it accepts only `length == 1` with both repositories and the head ref matching, has no subject fallback (the suffix is contributor text), and treats an answered `[]`, HTTP 404 and HTTP 422 as unresolved while any other failure is exit 3. `scripts/main-push-duplicate-skip.sh` is the other consumer; neither is edited.

- **The new weights are provisional.** The R4 coefficients (1.5 per row, half a lookup per candidate, 3 per PR, reserve 100) come from two days of measurements; the live run's `used_delta` vs `planned=` is the check, and the CTO flip trigger (`used_delta` above or within 10% of `planned`) is a stop, not a pass.
- **The head-ref identity check is the load-bearing one.** Measured 25 of 25 returned PRs (and 23 resolved) carried a `head.ref` equal to the run's branch; the live gate (`pr_unattributed_runs * 4 < green_pr_rows`) is what catches a systematic mismatch, and if it fails the identity checks are NOT loosened - re-measure on the 25-sample first.
- **A reused branch name** can only remove evidence (identity check fails closed), never add it; the quota reserve covers the extra lookups.
- **Retry changes request counts on every persistently failing path:** the four existing rows named under Test Scenarios must be re-read, not just re-run; the stub `gh` `sleep` calls become `command -p sleep` so the no-op `sleep` stub cannot swallow `SLOW_`/`HANG_`.
- **A mutant restoring `${#PR_EXCLUDED[@]}` survives on bash older than 5.3**, so the behavioural guard is the `facts_prs` counter mutation plus the static no-`${#PR_EXCLUDED` row, not the abort itself.
- **Plan hygiene:** the plan carries no unfinished-marker tokens; a `## User-Brand Impact` section is present with threshold `none`; the sensitive-path scope-out bullet is not required (no sensitive path is touched).
- **Do not** move the xtrace refusal, add an ORACLE or baseline edit, post to #10865, run collect/ejections/aggregate/verdict, or run the live probe more than once.

## Runbook wording to land (Phase 3)

- *Reads are bounded and oldest-first* bullet: GitHub caps a run listing at 1,000 results (measured 2026-10-28: the oldest listed run 2026-10-24T21:23Z, 551 of 1000 cancelled), so the oldest-250 prefix moves forward and PASS evidence does not latch; one sweep that sees every criterion closes the tracker. Quota text: the new pre-read formula and the `planned=` figure; facts allowance 180 s with the time arithmetic (stated once, here; the probe header only points to the runbook).
- *Forgery bound* bullet: a pull_request run whose `pull_requests` is empty (GitHub empties it at merge) is attributed by `commits/<sha>/pulls?per_page=2` iff exactly one same-repo PR with the run's head ref comes back; unresolved runs are excluded and counted (`pr_unattributed_runs`); fork runs are excluded by the run's own head repository and by `pr_facts`.
- Observation log entry, 2026-10-28: the finding (135 of 151 green runs without a PR, 0 fork runs, structurally 0 distinct PRs), the fix, and that no evidence run was re-collected.
