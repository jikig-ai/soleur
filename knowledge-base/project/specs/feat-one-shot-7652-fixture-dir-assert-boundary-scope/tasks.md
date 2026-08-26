# Tasks — fix #7652: fixture dir operand + repo-write boundary scope

Derived from `knowledge-base/project/plans/2026-08-26-fix-7652-fixture-dir-assert-and-boundary-scope-plan.md`
(revision R2, post-panel). Phase order is load-bearing — read the plan's Implementation Phases
preamble before reordering anything.

## Phase 0 — Measure, freeze, decide (no product edits)

- [ ] 0.1 Reproduce `git -C ""` in both directions: inside a repo (writes to CWD) and outside one
      (`fatal`, rc≠0). Capture both for the PR body.
- [ ] 0.2 Cost CWD isolation: run the affected shards with each suite's CWD outside any repository
      (plus `GIT_CEILING_DIRECTORIES`) and record exactly which suites break. Candidate set is the
      29 suites using `git rev-parse --show-toplevel`; the other 358 resolve from `BASH_SOURCE`.
- [ ] 0.3 Apply the pre-committed decision rule: ≤ 40 breaks, each a path-resolution fix ⇒ isolation
      is the primary mechanism and Phase 3 is residual only. Record the measured number either way.
- [ ] 0.4 Build the Phase 3 scanner as a read-only probe; freeze its first output (site count + file
      list) as the shrink-only baseline, **before** choosing the remediation idiom.
- [ ] 0.5 Re-measure every machine-state number and print the probe beside each. Do not inherit any
      figure from the plan text.
- [ ] 0.6 Assert `extensions.worktreeConfig` unset and no `config.worktree`.
- [ ] 0.7 Record pre-change verdicts for every suite in scope plus
      `scripts/test-all-killed-classification.test.sh` and
      `scripts/test-all-infra-coverage-notice.test.sh`.
- [ ] 0.8 Observe-only full run with the widened `_repo_state` reporting but not failing, on a clean
      CI-shaped checkout **and** locally. Confirm a zero delta across every dimension. This gates
      whether the boundary half can ship before the sites are fixed.

## Phase 1 — CWD isolation at `run_suite` (primary mechanism)

- [ ] 1.1 `run_suite()` starts each suite in a per-run throwaway directory outside any git
      repository, with `GIT_CEILING_DIRECTORIES` set.
- [ ] 1.2 Convert the 29 `git rev-parse --show-toplevel` suites to `BASH_SOURCE` root resolution.
- [ ] 1.3 Add a guard: a suite whose recorded CWD is inside a git repository fails.
- [ ] 1.4 State the limit explicitly — isolation does not reach a suite invoked directly, the
      lefthook path, or corpora outside `SUITE_GLOBS`. That limit goes in the boundary message.

## Phase 2 — The boundary: inspect more, claim exactly that

- [ ] 2.1 Create `scripts/lib/repo-write-boundary.sh`. Source it from `scripts/test-all.sh` with the
      `_REL_LIB` contract (missing file ⇒ `exit 2`), plus a `declare -F` set check so a stale lib is
      named rather than silently narrowing.
- [ ] 2.2 **Placement:** the `source` line, the function definition and every new variable
      initialisation go **above** `tc_acquire "test-all"` — both SUT sandboxes delete everything
      between that anchor and `tc_epilogue`, and the end block runs under `set -u`.
- [ ] 2.3 `_repo_state()` returns a dimension manifest (`measured` / `not-measured` per dimension).
      The message's inspected / not-inspected lists render **from the manifest**, never a literal.
- [ ] 2.4 Dimension: HEAD (`git rev-parse HEAD`) — status quo.
- [ ] 2.5 Dimension: working tree / index (`git status --porcelain`) — status quo.
- [ ] 2.6 Dimension: local config — `git config --local --list -z`, split on NUL, digest every value
      with a per-run salt, keep every key name, sort. Carve out **only**
      `branch.*.vscode-merge-base`; keep `branch.*.remote` and `.merge` (see 2.8).
- [ ] 2.7 Dimension: local refs — `git show-ref --heads --tags`, sorted, split by harm class measured
      from `git worktree list`. FATAL: this worktree's branch, the default-branch ref, any ref
      **deleted**, any tag. REPORT: a head belonging to a branch checked out elsewhere. Exclude
      `refs/remotes/**`.
- [ ] 2.8 Verify the composition case: a `git -C "" checkout -b probe origin/main` escape must be
      caught. With a blanket `branch.*` cut it was invisible in both dimensions at once.
- [ ] 2.9 Shell discipline: brace form `{ grep -v … || true; }` **inside** the pipeline (zero-match
      `grep` exits 1 and `pipefail` promotes it). Distinguish `git show-ref` rc=1 "no refs" from a
      capture failure, or ref deletion reads as not-measured and fails open.
