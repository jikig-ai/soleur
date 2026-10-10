# Tasks: pid-namespace guard for signal-helper mutants

Plan: `knowledge-base/project/plans/2026-10-10-chore-pid-namespace-guard-for-signal-helper-mutants-plan.md`
Branch: `feat-one-shot-pid-namespace-guard-signal-helpers`. Tracker 9217 is `Ref` only.

## Phase 0: Setup and baselines (no edits)

- 0.1 Merge `origin/main` once; re-run premise checks (9217 open; no open grep-q slice PR touching `plugins/soleur/test/roadmap-reconcile.test.sh`; #8626 vs `review/SKILL.md` bytes).
- 0.2 Record base numbers: `wc -c plugins/soleur/skills/review/SKILL.md`, `lint-shell-capture-exit` summary, shellcheck counts of files to touch, `lint-orphan-test-suites` summary. One gate at a time (load 25 to 41).
- 0.3 Re-measure the namespace facts (`$$` 1, `$PPID` 0, rc passthrough 0/3/7/125, nested use, background child reaped).

## Phase 1: the helper (tests first)

- 1.1 Write `plugins/soleur/scripts/run-in-pid-namespace.test.sh` (rows R1 to R9, N1 to N7 incl. N5b, literal floors, `cases + skipped == planned`, SKIP line, witness control); run it RED.
- 1.2 Write `plugins/soleur/scripts/run-in-pid-namespace.sh` (`type -P` once, probe with the NSpid check, refusal arms each printing the marker, rc 125, `exec "$u" ... sh -c '<check> || ...; exec -- "$@"'`); run GREEN.
- 1.3 Add the nonce-walker data file under `plugins/soleur/test/fixtures/ancestor-signal/` (fail-closed preconditions) and the N4 chain; run the refusal rows after every text edit.

## Phase 2: the scan

- 2.1 Fixture data files (`.txt`, under `plugins/soleur/test/fixtures/ancestor-signal/`) and `plugins/soleur/scripts/scan-ancestor-signal-helpers.test.sh` first (Guard 2 rows 1 to 18, live row, floors); RED.
- 2.2 Write `plugins/soleur/scripts/scan-ancestor-signal-helpers.py` (W, P, G gated, L listed; bound rule; multiset baseline; rc 0/1/3).
- 2.3 Seed `plugins/soleur/scripts/ancestor-signal-helpers.baseline.txt` from `--write-baseline`; review each of the 7 rows; header carries the replacement rule.

## Phase 3: the allocator verb

- 3.1 Arms in `tests/scripts/test-soleur-sandbox.sh` first (valid sandbox, bad shapes, missing `--`, missing helper, trailing slash, usage); RED.
- 3.2 `run-isolated` arm in `scripts/soleur-sandbox.sh`; GREEN.

## Phase 4: wiring

- 4.1 `work-scratch-sandboxes.md` section (D5 sentence, verb, helper path, rc 125, PID-1 caveat, `timeout -k`, environment differences, nonce technique, scan).
- 4.2 `review/SKILL.md` pointer (<= 220 bytes, only if it fits; never edit `skill-body-budget.json`).
- 4.3 `risk-tier-and-fix-rounds.md` bullet (check `review-tier-parity`, `fix-round-seats.sh`, `emit-review-trailer.sh` anchors).
- 4.4 `test-design-reviewer.md` bullet.
- 4.5 `plan-sharp-edges.md` entry.
- 4.6 ADR-250 one-line amendment only if it enumerates the allocator's verbs.

## Phase 5: bound the second walker

- 5.1 `plugins/soleur/test/roadmap-reconcile.test.sh`: export `SOLEUR_TEST_SUITE_PID=$$`, bound the `term` walk, fail closed when unset, hazard comment at the match line.
- 5.2 No-kill rehearsal, suite green, catch-all mutant red through the helper only.
- 5.2b One committed anchored row in `plugins/soleur/test/roadmap-reconcile.test.sh` (guard, suite-PID comparison and `-gt 1` on non-comment lines of the `term` branch).
- 5.3 Hand-edits ledger entry only if an open slice PR touches the file.

## Phase 6: verification (serial)

- 6.1 Lints: `lint-shell-capture-exit` (baseline), `guard-vacuity-floor.test.sh`, `lint-orphan-test-suites.sh`, `lint-guard-contract.py` on the plan, `grep-q-pipe-guard.test.sh`, `lint-skill-body-budget.test.sh`, `bun test plugins/soleur/test/components.test.ts` when bun is installed, shellcheck delta, `pre-push-ratchet-lane.sh` last.
- 6.2 Targeted suites by name (new suites, `test-soleur-sandbox`, `roadmap-reconcile`, `resolve-regenerable-conflicts`, shard manifest and totality). No `--affected`, no `--print-selection`.
- 6.3 `ubuntu:24.04` run if docker and load allow; otherwise record CI as the userland check.
- 6.4 Mutation batteries for Guards 1 to 3 inside the helper, `ulimit -v 6000000`, one mutant at a time, `timeout -k`, pristine restore from a `cp` backup; write `evidence.md` from the final state.
- 6.5 Re-derive the workflows a merge fires on the final file list; PR body first line states them; `Ref #9217` only; banned words and operator-verb bullets avoided; `semver:patch`, `type/chore`, `domain/engineering`.
