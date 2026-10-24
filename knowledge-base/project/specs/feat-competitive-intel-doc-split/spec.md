---
title: Split competitive-intelligence.md into index + shards
date: 2026-10-24
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-10-24-competitive-intel-doc-split-brainstorm.md
---

# Spec: Competitive-intelligence doc split + living-KB sharding convention

## Problem Statement

`knowledge-base/product/competitive-intelligence.md` is 569 lines / ~134 KB and grows monthly (cron) plus per targeted addition. ~52% is two embedded peer-plugin audits; the Executive Summary is accumulating dated intake blocks into a changelog. The file is hard to read for humans (dashboard at `/dashboard/kb/product/competitive-intelligence.md`) and wasteful for agents (every cascade specialist + roadmap read loads the whole file). A monthly cron writes it behind a path allowlist, so any restructure that doesn't update producer surfaces silently drops future writes.

## Goals

1. Split the doc into a stable-path **index** (living synthesis: slim exec summary, all tier overlap matrices, takeaways, new entrants, recommendations, cascade results, shard map) at the **unchanged** `knowledge-base/product/competitive-intelligence.md` path, plus a sibling **`competitive-intelligence/`** shard directory holding dated records and per-competitor detail.
2. Update every producer surface in the same PR so monthly scans and peer audits write the new structure with zero silently-discarded writes.
3. Ship the pattern as a reusable convention — one ADR + one plugin-carried reference doc — so other Soleur users' growing curated KB docs can adopt the same shape.

## Non-Goals

- No per-competitor shard for every matrix row (Option C rejected — destroys the comparison surface + cascade extraction contract).
- No per-tier shard split (Option B rejected — costs product-roadmap + cascade prompt retargeting for equal readability gain).
- No new `kb-shard` skill (deferred — ~2-word description-budget headroom, one consumer; trigger recorded in brainstorm Open Questions).
- No `depends_on` / citation sweep (index keeps its exact path — nothing to repoint).
- No UI/web-platform frontend work (catch-all KB route + file tree already render directories and links).
- No changes to append-only legal/compliance registers (convention explicitly excludes them).
- No consumer-side changes to the 4 cascade specialists' write targets.

## Functional Requirements

- **FR1** — `competitive-intelligence.md` index ≤ ~220 lines: unchanged frontmatter semantics (`last_updated`, `last_reviewed`, `review_cadence`, `owner`, `depends_on`, `tiers_scanned`), slim Executive Summary (dated intake blocks → one-line links), Tier 0–5 overlap matrices + Key Takeaways, New Entrants, Recommendations, Cascade Results, and a `## Detail files` map of the shard dir.
- **FR2** — Overlap-matrix Differentiation cells are slimmed to the key differentiator + a doc-relative `→ detail` link where a shard exists; competitors without detail keep fuller cells.
- **FR3** — Shards live at `knowledge-base/product/competitive-intelligence/`: `audits/<owner>-<repo>.md` for peer-plugin audits (mattpocock, humanlayer move verbatim incl. addenda) and `tier-<N>-<slug>.md` for per-competitor detail (dated intake blocks, metrics history, positioning narrative, sources). No file named `INDEX.md`.
- **FR4** — Shard frontmatter is minimal: `title`, `competitor`/`target`, `tier`, `last_updated`, `publishable: internal|external`. Shards carry **no** `review_cadence`, `owner`, or `depends_on` (review machinery stays on the index; `review-reminder.yml` scans all depths).
- **FR5** — Every source URL and "unverified/marketing/contradiction" qualifier moves **with** the claim it qualifies (CLO qualifier-severance rule) — verified by a post-split content assertion.
- **FR6** — Producer surfaces updated in the same commit(s): `COMPETITIVE_ANALYSIS_ALLOWED_PATHS` gains `knowledge-base/product/competitive-intelligence/` (trailing-slash dir entry; `competitive-intelligence.md` file entry stays), the verbatim PERSISTENCE prompt path list, `cron-competitive-analysis.test.ts` (`toEqual` array + canary), `cron-cohort-dedup.test.ts` fixtures.
- **FR7** — Instruction surfaces updated: `plugins/soleur/agents/product/competitive-intelligence.md` output contract (index+shard writes, slim-cell rule, exclusive-write re-scoped to index+dir, cascade task prompts still name the index), `skills/competitive-analysis/SKILL.md` (L16/L58 + stale scheduled-workflow lines), `skills/competitive-analysis/references/peer-plugin-audit.md` (upsert `audits/<owner>-<repo>.md` + index audit-row; rewrite the L207 no-parallel-files rule; `last_reviewed` bump → `last_updated` per ADR-094).
- **FR8** — Convention artifacts: one ADR (`living KB doc sharding: stable-path index + dated-record shards`, including the exclusion of append-only legal registers and the declared size trigger) + `plugins/soleur/skills/competitive-analysis/references/living-kb-doc-sharding.md` linked from the agent contract.

## Technical Requirements

- **TR1** — `isPathAllowed` is bare `startsWith`: the allowlist needs BOTH `knowledge-base/product/competitive-intelligence.md` AND `knowledge-base/product/competitive-intelligence/` — neither prefix matches the other's paths.
- **TR2** — Commits that move/delete `last_reviewed:` lines need a `Context-Reviewed:` trailer (`context-reviewed-gate.sh`).
- **TR3** — Links are doc-relative in both directions (`competitive-intelligence/tier-3-polsia.md` down, `../competitive-intelligence.md` up); moved `](../project/...)` links in relocated audit content get one extra `../`.
- **TR4** — Index links are the live-competitor set; audit/intake shards are append-only dated records never regenerated; monthly run regenerates index + touched shards only.
- **TR5** — Preserve the commit message `docs: update competitive intelligence report` (freshness anchors `cron-artifact-age.sh` + `_cron-shared.ts` are message-keyed, not path-keyed).
- **TR6** — `knowledge-base/product/competitive-analysis.md` is a different doc in `DASHBOARD_FOUNDATION_KB_PATHS` — shard filenames must stay clearly distinct.

## Acceptance Criteria

- Dashboard renders index at existing URL and every shard link resolves in-app.
- `bun test apps/web-platform/test/server/inngest/cron-competitive-analysis.test.ts` + `cron-cohort-dedup.test.ts` + `cron-safe-commit-parity.test.ts` green.
- Dry-run/read of `cron-competitive-analysis` persistence: a write under `competitive-intelligence/` would be persisted (allowlist covers dir).
- Post-split grep: no live `depends_on` or citation pointer is stale; relative links `](../project/` inside moved shards are depth-corrected.
- Content assertion: every `unverified`/`marketing`-flagged claim retains its qualifier + source URL in its shard.
- Brainstorm + spec committed; ADR + convention doc committed; agent contract names index+dir.
