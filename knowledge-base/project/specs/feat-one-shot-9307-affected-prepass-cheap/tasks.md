# Tasks: cheap affected pre-pass (umbrella #9307, PR-A)

Plan: `knowledge-base/project/plans/2026-10-01-feat-cheap-affected-prepass-and-pr1-residuals-plan.md`
Challenges: `knowledge-base/project/specs/feat-one-shot-9307-affected-prepass-cheap/decision-challenges.md`

Scope of this branch is PR-A only (byte-identical speedup). PR-B and PR-C are re-filed on #9307, not started.
Every lever is test-first: write or flip the RED row, see it red locally, then change the code. Never run the
full local gate (the runner is touched); run the named targeted suites and let CI gate.

## 1. Phase 0: bench and derive suite

- [ ] 1.1 Write `scripts/test-affected-derive.test.sh` rows R1, R2, R3, R3b, R4 and R7 (bench compare rows) and see them red
- [ ] 1.2 Create `scripts/affected-prepass-bench.sh` (`--base`, `--head`, `--probe`, `--runs`, `--compare-only`, `--report-diff`; both sides rc 0; `AFFECTED_SUMMARY` `of=` equals the enumerated count; unset `CI` and `SOLEUR_TEST_FORCE_ALL`; also compare `--print-affected-set`)
- [ ] 1.3 Register the suite (`run_suite` line in `scripts/test-all.sh`) and its declared edge array in `scripts/lib/test-affected-paths.sh`; keep the commit green
- [ ] 1.4 Record the baseline once more with the bench at the merge-base (user+sys, load average, `BASH_VERSION`)

## 2. Phase A: levers (one commit each; bench IDENTICAL after each)

- [ ] 2.1 A1: `shopt -u patsub_replacement 2>/dev/null || true` as the first statement of the derive block (after the `_AC_CLASS=""` declaration); flip R1; run the bench
- [ ] 2.2 A2: growth-bounded `_affected_resolve_vars` (input length + 4096, first substitution always happens); flip R2, R3, R3b; run the bench; add the self-reference rule only if the cap alone leaves measured cost
- [ ] 2.3 A3a: `_AC_ESET` plus `_affected_reset_edges` chokepoint, defaults so the extracted t11/m9 block works unchanged; flip R4; run a focused copy of the t11/m9 rows; run the bench
- [ ] 2.4 Profile step: attribute the remaining CPU; take A3b/A4 levers (closure `_seen` set, `_FE_BUF` set, `_FE_FILES` index, O(1) variable lookup, minted-form replay) only above 10% each and only while the bench stays IDENTICAL
- [ ] 2.5 Measure the eight profiled suites (each under 3 s) and the final CPU factor (median of three, load average quoted)

## 3. Phase B: docs and records

- [ ] 3.1 Amend ADR-242 (`## Amendment — 2026-10-01`: decision 16, corrected decision-15 figures) via `soleur:architecture`
- [ ] 3.2 Correct the cost-attribution paragraph in `knowledge-base/project/specs/feat-affected-parallel-test-gate/always-on-audit.md`
- [ ] 3.3 Read all three C4 model files; run `bash plugins/soleur/test/c4-count-parity.test.sh` and cite the green run
- [ ] 3.4 Write the learning under `knowledge-base/project/learnings/` (bash 5.2 `patsub_replacement`, version-dependent selection, profile before choosing the lever)

## 4. Phase C: pre-push and ship

- [ ] 4.1 Run the Quality Gates list from the plan (targeted suites only; `scripts/test-all-affected.test.sh` via a focused copy of the t11/m9 rows)
- [ ] 4.2 `python3 scripts/lint-guard-contract.py` and `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`
- [ ] 4.3 Remove the scratch worktrees (`git worktree remove`)
- [ ] 4.4 Re-file PR-B, PR-C and D5 on #9307 as tracked issues with measured reasons (check labels with `gh label list --limit 200` first)
- [ ] 4.5 PR body: `Ref #9307`, net-issue-flow justification, "affected-suite gate passed" wording, plain-terms before/after numbers, CI is the authoritative gate

## Follow-on (not in this branch)

- PR-B: B1 recorder (`scripts/audit-suite-reads.sh`), B2 re-demote `scripts/domain-model-drift`, B3 audit Round 2, D2 ratchet breadth, D3 subcommand forms, D4 deleted declared subject (migrate slash-less directory entries first)
- PR-C: A5 runner as closure leaf (keep real `source` edges), D1 `REPO_ROOT` idiom, Phase C (four candidates)
- Post-merge: D5 regenerate `scripts/suite-shard-legs.tsv`
