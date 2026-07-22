# Tasks — chore: frontmatter-strip TS twin + rule-metrics denominator (#6794)

Plan: `knowledge-base/project/plans/2026-07-22-chore-frontmatter-strip-ts-and-rule-metrics-denominator-plan.md`
Lane: cross-domain · Threshold: none · ADR-094 (amend)

## Phase 0 — Preconditions
- [ ] 0.1 Confirm only `AGENTS.core.md` has leading frontmatter (`AGENTS.md` does not) → strip is a no-op on the index.
- [ ] 0.2 Confirm linter byte basis: `b_core = len(strip_frontmatter(core).encode("utf-8"))`, `b_index = file_bytes(index)` (raw).
- [ ] 0.3 Confirm parity test is orphaned (`grep frontmatter-strip scripts/test-all.sh` empty) and scripts CI shard has no bun / node can't run `.ts`; bun shard has bun 1.3.14.
- [ ] 0.4 Confirm no existing cross-boundary import into `apps/web-platform/server/`; read `next.config.ts` for `experimental`/`outputFileTracing*`.

## Phase 1 — strip.ts
- [ ] 1.1 Create `scripts/lib/frontmatter-strip/strip.ts` — pure `stripFrontmatter(text)`, byte-identical to `strip.py`; node-compatible `process.argv`/`process.stdin` filter guard (NO `Bun`/`import.meta.main`).
- [ ] 1.2 Amend `scripts/lib/frontmatter-strip/SPEC.md` — add `strip.ts` + its consumers to the impl list.

## Phase 2 — Parity test + registration
- [ ] 2.1 Extend `scripts/lib/frontmatter-strip.test.sh` — `bun` skip-gate; three-way byte-identity (`strip.sh`==`strip.py`==`strip.ts`) over all fixtures (incl. `empty-frontmatter-body`).
- [ ] 2.2 Register the parity test in `scripts/test-all.sh` `want_bun` block. (No `ci.yml` edit — bun job already runs `test-all.sh bun`.)

## Phase 3 — Wire promoters (riskiest)
- [ ] 3.1 `cron-compound-promote.ts` — strip both `alwaysLoadedNow` and `postBytes` via `Buffer.byteLength(stripFrontmatter(text),"utf8")`; over-strip guard → RAW fallback + `op="frontmatter-overstrip-fallback"`; update UNIT-SKEW comment; literals unchanged.
- [ ] 3.1a HARD GATE: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes AND Next production build bundles the import; else add `externalDir`/`outputFileTracingIncludes` to `next.config.ts`.
- [ ] 3.2 `scripts/compound-promote.sh` — source `strip.sh`; `strip_frontmatter < file | wc -c` for both files; over-strip → RAW fallback + `::warning::`; update UNIT-SKEW comment; literals unchanged.

## Phase 4 — Sync guard + ADR
- [ ] 4.1 `scripts/lint-agents-compound-sync.sh` — tighten `UNIT_NOTE` + top comment (all measurement consumers now stripped-basis; unit-exact); constants unchanged; guard still `OK`.
- [ ] 4.2 Amend `ADR-094` — third impl + promoter unit-exactness + CI-enforced parity.
- [ ] 4.3 If present, update raw-vs-stripped skew prose in `compound-promote-runbook.md` (literals unchanged).

## Phase 5 — Item 1 investigation (independent)
- [ ] 5.1 Locate `.claude/.rule-incidents.jsonl` + archives across worktrees (never the bare mirror); count valid rule-carrying lines + timestamp span.
- [ ] 5.2 Compute events/week; classify telemetry-absence vs credible-unused.
- [ ] 5.3 Re-derive 101/98 by two independent methods; confirm 202 = 2×101 double-count.
- [ ] 5.4 Record decision in `knowledge-base/project/learnings/<topic>.md` (date at write time): finding + "do not prune now" + re-eval trigger; tick #6794 boxes in PR body.

## Verification / Ship
- [ ] `bash scripts/lib/frontmatter-strip.test.sh` → Fail: 0.
- [ ] `bash scripts/lint-agents-compound-sync.sh` → OK.
- [ ] `bash scripts/lint-agents-rule-budget.test.sh` (T8) passes.
- [ ] `bash scripts/test-all.sh scripts` and `bash scripts/test-all.sh bun` pass.
- [ ] PR body `Closes #6794`; four checkboxes ticked; no post-merge operator step.
