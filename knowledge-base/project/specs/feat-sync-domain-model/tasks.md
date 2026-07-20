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
- [ ] 1.2 Implement `scripts/domain-model-drift.sh extract [--repo <path>]` (+ `scripts/lib/domain-model-lib.sh` tokenizer for #5871 reuse):
  - [ ] 1.2.0 header: `set -euo pipefail`; quote all expansions; `--` arg terminators; `realpath`-confine `--repo`; `[[ -L ]]` symlink-deny on the walk; default `--repo` → `apps/web-platform` (AP-010)
  - [ ] 1.2.1 glob **base migrations only** (`*[0-9].sql`, **exclude `*.down.sql`** — P0); `LC_ALL=C` sort == apply order; replay CREATE/ALTER/DROP POLICY (ALTER = **merge** USING/WITH CHECK, not replace)
  - [ ] 1.2.2 extract PK/UNIQUE/CHECK/FK, live policy predicate, `SECURITY DEFINER` signatures, named TS guard symbols; treat SQL as **data only** (no eval; `grep -F --`/awk `-v`)
  - [ ] 1.2.3 content-anchor = **full base-filename + table-qualified object** (not 3-digit number, not bare policy name); no line numbers
  - [ ] 1.2.4 normalize multi-line predicates; `LC_ALL=C` sort; `jq -S` emit with a `schema_version` field (internal/unstable); `blind_spots` triggers on `DO $$` AND `EXECUTE format(` + un-mergeable ALTER + schema-qualified/cross-table same-name
  - [ ] 1.2.5 **fail-closed secret-shape scan** (port `extract-api-spend.sh` grep) before emit → refuse + exit non-zero; project citation anchor, not full predicate bodies
  - [ ] 1.2.6 graceful degradation on non-Supabase repo (disclaimered empty, exit 0)
- [ ] 1.3 Register both suites in `scripts/test-all.sh` (`run_suite` lines mirroring L124/L131)
  - [ ] 1.3.1 test fixtures: `.down.sql`-DROP-does-not-delete-live-fact; ALTER-merge; anchor-collision (shared number, cross-table same-name); planted-secret→refuse; `DO $$`→blind_spots; idempotency byte-identical

## Phase 2 — Drift diff + register-citation parser

- [ ] 2.1 Register-citation parser: scan the WHOLE row (Statement + Source) with a citation-token grammar (`ADR-\d+`, `migration \d+ › <obj>`, `<file>.ts › <symbol>`, `#\d+`)
- [ ] 2.2 `drift --repo <path> --register <path>` mode: set-diff live facts vs parsed citations → `stale` + `undocumented`
- [ ] 2.3 Exact-token, file-scoped citation resolution (guard against `resolveActiveWorkspace*` substring false-match)
- [ ] 2.4 Pinned report template (fixed columns, `LC_ALL=C` sort, severity enum) + completeness disclaimer + explicit blind-spots line
- [ ] 2.5 `drift` exit codes: `0`=clean / `1`=drift found / `2`=error (the #5871 contract); citation parser resolves `migration NNN` → base (non-`.down`) file, flags ambiguous numbers
- [ ] 2.6 Test: stale fixture flagged; live `resolveActiveWorkspace` (workspace-resolver.ts:398) NOT flagged (negative control); one `undocumented` from a missing-constraint fixture; exit-code assertions

## Phase 3 — Command wiring + approval-gated write + ADR

- [ ] 3.1 Edit `plugins/soleur/commands/sync.md`: add `domain-model` to argument-hint (L4), Valid areas (L20), area-note (L22); Parse Area Filter branch (L69, skip Phase 2-4); new `#### Domain Model Analysis` section
- [ ] 3.2 Approval-gated accept/skip/edit write into `## Auto-inferred (unreviewed)` (self-contained review UX, not Phase-2 re-entry); never write curated `## Business Rules`; never mint `BR-*`; content-anchor keyed so accepted rows are not re-proposed
  - [ ] 3.2.1 **atomic** whole-file rewrite (mktemp+trap+mv, per `rule-metrics-aggregate.sh`); re-parse `## Auto-inferred` heading offset immediately before write, abort on missing/duplicate anchor (TOCTOU)
  - [ ] 3.2.2 **markdown-injection safe**: escape `|`→`\|`, strip/encode newlines + control chars (`\x7f`/` `/` `), reject rows matching `^BR-`/`^##`, validate fields against citation grammar; second fail-closed secret-scan before write
- [ ] 3.3 Add `tests/commands/test-sync-domain-model.sh` (mirror `test-sync-rule-prune.sh`): area valid, excluded from `all`, dispatches to script
- [ ] 3.4 Edit `knowledge-base/engineering/architecture/domain-model.md`: completeness disclaimer in header; empty `## Auto-inferred (unreviewed)` section; promotion-flow note (`Auto-inferred → BR-*` human edit keeps anchor); maintenance note update
- [ ] 3.5 `/soleur:architecture create` ADR-0XX (deterministic-first, last-writer-wins, content-anchored, structural-not-semantic); JSON contract for #5871 deferred; link from register

## Exit

- [ ] All ACs green; `bash scripts/test-all.sh` passes the two new suites; `/soleur:qa`; review; ship.
