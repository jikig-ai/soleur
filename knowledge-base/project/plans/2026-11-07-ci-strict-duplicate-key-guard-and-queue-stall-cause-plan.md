---
title: "ci: strict duplicate-key parse of workflows in quality-guards, and name the failed-push-without-merge_group queue stall"
date: 2026-11-07
slug: ci-strict-duplicate-key-guard-and-queue-stall-cause
branch: feat-one-shot-ci-duplicate-yaml-key-guard-queue-stall
issue: 12283
refs: [9927, 12283]
closes: none (PR body carries "Ref #9927" and "Ref #12283", never a closing keyword)
type: ci
priority: p2-medium
domain: engineering
brand_survival_threshold: aggregate pattern
lane: cross-domain
---

# ci: strict duplicate-key parse of workflows in quality-guards, and name the failed-push-without-merge_group queue stall

## Enhancement Summary

**Deepened on:** 2026-11-07 (plan-review panel: DHH, Kieran, code-simplicity; CTO rulings R1-R5 plus the R3 evidence amendment; live read-only probes of the GitHub API; local prototypes of the walker).
**Sections enhanced:** Component A (engine), Component D (join key, pagination), Research Insights, Guard Contract, Sharp Edges, decision-challenges rows D10-D12.

### Key Improvements
1. The engine moved from a `construct_mapping` override to a compose-graph walker. A prototype showed it handles anchor + `<<` + explicit override, flow mappings, alias reuse and the incident shape with no false duplicate and correct `line:col`.
2. The join between a failed push run and a `merge_group` run is now `workflow_id`, live-verified equal across the failed push run (42336368201) and a healthy `merge_group` CI run (42341892605): both `229699184`. The same pair shows the load-failure signature directly: the healthy run's `name` is `CI`, the failed push run's `name` is the file path.
3. The `--paginate` jq shape is specified and verified (47 runs over 5 pages at `per_page=10` flatten with `jq -s '[.[].workflow_runs[]]'`); `exclude_pull_requests=true` is accepted.

### New Considerations Discovered
- Pure-Python `SafeLoader` takes 5.7 s over the 114 files; `CSafeLoader` 0.44 s. The guard prefers `CSafeLoader` and falls back to `SafeLoader` (a 6 s worst case on a 15-minute job is acceptable; the umbrella exists to save runner slots, so the fast path matters).
- `yaml.compose` fails closed on its own for multi-document input (`ComposerError`) and tab indentation (`ScannerError`); an empty file returns `None` (the guard must treat that as a finding); quote style does not hide a duplicate (`"a"` and `a` collide).
- actionlint already reports duplicated `with:` keys (and notes the check is case-insensitive); it is advisory, non-blocking and does not cover `action.yml`, so it complements rather than replaces the guard. A case-folded `with:`/`env:` extension is a stated residual.

Spec lacks valid lane: no `spec.md` exists for this branch, so `lane:` defaulted to `cross-domain` (TR2 fail-closed).

## Overview

