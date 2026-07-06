---
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-07-chore-observability-schema-parity-test-plan.md
issue: 4133
---

# Tasks — Observability-block schema parity test (#4133)

## Phase 1 — Setup / Write test

- [ ] 1.1 Create `plugins/soleur/test/observability-schema-parity.test.ts` (`bun:test`, resolve `REPO_ROOT` via `import.meta.dir`).
- [ ] 1.2 Implement `topLevelKeys(blockBody)` (column-0 `^([a-z_]+):` extractor) and `observabilityYamlBlocks(md)` (walk every ```yaml block under a `## Observability` heading).

## Phase 2 — Core assertions (one test per surface)

- [ ] 2.1 Canonical: extract 5 top-level keys from `plan/SKILL.md §2.9`; assert `length === 5` and set equals `{liveness_signal, error_reporting, failure_modes, logs, discoverability_test}`.
- [ ] 2.2 Templates: block-walk `plan-issue-templates.md`; assert exactly 3 blocks; each top-level-key set equals canonical.
- [ ] 2.3 deepen-plan §4.7: extract backticked field names from the enumeration lines; assert set equals canonical; assert count word `5 === canonical.length`.
- [ ] 2.4 AGENTS.core.md: assert `hr-observability-as-plan-quality-gate` line contains `(${canonical.length} fields)`, `discoverability_test`, and a WITHOUT-SSH invariant token. (No name-set assertion — names intentionally absent.)

## Phase 3 — Testing / Verification

- [ ] 3.1 RED evidence: rename one field in one surface locally → confirm FAIL names the surface → revert. Capture output for PR body.
- [ ] 3.2 GREEN: `bun test plugins/soleur/test/observability-schema-parity.test.ts` exits 0.
- [ ] 3.3 Confirm auto-discovery: `bun test plugins/soleur/` runs the new test (no `scripts/test-all.sh` edit needed).
