# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-9232-duration-aware-shard-packing/knowledge-base/project/plans/2026-09-29-ci-duration-aware-shard-packing-plan.md
- Status: complete

### Errors
None — all pre-commit hooks (gitleaks, lint-infra-no-human-steps, markdown-lint) and `lint-guard-contract.py` passed. Harness limitation, disclosed in the plan: no Task/Skill spawn tool, so deepen-plan's research/review fan-outs ran inline under `Reviewed-Coverage: sequential-fallback`; no independent review is claimed.

### Decisions
- Corrected the issue's stale premise in-plan: sticky-LPT already exists (ADR-240); the plan extends it with last-N-run **median** aggregation, a documented floor for untimed labels (median-of-measured, else `DEFAULT_SUITE_MS=60000`, replacing two `die` sites with WARN-degrade), and `src=floor` provenance so estimates never launder into measurements.
- Committed `suite-durations*.tsv` per group is the single duration source; `--legs K` emits an arbitrary-K packing consumed by #8231 through the existing `SOLEUR_SHARD_MANIFEST`/`SCRIPTS_SHARD` seams — zero `test-all.sh` machinery changes (one `run_suite` line for the soak probe only). `--write` to the committed manifest with `K !=` workflow N is refused.
- Enrolled a `ci-leg-balance-9232` followthrough soak probe for the "~2x of mean" AC (live precedent: `deploy-script-tests-legs-8736.sh`); ADR-240 gets an amendment, not a new ADR; no C4 impact.
- All deepen-plan halts evaluated inline: 4.5/4.55/4.8/4.9/4.10 clean, 4.6 PASS with scope-out bullet covering both `apps/web-platform/infra/*.tsv` matches, 4.7 PASS, 4.11 green via `lint-guard-contract.py`.

### Components Invoked
`soleur:plan` (in-process read of SKILL.md + references), `soleur:deepen-plan` (in-process read of SKILL.md + all 4.x gates inline), `scripts/markdown-lint.sh` (in-scope-exempt), `python3 scripts/lint-guard-contract.py` (green), `gh` (issue/PR/artifact verification), lefthook pre-commit hooks via `git commit`/`git push`.

## Work Phase (in progress)
- RED: `regenerate-shard-manifest.test.sh` fixtures D3/I/J/K/L/M/N/O + MIN_CASES=40; `scripts-shard-manifest.test.sh` durations block (light+heavy) + MIN_CASES=45; `test-infra-suite-registration.sh` durations coherence arm + mutations M28–M30 (MIN_ASSERTS=31).
- GREEN: generator v3 — `green_main_runs()` via `gh run list` (the REST runs-list endpoint 404s under `gh api -f` because -f flips to POST; artifacts endpoint unaffected), `--runs N` (default 5), repeatable `--timings-dir`, `--durations`/`--durations-out`, `--legs K`, median aggregation, floor tabling with src=measured|floor, all-floor WARN-degrade, committed-manifest n-mismatch refusal.
- Regenerated: light 519 rows (spread 21s across 7 legs), heavy 3, infra 154 (3 of 5 recent green runs had no infra artifacts — paths-filtered; multi-run aggregation carried the gap + floored 10).
- Probe: `scripts/followthroughs/ci-leg-balance-9232.sh` + stub-gh fixture harness, 9/9 arms green, registered in test-all.sh (single hunk).
- Docs: ci.yml positional-era comment replaced, runbook Regeneration section rewritten, ADR-240 amendment appended, consumption-contract comment posted on #8231.
- Verified: local K=4 pack from committed durations table → SOLEUR_SHARD_MANIFEST enumerate union == full set (519), disjoint legs.
- PENDING AT SHIP: post `soleur:followthrough` directive comment on #9232 with earliest=<merge ts> to enroll the probe.
- Affected battery (`test-all.sh --affected`) running in background.