On 2026-11-07 the merge queue stalled for 175 minutes (#12283). The merge candidate for #12275 carried a `ci.yml` with two
`fetch-depth` keys in one `with:` mapping (git merged it cleanly; a duplicate-key-strict parse fails at line 2225). GitHub
recorded a failed `push` run for `ci.yml` on the queue temp ref, never created the `merge_group` run, the required `test`
context never reported, and the groups behind it waited. Two guards are owed (CTO-ruled on #12283, both unticked boxes):

1. **Prevention.** A duplicate-key-strict YAML parse that runs on `merge_group`, in a required workflow that does not depend
   on `ci.yml` loading. It goes into `pr-quality-guards.yml` as a fourth member step of the `quality-guards` umbrella. No new
   required context, no ruleset change. Live evidence that this is the right home: on the broken candidate, `PR quality
   guards` ran on `merge_group` and concluded `success` (runs 42337331258 / 42336368368), so a red member there would have
   ejected the candidate in minutes instead of stalling it for 175.
2. **Diagnosis.** `merge-queue-stall-check.yml` names the cause when a queue candidate has a failed `push` run on its temp
   ref and no `merge_group` run, instead of always saying "suspected".

Out of scope, never touched: the dequeued duplicate-fetch-depth PR (#12275, another session's), the `CI_ORACLE_LANE`
variable, the SOLEUR-DEBT marker near `ci.yml:2220`, anything under `apps/web-platform/infra/`, and every operator-held
item named in the brief (A6 signing, off-project copy spend, `apply_target=inngest-host-replace`, closing
#9927/#12158/#11265, the arm-token write path and `inngest-arm-write-token.tf`, the G2e pin).

## Research Reconciliation (brief vs. repo reality)

| Brief claim | Reality (verified) | Plan response |
|---|---|---|
| "every `.github/workflows/*.yml` that runs on `merge_group`" | Only 7 of 105 workflows parse with `merge_group` in `on:`. Classifying needs `on:` parsing, which is exactly what fails on a broken file, and misses `workflow_call` callees (`reusable-release.yml`). | CTO R1 (B): scan all 105 workflows + all 9 `action.yml`; no classification code. The brief's "105 files, 0 duplicates" already measured the superset. |
| `merge-queue-stall-check.yml` should act when there is "a failed `push` run on its temp ref and no `merge_group` run" | Read literally it never fires on the real incident: six OTHER workflows ran on `merge_group` on the same ref; only `ci.yml` is missing. | Per-workflow-path predicate (see Phase 3). Recorded as a technical ruling. |
| CTO R3 sub-clause (this session): "zero jobs required" | The stalled entry's own failed push run (42336368201) has `jobs total_count` 2 (`cla-check`, `cla-evidence`); only #12279's run (42337331354) has `jobs: []`. A zero-jobs gate misses the headline entry. | Dropped as a gate; jobs count is corroboration only. Replaced by the live-verified `name == path` gate (a loaded run shows the workflow's `name:`). Re-confirmed by the CTO agent (decision-challenges.md row D4). |
| temp ref identifies a candidate | PR #12279 has TWO temp refs (`...-6eafbf40...` broken, `...-1d2efed...` healthy). A stale failure on a superseded ref must not name a cause for the live one. | Evaluate only the LATEST temp ref of the PR. |
| `scripts/test-all.sh` registration | Not needed. `.github/scripts/test/run-all.sh` globs `test-*.sh` and is the `guard-script-fixture-tests` member of this same umbrella; it is already registered in `scripts/test-all.sh`, and `GITHUB_SCRIPTS_SUITE_PATHS` carries the bare `.github` prefix. | New suite lands in `.github/scripts/test/`; `MIN_SUITES` 17 to 18. `scripts/test-all.sh` is NOT in the diff (RV-Q2 whole-ledger void avoided). |
| PyYAML availability | `ubuntu-24.04` quality-guards merge_group log (run 42341892616) has no `Collecting pyyaml`: preinstalled. `test-check-inngest-bootstrap-build.sh` in the same job already requires it. | Guard exits 2 when PyYAML is missing; no pip fallback (CTO R2). |

## Research Insights

**Premise validation.** #9927, #12283 OPEN; #12158, #11265 not touched. PR 12295 is this branch's draft. #12275 dequeued (not
ours). Cited files all exist on `origin/main`: `pr-quality-guards.yml` (`quality-guards` job with `aggregate` step),
`merge-queue-stall-check.yml`, `plugins/soleur/test/merge-queue-stall-check.test.sh` (712 lines, exact-floor `EXPECTED_PASSES=61`),
`.github/scripts/test/run-all.sh` (`MIN_SUITES=17`, 17 `test-*.sh` today). The ADR corpus does not reject the mechanism
(ADR-032 amendment 2026-11-06 defines the umbrella/member contract; ADR-140's paragraph on rows W3/W4 records the strict loader as accepted
prior art in `ci-test-aggregator-diagnosis.test.sh` W4). Collision pre-check: no open PR names #12283 other than this one.

**Property List.**
- P1. A workflow or composite-action file containing a repeated mapping key on a merge candidate turns a REQUIRED check red on `merge_group`, with `path:line`.
- P2. That check cannot be silenced by `ci.yml` failing to load.
- P3. A stalled queue entry whose candidate ref shows a failed `push` run and no `merge_group` run for the same workflow file is filed with that file named, and any entry without that evidence is still filed as "suspected".

**Cut List.**
- A new required context / ruleset edit: buys nothing P1 needs; `quality-guards` is already required on `merge_group` (cut).
- A check inside `ci.yml`: cannot satisfy P2 (cut, per the brief).
- `scripts/test-all.sh` registration: the nested runner already carries the new suite (cut; avoids the RV-Q2 void path).
- A `pip install pyyaml` fallback in the member step: adds a network dependency to a required check; PyYAML is preinstalled (cut, CTO R2).
- `on: merge_group` classification code: covered by scanning everything (cut, CTO R1).
- A `headCommit.oid` / `head_sha` correlation arm in the stall check: unverifiable while the queue is empty (queue empty on 2026-11-07); the prefix is live-verified on two real refs (deferred, tracking issue filed in Phase 5).

**Live evidence (read-only, 2026-11-07).**
- Failed push runs on queue temp refs: `42336368201` (`pr-12275-1d2efed7...`, head_sha `6eafbf40...`) and `42337331354` (`pr-12279-6eafbf40...`); both `event=push`, `path=.github/workflows/ci.yml`, `name` equals the path (a loaded run shows the workflow's `name:`), `conclusion=failure`.
- `merge_group` runs on those refs: CLA synthetics, vendor-pin-verify, Apply sentry infra, Tenant integration, secret-scan, PR quality guards. No `CI`.
- `gh api -X GET repos/jikig-ai/soleur/actions/runs -f event=push -f created=">=<iso>" -F per_page=100` works (65 push runs / 3 h window); the `created=` range filter bounds the window to the entry's age.
- Strict PyYAML collecting loader over the live tree: 114 files (105 workflows + 9 `action.yml`), 0 duplicates, 0 unparseable.
- Join key (deepen, live): failed push run 42336368201 and healthy `merge_group` CI run 42341892605 both carry `workflow_id` 229699184 and `path` `.github/workflows/ci.yml`; `name` is `CI` on the healthy run and the path on the failed one.
- Pagination (deepen, live): `gh api -X GET --paginate ... -F per_page=10 -F exclude_pull_requests=true` returned 5 page-objects for 47 runs; `jq -s '[.[].workflow_runs[]] | length'` = 47.
- `MergeQueueEntry` GraphQL fields (introspected): `baseCommit, enqueuedAt, headCommit, position, pullRequest, state, solo, jump, estimatedTimeToMerge`.

**Institutional learnings applied.** `2026-11-07-a-required-shard-on-its-timeout-edge-made-the-merge-queue-a-coin-flip.md` (same night; bare `gh pr merge`, close the false-positive bot issue and state the gate override in the PR body). ADR-032 Sharp Edge 1 (paired edits for required contexts: not triggered, no context changes). #6049 per-member disposition (new member on a bot-synthesized context needs a stated disposition).

## Proposed Solution

### Component A: the guard (`.github/scripts/check-workflow-duplicate-keys.py`)

- Python 3 + PyYAML. Detection runs on the COMPOSED node graph, not during construction (a `construct_mapping` override sees mappings after `flatten_mapping` has merged `<<` entries in place, which can fake a duplicate; verified with a prototype: anchor + `<<` + explicit override, flow mappings, alias reuse and the incident shape all behave). `load_strict(text)` = `yaml.compose(text, Loader=yaml.SafeLoader)` plus a walker over `MappingNode`s with a visited-node-id set (alias cycles terminate; a node reached through several aliases is reported once). For each mapping, scalar keys are compared by `(resolved tag, text)`; keys with the merge tag `tag:yaml.org,2002:merge` are skipped; non-scalar keys are skipped (never raise). Loader: `getattr(yaml, "CSafeLoader", yaml.SafeLoader)` (measured 0.44 s vs 5.7 s on the 114 files); the summary line prints `loader=c|py`, and `WFDK_PURE_PYTHON=1` (documented test-only seam) forces the pure loader so the suite runs row B1 under both. `compose` returning `None` (empty file) is a finding. Every repeat is COLLECTED as `(line, col, key, first_line)` using `key_node.start_mark.line + 1` / `column + 1`, then the walk continues, so all duplicates in all files are reported.
- Why not actionlint: actionlint 1.7.7 does report `key "fetch-depth" is duplicated in "with" section` (measured on a synthesized fixture), but `scripts/lint-workflows.sh` exits 0 on findings (93-finding steady state, #7042), actionlint is not a required `merge_group` context, and it does not lint composite `action.yml`. The guard is the blocking, workflow-and-action-wide complement. Residual, stated: GitHub treats `with:`/`env:` input names case-insensitively (actionlint notes this), so `Fetch-Depth` plus `fetch-depth` passes this guard; extending to case-folded keys under `with:`/`env:` is a possible follow-up, not built here.
- File set (the assembly): `<root>/.github/workflows/*.yml` and `*.yaml`, plus recursive `<root>/.github/actions/**/action.yml` and `action.yaml`. GitHub loads both extensions; a `.yml`-only glob would be a blind spot.
- Output: per finding `::error file=<rel>,line=<L>,col=<C>::duplicate key '<k>' (first at line <F>)`; a summary line `workflow-duplicate-keys=OK files=<N>` or `workflow-duplicate-keys=FAIL files=<N> duplicates=<D> unparseable=<U>`.
- Exit codes: 0 clean; 1 any duplicate, unparseable file, multi-document file, or non-mapping top level (fail closed); 2 environment (no PyYAML, root missing, zero workflow files scanned). No pip fallback.
- Cross-enumeration anchor: the summary prints `files=<N>`; the fixture suite compares it to `git ls-files` on the real tree with explicit pathspecs `:(glob).github/workflows/*.yml`, `:(glob).github/workflows/*.yaml`, `:(glob).github/actions/**/action.yml`, `:(glob).github/actions/**/action.yaml` (the `:(glob)` magic matches the guard's recursive glob semantics). The row SKIPS with a printed notice outside a git work tree. No literal counts are asserted anywhere.

### Component B: the member step (`pr-quality-guards.yml`, job `quality-guards`)

- New step `- id: workflow-duplicate-keys`, `if: ${{ !cancelled() }}`, `name: Strict duplicate-key parse of workflows and composite actions`, `run: python3 .github/scripts/check-workflow-duplicate-keys.py` (bare: no `|| true`, no `continue-on-error`). Placed directly after checkout so it reports first and cheaply (~1 s).
- New `member workflow-yaml-strict '*' 'workflow-duplicate-keys' ...` row (member name `workflow-yaml-strict`, step id `workflow-duplicate-keys`; both names are used verbatim in the disposition bullet, the ADR addendum and the post-merge evidence grep) in the `aggregate` step, same arg shape as the existing three rows, `|| failed=1`. `scripts/lint-umbrella-aggregate.sh` already enforces coverage, `!cancelled()` and verdict flow.
- NO job-level `if:` (the merge_group note at the top of the file stands). The `detect` job already treats `.github/scripts/` as a self/dependency trigger.

### Component C: the suite (`.github/scripts/test/test-check-workflow-duplicate-keys.sh`)

Bash-only per run-all.sh CONTRACT (#6454): PyYAML via `python3`, no terraform/apt. Synthesized fixtures only (`cq-test-fixtures-synthesized-only`); the guard is parameterized by root so fixtures are tiny trees under `mktemp -d`. Battery function `run_battery <guard-path>`; the mutation rows run the same battery against a sandbox copy of the guard with a mutation applied and require the battery to go RED for the expected reason. Exact-floor accounting like `merge-queue-stall-check.test.sh`.

### Component D: stall-cause naming (`merge-queue-stall-check.yml`)

- GraphQL selection unchanged. The `stalled` TSV gains a fifth field `enqueuedAt`.
- New function `queue_candidate_cause <pr> <enqueuedAt>`, called per entry AFTER the dedupe check (no API cost for deduped entries). It never fails the step.
  1. List push runs and merge_group runs created `>=` (enqueuedAt minus 5 min; the slack covers clock skew between the queue's `enqueuedAt` and the run `created_at`, and the window is cheap to widen): `if ! out="$(gh api -X GET --paginate repos/$GH_REPO/actions/runs -f event=<e> -f created=">=<iso>" -F per_page=100 -F exclude_pull_requests=true 2>err)"; then warn; return 0; fi` (the function captures the exit code itself and never relies on `set -e`). `--paginate` emits one `{total_count, workflow_runs:[...]}` object per page, so standalone `jq -s '[.[].workflow_runs[]]'` flattens the pages, then filters `head_branch` starting with `gh-readonly-queue/main/pr-<N>-` (trailing dash: `pr-1-` must not match `pr-12-`).
  2. Select the LATEST temp ref: the `head_branch` with the newest `created_at` across both lists.
  3. On that ref, for each push run with `conclusion == "failure"` AND `name == path`, take its `path` P; P is NAMED iff no merge_group run on that ref has the same `workflow_id` (the join key, live-verified equal across a failed push run and a healthy merge_group run of the same workflow; `path` is display only). The `name == path` gate keeps a legitimately failing push-only workflow (which shows its own `name:`) from being blamed as a load failure; residual: a workflow with no `name:` also shows its path, so for that narrow class the claim stays at "suspected" wording.
  4. Output per named P: path and push-run URL only (no jobs-count or sibling-count corroboration: the jobs count was inconsistent across the two real runs, so it cannot corroborate anything).
  5. Inline comment in the workflow cites runs 42336368201 and 42337331354 as the observed `name == path` signature (GitHub does not document it; if it changes the failure is safe: the issue stays "suspected"). Any listing failure: `::warning::` with a bounded ASCII snippet and fall back to "suspected" (CTO R3).
- Title keeps the dedupe/drain prefix `merge-queue stall: PR #N pending >45m` and swaps only the suffix: `(cause: load failure suspected in <P>; duplicate/invalid key is the usual cause)` versus the existing `(suspected, verify first)`. Body gets a leading `CAUSE (observed)` paragraph with the run URL, the fact that GitHub records exactly this signature when a workflow file cannot be loaded, and the agent-runnable next step: fetch the temp ref into a scratch checkout and run `python3 .github/scripts/check-workflow-duplicate-keys.py <that checkout root>` (the guard takes a root path).
- `permissions:` gains `actions: read` (CTO R4); suite pin S4/M8 changes to exactly `contents: read`, `issues: write`, `actions: read`. Header comment updated (the "default GITHUB_TOKEN + gh issue ONLY" sentence gains the read-only runs lookup; no app secrets introduced).

### Component E: paper trail (CTO R5)

- `scripts/required-checks.txt`: comment-only disposition bullet for member `workflow-yaml-strict` (step `workflow-duplicate-keys`) (CONTENT-SCOPED, UNREACHABLE from the bot `ALLOWED_PATHS={weakness-digest.md}`: scan surface is `.github/workflows` and `.github/actions`; intersection empty), and the quality-guards `members:` line gains it.
- `ADR-032`: dated addendum (2026-11-07) naming the fourth member; no change to the three-umbrella inventory table beyond the member list.
- No ruleset / `.tf` / canonical-JSON change.

## Implementation Phases

Order is test-first (`cq-write-failing-tests-before`): each phase writes the RED rows before the code.

### Phase 1: RED suites

1. Create `.github/scripts/test/test-check-workflow-duplicate-keys.sh` with the battery and mutation rows below; it fails because the guard does not exist.
2. Extend `plugins/soleur/test/merge-queue-stall-check.test.sh`: `gh` stub gains an `api -X GET repos/.../actions/runs` arm that APPLIES `event`, `created` (range) and `per_page`/pagination to canned run JSON (a stub that ignores the filters is vacuous: add a control row where a wrong `event=` returns empty); new rows L1-L9 (Test Scenarios); S4/M8 permission pin updated; `EXPECTED_PASSES` re-derived from a green run.
3. Confirm both are RED for the right reason (missing guard / unnamed cause), not for an unrelated break.

### Phase 2: guard + member step

1. Write `.github/scripts/check-workflow-duplicate-keys.py`.
2. Add the member step and aggregate row to `pr-quality-guards.yml`; update the file's header comment (four members; the folded-contexts sentence stays).
3. Raise `MIN_SUITES` 17 to 18 in `.github/scripts/test/run-all.sh` with the dated floor-history comment line.
4. Component E documents.
5. Run: new suite green; `python3 .github/scripts/check-workflow-duplicate-keys.py` on the real tree prints `workflow-duplicate-keys=OK files=<N>` with N equal to the `git ls-files` count; `bash scripts/lint-umbrella-aggregate.sh`; `bash .github/scripts/test/run-all.sh`.

### Phase 3: stall-cause naming

1. Implement Component D in the workflow; suite green; `actionlint`/`bash scripts/lint-workflows.sh .github/workflows/merge-queue-stall-check.yml pr-quality-guards.yml`; `python3 scripts/lint-workflow-issue-write-scope.py`.
2. Live replay (read-only, evidence for #12283): run the extracted function against the real API for PR 12275 and 12279 (`created=` bound at 2026-11-07T03:00Z) with `gh issue create` stubbed to print; expected: #12275 latest ref names `.github/workflows/ci.yml`; #12279 latest ref (healthy `1d2efed`) names nothing. Paste the output into the PR body.

### Phase 4: verification gates

Local: all of the above plus `bash plugins/soleur/test/merge-queue-stall-check.test.sh`, `bash scripts/lint-orphan-test-suites.sh`, the markdown lint on the new docs, and `python3 scripts/lint-guard-contract.py` on this plan. If `lint-orphan-test-suites.sh` demands an entry in `scripts/lib/test-affected-paths.sh`, add it and state in the PR body that `scripts/lib/` was touched (voids a1/a2/b only per the invalidation rule, not every row).

### Phase 5: ship (ends with a merged PR)

- PR body: `Ref #9927`, `Ref #12283`, never `Closes`/`Fixes`/`Resolves`. States `scripts/test-all.sh` is NOT in the diff (RV-Q2 void path avoided); states the `scripts/required-checks.txt` and ADR-032 comment-only edits; states the gate override for the bot-filed stall issue if the net-issue-flow gate counts it (close it first as a false positive).
- Every CI claim names its run kind and leg. Only a `merge_group` or `workflow_dispatch` run on the merge SHA counts as evidence of the merge-blocking guard; a green `push` run is not evidence. Required legs to cite: `quality-guards` (it prints the `PASS  workflow-yaml-strict` row from `aggregate`) and `test`, from the `merge_group` run.
- After every merge from main: re-run `python3 .github/scripts/check-workflow-duplicate-keys.py` (it is the ci.yml duplicate re-parse, and covers the other 113 files) before pushing.
- `gh pr merge` as a bare command, its own call. Waits through Monitor, no `sleep` in Bash.
- File one deferral issue (what: `headCommit.oid` arm in the stall check; why: unverifiable on an empty queue; re-evaluate: next real non-empty stall; milestone from `knowledge-base/product/roadmap.md`).
- Post-merge: classify the merge on #9927 with `git diff --name-only <prev-tip>..<new-tip>` and record the class (this PR's expected class: "voids nothing beyond the a2 re-read", provided `scripts/lib/` stays untouched). Tick the #12283 boxes ONLY with cited evidence: box 1 with the `merge_group` run URL on the merge SHA whose log shows `PASS  workflow-yaml-strict`; box 2 with the Phase 3 live-replay output plus the `workflow_dispatch` run of `merge-queue-stall-check.yml` on the merge SHA (read of the runs list succeeded under the new permission: no `could not read` warning). Do not close #9927/#12158/#11265.

## Files to Edit

- `.github/workflows/pr-quality-guards.yml` (member step, aggregate row, header comment)
- `.github/workflows/merge-queue-stall-check.yml` (permissions, cause lookup, title/body, header comments)
- `plugins/soleur/test/merge-queue-stall-check.test.sh` (stub arm, rows, pins, `EXPECTED_PASSES`)
- `.github/scripts/test/run-all.sh` (`MIN_SUITES` 17 to 18 plus floor-history line)
- `scripts/required-checks.txt` (comment-only disposition + members line)
- `knowledge-base/engineering/architecture/decisions/ADR-032-github-branch-protection-as-iac.md` (dated addendum)

## Files to Create

- `.github/scripts/check-workflow-duplicate-keys.py`
- `.github/scripts/test/test-check-workflow-duplicate-keys.sh`
- `knowledge-base/project/specs/feat-one-shot-ci-duplicate-yaml-key-guard-queue-stall/decision-challenges.md`
- `knowledge-base/project/specs/feat-one-shot-ci-duplicate-yaml-key-guard-queue-stall/tasks.md`

Explicitly NOT touched: `scripts/test-all.sh`, `.github/workflows/ci.yml`, `scripts/lib/*` (unless Phase 4 forces it), `apps/web-platform/infra/**`, `CI_ORACLE_LANE`, the SOLEUR-DEBT marker, `infra/github/*.tf`, the canonical JSONs.

## Open Code-Review Overlap

1 open scope-out touches these files: #3829 (CI gate: new Sentry monitor type must change `sentry-scrub.ts`) names `pr-quality-guards.yml`. **Acknowledge:** different concern (advisory-style Sentry carve-out enforcement), needs its own cycle; it remains open.

## Guard Contract

### Guard 1 - strict duplicate-key parse (`check-workflow-duplicate-keys.py` + `workflow-duplicate-keys` member)

**Property.** No file in the merge candidate's `.github/workflows/` or `.github/actions/` contains a mapping with a repeated key, and a violation turns the required `quality-guards` context red with `path:line`.

**Assembly.** One chokepoint for key checking: the `construct_mapping` override on the single `SafeLoader` subclass (every block, flow, nested and sequence-item mapping flows through it). File set: `.github/workflows/*.yml` plus `*.yaml`, plus `.github/actions/**/action.yml` plus `action.yaml` recursively; the set is cross-checked against `git ls-files` by the suite. One invocation site: the `workflow-duplicate-keys` step in `quality-guards`, whose verdict reaches the required context only through the `aggregate` `member workflow-yaml-strict` row (enforced by `scripts/lint-umbrella-aggregate.sh`). Events: `pull_request` and `merge_group` (no job-level `if:`). Not covered, stated: it is not a GitHub-schema validator (unknown keys, bad expressions); actionlint is the separate advisory tool.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Swap the strict loader for the permissive one (in a sandbox copy replace the `load_strict(...)` call with `yaml.safe_load(...)`, which keeps last-wins semantics) | RED: the nested `with:` / two `fetch-depth` fixture is no longer rejected |
| 2 | Dispatch: point the guard at a root with zero workflow files; and delete the zero-files exit-2 arm in a copy | RED: a scan of nothing reports OK |
| 3 | Second member: tree with a clean file, then a duplicate file, then another duplicate file; mutate the copy to stop at the first finding (raise-first) | RED: the second and third findings are not reported |
| 4 | Extension coverage: duplicate in a `.yaml` workflow and in `action.yaml`; mutate the glob to `*.yml` only | RED |
| 5 | Line accuracy: duplicate at a known line; mutate the reported line to `mark.line` without `+1` | RED (off by one) |
| 6 | Member wiring, applied to a SANDBOX copy of `pr-quality-guards.yml` (four sub-mutations: strip `!cancelled()`, drop the `aggregate` member row, append `\|\| true`, add `continue-on-error`) | RED from the suite's own structural rows (`scripts/lint-umbrella-aggregate.sh` reads the repo's hard-coded path and cannot be pointed at a copy; it independently guards the real file in CI) |
| 7 | Fail closed: unparseable file, multi-document file, non-mapping top level; mutate the copy so a parse error is skipped | RED |

**Harness rows.** (a) The mutation harness asserts each mutation landed (diff against the pristine copy) and that the battery went RED for the NAMED reason, with three control rows proving the helper itself fails (mutation did not land; stayed GREEN; RED for the wrong reason), copying `merge-queue-stall-check.test.sh`. (b) Must-PASS inputs that are NOT the canonical clean tree: same key under different parents (`with:` in two steps each holding `fetch-depth`), a flow mapping, anchors/aliases with `<<` merge overriding a key, a key literally named `on`, a multi-line string value containing `key:`, and a CRLF file. (c) Exact pass-count floor. (d) The real-tree row compares the guard's `files=` to the `git ls-files` count (pathspecs above); must-PASS corpus adds `1` vs `true` keys, anchor reuse via several aliases, and an alias cycle.

**Anchor.** The guard holds no stored value. Its only count assertion (`files=` equals `git ls-files` for the same pathspecs) is taken from an enumerator outside the script's own glob (the git index), and the suite lives in a different file from the guard, so one edit cannot weaken both without the other row going RED.

### Guard 2 - stall-cause naming (`queue_candidate_cause` in `merge-queue-stall-check.yml`)

**Property.** An entry whose latest temp ref shows a failed `push` run of workflow P (run `name` equal to its path) and no `merge_group` run of P is filed with P named; an entry lacking that evidence is filed unchanged as "suspected"; a lookup failure never fails the step.

**Assembly.** Chokepoints: one filing site (`gh issue create` in the loop) and one cause function. Data sources: the push-runs list, the merge_group-runs list (same endpoint, two `event` values). Consumers of the title: the dedupe anchor `merge-queue stall: PR #N pending`, the drain `capture("PR #(?<pr>[0-9]+) pending")`, and already-open issues in the old form. Loop state: the cause variable is reset per entry.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Replace per-path "no merge_group run of P" with "no merge_group run at all" | RED: the real-incident fixture (six other merge_group runs) is no longer named |
| 2 | Drop the latest-ref selection (consider every ref under the prefix) | RED: stale failure on superseded ref names a cause for a healthy ref |
| 3 | Prefix without the trailing dash | RED: `pr-12-` fixture collides with `pr-123-` |
| 4 | Dispatch: the runs list is empty / the endpoint fails; mutate the copy to treat failure as named or to `exit 1` | RED (must be "suspected", exit 0, one `::warning::`) |
| 5 | Two stalled entries, only the second has the signature; mutate to not reset the cause variable per iteration | RED: the first entry would carry the second's cause or vice versa |
| 6 | Change the title suffix so the drain/dedupe anchors stop matching | RED: existing dedupe + drain rows |
| 7 | Count a `cancelled` or `success` push run as failed (`conclusion == "failure"` literal) | RED: rows L8 (`cancelled`) and L11 (`success`) |
| 8 | Drop the `name == path` conjunct (literal `.name == .path` in the jq) | RED: a named, legitimately failing push-only workflow fixture is wrongly blamed |
| 9 | Join on `path` instead of `workflow_id` | RED: fixture whose merge_group run `path` carries a suffix but whose `workflow_id` matches must stay "suspected" |
| 10 | Drop the `created=` bound / slack arithmetic | RED: stub control that serves nothing without the right `created` range |
| 11 | Call the lookup before the dedupe check | RED: a deduped entry must make zero `actions/runs` calls |

**Harness rows.** The `gh` stub APPLIES `event`, `created` and pagination (control row: wrong `event` returns nothing); canned JSON is synthesized from the live shape, not copied; must-PASS non-canonical inputs: run list with unrelated workflows, runs older than the window, push run `cancelled` on the ref; exact floor on `EXPECTED_PASSES`.

**Anchor.** Thresholds stay derived from the `.tf` as today; the new `actions: read` pin is asserted by the existing S4/M8 rows, which a permission edit must change in the suite file (a second file).

## Observability

```yaml
liveness_signal:
  what:            "quality-guards aggregate prints 'PASS  workflow-yaml-strict' and the guard prints 'workflow-duplicate-keys=OK files=N' on every PR and merge_group run"
  cadence:         "per pull_request / merge_group run"
  alert_target:    "required context quality-guards goes red on the PR or queue entry; stall issues carry the named cause"
  configured_in:   ".github/workflows/pr-quality-guards.yml (step workflow-duplicate-keys + aggregate member row); .github/workflows/merge-queue-stall-check.yml"
error_reporting:
  destination:     "GitHub Actions annotations (::error file=,line=) and the aggregate FAIL row; stall check files a GitHub issue labelled merge-queue-stall + action-required"
  fail_loud:       "::error file=<path>,line=<L>::duplicate key; guard exit 1 (findings) or 2 (environment); lookup failure in the stall check emits ::warning:: and the issue says 'suspected'"
failure_modes:
  - mode:          "duplicate key merged into a candidate"
    detection:     "guard exit 1 inside quality-guards on merge_group"
    alert_route:   "red required context ejects the entry; annotation names file and line"
  - mode:          "guard scans nothing (glob drift, missing dir)"
    detection:     "exit 2 when zero workflow files are found; suite compares files= to git ls-files"
    alert_route:   "red quality-guards"
  - mode:          "cause lookup unavailable (permission or API error)"
    detection:     "::warning:: in the stall-check run and 'suspected' wording in the filed issue"
    alert_route:   "visible in the filed issue body; post-merge workflow_dispatch run is the check that the read works"
logs:
  where:           "GitHub Actions run logs for quality-guards and merge-queue-stall-check"
  retention:       "GitHub default run-log retention (90 days)"
discoverability_test:
  command:         python3 .github/scripts/check-workflow-duplicate-keys.py
  expected_output: workflow-duplicate-keys=OK
```

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Ruled by CTO agent, 2026-11-07: R1 B (scan all workflows and actions), R2 collecting loader + exit 2 without pip, R3 per-path predicate with fail-soft lookup and the title prefix preserved, R4 add `actions: read`, R5 disposition comment + ADR-032 addendum. R3's "zero jobs required" sub-clause was amended on live evidence (decision-challenges.md D4). Product/UX: no user-facing surface (CI-only), mechanical UI override did not fire.

## User-Brand Impact

- **If this lands broken, the user experiences:** a falsely red required `quality-guards` context that stops every PR and merge-queue entry from merging until fixed (delivery stalls; no end-user data or UI affected). The failure the PR removes is the opposite one: a 175-minute silent stall.
- **If this leaks, the user's [workflow] is exposed via:** nothing new. The guard reads tracked files and public Actions run metadata; `actions: read` is a read scope on the same repo; no secret, token or Doppler value is read or written.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** a bad guard degrades merge throughput across many PRs (a pattern), but exposes no single user's data and ships behind a fixture battery and a mutation harness, so `single-user incident` does not apply.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Add a duplicate-key-strict YAML parse of every `.github/workflows/*.yml` that runs on `merge_group`, and of `.github/actions/**/action.yml`." | Component A + B (scope widened to all files by CTO R1; superset of the ask) | mapped |
| 2 | "Put it in an existing required `merge_group` workflow that is not `ci.yml` (candidate: `pr-quality-guards.yml` as a member step of the `quality-guards` umbrella; no new required context, no ruleset change)." | Component B | mapped |
| 3 | "Tests use synthesized fixtures only: a file with two `fetch-depth` keys in one `with:` mapping must fail with the line number; the clean tree must pass." | Component C battery rows B1/B2; real-tree AC | mapped |
| 4 | "Mutation-test that the guard goes red when the strict loader is swapped for a permissive one." | Guard 1 mutation row 1 | mapped |
| 5 | "Make `merge-queue-stall-check.yml` name the cause when a queue candidate has a failed `push` run on its temp ref and no `merge_group` run, instead of saying \"suspected\"." | Component D (per-path refinement, CTO R3) | mapped |
| 6 | "Do NOT touch the dequeued duplicate-fetch-depth PR (another session's), the `CI_ORACLE_LANE` variable, the SOLEUR-DEBT marker near ci.yml:2220, or any `apps/web-platform/infra/` path." | Files lists exclude all four; AC diff-scope check | mapped |
| 7 | "PR body: \"Ref #9927\" and \"Ref #12283\", never \"Closes\". After merge, tick #12283 boxes only with cited evidence." | Phase 5 | mapped |
| 8 | "if the diff touches `scripts/test-all.sh` that is a whole-ledger-void path (RV-Q2); prefer a registration route that avoids it" | Research Reconciliation row; `.github/scripts/test/` auto-glob route | mapped |
| 9 | "re-parse ci.yml for duplicate keys after every merge from main; run `gh pr merge` as a bare command; use Monitor for waits, no sleep in Bash" | Phase 5 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Component E (required-checks.txt comment, ADR-032 addendum) | "no new required context, no ruleset change" | inferred - justification: adding a member to a bot-synthesized required umbrella needs its #6049 per-member disposition (CTO R5); comment-only, no ruleset change |
| `actions: read` permission | "Make `merge-queue-stall-check.yml` name the cause" | inferred - justification: reading the runs list is the only way to name it; explicit scope removes an unverifiable dependency (CTO R4) |
| `MIN_SUITES` 17 to 18 | "prefer a registration route that avoids it" | asked (the auto-glob route carries a floor that must move with the suite) |
| `.yaml` extension coverage, fail-closed on multi-document / non-mapping / unparseable files, exit-2 environment arm | "Add a duplicate-key-strict YAML parse of every `.github/workflows/*.yml`" | inferred - justification: GitHub loads `.yaml` too; a guard that skips what it cannot parse is the vacuous-green shape the incident came from |
| Latest-temp-ref selection, `name == path` gate, `workflow_id` join, 5-minute window | "name the cause when a queue candidate has a failed `push` run on its temp ref and no `merge_group` run" | inferred - justification: live data (two temp refs for #12279; six other merge_group runs on the broken ref; `name == path` on both incident runs), CTO R3 |
| Guard 2 mutation matrix, `decision-challenges.md` | "Mutation-test that the guard goes red" / "Persist every decision as a row" | asked (matrix is the Guard Contract format; the file is mandated by the brief) |
| Deferral issue for the `headCommit` arm | "name the cause ... instead of saying \"suspected\"" | inferred - justification: an unverified arm is cut rather than shipped; the deferral keeps it visible (deferral-tracking rule) |

### Split Assessment

- Subsystems touched: 3 - `.github/workflows` + `.github/scripts`, `plugins/soleur/test`, `scripts` + KB docs
- Planned files: 10 | Estimated changed lines: ~650
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR (both guards answer one incident, #12283)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `python3 .github/scripts/check-workflow-duplicate-keys.py` on the real tree prints `workflow-duplicate-keys=OK files=<N>` with N equal to the `git ls-files` count of the same pathspecs, and exits 0 (today's measurement was 114 = 105 workflows + 9 actions; no literal is asserted).
- [ ] Fixture with two `fetch-depth` keys in one `with:` mapping exits 1 and prints `line=<the second key's line>`; clean synthesized tree exits 0.
- [ ] Mutation row: swapping the strict loader for the permissive one makes the battery RED for the named reason; 3 control rows prove the mutation helper fails when it should.
- [ ] `pr-quality-guards.yml`: member step has `if: ${{ !cancelled() }}`, no `continue-on-error`, bare command; `aggregate` has the `member workflow-yaml-strict` row; `bash scripts/lint-umbrella-aggregate.sh` green; no job-level `if:` added.
- [ ] `MIN_SUITES=18` and `bash .github/scripts/test/run-all.sh` green; `git diff --name-only origin/main...HEAD` does NOT list `scripts/test-all.sh`, `.github/workflows/ci.yml`, `apps/web-platform/infra/`, or any `scripts/lib/` path (if `scripts/lib/` is forced by `lint-orphan-test-suites.sh`, the PR body says so).
- [ ] Stall check: with the real-incident fixture (six other merge_group runs, failed push run of `ci.yml`, no `ci.yml` merge_group run) the filed title carries the cause suffix and the body names `.github/workflows/ci.yml` and the run URL; with no failed push run it files the unchanged "suspected" form; a runs-list API failure files "suspected" with a `::warning::` and exits 0; `pr-12-` does not match `pr-123-`; stale superseded-ref failure does not name a cause.
- [ ] `plugins/soleur/test/merge-queue-stall-check.test.sh` green with the updated `EXPECTED_PASSES`, permission pin `contents: read` + `issues: write` + `actions: read`.
- [ ] `actionlint` (via `scripts/lint-workflows.sh`) shows no new findings for the two workflows; `python3 scripts/lint-workflow-issue-write-scope.py` green.
- [ ] `python3 scripts/lint-guard-contract.py` green on this plan.
- [ ] PR body contains `Ref #9927` and `Ref #12283`, contains none of `Closes`, `Fixes`, `Resolves` for those numbers, states the RV-Q2 position, and names run kind + leg for every CI claim.

### Post-merge (operator-free, agent-run)

- [ ] Evidence on the merge SHA, from a `merge_group` run (not `push`): `quality-guards` log shows `PASS  workflow-yaml-strict` and `workflow-duplicate-keys=OK`.
- [ ] `workflow_dispatch` run of `merge-queue-stall-check.yml` on the merge SHA succeeds with no cause-lookup warning.
- [ ] #12283 boxes ticked, each with its cited evidence link; #9927 receives the merge classification from `git diff --name-only <prev-tip>..<new-tip>`; nothing is closed.
- [ ] Deferral issue filed for the `headCommit` arm.

## Test Scenarios

Guard battery (`test-check-workflow-duplicate-keys.sh`): B1 duplicate in nested `with:` (incident shape) -> rc 1 + line; B2 clean tree -> rc 0; B3 two duplicates in one file -> both reported; B4 three files, dups in 2nd and 3rd -> both reported; B5 `.yaml` workflow + `action.yaml` dup -> rc 1; B6 flow-mapping dup `{a: 1, a: 2}` -> rc 1; B7 unparseable / multi-document / non-mapping -> rc 1; B8 empty root -> rc 2; B9 no PyYAML (stub `python3` without the module) -> rc 2; B10 must-PASS corpus (sibling same keys, merge key, key named `on`, CRLF, multiline strings); B11 structural rows over the real `pr-quality-guards.yml` (step id, `!cancelled()`, bare command, aggregate row, no job `if:`); B12 real-tree `files=` equals `git ls-files`; mutation rows M1-M7 with controls.

Stall check (`merge-queue-stall-check.test.sh`): L1 real-incident shape -> named; L2 no failed push run -> suspected; L3 failed push run but a merge_group run of the same path exists -> suspected; L4 stale failure on a superseded ref, latest ref healthy -> suspected; L5 `pr-12-` vs `pr-123-` prefix; L6 runs endpoint fails -> suspected + warning + rc 0; L7 two entries, cause on the second only; L8 push run `cancelled` -> suspected; L10 failed push run whose `name` differs from its path (a loaded workflow) -> suspected; L1 fixture = six other merge_group runs + failed push run with `name == path` and jobs 2 + a second stale temp ref for the same PR; L9 stub controls: wrong `event=` and wrong `created` range return nothing; L11 `success` push run -> suspected; L12 two-page `--paginate` stub with the broken run on page 2; L13 deduped entry makes zero `actions/runs` calls; L14 merge_group run with a suffixed `path` but matching `workflow_id` -> suspected; mutation targets are the literals `pr-${pr}-`, `.name == .path`, `workflow_id`, `conclusion == "failure"`; plus S4/M8 pin and drain/dedupe rows unchanged.

## Sharp Edges

- A plan whose `## User-Brand Impact` is empty or placeholder fails deepen-plan; this one declares `aggregate pattern`.
- `workflow-duplicate-keys` verdict reaches the required context only through the `aggregate` row. A step without its `member` row is a verdict the job never reads; `scripts/lint-umbrella-aggregate.sh` is the check.
- PyYAML maps `on` to boolean `True`; the guard compares constructed keys, so `on` and `true` collide (a false RED on a pathological spelling, never a false green).
- A CI claim is merge-blocking evidence only from a `merge_group` or `workflow_dispatch` run on the merge SHA. A green `push` run is not evidence; a `workflow_dispatch` run of the stall check does not prove the naming path (only the replay and the suite do).
- The live-replay evidence depends on GitHub run retention (90 days) and on #12275's runs still being listable; capture it before merge.
- Grouped merging: a member PR's temp ref names the DEEPEST member, so the prefix lookup for a non-deepest member finds nothing and the issue stays "suspected" (safe direction; the existing triage text already says so).
- Blast radius of the exit-2 arm: if a runner image ever drops PyYAML, `quality-guards` goes red on every PR and queue entry. Accepted by the CTO (R2) because `test-check-inngest-bootstrap-build.sh` in the same job already shares the dependency and fail-closed beats a silent skip; the fix is one pinned install in that job.
- The cause is named only when the FIRST filing run sees the evidence. Dedupe skips an existing open issue, so a "suspected" issue filed while the lookup failed (or before the failed push run was listed) is never upgraded; accepted, the issue body already carries the agent-runnable triage.
- Mutation rows are applied by literal replacement on a sandbox copy (the existing M-row style); each row names its literal so "RED for the named reason" is mechanical.
- Do not edit `ci.yml`, even to "fix" a duplicate: the tree is clean and the brief forbids it.
