# Tasks — path-gate file-scoped PR workflows (required-safe mechanism)

Plan: `knowledge-base/project/plans/2026-09-25-feat-ci-path-gating-plan.md`
Branch: `feat-one-shot-ci-path-gating` · PR: #8897 (draft)

## Phase 0 — Preconditions (verify at implementation time, do not assume)

- [ ] **0.1** Re-pull live rulesets and diff against the plan's recorded state:
      `gh api repos/jikig-ai/soleur/rulesets/14145388 --jq '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context' | sort`
      → must still be the 24 contexts in the plan. Same for `13304872` (CLA:
      `cla-check`, `cla-evidence`). If either changed, re-derive verdicts
      before touching files.
- [ ] **0.2** Collision re-check:
      `gh pr list --state open --json number,files -q '.[] | .number as $n | .files[] | select(.path | startswith(".github/workflows/") or . == "scripts/pr-fanout-ledger.txt") | "\($n) \(.path)"'`
      → confirm no new open PR touches `dependency-review.yml`,
      `pr-quality-guards.yml`, `scripts/pr-fanout-ledger.txt`. If #8878
      (skill-security-scan-pr-trailer.yml) merged, the deferral of that file
      still stands (fail-closed-diff duplication) unless re-triaged.
- [ ] **0.3** Baseline sanity run: `bash plugins/soleur/test/pr-fanout-ledger.test.sh`
      green on the untouched tree (a later red is attributable to this change).
- [ ] **0.4** Rebase check: `git fetch origin && git status -sb` — if behind
      `origin/main` on any of the three touched paths, rebase first.

## Phase 1 — `dependency-review.yml`: in-job detect + step gate

- [ ] **1.1** Add `detect` step FIRST in the `dependency-review` job (before
      checkout): `gh api --paginate "repos/$GH_REPO/pulls/$PR_NUMBER/files"
      --jq '.[].filename'` → grep the manifest/lockfile superset regex (full
      list in plan §1) + self-trigger `^\.github/workflows/dependency-review\.yml$`.
      `if: github.event_name == 'pull_request'`. Output `deps`.
- [ ] **1.2** FAIL-OPEN branches: API error OR empty file list OR missing
      `PR_NUMBER` → `deps=true`. Comment records that a required check may
      only skip on proof.
- [ ] **1.3** Gate the pull_request step:
      `if: github.event_name == 'pull_request' && steps.detect.outputs.deps == 'true'`.
      The `merge_group` step stays `if: github.event_name == 'merge_group'` —
      unconditional within its arm.
- [ ] **1.4** Job-level `if:`: NONE. Job name `dependency-review` untouched
      (required ABI). Header comment extended: note the in-job detect and the
      manifest-superset maintenance rule ("err wide").
- [ ] **1.5** Ledger: `dependency-review.yml` row unchanged in columns; append
      an in-job-detect clause to the consequence (ci.yml-row convention:
      `paths` stays `no` for trigger-invisible gating).

## Phase 2 — `pr-quality-guards.yml`: detect job + five job gates

- [ ] **2.1** Add `detect` job (first job; `timeout-minutes: 5`; no checkout;
      outputs `settings_json`, `worktrees`, `webplat`, `client_pii`, `sweep`)
      per plan §2 semantics:
      - non-`pull_request` event OR `gh api` failure OR unresolvable list →
        all five `true` (fail-open);
      - `^\.github/workflows/pr-quality-guards\.yml$` or `^\.github/scripts/`
        in the file list → all five `true` (machinery self-trigger);
      - `sweep` additionally fetches `.github/enforcement-contracts.json` at
        the PR head (`gh api repos/…/contents/…?ref=<head_sha>` + `jq
        '.sibling_sets[].trigger[]'`) and matches the file list against the
        trigger set; fetch/parse failure → `true`.
- [ ] **2.2** Gate the five advisory jobs — add `needs: detect` and extend the
      existing `if: github.event_name == 'pull_request'`:
      `settings-json-integrity` → `settings_json`;
      `stray-worktree-marker-block` → `worktrees`;
      `userid-bypass-lint` → `webplat`;
      `client-pii-grep` → `client_pii`;
      `sweep-completeness` → `sweep`.