- [ ] 2.10 Whole-function degrade-open. No per-dimension not-measured state feeding a static claim.
- [ ] 2.11 Rewrite the message: inspected list, not-inspected list (push *content*, loose objects,
      `.git/hooks/`, `branch.*.vscode-merge-base`, remote-tracking refs, reflogs, multivar ordering,
      other entry points, suites this runner did not start), **per-dimension next action**, and
      attribution pointing at the `[contention]` preamble. Do not echo `SIBLING_RUN_DETECTED`.
- [ ] 2.12 Re-emit the verdict in the breakdown area so it survives scrollback. It must **not** be
      `=== `-shaped — `=== N/M suites passed ===` stays the last `===` line.
- [ ] 2.13 EXIT-trap NOTE so a killed run cannot read as clean.
- [ ] 2.14 Teach `scripts/test-all-killed-classification.test.sh` and
      `scripts/test-all-infra-coverage-notice.test.sh` to copy the new lib into their sandboxes.
- [ ] 2.15 Update the runner's EXIT CONTRACT block (`scripts/test-all.sh:4-35`) for the new REPORT
      class.
- [ ] 2.16 Create `scripts/lib/repo-write-boundary.test.sh` (auto-registers). Include the
      narrow-form control: the pre-#7652 snapshot must report **no** delta on a config write and a
      `refs/heads/main` move.

## Phase 3 — The residual assertion and the guard that keeps it

- [ ] 3.1 Author `assert_fixture_dir` with one canonical body: reject empty, reject relative, reject
      bare `/`. Test the leading `/` only — never `realpath` (symlinked `/tmp`).
- [ ] 3.2 Delivery: sourced where the file already sources `plugins/soleur/test/test-helpers.sh`;
      defined inline elsewhere (the `cdx()` precedent), with a rule that inline definitions match the
      canonical bytes.
- [ ] 3.3 Create `plugins/soleur/test/lib/fixture-scan.py` — the shared corpus walk, heredoc skipping
      and comment skipping. Not a `*.test.sh`, so the orphan lint is unaffected.
- [ ] 3.4 Create `plugins/soleur/test/fixture-dir-operand-assert.test.sh` importing that module.
      Scope: **P1a only** — `git -C "$X" <write-verb>` with `X` bound from a positional (at binding
      or use site) or **any** command substitution. Name `init`, `clone` and `worktree add` in the
      verb list explicitly.
- [ ] 3.5 Corpus is `git ls-files '*.sh'`, not `'*.test.sh'` — the suffix misses
      `tests/hooks/test_hook_emissions.sh` (which the runner runs), sourced libs, and
      `scripts/context-reviewed-gate-discoverability.sh`.
- [ ] 3.6 Create `plugins/soleur/test/fixture-dir-operand-assert.baseline.txt` in the
      `scripts/lint-shell-capture-exit.py` shape (`--baseline`, `--write-baseline`, shrink-only).
- [ ] 3.7 Remediate the sites the baseline records. Known-certain: the five positional helpers;
      `context-reviewed-gate.test.sh`'s `mktemp` binding **and its caller at `:80``;
      `ship-unpushed-commits-gate.test.sh`'s ten `read … < <(make_synced_branch …)` sites;
      `tests/hooks/test_hook_emissions.sh`; `scripts/context-reviewed-gate-discoverability.sh`.
- [ ] 3.8 Re-run each touched suite individually. Where a relative path is intended, make the **call
      site** absolute rather than relaxing the assertion.
- [ ] 3.9 Record every flagged row that is culled, with its reason. No silent drops.
- [ ] 3.10 Add `config` to `fixture-cd-containment.test.sh`'s `WRITE` regex; correct its `git -C`
      exemption comment and its "Prefer the last" header prose; import the shared module.
- [ ] 3.11 Bump `MIN_FIRING_SUITES` by the number of firing suites added. Leave
      `MAX_CONSTRUCTION_FAILURES` alone — fix the suite instead.
- [ ] 3.12 File three tracking issues: P1b relative operands; the plugin-local-runner precondition;
      the pre-existing `gdpr-gate` rule staleness (label `compliance/critical`).

## Phase 4 — Verification

- [ ] 4.1 Both new suites GREEN; every touched suite re-run individually.
- [ ] 4.2 Full battery on the affected shards, then assert **all** inspected dimensions unchanged —
      not only HEAD and porcelain.
- [ ] 4.3 Execute every row of the Guard 1, Guard 2 and Guard 3 mutation matrices; prove each
      mutation landed with `diff -q` against a pristine copy, never against `HEAD`.
- [ ] 4.4 `scripts/lint-orphan-test-suites.sh` and `scripts/guard-vacuity-floor.test.sh` green; both
      SUT sandbox suites pass.
- [ ] 4.5 `bash scripts/lint-diagnosis-claims.sh` green (BLOCKING, AP-021 — it owns the diagnostic
      text this change rewrites).
- [ ] 4.6 Confirm no config value appears in any boundary output, against both a `credential.*` key
      and an `http.*.extraheader` key.

## Notes

- `## Review Disposition` in the plan records what the eight-consult panel changed and why.
- `decision-challenges.md` in this directory carries UC-1 (the two-PR split) for the operator.
- The plan's file inventory is a starting point, never an acceptance set — the scanner defines the
  population and the frozen baseline records it.
