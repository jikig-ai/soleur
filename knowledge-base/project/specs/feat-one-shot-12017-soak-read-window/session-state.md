# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-10-ci-soak-read-window-bound-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
- One tool-level commit rejection ("Committing directly to main/master is not allowed") — false positive from a stale session CWD; resolved by explicit `cd`. Worktree always on feat-one-shot-12017-soak-read-window.
- Collision precheck flagged PR #12622 and five foreign test-all.sh processes — verified: #12622 is this branch's own WIP draft; processes belong to sibling worktree pipelines.
- No agent/Task tool in this harness: prescribed fan-outs ran as sequential-fallback inline passes — recorded in the plan's Enhancement Summary.
- plan-sharp-edges.md middle section not read linearly; applicable classes covered via targeted greps + catalogue tail.

### Decisions
- Bound targets enumeration cost, not sample size: ADR-276 S2 pins "trailing sample ≤100 push runs" — MAX_RUNS cannot shrink; +190% is suite wall time (~420 probe invocations × ~6–7 subprocesses/run).
- Probe-side batching: merge 4 per-run jq evaluations into one `[(P1),(P2),(P3),(P4)] | @tsv`; epoch in runs TSV; voucher check single post-loop jq diff.
- Paginate to cap: `api --paginate` → `for page in 1..MG_MAX_PAGES=10` loop (pr-battery-gate-saving-9323.sh / cron-machinery-soak-9272.sh precedent); full last page at cap → exit 3 CANNOT ESTABLISH.
- Suite-side bounds: build_fx memoization keyed `"$fx|$*"`; three ALL_ROWS controls → named 12-row CONTROL_ROWS subset (floor recomputed ≥10/12); re-price suite-durations.tsv per PR #12419.
- Four technical rulings persisted as `pending - assumed:` rows in decision-challenges.md for the parent's batched CTO spawn.

### Components Invoked
- soleur:plan (run to completion), soleur:deepen-plan (run to completion)
- cloud-detect.sh (not-local:no-devin-env), collision-precheck.sh, lint-guard-contract.py
- Commits: 7e36ce77c3 (plan+tasks+decision-challenges), da36b0a072 (deepened plan)

## Operator Constraints

- constraint: ADR-276 S2 contract — MAX_RUNS=100 trailing-sample cannot shrink; bound applies to enumeration/pagination cost only.
- constraint: Full last page at the page cap exits 3 CANNOT ESTABLISH — never degrade vouchers into a wrong-elision FAIL.
- constraint: jq programs copied verbatim into merged form — jq-internal mutant anchors must survive byte-identical.

## Technical Rulings
- cto_spawns=1 (batched, 4 rows): all assumed defaults APPROVED — CONTROL_ROWS 12-row subset; merged-jq batching (worker model = fallback); MG_MAX_PAGES=10 + rc-3-on-exhaustion; epoch-in-slice. Rows rewritten to `Ruled by CTO agent, 2026-11-10` in decision-challenges.md.
