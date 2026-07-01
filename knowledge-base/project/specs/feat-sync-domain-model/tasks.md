---
feature: sync-domain-model
lane: cross-domain
brand_survival_threshold: single-user incident
issue: 5754
plan: knowledge-base/project/plans/2026-07-01-feat-sync-domain-model-drift-plan.md
---

# Tasks — `/soleur:sync domain-model` drift analyzer

Derived from the finalized (post-plan-review) plan. Full scope: extractor + two-way drift report +
approval-gated auto-write + generic-repo degradation. Brand-survival: single-user incident.

## Phase 1 — Deterministic extractor + tests (RED→GREEN)

- [ ] 1.1 Write `scripts/domain-model-drift.test.sh` (failing) with synthesized fixtures only:
  - [ ] 1.1.1 mini migration dir (PK, CHECK, `CREATE POLICY`, `SECURITY DEFINER`) → expected facts
  - [ ] 1.1.2 later-migration `DROP POLICY` + `CREATE POLICY` same name, new predicate → only live predicate (last-writer-wins)
  - [ ] 1.1.3 idempotency: unchanged→byte-identical; mutate constraint→differs
  - [ ] 1.1.4 `EXECUTE format()`/`DO` policy fixture → appears in `blind_spots`, not silently dropped
  - [ ] 1.1.5 non-Supabase repo fixture → disclaimered empty output, exit 0
- [ ] 1.2 Implement `scripts/domain-model-drift.sh extract [--repo <path>]`:
  - [ ] 1.2.1 walk migrations tree (no hardcoded count); replay CREATE/ALTER/DROP POLICY in migration order (last-writer-wins)
  - [ ] 1.2.2 extract PK/UNIQUE/CHECK/FK, live policy predicate, `SECURITY DEFINER` signatures, named TS guard symbols
  - [ ] 1.2.3 table-qualified, content-anchored citations (`migration NNN › object`, `file.ts › symbol()`); no line numbers
  - [ ] 1.2.4 normalize multi-line predicates; deterministic sort; emit `blind_spots` list
  - [ ] 1.2.5 graceful degradation on non-Supabase repo
- [ ] 1.3 Register both suites in `scripts/test-all.sh` (`run_suite` lines mirroring L124/L131)

## Phase 2 — Drift diff + register-citation parser

- [ ] 2.1 Register-citation parser: scan the WHOLE row (Statement + Source) with a citation-token grammar (`ADR-\d+`, `migration \d+ › <obj>`, `<file>.ts › <symbol>`, `#\d+`)
- [ ] 2.2 `drift --repo <path> --register <path>` mode: set-diff live facts vs parsed citations → `stale` + `undocumented`
- [ ] 2.3 Exact-token, file-scoped citation resolution (guard against `resolveActiveWorkspace*` substring false-match)
- [ ] 2.4 Pinned report template (fixed columns, stable sort, severity enum) + completeness disclaimer + explicit blind-spots line
- [ ] 2.5 Test: stale fixture flagged; live `resolveActiveWorkspace` (workspace-resolver.ts:398) NOT flagged (negative control); one `undocumented` from a missing-constraint fixture

## Phase 3 — Command wiring + approval-gated write + ADR

- [ ] 3.1 Edit `plugins/soleur/commands/sync.md`: add `domain-model` to argument-hint (L4), Valid areas (L20), area-note (L22); Parse Area Filter branch (L69, skip Phase 2-4); new `#### Domain Model Analysis` section
- [ ] 3.2 Approval-gated accept/skip/edit write into `## Auto-inferred (unreviewed)` (self-contained review UX, not Phase-2 re-entry); never write curated `## Business Rules`; never mint `BR-*`; content-anchor keyed so accepted rows are not re-proposed
- [ ] 3.3 Add `tests/commands/test-sync-domain-model.sh` (mirror `test-sync-rule-prune.sh`): area valid, excluded from `all`, dispatches to script
- [ ] 3.4 Edit `knowledge-base/engineering/architecture/domain-model.md`: completeness disclaimer in header; empty `## Auto-inferred (unreviewed)` section; promotion-flow note (`Auto-inferred → BR-*` human edit keeps anchor); maintenance note update
- [ ] 3.5 `/soleur:architecture create` ADR-0XX (deterministic-first, last-writer-wins, content-anchored, structural-not-semantic); JSON contract for #5871 deferred; link from register

## Exit

- [ ] All ACs green; `bash scripts/test-all.sh` passes the two new suites; `/soleur:qa`; review; ship.