- [ ] **2.3** DO NOT touch: `guard-script-fixture-tests`, `markdown-lint`
      (required + whole-corpus-deliberate), `pii-grep`, `pr-body-vs-diff`,
      `auto-commit-message-density` (whole-diff/metadata surfaces). Do not
      weaken any opt-out-label or no-opt-out comment.
- [ ] **2.4** Header comment updated: the merge_group note must reflect that
      the five gated jobs are now doubly gated (event AND detect); the "DO
      NOT add an `if:`" warning for the two required jobs stays verbatim.
- [ ] **2.5** Ledger: `pr-quality-guards.yml` jobs `10 → 11`, consequence
      clause naming `detect` (fail-open file-list detector gating the five
      file-scoped advisory jobs; required jobs stay every-push). The jobs
      column is a CEILING — 11 must cover `detect` plus existing 10.

## Phase 3 — Structural test `plugins/soleur/test/ci-path-gating.test.sh`

- [ ] **3.1** Assert dependency-review.yml: `detect` step present before the
      action step; PR action step `if:` references `steps.detect.outputs.deps`;
      job has NO job-level `if:`; merge_group step unchanged
      (`github.event_name == 'merge_group'`).
- [ ] **3.2** Assert pr-quality-guards.yml: `detect` job declares all five
      outputs; each gated job's `needs:` includes `detect` and its `if:` names
      the right output; `guard-script-fixture-tests` and `markdown-lint` have
      no `needs.detect` edge and no new `if:`.
- [ ] **3.3** Assert the manifest regex contains the repo's live manifests
      (`package.json`, `package-lock.json`, `requirements.txt` — grep-anchored)
      plus the workflow self-path.
- [ ] **3.4** Assert script-surface ⊆ detect-surface per gate (settings script
      names `.claude/settings.json`; client-pii `find` roots ⊆ `client_pii`
      pattern; stray-worktree greps `.claude/worktrees/`).
- [ ] **3.5** Assert fail-open branches exist in both files (grep the
      error→true branches, not a prose claim).
- [ ] **3.6** Register the suite in `scripts/test-all.sh` /
      `.github/scripts/test/run-all.sh` per whichever convention the new suite
      falls under (bash-only, no network — fixture-test contract #6454).

## Phase 4 — Validate

- [ ] **4.1** `bash plugins/soleur/test/pr-fanout-ledger.test.sh` green.
- [ ] **4.2** `bash plugins/soleur/test/ci-path-gating.test.sh` green.
- [ ] **4.3** `actionlint` (if wired in repo hooks) / YAML parse on both
      touched workflows.
- [ ] **4.4** Grep gate: no `paths:`/`paths-ignore:` added under
      `pull_request` in `dependency-review.yml` or `pr-quality-guards.yml`;
      no `types:` list narrowed.
- [ ] **4.5** Push and read THIS PR's own checks: `dependency-review` must
      report SUCCESS on this PR (it touches only workflows — expect the
      self-trigger to run the scan once, which also exercises the path);
      the five gated guard jobs must report per their surfaces
      (`pr-quality-guards.yml` self-trigger → all five RUN here — a live
      exercise of the gate).

## Phase 5 — Post-merge measurement (record in this file)

- [ ] **5.1** ≥10 subsequent `dependency-review.yml` runs: job-time vs 13–18 s
      baseline; skipped-run share.
      `gh api "repos/jikig-ai/soleur/actions/workflows/dependency-review.yml/runs?per_page=10&status=completed"` then `…/runs/<id>/jobs`.
- [ ] **5.2** ≥10 subsequent `pr-quality-guards.yml` runs: per-job
      durations + skipped share of the five gated jobs vs ~60–75 s/push sum.
- [ ] **5.3** Any false-skip incident → revert the offending output to
      always-true and record.

## Explicitly NOT in scope (verdicts recorded in the plan)

- `skill-security-scan-pr-trailer.yml` — already in-job gated; deferred
  (#8878 collision + ~20 s value + fail-closed-diff-semantics duplication).
- `guard-script-fixture-tests`, `markdown-lint`, `ci.yml` suites — required /
  unbounded-surface / deliberate whole-corpus.
- `secret-scan.yml`, `pii-grep`, `pr-auto-close-scanner`, CLA pair,
  board-status-sync, cancel-superseded-pr-runs, cleanup-unmerged-bot-branches,
  dev-ledger-reconcile, constraint-gates, claude-code-review — see verdicts
  table for the named reason on each.
