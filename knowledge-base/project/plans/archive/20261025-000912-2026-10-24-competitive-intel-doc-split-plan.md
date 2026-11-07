---
title: Split competitive-intelligence.md into index + shards
date: 2026-10-24
lane: cross-domain
brand_survival_threshold: single-user incident
issue: 11032
spec: knowledge-base/project/specs/feat-competitive-intel-doc-split/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-10-24-competitive-intel-doc-split-brainstorm.md
---

# Plan: Competitive-intelligence doc split + living-KB sharding convention

## Overview

`knowledge-base/product/competitive-intelligence.md` (569 lines / ~134 KB) becomes an index at its **unchanged path** plus a sibling `knowledge-base/product/competitive-intelligence/` shard directory. Producer surfaces update in the same PR so the monthly cron + peer audits write the new structure with zero dropped writes. Pattern ships as one ADR + one plugin reference doc.

## Domain Review (carried forward from brainstorm)

### Engineering (CTO)
Bare-`startsWith` allowlist needs BOTH file + trailing-slash dir entries; `toEqual` test assert; `context-reviewed-gate.sh` needs `Context-Reviewed:` trailers on `last_reviewed` moves; recommends the ADR. Blast radius single-user.

### Product (CPO)
Index keeps living synthesis; exec summary is becoming a changelog — intake blocks must shard too; `peer-plugin-audit.md` L207 no-parallel-files rule must be explicitly rewritten.

### Legal (CLO)
No new GDPR processing activity. Qualifier-severance is the primary risk — per-claim sources/unverified flags move with claims. Adopt `publishable:` shard field; exclude append-only legal registers from convention. Repo is public — shards stay published artifacts.

### Marketing (CMO)
Cascade feeds 4 downstream artifacts; split must not break the matrix-extraction contract. Per-shard freshness helps battlecards/seo-refresh. Convention is a marketable capability.

## User-Brand Impact

- **Artifact:** `knowledge-base/product/competitive-intelligence.md` + `competitive-intelligence/` shard dir + cron persistence surface.
- **Vector:** silent shard write-drop (allowlist miss) or qualifier severance propagating unverified competitor figures to public comparison pages.
- **Threshold:** single-user incident.

## Implementation Phases

### Phase 1 — Shard extraction (the move)

1. `mkdir -p knowledge-base/product/competitive-intelligence/audits`.
2. Move `## Peer-Plugin Audit — mattpocock/skills` and `## Peer-Plugin Audit — humanlayer/humanlayer` sections verbatim into `audits/mattpocock-skills.md` and `audits/humanlayer-humanlayer.md` (minimal shard frontmatter; depth-2 back-link `../../competitive-intelligence.md`; `](../project/` → `](../../../project/`); move `### Peer-Plugin Audit Log` → `audit-log.md`.
3. Create `tier-<N>-<slug>.md` shards only for competitors with dated records — move each dated "targeted addition" exec-summary block into its competitor's shard (Cofounder→`tier-3-cofounder.md`, Multica→`tier-3-multica.md`, Omnigent→`tier-4-omnigent.md`, Sutra→`tier-3-sutra.md`, HumanLayer→`tier-3-humanlayer.md`; Polsia/NanoCorp only if detail exceeds a slim cell).
4. Slim each matrix Differentiation cell to key differentiator + `→ detail` link where a shard exists; keep fuller cells where none does.
5. Rewrite index: frontmatter unchanged; exec summary = narrative + one-line links to shards; add `## Detail files` map; keep New Entrants, Recommendations, Cascade Results. Target ≤220 lines.
6. Every `unverified`/`marketing`-flagged claim keeps qualifier + source URL adjacent (CLO qualifier-severance — content assertion, not a grep).
7. Commits that move/delete `last_reviewed:` lines carry `Context-Reviewed:` trailers.

### Phase 2 — Producer lockstep (same PR, atomic with Phase 1)

- `apps/web-platform/server/inngest/functions/cron-competitive-analysis.ts`: add `"knowledge-base/product/competitive-intelligence/"` to `COMPETITIVE_ANALYSIS_ALLOWED_PATHS` (keep the `.md` entry — bare `startsWith` matches neither for the other); rewrite the PERSISTENCE prompt path list (~L157) to name index + dir.
- `apps/web-platform/test/server/inngest/cron-competitive-analysis.test.ts`: update `toEqual` array + prompt canary.
- `apps/web-platform/test/server/inngest/cron-cohort-dedup.test.ts`: update `hit`/`nearMiss` fixtures for the dir prefix.
- `plugins/soleur/agents/product/competitive-intelligence.md`: Output Contract → index+shard writes as the mandated shape for ALL installs (unsharded repos get migrated, never orphan shards); slim-cell rule; exclusive-write re-scoped to index+dir; cascade task prompts name the index AND tell specialists to follow `→ detail` links for depth; orphan policy (index links = live set; shards append-only).
- `apps/web-platform/server/inngest/functions/cron-competitive-analysis.ts` (also here): `--max-turns` 45→60 for index + N shards + 4-specialist cascade.
- `plugins/soleur/skills/competitive-analysis/SKILL.md`: update L16/L58; fix stale deleted-GHA "Scheduled Execution" lines.
- `plugins/soleur/skills/competitive-analysis/references/peer-plugin-audit.md`: upsert `audits/<owner>-<repo>.md` + index audit-row; rewrite the L207 no-parallel-files rule as superseded; `last_reviewed` bump → `last_updated` (ADR-094); fix stale "Skill Library Tier" wording.
- `plugins/soleur/skills/brainstorm/SKILL.md` L221: correct misnamed path (`agents/product/` → the KB doc row reference).

### Phase 3 — Convention artifacts

