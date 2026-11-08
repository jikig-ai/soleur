# Decision Challenges — feat-one-shot-12393-oracle-lane-bound

Planning run: 2026-11-08, headless one-shot pipeline. The planning subagent had no spawn
capability, so technical items were recorded `pending - assumed:`; the parent session batched
all four into one `soleur:engineering:cto` spawn (Rule interface) and converted them below.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Design fork: matrix-ize the manifest across parallel legs vs. raise `timeout-minutes` with evidence vs. cut the ~11 s/case mutation-matrix cost | technical | Ruled by CTO agent, 2026-11-08: matrix-ize the 15 manifest members across K parallel legs under the unchanged `oracle-index-check` job ID via `strategy.matrix.leg`, keeping `    timeout-minutes: 30` alone on its line - serial measured 65.4 min (suite-durations.tsv sum 3,922,187 ms) and the canary's 30m15s bound-kill is API-verified; no bound-raise is consistent with epic #11556's ≤20-min goal and a 2× per-case cut still leaves ~33 min > 30. Dissent: +K−1 sub-minute no-op legs on non-oracle runs cost runner slots against the 20-concurrent ceiling; revisit only if oracle-only diffs become frequent |
| Leg-assignment mechanism: separate `label<TAB>leg` file vs. third column in the manifest vs. runtime LPT from `suite-durations.tsv` | technical | Ruled by CTO agent, 2026-11-08: separate committed `scripts/ci-oracle-lane-legs.tsv` (`label<TAB>leg`, the ADR-240 checked-in-data shape) - a third column fails `check_manifest()`'s 2-field `MEMBER-BAD-FIELDS` pin (in `scripts/ci-oracle-lane.test.sh`, not `test-all.sh`) and corrupts `read -r -a cmd <<< "$argv"`; runtime LPT is unreviewable in-diff. Dissent: a second source of truth needing parity with the manifest; the `check_legs()` sentinel + CODEOWNERS pairing makes drift loud, the only acceptable mitigation |
| `ORACLE_LEG` unset/malformed at leg runtime | technical | Ruled by CTO agent, 2026-11-08: fail-closed `::error` + exit 1, checked after the `not-oracle-only` early exit and before any legs-file read - ordering is load-bearing because checkout is oracle-gated so the legs file does not exist on non-oracle runners; mirrors `test-all.sh`'s `SCRIPTS_SHARD` malformed validator. Dissent: diverges from `SCRIPTS_SHARD` unset→full-group precedent; the correctness-preserving fallback, if wiring proves brittle, is full-manifest-on-that-leg, never run-none |
| K = 5 vs. other leg counts | technical | Ruled by CTO agent, 2026-11-08: K=5 - the worst leg is floored by `ci-pr-affected-replay-a` (17.2 min) regardless of K and resplitting its `--rows` needs a new `run_suite` registration that P4 forbids and #12377 makes hazardous; K=5 leaves a light 7.7-min leg absorbing growth, ~19-min worst ≈ 37% headroom. Dissent: K=4 is the honest near-miss (same floor, one fewer job); first squeeze if the 20-concurrent ceiling binds |
| Comment sweep: absorb stale `ci.yml` oracle comments here vs. leave to #12375 | operator (scope) | Leave the wider sweep to #12375; refresh only comments inside the `oracle-index-check` block this diff already touches |
| #12274 disposition | operator (scope) | PR body notes verified-fixed-on-main and recommends close (no `Closes` keyword — the fix predates this PR) |

## Notes

- Founder check: headless run — no `founder_check` block written (plan-founder-check.md §When
  it runs).
- Plan-review reviewer fan-out (eng panel + named lens panel) could not be spawned in this
  environment; the plan carries the inline disclosure under References. deepen-plan remains the
  next gate.
