# Measurement Record — feat-one-shot-8621-converge-selectors

Single source for the decline-set comparison the #8621 convergence decision cites. The plan
file and the PR body cite this file; numbers are not restated elsewhere.

## 1.0 — The precision comparison (#8621's fork-in-the-road input)

**Run 2026-10-27, worktree `feat-one-shot-8621-converge-selectors`, runner @ 6d7f678b50 (pre-change).**
Verdict: the heuristic under-selects on EVERY corpus diff — **fold** (issue criterion 2);
`TEST_GROUP=affected` becomes a compat alias of `--affected`, the declared index is the single
selector.

### Method

For each corpus pathset `P`, three probes against the same checkout:

- **Runnable stream** — `bash scripts/test-all.sh --enumerate-commands --paths=P`
  (TEST_GROUP=all): the registration list plus the call-site relevance/`skip_suite` declines
  (`SUITE_COMMAND_DECLINED`), which BOTH selectors see identically. `runnable` below is the
  `SUITE_COMMAND` count — the population either selector could decline.
- **Declared-edge set** — `bash scripts/test-all.sh --print-selection --paths=P`:
  `AFFECTED_SELECTED <label> <0|1>` per runnable registration (`decl-sel` = bit 1 count;
  `AFFECTED_SUMMARY` names any degraded-full `fallback=`).
- **Heuristic set** — `TEST_GROUP=affected bash scripts/test-all.sh --enumerate-commands
  --paths=P`: a `SUITE_COMMAND_DECLINED` record that was runnable in the base stream is a
  chokepoint decline. `heur-sel` = `SUITE_COMMAND` count.

**MISS** = heuristic declined, declared selected (under-coverage — the issue's evidence for
folding). **OVER** = heuristic selected, declared declined (over-coverage — safe but slow).

The three `fallback=runner-changed` rows have no per-suite `AFFECTED_SELECTED` rows: the
declared gate degraded to the full battery, so every runnable registration is selected and
the MISS column is the heuristic's whole chokepoint decline set (measured separately:
`runnable ∩ heuristic-declined`).

### Corpus (19 diffs: 16 real origin/main squash-merged PRs + 3 synthesized pathsets)

| diff | paths | runnable | decl-sel | heur-sel | MISS | OVER | note |
|---|---|---|---|---|---|---|---|
| `ship-skill-only` (synth: `plugins/soleur/skills/ship/SKILL.md`) | 1 | 674 | 255 | 311 | 104 | 160 | |
| `lint-rule-ids-py` (synth: `scripts/lint-rule-ids.py`) | 1 | 673 | 137 | 308 | 49 | 220 | |
| `webplat-infra-tf` (synth: `apps/web-platform/infra/main.tf`) | 1 | 676 | 175 | 310 | 63 | 198 | |
| `3b2c3ea35d` ci: campaign calendar | 2 | 673 | 121 | 305 | 50 | 234 | |
| `39ba94781f` docs: community digest | 1 | 673 | 121 | 304 | 50 | 233 | |
| `1330f9b7eb` chore(infra): inngest-bootstrap pin | 2 | 677 | 177 | 311 | 63 | 197 | |
| `4a2f588806` chore(vendor-drift) — plugins/soleur only | 1 | 674 | 252 | 309 | 104 | 161 | |
| `67c17cb861` fix(supabase): RESTRICTIVE self-subqueries | 11 | 674 | 160 | 308 | 56 | 204 | |
| `aba83ca850` fix(web-platform): dashboard send enqueue | 27 | 674 | 158 | 307 | 56 | 205 | |
| `153bc8c192` feat(marketing): social handles | 6 | 674 | 253 | 307 | 107 | 161 | |
| `be43cffa73` feat(supabase): grants snapshot + guard | 29 | 678 | 199 | 354 | 57 | 212 | |
| `574bb6bdda` fix(compound-promote): edit-line caps | 27 | 675 | 284 | 319 | 105 | 140 | |
| `a9b118b8a2` feat(ship): gitleaks range scan | 14 | 680 | all | 325 | **355** | 0 | `fallback=runner-changed` (touches `scripts/lib/test-affected-paths.sh`) |
| `11a40a93a2` fix(hooks): chained-commit index scan | 24 | 680 | all | 326 | **354** | 0 | `fallback=runner-changed` (touches `scripts/lib/test-affected-paths.sh`) |
| `661663a7fc` docs: weekly growth audit | 5 | 673 | 121 | 305 | 50 | 234 | |
| `63eabdb061` fix(pencil-setup): headless adapter | 26 | 674 | 270 | 313 | 105 | 148 | |
| `852b0ef01a` fix(web-platform): docker git-data keys | 13 | 676 | 179 | 309 | 63 | 193 | |
| `fdd0fd7c74` feat(infra): owner-ask probe A5/A6 | 8 | 680 | all | 378 | **302** | 0 | `fallback=runner-changed` (touches `scripts/test-all.sh`) |
| `5e46901abe` chore(infra): monitored signal + identity | 20 | 679 | 310 | 321 | 120 | 131 | |

### Findings

1. **MISS > 0 on all 19 diffs** — minimum 49, median ~63, maximum 355. The union of missed
   labels is 132 distinct suites. Under the issue's own criterion this is "misses land":
   folding is the supported convergence.
2. **The missed labels are disproportionately the always-on floor.** Labels missed on all 16
   non-fallback diffs include `scripts/verify-marketplace-ruleset`, `scripts/lint-guard-contract`,
   `scripts/tenant-dpa-register-guard-live`, `scripts/digest-oracle-guard`,
   `plugins/soleur/test/auto-close-scanner.test.sh`, `scripts/rename-guard`,
   `scripts/lint-agents-rule-budget-unit`, `scripts/suite-exit-class-parity` — all classed
   `always_on` in the declared index (verified against `AFFECTED_SELECTED` class column). The
   heuristic's census backstop — a fixed grep over suite text for enumerator shapes — fails to
   recognize these as repo-wide suites and declines them: the backstop is structurally blind
   to exactly the class it exists to protect (a maintained `ALWAYS_ON_SUITES` census can name
   a suite a grep cannot classify).
3. **The heuristic has no runner-changed degradation.** On the three diffs touching
   `scripts/test-all.sh`/`scripts/lib/test-affected-paths.sh` the declared gate degrades to
   full (`AFFECTED_FALLBACK reason=runner-changed`, all ~680 runnable); the heuristic still
   declined 302–355 suites — the single largest miss class in the corpus, and it lands on
   precisely the diffs where selection logic itself is under test.
4. **OVER is also large** (131–234) — the heuristic is both blunter and leakier than the index:
   it runs more suites AND misses coverage. The two errors do not cancel.

### Reproduction

```bash
paths=...    # comma-joined repo-relative pathset
bash scripts/test-all.sh --enumerate-commands --paths="$paths"                       # base
TEST_GROUP=affected bash scripts/test-all.sh --enumerate-commands --paths="$paths"   # heuristic
bash scripts/test-all.sh --print-selection --paths="$paths"                          # declared
```

Corpus shas above resolve their pathsets via `git diff-tree --no-commit-id --name-only -r <sha>`.
