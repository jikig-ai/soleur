# Plan: skip proven-duplicate push-to-main gates (tree-identity proof)

Date: 2026-09-25
Branch: `feat-one-shot-ci-main-duplicate-skip` · PR: #8919 (draft)
Arc: CI-efficiency item 5 of 5 (items 1-4 merged: #8854, #8891, #8897, #8902).
Prior art: ADR-217 (per-SHA-on-push convention); `commits/{sha}/pulls` resolver
precedent in `reusable-release.yml` / `post-merge-monitor.yml` /
`fix-constraints-stage-b.template`; merge_group trust-the-PR-run precedent in
`secret-scan.yml` Pattern (B) and `tenant-integration.yml` (#5585, ADR-032).

## Overview

Five push-to-main workflows re-execute on the merge commit exactly what already
ran green on the merged PR's head. Because `ruleset-ci-required.tf` sets
`strict_required_status_checks_policy = true`, a mergeable PR's head is
up-to-date with main, so a squash merge produces a commit whose **tree SHA
equals the PR head's tree SHA**. When that equality is PROVEN (not assumed) and
this workflow's own pull_request run at that head concluded `success` with the
load-bearing jobs actually executed, the push run is a byte-identical re-run —
skippable. Every ambiguity fails OPEN toward running.

A shared script `scripts/main-push-duplicate-skip.sh` carries the whole proof;
each candidate workflow wires it into the cheapest existing chokepoint (the
`detect-changes` job where one exists, a new `detect-duplicate` job where not).

## Verification-first premises — per-file verdict (all 23 push:main workflows)

| File | push:main shape | Also on PR? | `workflow_run` upstream? | Stateful effect? | Verdict |
|---|---|---|---|---|---|
| `ci.yml` | push+PR+merge_group+dispatch | yes | YES — `web-platform-release` (deploy) + `post-merge-monitor` (bot-fix auto-revert) | no, but its conclusion is consumed | **KEEP.** A skipped-jobs run still completes `success` — vacuously green — and would let release deploy / monitor "verify" a SHA no check touched. Requirement says keep release deps; the risk independently confirms it. |
| `infra-validation.yml` | push paths ⊂ PR paths (lines 31-43 vs 44+) | yes | no consumer (verified: no `workflows:` list names it; `notify-main-failure` is the watcher, per the #7299 comment) | no (validate/tests only; `plan` is PR-only) | **GATE.** ~14 job-min/run measured (concurrency-cancel plan). Fold proof into `detect-changes` as output `pr_duplicate`. |
| `tenant-integration.yml` | push (unfiltered) + PR + merge_group + dispatch | yes | no | dev-Supabase suite (rate-budgeted, mutex-held — skipping SAVES budget) | **GATE.** Fold into `detect-changes`: proven-duplicate push emits `tenant=false`; aggregator posts PASS via the existing merge_group suite=skipped path. Requires PR run's `tenant-integration` job conclusion == `success` (a skipped suite is not coverage). |
| `vendor-pin-verify.yml` | push (unfiltered) + PR + merge_group + dispatch | yes | no | no (network read verify) | **GATE.** Same fold → `vendor=false`. Requires PR run's `verify-upstream-blobs` == `success`. Residual recorded: the push run is also the standing "does upstream still serve the pin" liveness probe; no scheduled vendor-drift workflow exists, so upstream-history-deletion detection cadence drops to vendor-touching merges. Accepted — blob set is a pure function of the tree. |
| `validate-vector-config.yml` | push paths == PR paths (byte-identical lists, lines 18-28 vs 30-40) | yes | no | no | **GATE.** New `detect-duplicate` job + `needs`/`if` on `validate-vector-config`. Ledger row 1→2. |
| `skill-security-scan-corpus.yml` | push unfiltered; PR path-filtered to rules/scripts | yes (subset) | no | no | **GATE.** Same new-job pattern. Skips only when the PR actually ran it (rule-pack PRs) — automatic via the workflow-runs lookup. Ledger row 1→2. |
| `secret-scan.yml` | push + PR + merge_group + schedule | yes | no | no | **KEEP.** Push arm carries unique non-tree coverage: full main-ancestry re-scan (blocking), all-refs advisory sweep (`-m --all`), plus it produces 5 required contexts. Partial step-level gating would save ~2 job-min for a large complexity/safety cost. |
| `skill-security-scan-postmerge.yml` | push only | n/a | no | files `compliance/critical` issues | **KEEP.** It is the BYPASS audit (#2719 Layer D) — "the PR gate was green" is precisely the condition it exists to distrust. Skipping on that proof inverts its purpose. |
| `version-bump-and-release.yml` | push paths + dispatch | no | YES — upstream for `deploy-docs` | mints GitHub Release + tag | **KEEP.** Effect, not a check; identical inputs still require the apply (the release does not yet exist). |
| `web-platform-release.yml` | push + dispatch + workflow_run | no | consumer | release build + prod deploy | **KEEP.** The deploy itself. |
| `deploy-docs.yml` | push paths + workflow_run + dispatch | no | consumer | `wrangler pages deploy` to prod Pages | **KEEP.** Stateful deploy. |
| `apply-deploy-pipeline-fix.yml` | push paths + dispatch | no | no | terraform apply + bounded re-push | **KEEP.** Stateful apply. |
| `apply-github-infra.yml` | push paths + dispatch | no | no | terraform apply (branch protection itself) | **KEEP.** Stateful apply; already carries its own "applied tree == origin/main" assertion (line 123-133) — orthogonal. |
| `apply-inngest-rls.yml` | push paths + schedule + dispatch | no | no | applies SQL RLS lockdown | **KEEP.** Stateful apply. |
| `apply-sentry-infra.yml` | push paths + PR + merge_group + dispatch | yes (plan only) | no | terraform apply on push | **KEEP.** The push arm is the APPLY; the PR arm is plan-only — never equivalent. |
| `apply-web-platform-infra.yml` | push paths + dispatch | no | YES — upstream for `git-data-pin-redeploy` | terraform apply | **KEEP.** Stateful apply + consumer. |
| `registry-host-replace-dispatch.yml` | push paths (`cloud-init-registry.yml`) + dispatch | no | no | dispatches a prod host replace | **KEEP.** Real stateful delivery trigger — merge IS the intent to deliver (header comment). |
| `cutover-inngest.yml` | push paths (self-file only) + dispatch | no | no | — | **KEEP.** Push arm is the Actions-UI registration shim; job `if: workflow_dispatch` makes it a literal no-op. Zero cost already. |
| `deploy-inngest-image.yml` | push paths (self-file) + dispatch | no | no | — | **KEEP.** Same registration shim; no-op on push. |
| `restart-inngest-server.yml` | push paths (self-file) + dispatch | no | no | — | **KEEP.** Same shim (#6425 guard). |
| `inngest-watchdog-restart-dispatch.yml` | push paths (self-file) + issues[labeled] | no | no | — | **KEEP.** Same shim; job gates on `issues`+label+Bot. |
| `registry-zot-inventory-dispatch.yml` | push paths (self-file) + issues | no | no | — | **KEEP.** Same shim. |
| `registry-zot-inventory.yml` | push paths (self-file) + dispatch | no | no | — | **KEEP.** Same shim; `if: workflow_dispatch`. |

## Chosen mechanism

### Shared proof script — `scripts/main-push-duplicate-skip.sh`

```
usage: main-push-duplicate-skip.sh <workflow-file> <merge-sha> [required-job-prefix ...]
stdout: exactly one line  duplicate=true  OR  duplicate=false
exit:   always 0 — every failure path emits duplicate=false (fail-OPEN)
```

Logic (house style: verdict script in `scripts/`, unit test in `tests/scripts/`,
mirroring `vendor-pin-gate-verdict.sh` + `test-vendor-pin-gate-verdict.sh`):

```bash
set -uo pipefail                      # NOT -e: every error must emit false, not die
emit() { echo "duplicate=$1"; }
REPO="${GITHUB_REPOSITORY:?}"; WF="$1"; SHA="$2"; shift 2

# 1. PR association. One call returns full PR objects incl. head.sha,
#    merged_at, merge_commit_sha. Bind on merge_commit_sha == $SHA so a PR that
#    merely CONTAINS the commit (rebase-merge range, stacked PR) cannot match.
prs="$(gh api "repos/${REPO}/commits/${SHA}/pulls" 2>/dev/null)" || { emit false; exit 0; }
head="$(jq -r --arg sha "$SHA" \
  '[.[] | select(.merged_at != null and .merge_commit_sha == $sha)][0].head.sha // empty' \
  <<<"$prs")"
[ -n "$head" ] || { emit false; exit 0; }    # manual push, rebase-merge miss, bot push → RUN

# 2. Tree identity — the load-bearing proof. squash-of-up-to-date ⟹ equal.
head_tree="$(gh api "repos/${REPO}/git/commits/${head}" --jq .tree.sha 2>/dev/null)" || { emit false; exit 0; }
merge_tree="$(gh api "repos/${REPO}/git/commits/${SHA}" --jq .tree.sha 2>/dev/null)" || { emit false; exit 0; }
[ "$head_tree" = "$merge_tree" ] || { emit false; exit 0; }   # drift / merge-order → RUN

# 3. This workflow's own latest pull_request run at that head must be green.
run_id="$(gh api "repos/${REPO}/actions/workflows/${WF}/runs?head_sha=${head}&event=pull_request&per_page=10" \
  --jq '[.workflow_runs[] | select(.status=="completed")] | .[0] | select(.conclusion=="success") | .id // empty' \
  2>/dev/null)" || { emit false; exit 0; }
[ -n "$run_id" ] || { emit false; exit 0; }   # never ran (paths-filtered), red, or cancelled-latest → RUN

# 4. Each named job must have EXECUTED successfully on that run — a skipped
#    heavy job is not coverage (tenant suite / verify-upstream-blobs case).
for prefix in "$@"; do
  ok="$(gh api "repos/${REPO}/actions/runs/${run_id}/jobs?per_page=100" \
    --jq --arg p "$prefix" '[.jobs[] | select(.name | startswith($p))] | if length==0 then "missing" elif all(.[]; .conclusion=="success") then "ok" else "bad" end' \
    2>/dev/null)" || { emit false; exit 0; }
  [ "$ok" = "ok" ] || { emit false; exit 0; }
done
emit true
```

Caller's event gate (`EVENT_NAME == 'push'`) lives in the workflow, not the
script — the script stays event-agnostic and unit-testable.

### Wiring per workflow

**(a) `infra-validation.yml` — fold into `detect-changes` (ledger stays 11/11):**

```yaml
  detect-changes:
    permissions:                 # job-level, additive — workflow grants contents: read
      contents: read
      actions: read              # reads this workflow's runs on the PR head
      pull-requests: read        # commits/{sha}/pulls association
    outputs:
      directories: ${{ steps.dirs.outputs.directories }}
      pr_duplicate: ${{ steps.dup.outputs.duplicate }}     # NEW
    steps:
      - uses: actions/checkout@…   # unchanged
      - name: Find changed infra directories  # unchanged
      - name: Prove-or-disprove PR-run duplication (push arm only)   # NEW
        id: dup
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          EVENT_NAME: ${{ github.event_name }}
          MERGE_SHA: ${{ github.sha }}
        run: |
          if [[ "$EVENT_NAME" != "push" ]]; then
            echo 'duplicate=false' >> "$GITHUB_OUTPUT"; exit 0
          fi
          bash scripts/main-push-duplicate-skip.sh \
            infra-validation.yml "$MERGE_SHA" \
            validate deploy-script-tests deploy-script-tests-fixed \
            >> "$GITHUB_OUTPUT"
```

Then the conjunct `&& needs.detect-changes.outputs.pr_duplicate != 'true'` is
added to the `if:` of `validate`, `registry-userdata-budget`,
`inngest-userdata-budget`; `needs: [detect-changes]` + the `if:` is added to
`deploy-script-tests` and `deploy-script-tests-fixed` (they carry none today);
`deploy-script-tests-done` gains `detect-changes` in `needs:` and the conjunct
in its `if: always() && …`; **`notify-main-failure` gains the conjunct** —
load-bearing: `needs.deploy-script-tests-done.result != 'success'` is TRUE for
a skipped job (`skipped ≠ success`), so without the conjunct every skipped push
emails ops a false "[ALERT] Infra Validation failed on main". `check-secrets`
and `plan` are untouched (`plan` is already `event_name == 'pull_request'`).

**(b) `tenant-integration.yml` — fold into `detect-changes` (ledger stays 3/3):**
in the filter step's `EVENT_NAME != 'pull_request'` branch, replace the
unconditional `tenant=true` with: on `push`, run the script with required-job
prefix `tenant-integration`; proven → `tenant=false` (+ `::notice::` naming the
PR head SHA); unproven/dispatch → `tenant=true`. The `tenant-integration` job
and `tenant-integration-required` aggregator need NO edits — the aggregator's
existing suite=skipped PASS branch (the merge_group path) handles it.

**(c) `vendor-pin-verify.yml` — same fold (ledger stays 3/3):** proven →
`vendor=false`; required-job prefix `verify-upstream-blobs`. `vendor-pin-required`
aggregator untouched (its verify=skipped PASS branch is merge_group-proven).

**(d) `validate-vector-config.yml` + `skill-security-scan-corpus.yml` — new
`detect-duplicate` job** (the (a) YAML, minus `checkout`? — keep checkout: the
script lives in the repo), then `needs: detect-duplicate` + `if:
needs.detect-duplicate.outputs.duplicate != 'true'` on the single work job.
Ledger rows 1→2 with named consequence.

## Guard Contract

### Guard 1 — the proof script is fail-open and proof-complete

**Property.** `duplicate=true` is emitted only when ALL of: a merged PR's
`merge_commit_sha` equals the push SHA; PR-head tree SHA equals merge-commit
tree SHA; this workflow's latest completed pull_request run at that head
concluded `success`; every required-job prefix resolved to ≥1 job ALL with
`conclusion == 'success'`. Every API failure, empty lookup, or ambiguity emits
`duplicate=false` with exit 0.

**Assembly.** `tests/scripts/test-main-duplicate-skip.sh` — stubbed `gh` on
PATH (precedent: `tests/scripts/test-registry-delivery-change.sh` stub design:
per-SHA fixture files, `*/pulls` dispatched before `commits/<sha>`, unfixtured
argv → exit 64 so a miss fails loudly; call LOG asserted). Registered in
`scripts/test-all.sh` explicitly — `tests/scripts/` is NOT auto-globbed.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop the tree-SHA equality check | RED — the "tree differs" fixture row now emits true |
| 2 | Bind on `.number` presence instead of `merge_commit_sha == SHA` | RED — the unmerged-association fixture emits true |
| 3 | Accept run conclusion `!= 'failure'` (i.e., cancelled counts) | RED — cancelled-latest row |
| 4 | Treat a `skipped` required job as coverage | RED — suite-skipped row emits true |
| 5 | `exit 1` on API failure instead of `emit false` | RED — API-error row asserts output+rc |
| 6 | Match required job by `contains` instead of `startswith` | RED — prefix-collision fixture (`deploy-script-tests` vs `deploy-script-tests-done` must not satisfy `deploy-script-tests`) |

### Guard 2 — ledger job ceilings ratchet, not absorb

**Assembly.** `scripts/pr-fanout-ledger.txt` rows for the five touched
workflows; `plugins/soleur/test/pr-fanout-ledger.test.sh` A3/A5 checks.

**Property.** Declared jobs ≤ each row's ceiling (`pr-fanout-ledger.test.sh`
A3). infra-validation/tenant-integration/vendor-pin-verify add steps to
`detect-changes`, not jobs → ceilings unchanged. The two single-job workflows
raise 1→2 with the named consequence "detect-duplicate job: tree-identity proof
gating the push arm (#8919)".

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add `detect-duplicate` to validate-vector-config without bumping its row | RED — A3 declared(2) > row(1) |
| 2 | Add a whole extra job to infra-validation instead of the detect-changes step | RED — A3 12 > 11 |
| 3 | Raise a row without consequence text | RED — A-parse/A5 consequence rule |

### Guard 3 — required contexts, queue arms, and workflow_run consumers untouched

**Assembly.** `infra/github/ruleset-ci-required.tf` (24 contexts),
`scripts/required-checks.txt`, `workflows:` keys in every
`.github/workflows/*.yml`, and the five gated files' `on:`/`concurrency`
blocks.

**Property.** The 24 required contexts (`ruleset-ci-required.tf` +
`scripts/required-checks.txt`) still report on PRs; `merge_group` arms
dormant-but-present are unchanged (gates are `push`-event-scoped); no gated
workflow is a `workflows:` upstream (verified list: CI ← release+monitor,
Version Bump and Release ← deploy-docs, Apply web-platform infra ←
git-data-pin-redeploy, fix-constraints-stage-a ← stage-b).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Gate without the `EVENT_NAME == 'push'` scope (affects PR runs) | RED-by-review + test row: dispatch/PR arms emit duplicate=false |
| 2 | Drop `if: always()` from `tenant-integration-required` | pre-existing guard: verdict-script suite + aggregator review |
| 3 | Add the gate to `ci.yml` | rejected by Guard 4 + the exclusion diff (AC5-style) |

### Guard 4 — skipped push runs cannot masquerade as failures or silence alerts wrongly

**Property.** On `infra-validation`, a proven-duplicate push skips the work
jobs AND does not email ops. `notify-main-failure`'s `!= 'success'` term is
true under `skipped` → the `pr_duplicate != 'true'` conjunct is load-bearing,
pinned by a grep-assert in the new test file (assert-anchor form: the conjunct
line in the job's `if:`).

**Assembly.** `infra-validation.yml` `notify-main-failure` `if:` block;
`deploy-script-tests-done` aggregator; `tests/scripts/test-main-duplicate-skip.sh`
Guard-4 grep pin.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop `pr_duplicate != 'true'` from `notify-main-failure`'s `if:` | RED — the Guard-4 grep pin reds |
| 2 | Drop `always()` from `deploy-script-tests-done` | RED — skipped parents hide the aggregate verdict |
| 3 | Emit `duplicate=true` without verifying `notify-main-failure` coverage | RED-by-review: un-alerted skip drift |

## Required-check / branch-protection risks

- Required status checks evaluate PR heads, not pushes — skipping a push run
  can never leave a required context "Expected — Waiting".
- `strict_required_status_checks_policy = true` is what makes the tree
  identity usually hold; it is also why the proof is verifiable rather than
  heuristic.
- Merge queue is REVERTED (#5780 kill-switch); the dormant `merge_group` arms
  are untouched. If the queue is re-adopted, these gates are inert on
  `merge_group` (event-scoped) — correct by construction.
- New permissions `actions: read` + `pull-requests: read` on the detect
  job/step surface: repo is public; both are read scopes; declared explicitly
  because these workflows set `permissions:` (unspecified → none).
- API lag on `commits/{sha}/pulls`: verified authoritative at merge time in
  this repo (registry-dispatcher plan, run 35352234356, 3 s post-merge). A miss
  still fails open → run.

## Measurement plan

Before: `gh api repos/{r}/actions/workflows/<wf>/runs?branch=main&event=push&per_page=100&created=<7d-window>`
+ `/runs/{id}/jobs` for job-min. Record per workflow: push-runs, job-min/run,
total. Expect: tenant-integration ≈15 min × every push; infra-validation ≈14
job-min × infra-touching pushes; vendor-pin ≈3; vector ≈3; corpus ≈1.
After (7d): same queries + count runs whose `detect`/`detect-changes` log shows
`duplicate=true` → skip-rate ≈ share of PR-merged pushes (direct pushes never
skip). Success = job-min per merge push for the 5 workflows drops by the skip
rate × run cost; zero `[ALERT] Infra Validation` false emails; zero missed-
coverage regressions attributable to a skipped run (tree-diff pushes must all
still run — observable by the `::notice::` lines).

## Acceptance Criteria (testable)

- **AC1** `bash tests/scripts/test-main-duplicate-skip.sh` exits 0 incl. the
  six-mutant battery.
- **AC2** `bash plugins/soleur/test/pr-fanout-ledger.test.sh` exits 0 — rows
  for the two single-job workflows read 2 with named consequences; the other
  three unchanged.
- **AC3** `git diff origin/main -- .github/workflows/` touches ONLY the five
  gated files; `ci.yml`, `secret-scan.yml`, `skill-security-scan-postmerge.yml`,
  all `apply-*`, `deploy-*`, `version-bump-and-release.yml`,
  `web-platform-release.yml`, registry/restart/cutover files have empty diffs.
- **AC4** Post-merge live check: the next squash-merged PR whose head was
  up-to-date produces `duplicate=true` notices in the five workflows' detect
  logs and skips the heavy jobs; a subsequent direct/config push produces
  `duplicate=false` and runs.
- **AC5** A merge where main moved after the PR's last check (stale merge /
  merge-order) yields tree≠ → full run (can be simulated in the test via
  fixture; live-verified opportunistically).

## Test scenarios

- Given a squash merge of an up-to-date PR → trees equal, PR run green → skip.
- Given the same but main advanced between check and merge → trees differ → run.
- Given a direct push / admin merge with no PR → `pulls` empty → run.
- Given a rebase-merged PR → `merge_commit_sha` bind + tree compare decide; a
  clean replay of an up-to-date branch still skips, a divergent one runs.
- Given a PR whose `tenant-integration` suite was skipped (non-tenant paths) →
  required-job check fails → push run executes (the suite's only coverage).
- Given the GitHub API 5xx mid-proof → run.

## Alternatives / rejection list

| Alternative | Rejected because |
|---|---|
| Gate `ci.yml` | `workflow_run` consumers read only the run conclusion; an all-skipped run reports `success` and deploys/monitors a SHA no check touched. Requirement forbids it; risk confirms it. |
| Gate `secret-scan.yml` | Push arm's all-refs advisory sweep + main-ancestry re-scan are not tree-bound duplicates; it is the security floor and produces 5 required contexts. ~2 job-min not worth a partial-step gate. |
| Gate any `apply-*` / `deploy-*` / `version-bump-and-release` / dispatch workflow | Stateful effects: identical inputs ≠ already-applied. Skipping an apply never delivers the change. |
| Gate `skill-security-scan-postmerge.yml` | It is the bypass audit; "the PR gate was green" is the condition it exists to distrust. |
| Path-list comparison instead of tree SHA | Path filters drift (the #7299/#7764 defect class); the tree SHA is the proof, not an approximation. |
| `check-runs` API instead of `actions/runs` | Requires `checks: read` and name-matching against job display names; workflow-runs API keys off the workflow file and run id directly. |
| A single shared workflow that skips others via API | Skip decisions must live inside each push run (job graphs, `always()` aggregators, notify edges differ per file); a central canceller recreates the pending-eviction problems the ledger documents. |
| Assume squash-merge equivalence without the API proof | The requirement's own stipulation — and stale-base/merge-order merges are exactly infra-validation's #7299 raison d'être. |

## Deferred follow-ups

- If the queue is re-adopted (#5780), the same proof could gate `merge_group`
  re-runs — out of scope; the event-scope makes it safe regardless.
- vendor-pin upstream-liveness drift cadence (see its residual) — candidate
  for a weekly scheduled probe if a vendor drift monitor is later wanted.
- `secret-scan`'s advisory sweep could be split into its own always-run job to
  make the blocking legs skippable — rejected now on complexity; revisit only
  if push volume makes it material.

## Blast radius (files changed)

- `scripts/main-push-duplicate-skip.sh` — new (~80 lines).
- `tests/scripts/test-main-duplicate-skip.sh` — new; +1 `run_suite` line in
  `scripts/test-all.sh`.
- `.github/workflows/infra-validation.yml` — detect-changes output+step, needs/if
  conjuncts on 6 jobs incl. `notify-main-failure`.
- `.github/workflows/tenant-integration.yml` — detect-changes push branch + perms.
- `.github/workflows/vendor-pin-verify.yml` — same.
- `.github/workflows/validate-vector-config.yml`, `skill-security-scan-corpus.yml`
  — `detect-duplicate` job + `needs`/`if`.
- `scripts/pr-fanout-ledger.txt` — two rows 1→2 with named consequence.
