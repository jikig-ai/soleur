# Tasks: merge-effect-class.sh classifier (#10923, Ref #9757)

Plan: `knowledge-base/project/plans/2026-10-24-feat-merge-effect-class-classifier-plan.md`

## Phase 0: ADR first (no code before this commit)

- 0.1 `git fetch origin main`; list `origin/*` refs; confirm ADR-297 is free.
- 0.2 Write ADR-297 with `soleur:architecture` (rich shape, `status: active`): closed-world allowlist with the
  `AGENTS*.md`/`CLAUDE.md` basename exclusion, exit 0/1/2 contract, flat ci-only list plus parity test with
  closed-world trigger enumeration and derived witnesses, single consumer, repo-owned applicability sentinel,
  `--pr` state/base/head binding; the verdict meaning ("no path-gated production workflow fires from this file
  list") and the ci-only meaning ("not directly gated by the merged file list as a production act"); never evidence
  in a `Gate:` or receipt; precedence against the Deploy Pipeline Fix Drift Gate, the `Blast Radius:` label, the
  infra "merge-effect first line" and the `{OUTCOME}` sentence; Rejected for now: the epic-reference scope class
  with four flip conditions; true stale-copy residual; review-owned ci-only and inert lists; AP-020 note; "no C4
  impact" with the cited `plugin -> github` edge check.
- 0.3 Commit the ADR alone.

## Phase 1: RED tests, then the guard

- 1.1 Write `plugins/soleur/scripts/merge-effect-class.test.sh`: table-driven rows, exit and stdout contract,
  consumer-rule rows (substring consumer and `$?`-only consumer must be detected, `rc != 0` branch), a `gh` fake
  that accepts exactly the modelled argv (exit 64 otherwise) with a two-page `--slurp` fixture, minimum-assertion
  floor, exactly six executable mutants (`widen`, `gutted`, `first-only`, `exit2-not`, `no-slash-guard`,
  `drop-prev`) on a scratch copy (`# mut:` markers, noop and pristine-green controls, replacement count 1, temp
  file plus `mv`, `cmp`, crashed is not killed). Run RED.
- 1.2 Write `plugins/soleur/scripts/merge-effect-class.ci-only.tsv` and
  `plugins/soleur/test/merge-effect-class-parity.test.sh` (python3 -I, PyYAML, fails loudly if absent) with the
  hand-rolled matcher and its unit table, the real-tree sweep, the anti-vacuity instantiation, and the
  `MEC_WORKFLOWS_DIR` / `MEC_CI_ONLY_LIST` / `MEC_INVARIANTS_TEST` / `MEC_SCRIPT` seams.
  - 1.2.1 Read each unfiltered, `workflow_run`-only, `release` and `pull_request: closed` workflow (and
    infra-validation.yml) and give it a deliberate ci-only reason, or stop and take it back to the CTO if its
    unfiltered firing mutates production on every merge.
  - 1.2.2 Assert `workflow-run-deploy-invariants.test.sh` still carries the executable P3 and P1 assertions (the
    one deemed-gated constant, `web-platform-release.yml`).
- 1.3 Implement `plugins/soleur/scripts/merge-effect-class.sh` (`--files-from`, `--pr`, `--print-witnesses`,
  `--self-check`); reuse the `admin-merge-ready.sh` fetch shape with per-object `jq -e` checks. GREEN.
- 1.4 Measure the base rate with `--pr` over the last ~50 merged PRs (read-only `gh`); record the distribution for
  the PR body.

## Phase 2: consumer

- 2.1 Edit `plugins/soleur/skills/ship/references/operator-holds.md` section 3 step 2: the literal bash block
  (`out=$(...) && rc=0 || rc=$?`, whole-line equality, AND across several PRs), the two plain sentences, the
  recorded PR-body verdict line, the `--match-head-commit` rule, and the one-line `not-applicable` bug signal.
- 2.2 Run `go-hold-routing.test.sh`, `cto-interface-selector.test.sh`, `pr-overlap-preflight.test.sh` and the
  hold-evaluator suite; confirm none pins the replaced sentence.

## Phase 3: registration

- 3.1 Add the `AFFECTED_*` array in `scripts/lib/test-affected-paths.sh`: `.github/workflows/*.yml`, the ci-only
  list and the script itself.
- 3.2 Add rows to `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv`,
  `plugins/soleur/test/fixture-relative-assert.baseline.txt` only where a linter reports a gap.
- 3.3 Run `scripts/lint-orphan-test-suites.sh` (after the files are tracked), `scripts/markdown-lint.sh
  --repo-sweep`, `bash .claude/hooks/grep-q-pipe-guard.test.sh` (`PJ_TRIPLES` is 288 on main today), and
  `plugins/soleur/test/c4-count-parity.test.sh`; confirm the parity test runs in the test-scripts shard of the
  required `test` aggregate; record the affected-index ratchet as advisory. Run long suites detached with an rc
  file.

## Phase 4: ship hygiene

- 4.1 `git config user.name; git config user.email` prints `Jean Deruelle` / `jean.deruelle@jikigai.com` before the
  first commit.
- 4.2 PR body: `Ref #9757` only, `## Merge Danger` (`Blast Radius: plugin`), `## Changelog`, verdict distribution,
  ci-only classifications.
- 4.3 File two tracking issues: ADR-289 `adopting -> accepted` flip (cite receipts `issuecomment-6339592687` and
  `issuecomment-6344903791`); scope-class revisit with the four flip conditions.
- 4.4 `gh pr merge <N> --squash --auto` (never `--admin`); the PR touches no apply workflow, so no operator
  question.
- 4.5 Run `plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch` and markdownlint on the plan, this
  file and `decision-challenges.md`.
