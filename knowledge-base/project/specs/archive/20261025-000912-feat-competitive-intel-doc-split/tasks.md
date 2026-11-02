---
title: Tasks — split competitive-intelligence.md into index + shards
date: 2026-10-24
lane: cross-domain
issue: 11032
plan: knowledge-base/project/plans/2026-10-24-competitive-intel-doc-split-plan.md
---

# Tasks

## Phase 1 — Shard extraction

- [x] 1.1 Create `knowledge-base/product/competitive-intelligence/audits/`; move `## Peer-Plugin Audit — mattpocock/skills` → `audits/mattpocock-skills.md`, `## Peer-Plugin Audit — humanlayer/humanlayer` → `audits/humanlayer-humanlayer.md` (verbatim incl. addenda; minimal shard frontmatter incl. `target:` + `publishable:`; depth-2 back-link `../../competitive-intelligence.md`; `](../project/` → `](../../../project/`); move `### Peer-Plugin Audit Log` → `audit-log.md`
- [x] 1.2 Create `tier-<N>-<slug>.md` shards for Cofounder, Multica, Omnigent, Sutra, HumanLayer, Polsia, NanoCorp (predicate: dated record or detail exceeding a slim cell); move each dated exec-summary intake block into its competitor's shard; HumanLayer tier shard links `audits/humanlayer-humanlayer.md` both ways
- [x] 1.3 Rewrite index: unchanged frontmatter (`last_updated` bumps, `last_reviewed` stays 2026-07-04 — scanner-owned); slim exec summary (one-line links); slimmed Differentiation cells with `→ detail` links; convert all "see full audit below"-style prose anchors to links; keep takeaways/new-entrants/recommendations/cascade-results; add `## Detail files` map; ≤220 lines
- [x] 1.4 Content assertion: every `unverified`/`marketing`-flagged claim retains qualifier + source URL adjacent (CLO qualifier-severance)
- [x] 1.5 `Context-Reviewed:` trailer on any commit moving/deleting `last_reviewed:` lines

## Phase 2 — Producer lockstep (same PR)

- [x] 2.1 `cron-competitive-analysis.ts`: add `"knowledge-base/product/competitive-intelligence/"` to `COMPETITIVE_ANALYSIS_ALLOWED_PATHS`; rewrite PERSISTENCE prompt path list
- [x] 2.2 Update `cron-competitive-analysis.test.ts` (`toEqual` array + canary) and `cron-cohort-dedup.test.ts` fixtures
- [x] 2.3 `plugins/soleur/agents/product/competitive-intelligence.md`: index+shard output contract (mandated shape for ALL installs — unsharded repos get migrated, never write-only orphan shards); slim-cell rule; exclusive-write rescope; cascade prompts name index + tell specialists to follow `→ detail` links for depth; orphan policy
- [x] 2.3a `cron-competitive-analysis.ts`: bump `--max-turns` 45→60 (index + N shard writes + 4-specialist cascade)
- [x] 2.4 `competitive-analysis/SKILL.md`: L16/L58 update + stale scheduled-workflow fix
- [x] 2.5 `peer-plugin-audit.md`: upsert `audits/<owner>-<repo>.md` + index audit-row; rewrite L207; `last_updated` fix (audit writes only — the INDEX's `last_reviewed` is scanner-owned, untouched); stale "Skill Library Tier" wording
- [x] 2.6 `brainstorm/SKILL.md` L221 path fix
- [x] 2.7 Boundary test in `cron-competitive-analysis.test.ts`: shard path `competitive-intelligence/audits/x.md` persists AND prefix-sibling decoy `competitive-intelligence-evil/x.md` is dropped (bare `startsWith`)

## Phase 3 — Convention

- [x] 3.1 ADR-NNN `living-kb-doc-sharding.md` (re-check ordinal vs origin/main pre-merge)
- [x] 3.2 `plugins/soleur/skills/competitive-analysis/references/living-kb-doc-sharding.md` convention doc (incl. re-tier rename policy, dual-shard interlinking, `publishable:` = do-not-republish semantics, shard frontmatter key rules); link from agent contract + ADR

## Phase 4 — Verify

- [x] 4.1 `bun test apps/web-platform/test/server/inngest/cron-competitive-analysis.test.ts apps/web-platform/test/server/inngest/cron-cohort-dedup.test.ts apps/web-platform/test/server/inngest/cron-safe-commit-parity.test.ts`
- [x] 4.2 Grep sweep: no stale live `depends_on`; all `](competitive-intelligence/` links resolve to committed files
- [x] 4.3 Index ≤220 lines; shard map complete
- [x] 4.4 Consumer sweep: `git grep -n 'competitive-intelligence'` — zero unaddressed live hits (harness mirrors opencode/cursor are stubs to the canonical agent — confirm unchanged; `docs/blog/case-study-*` is a dated record — leave)
- [x] 4.5 Index retains `last_reviewed` (strategy-review-check.sh reads top-level; dropping it → instant stale-issue)
