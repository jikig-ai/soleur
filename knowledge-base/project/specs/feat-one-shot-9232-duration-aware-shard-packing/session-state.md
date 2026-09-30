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

## Review Phase
- Class: code; design-risk: yes (new durations-table + --legs mechanism).
- Design-validity verdict (inline + performance-oracle subagent): mechanisms map 1:1 to requirements (durations table = single source for two consumers; src column = prevents estimate-laundering; --legs = arbitrary-K AC; n-mismatch refusal = prevents committed positional degrade). No simpler mechanism satisfies them.
- performance-oracle (subagent 26a2a602): NO BLOCKING; 4 nits — applied: floor_ms clamped to >=1 (median-of-measured could be 0 → zero-weight pileup), runbook note that --runs counts scanned runs, probe leg label made 1-based. Skipped: --paginate on artifacts-list (per_page=100 >> actual ~11; loud degradation via expected_legs WARN exists).
- simplicity/architecture/security/pattern/quality seats: subagent spawns repeatedly rate-limited (free-model cap); ran the lenses inline — no additional findings beyond a dead `weights = None` line (removed). Disclosed: inline lenses are lead-authored review, not independent.
- Remaining seats (git-history, data-integrity, agent-native): nothing in scope (no DB, no agent surface, no history claims beyond ADR citation).

## QA Phase
Test Scenarios are integration-level Given/When/Then prose (no executable
Browser:/API verify: steps) — per soleur:qa's skip rule, automated QA is
skipped; coverage is the unit batteries + measured dry-run evidence:
- median aggregation → fixture J (suite-mid 100/300/900 → 300) GREEN.
- untimed label floors at floor_ms w/ src=floor → fixture K GREEN.
- all-floor graceful degrade → fixtures D3/I/O GREEN (WARN, no die).
- --legs K default-path refusal → fixture L GREEN (exit 2, manifest untouched).
- --durations repack + SCRIPTS_SHARD=k/4 + SOLEUR_SHARD_MANIFEST enumerate
  consumption → measured live: union == 519, disjoint legs.
- floor never launders → fixture N GREEN.
- partial run (missing leg artifacts) → live infra regen: 3 of 5 green runs
  had no infra artifacts; WARN + contributed nothing — the allow_empty arm.
- insertion stability → scripts-shard-manifest.test.sh 49/49 + infra gate +
  32/32 mutation rows GREEN.
- Step 2.6 visual-regression gate: skipped (no dashboard/layout files touched).

## CI triage (push 6e58839b01)
4 legs red on first CI cycle, all diagnosed and fixed in da5f65a3c3:
- test-scripts 2/7 + 4/7: fixture-relative-assert baseline drifted (new test
  files add fixture sites — regenerated --write-baseline), exec-bit lint
  (probe files committed 644 → 755), lint-shell-capture-exit-live S1 (two
  unguarded grep captures in the new gate arm → || true).
- shard-totality-mutations 29-42: LEGS-COLOCATE arm pinned -b to hardcoded
  leg 3; regen put -a on leg 1 → vacuous mutant. Pin now reads -a's current
  leg from the TSV (re-verified: arm goes RED, 15/15).
- deploy-script-tests 3/4: luks-monitor broken-pipe + cloud-init T9 timing
  flakes — contention-class, not diff-caused; will re-score on the next
  cycle.
- Also found+fixed pre-push: fixture --write leaked into committed
  suite-durations.tsv (pairing rule: durations-out now pairs with the
  EMITTED manifest); shallow-clone broke tombstone census → git fetch
  --unshallow.

## Ship Phase
- Soak enrollment: #9232 labeled follow-through + directive in body
  (script=ci-leg-balance-9232.sh, earliest=2026-09-30T00:10:00Z, secrets=GH_TOKEN);
  PR body switched Closes -> Ref so the probe's PASS auto-closes.
- CI cycle 2 (merged head): all 7 test-scripts legs PASS with the balanced
  manifest (legs 10m9s-12m35s, ~2.4min spread vs issue's 6-19min); heavy 3/3
  PASS; totality-mutations all ranges PASS incl. fixed LEGS-COLOCATE.
- Infra legs red: (a) vinngest-v1.1.42 pin drift = main-state defect, fix
  in-flight on chore/7463 PR-B (every in-flight branch inheriting main reds
  the same suite); (b) luks-monitor printf-EPIPE flake -> filed #9245 per
  wg-when-tests-fail-and-are-confirmed-pre.
- Soak-gate hook's `-f` arm resolved the script path in a non-worktree cwd
  and blocked; enrollment verified via the hook's own predicates -> added
  the sanctioned gate-override comment to the PR body.
- Review trailer committed (mode=degraded, 1/3 seats) and pushed c70c7b5845.
- `gh pr merge --auto` ARMED 2026-09-29T23:35:56Z; required checks all green,
  mergeStateStatus BLOCKED until the trailer-head cycle completes.
- Local --affected full battery still running in background.
