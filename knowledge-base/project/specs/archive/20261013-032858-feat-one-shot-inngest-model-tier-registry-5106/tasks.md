---
feature: feat-one-shot-inngest-model-tier-registry-5106
issue: 5106
lane: single-domain
plan: knowledge-base/project/plans/2026-06-11-refactor-inngest-cron-model-tier-registry-plan.md
---

# Tasks — Inngest cron model-tier registry + MODEL_PRICING parity (#5106)

Derived from the finalized plan. Pure SSOT extraction — no model assignment
changes (sonnet stays sonnet, opus-4-7 stays opus-4-7). Run all tests/typecheck
via `cd apps/web-platform && ./node_modules/.bin/{vitest run,tsc --noEmit}` —
never `npm run -w` (no root workspaces), never `bun test`.

## Phase 0 — Preconditions
- [x] 0.1 Re-grep the canonical inventory against HEAD (counts drift): `grep -rln '"claude-sonnet-4-6"' apps/web-platform/server/inngest/functions/` and `'"claude-opus-4-7"'`.
- [x] 0.2 Confirm `apps/web-platform/node_modules/.bin/vitest` and `.../tsc` exist.
- [x] 0.3 Confirm `leader-prompts/index.ts:28-36` still re-exports `SONNET_MODEL`/`HAIKU_MODEL`/`AnthropicModelId`; registry will import from `./leader-prompts/constants` directly (cycle note `constants.ts:1-5`).
- [x] 0.4 Confirm `vitest.config.ts` `include:` collects `test/server/inngest/*.test.ts` before finalizing the new test path.

## Phase 1 — RED: drift/parity test
- [x] 1.1 Create `apps/web-platform/test/server/inngest/model-tiers.test.ts` with `vi.hoisted(() => { process.env.NEXT_PHASE = "phase-production-build"; })` BEFORE imports (idiom: `cron-roadmap-review.test.ts:19-30`).
- [x] 1.2 Assert (a) no-raw-literal directory walk over `functions/*.ts` (strip comment lines, match `"claude-sonnet-4-6"`/`"claude-opus-4-7"`), (b) walk found ≥17 files, (c) `MODEL_PRICING` keys ⊆ `AnthropicModelId` and vice-versa, (d) `EXECUTION_MODEL === SONNET_MODEL` and `AUDIT_MODEL === "claude-opus-4-7"`.
- [x] 1.3 Run RED — confirm failure.

## Phase 2 — GREEN: registry + consumer migration
- [x] 2.1 Create `apps/web-platform/server/inngest/model-tiers.ts`: import `SONNET_MODEL`/`HAIKU_MODEL` from `./leader-prompts/constants`; export `EXECUTION_MODEL = SONNET_MODEL` and `AUDIT_MODEL = "claude-opus-4-7" as const`; inline comment block (workload-class rationale, no-re-tier/never-downgrade per ADR-053, mixed alias/dated convention, opus-not-in-pricing rationale).
- [x] 2.2 Migrate 12 sonnet selection sites → `EXECUTION_MODEL` (import from `@/server/inngest/model-tiers`): cron-bug-fixer:148, cron-campaign-calendar:63, cron-community-monitor:123, cron-content-generator:78, cron-daily-triage:141, cron-follow-through-monitor:238, cron-growth-execution:94, cron-roadmap-review:97, cron-seo-aeo-audit:95, event-ship-merge:51, plus the two `ANTHROPIC_MODEL` consts: cron-compound-promote:67 (KEEP `export` — imported by `cron-compound-promote.test.ts:10,70`), cron-weekly-release-digest:45 (KEEP never-downgrade comment :40-44).
- [x] 2.3 Migrate 5 opus selection sites → `AUDIT_MODEL`: cron-agent-native-audit:100, cron-competitive-analysis:103, cron-growth-audit:65, cron-legal-audit:104, cron-ux-audit:71. Leave doc-comment occurrences verbatim.

## Phase 3 — GREEN: MODEL_PRICING keys
- [x] 3.1 In `functions/agent-on-spawn-requested.ts`, import `SONNET_MODEL`/`HAIKU_MODEL`; change `MODEL_PRICING` keys to `[SONNET_MODEL]:` / `[HAIKU_MODEL]:`; keep the 8 numeric values byte-identical. Leave `Record<string, ModelPricing>` unless parity-test design needs tightening (then run tsc and fix TS2322 rails).

## Phase 4 — Verify
- [x] 4.1 GREEN drift/parity test (AC6).
- [x] 4.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (AC7).
- [x] 4.3 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/` — full suite green incl. literal-asserting tests (`cron-compound-promote.test.ts:70`, `cron-bug-fixer.test.ts`, `cron-weekly-release-digest.test.ts`) and any function-registry-count suite (AC8, AC9).

## Phase 5 — Ship
- [ ] 5.1 PR body uses `Closes #5106` (AC10).
