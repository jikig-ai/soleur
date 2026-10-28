# Tasks: P4d bounded wait, then CI is the gate, on a refused local battery (rc=4)

Plan: `knowledge-base/project/plans/2026-10-28-feat-p4d-bounded-wait-on-battery-refusal-plan.md`
Branch: feat-one-shot-9757-p4d-rc4-bounded-wait. Issue: #10924 (Ref only). Umbrella: #9757 (Ref only). Draft PR: #11390.

Scope note: rc=4 here is the local battery refusal (`affected-tests.sh` / `test-all.sh`), not the monitor lock (CTO ruling F1 in decision-challenges.md).

## Phase 1: RED first

- 1.1 Create `plugins/soleur/test/ship-battery-refusal-wait.test.sh` (sources `test-helpers.sh` and `lib/git-fixture-env.sh`, owning EXIT trap installed first, scratch git repo per arm, argv-strict PATH stubs for `sleep` and `date`, stub `scripts/test-all.sh --capacity` in the scratch repo).
  - 1.1.1 Classifier rows: sibling text (1 and 2 siblings, CRLF, long preamble) -> contention; SOLEUR_SUBAGENT-only, `[FAIL]`, `[KILLED]`, `AFFECTED_UNRESOLVED`, mixed evidence, empty log, missing log, random text -> not-waitable.
  - 1.1.2 Wait-loop rows: `CAPACITY_OK measured_runs=0` -> exit 10; never drains -> 42 at budget; budget boundary; shared state across two invocations; `CAPACITY_CONTENDED ... measured_runs=0` keeps waiting; `measured_runs=?`, a failing call and a hung call (bounded by `timeout`) keep waiting; never readable -> 11 `capacity-unreadable`; empty state = fresh episode, garbage or future epoch exits 2; stray statuses 1/127/130 never continue.
  - 1.1.3 Infra rows: prefix, workflow file, committed / working-tree / untracked / rename-source, git failure -> exit 12, never 42; `--full` + contended -> 12.
  - 1.1.4 Arg rows: non-integer, negative, unknown flag -> exit 2; defaults 1800 / 60; no env var is read.
  - 1.1.5 Parity rows: sibling-refusal line and both infra literals present in the live `scripts/test-all.sh`; wiring rows (SKILL.md names script and reference, reference linked, REFUSED-nothing-ran sentence intact).
  - 1.1.6 Mutation rows 1-9 and harness rows H1, H2 from the plan's Guard Contract; PASS floor asserted. No property loop.
- 1.2 Run the suite once; confirm RED for the right reason (script absent).

## Phase 2: the script

- 2.1 Create `plugins/soleur/skills/ship/scripts/battery-refusal-wait.sh` (`set -uo pipefail`, header contract, sanitized output, no `eval`, no env-injected commands).
  - 2.1.1 `--classify-only FILE` prints `class=contention|not-waitable`, exit 0; whole-log scan, CR stripped, full refusal shape required.
  - 2.1.2 Episode epoch written atomically before the first poll when the state file is empty; flags only for budget and interval (`--budget-s`, `--interval-s`); `date +%s` via PATH; `timeout` around the capacity call.
  - 2.1.3 Capacity poll keyed on `CAPACITY_OK` + `measured_runs=0`; stderr captured with rc; track whether any valid reading was seen.
  - 2.1.4 Infra predicate mirroring the runner's `_diff_names` assembly (four `git diff` forms incl. `-M` rename sources, plus untracked), unanchored substring, two triggers; fail closed; `--full` flag treated as the same carve-out.
  - 2.1.5 One chokepoint `case`; exits RETRY 10, NOT_WAITABLE 11, QUEUE_IN_LOCK 12, usage 2, CI_IS_THE_GATE 42.
- 2.2 Run the suite to GREEN; drive every mutation row RED against its mutant.

## Phase 3: wiring and docs

- 3.1 Create `plugins/soleur/skills/ship/references/battery-refusal-wait.md` (launch-first one-Monitor recipe with `wait_rc`, fixed PR Test plan line, links to the contract and the substituted-shard learning).
- 3.2 Edit `plugins/soleur/skills/ship/SKILL.md`: replace the two contention paragraphs (including the unbounded up-front capacity loop) with one pointer paragraph that keeps the queue-in-lock command and links the reference; net bytes <= 0; keep the pinned-dispatch and REFUSED sentences; do not touch `review/SKILL.md`.
- 3.3 Edit `plugins/soleur/skills/ship/references/affected-gate-contract.md` rc 4 row (one clause).
- 3.4 Edit `scripts/lib/test-affected-paths.sh` (declaration) and `scripts/ci-pr-affected-audit.accept.tsv` only where the census / audit lint names them.
- 3.5 Add the ~5-line ADR-196 addendum via `soleur:architecture`.

## Phase 4: verify (local, bounded, no credentials)

- 4.1 New suite, `ship-battery-owed.test.sh`, `fullsuite-merge-gate.test.ts`, `components.test.ts`, `c4-count-parity.test.sh`, `lint-orphan-test-suites.sh`, `lint-skill-body-budget.py --base origin/main`, `lint-guard-contract.py`, markdown lint.
- 4.2 Real-log check (AC12): classify a real captured sibling refusal and a real degraded-affected refusal built from a real `flock` holder.
- 4.3 Confirm the diff leaves `apps/**`, `scripts/registry-restore-from-ghcr.sh`, `apply-web-platform-infra.yml`, `scripts/test-all.sh`, `affected-tests.sh`, `harness.ts`, `drain-prs/SKILL.md` and `monitor-pr-checks.sh` unchanged.

## Phase 5: ship (pipeline)

- 5.1 PR body `Ref #9757` + `Ref #10924` only; `## Changelog`; `semver:patch`.
- 5.2 `gh pr merge <N> --squash --auto` (one merge string per Bash command); postmerge: `deploy-arm.sh find --wait`, served -> CONTAINS; skip Sentry monitors, live-verify, sole-copy.
- 5.3 Tick the P4d box in #10924; do not close #10924 or #9757.
- 5.4 Emit the resume prompt for #10932 (read its residual-gaps comment first).
