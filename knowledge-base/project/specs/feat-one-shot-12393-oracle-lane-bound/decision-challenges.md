# Decision Challenges — feat-one-shot-12393-oracle-lane-bound

Planning run: 2026-11-08, headless one-shot pipeline. No Task/subagent spawn capability was
available in this environment, so technical items are recorded `pending - assumed:` per
`technical-ruling-delegation.md` (spawn `soleur:engineering:cto` to convert to a ruling).

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Design fork: matrix-ize the manifest across parallel legs vs. raise `timeout-minutes` with evidence vs. cut the ~11 s/case mutation-matrix cost | technical | pending - assumed: matrix-ize into K=5 parallel legs via committed `scripts/ci-oracle-lane-legs.tsv` — the serial 65.4-min measured total cannot satisfy the bound by any bound-raise consistent with epic #11556's ≤20-min goal, and a ≤2× per-case cut still leaves ~33 min > 30; matrix is the established repo topology (#7902, ADR-240) |
| Leg-assignment mechanism: separate `label<TAB>leg` file vs. third column in the manifest vs. runtime LPT from `suite-durations.tsv` | technical | pending - assumed: separate `ci-oracle-lane-legs.tsv` — `check_manifest()` pins the manifest grammar at exactly 2 fields (`MEMBER-BAD-FIELDS`), a column widens the #12377 conflict surface, and runtime LPT makes the assignment unreviewable in-diff (ADR-240: assignment is checked-in data) |
| `ORACLE_LEG` unset/malformed at leg runtime | technical | pending - assumed: fail-closed `::error` + exit 1 after the `not-oracle-only` early exit — a misconfigured leg must red, not silently run all or none |
| K = 5 vs. other leg counts | technical | pending - assumed: K=5 — the worst leg is floored by `ci-pr-affected-replay-a` (17.2 min) regardless of K; K=5 keeps every other leg ≤~14 min and leaves member-growth margin without a replay `--rows` resplit (which needs a new `run_suite` registration) |
| Comment sweep: absorb stale `ci.yml` oracle comments here vs. leave to #12375 | operator (scope) | pending - assumed: stays with #12375 — only comments inside the `oracle-index-check` block this diff already touches are refreshed; the wider post-unlock nit sweep is that issue's scope |
| #12274 disposition | operator (scope) | pending - assumed: PR body notes verified-fixed-on-main and recommends close (verification only — the fix predates this PR, so `Closes` would mis-attribute) |

## Notes

- Founder check: headless run — no `founder_check` block written (plan-founder-check.md §When
  it runs).
- Plan-review reviewer fan-out (eng panel + named lens panel) could not be spawned in this
  environment; the plan carries the inline disclosure under References. deepen-plan remains the
  next gate.
