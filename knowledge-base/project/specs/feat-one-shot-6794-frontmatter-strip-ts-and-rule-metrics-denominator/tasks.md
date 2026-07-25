# Tasks — chore: frontmatter-strip TS twin + rule-metrics denominator (#6794)

Plan: `knowledge-base/project/plans/2026-07-22-chore-frontmatter-strip-ts-and-rule-metrics-denominator-plan.md`
Lane: cross-domain · Threshold: none · ADR-094 (amend)

## Phase 0 — Preconditions
- [x] 0.1 Confirmed: `AGENTS.md` starts `# Ag` (no frontmatter → strip no-op); `AGENTS.core.md` starts `---`.
- [x] 0.2 Confirmed: `b_index = file_bytes(index)` (raw), `b_core = len(strip_frontmatter(core).encode("utf-8"))`; over-strip guard `^- .*\[id: `.
- [x] 0.3 Confirmed: parity test ALREADY runs in scripts shard via `scripts/lib/*.test.sh` glob (plan's "orphaned" premise corrected — literal-name grep missed the glob); scripts shard has no bun; bun 1.3.11 present (plan said 1.3.14 — stale, immaterial). want_bun registration is what runs the strip.ts arm.
- [x] 0.4 Confirmed: no cross-boundary import into `apps/web-platform/server/`; `next.config.ts` read (`experimental.externalDir` unset, `output: undefined`).

## Phase 1 — strip.ts
- [x] 1.1 Created `scripts/lib/frontmatter-strip/strip.ts` — pure `stripFrontmatter`, node-compatible `argv`/`stdin` filter guard.
- [x] 1.2 Amended `SPEC.md` — three byte-identical impls + consumers.

## Phase 2 — Parity test + registration
- [x] 2.1 Extended `frontmatter-strip.test.sh` — bun skip-gate + three-way byte-identity over all 4 fixtures. Verified 12/0.
- [x] 2.2 Registered in `test-all.sh` `want_bun` block.

## Phase 3 — Wire promoters (riskiest)
- [x] 3.1 `cron-compound-promote.ts` — `measureAlwaysLoadedBytes` helper (strip + anchored-regex over-strip guard + RAW fallback + `op="frontmatter-overstrip-fallback"`); both sites; UNIT comment now unit-exact; literals unchanged.
- [x] 3.1t Added both tests; 27/27 pass (2 new + 25 existing).
- [x] 3.1a HARD GATE PASSED: `tsc --noEmit` clean AND `next build` exit 0. Webpack resolved the cross-root import WITHOUT `experimental.externalDir` — no `next.config.ts` change needed (R1 did not materialize).
- [x] 3.2 `compound-promote.sh` — sources `strip.sh` (from SCRIPT dir, not `$REPO_ROOT` — fixture-root fix); strips both `wc -c`; UNIT comment unit-exact; no over-strip guard here. Test 22/0.

## Phase 4 — Sync guard + ADR
- [x] 4.1 `lint-agents-compound-sync.sh` — all THREE skew sites rewritten to unit-exact; constants unchanged; guard `OK`.
- [x] 4.2 Amended `ADR-094` — dated amendment (third impl + promoter unit-exactness + CI-enforced parity).
- [N/A] 4.3 `compound-promote-runbook.md` — its raw/stripped prose is operator "run the linter not `wc -c`" guidance (still true — a bare `wc -c` still overstates), NOT a promoter-skew claim; rewriting to "unit-exact" would make it wrong. Conditional not triggered.

## Phase 5 — Item 1 investigation (independent)
- [x] 5.1 Enumerated across worktrees (not bare): ~1191 events, 2026-07-06..07-22.
- [x] 5.2 ~520 events/week — telemetry PRESENT (absence hypothesis falsified); but only 21 of 101 rules fired, and the aggregate reads only one per-checkout log → fragmentation undercount.
- [x] 5.3 202 = 2×101 confirmed two ways (Method A grep: 101 pointers = 53+42+6 bodies; Method B: summary.total_rules_tagged=101).
- [x] 5.4 Recorded `knowledge-base/project/learnings/2026-07-22-rule-metrics-denominator-investigation.md` — do-not-prune decision + re-eval trigger.
- [x] 5.5 Breadcrumb added at the `rules_unused_over_8w` jq site. `Closes #6794` in PR body (ship).

## Verification / Ship
- [ ] `bash scripts/lib/frontmatter-strip.test.sh` → Fail: 0.
- [ ] `bash scripts/lint-agents-compound-sync.sh` → OK.
- [ ] `bash scripts/lint-agents-rule-budget.test.sh` (T8) passes.
- [ ] `bash scripts/test-all.sh scripts` and `bash scripts/test-all.sh bun` pass.
- [ ] PR body `Closes #6794`; four checkboxes ticked; no post-merge operator step.