- ADR-NNN `living-kb-doc-sharding.md` in `knowledge-base/engineering/architecture/decisions/` (next free ordinal — re-check against origin/main at commit): stable-path index + dated-record shards; declared trigger (~500 lines OR ≥2 embedded point-in-time records OR append-log in synthesis section); excludes append-only legal/compliance registers; cites ADR-126/ADR-151/ADR-200/ADR-235/ADR-266 precedents.
- `plugins/soleur/skills/competitive-analysis/references/living-kb-doc-sharding.md`: the operational convention (index layout, shard frontmatter schema incl. `publishable:`, naming `<axis>-<slug>.md`, link style, no-INDEX.md rule, write-boundary trailing-slash allowlist rule, qualifier-severance rule, orphan policy). Linked from the agent contract + ADR.

### Phase 4 — Verify

- `bun test apps/web-platform/test/server/inngest/cron-competitive-analysis.test.ts apps/web-platform/test/server/inngest/cron-cohort-dedup.test.ts apps/web-platform/test/server/inngest/cron-safe-commit-parity.test.ts`
- Grep sweep: no live `depends_on`/citation stale; `](../project/` depth-corrected inside shards.
- Local render check: index links resolve (`test -f` each `](competitive-intelligence/` target).
- Content assertion: every qualifier'd claim retains qualifier + URL.

## Files to Edit

- `knowledge-base/product/competitive-intelligence.md` (rewrite → index)
- `knowledge-base/product/competitive-intelligence/audits/mattpocock-skills.md`, `audits/humanlayer-humanlayer.md`, `tier-3-cofounder.md`, `tier-3-multica.md`, `tier-4-omnigent.md`, `tier-3-sutra.md`, `tier-3-humanlayer.md` (new)
- `apps/web-platform/server/inngest/functions/cron-competitive-analysis.ts`
- `apps/web-platform/test/server/inngest/cron-competitive-analysis.test.ts`, `cron-cohort-dedup.test.ts`
- `plugins/soleur/agents/product/competitive-intelligence.md`
- `plugins/soleur/skills/competitive-analysis/SKILL.md`, `references/peer-plugin-audit.md`, `references/living-kb-doc-sharding.md` (new)
- `plugins/soleur/skills/brainstorm/SKILL.md` (one-line path fix)
- `knowledge-base/engineering/architecture/decisions/ADR-NNN-living-kb-doc-sharding.md` (new)

## Observability

```yaml
liveness_signal:    # what: monthly cron writes land as index+shard commits / cadence: monthly (0 9 1 * *) / alert_target: cron-artifact-age detector / configured_in: scripts/cron-artifact-age.sh row `cron-competitive-analysis|0 9 1 * *|31|B|^docs: update competitive intelligence report`
error_reporting:    # destination: safeCommitAndPr drops non-allowlisted paths → marker in PR body + Sentry warn / fail_loud: yes
failure_modes:      # [{mode: shard write dropped by allowlist, detection: dir entry present in COMPETITIVE_ANALYSIS_ALLOWED_PATHS + toEqual test, alert_route: CI}, {mode: index committed without shards, detection: shard-map links resolve locally (AC), alert_route: PR review}]
logs:               # where: gh run logs for cron-competitive-analysis / retention: GHA default
discoverability_test:
  command: "git grep -c 'knowledge-base/product/competitive-intelligence/' -- apps/web-platform/server/inngest/functions/cron-competitive-analysis.ts"
  expected_output: "2"
```

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "the more we add to the competitive intelligence doc the harder it becomes to read. How could we better structure this for better both human and agents readability" | Phase 1 (index + shards) | mapped |
| 2 | "Shall we consider breaking it down and link the main doc to each competitor sub .md file for more details?" | `tier-<N>-<slug>.md` shards + `→ detail` matrix links | mapped (index+links form) |
| 3 | "Shall we improve our skills so it benefits other Soleur users too that may face the same issue?" | Phase 2 producer updates + Phase 3 ADR + convention ref doc | mapped |

### Plan-Item Provenance

| Plan item | User words cited | Verdict |
|-----------|------------------|---------|
| Phase 2 cron/test updates | — | inferred — justification: writes outside the allowlist are silently discarded; lockstep is the only safe ordering (all 6 agents concur) |
| `publishable:` shard field | — | inferred — justification: CLO ruling, formalizes existing Sutra precedent |
| brainstorm SKILL.md L221 path fix | — | inferred — justification: misnamed-path cleanup inside touched subsystem |
| `kb-shard` skill | "improve our skills" | descoped — ~2-word description-budget headroom, one consumer; documented in brainstorm Open Questions with re-eval trigger |

### Split Assessment

- Subsystems touched: 3 — `knowledge-base/product/`, `apps/web-platform/` (server+tests), `plugins/soleur/` (agent+skills+ADR)
- Planned files: ~14 | Estimated changed lines: ~800
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the split and producer updates are atomic by design; splitting them creates the silent-write-drop window

## Acceptance Criteria

- Index at `competitive-intelligence.md` ≤220 lines; every matrix slim-cell `→ detail` link resolves to a committed shard.
- `COMPETITIVE_ANALYSIS_ALLOWED_PATHS` contains both `.md` file and trailing-slash dir entries; `toEqual` test updated and green.
- Agent contract names index+dir; peer-plugin-audit.md upserts `audits/<owner>-<repo>.md`; L207 rewritten; `last_updated` fix landed.
- ADR + `living-kb-doc-sharding.md` committed; convention excludes append-only legal registers.
- Qualifier-severance content assertion passes; `Context-Reviewed:` trailers on `last_reviewed`-moving commits.
- All three named test files green; no stale live `depends_on`.
