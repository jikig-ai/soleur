## Summary

`knowledge-base/product/competitive-intelligence.md` is 569 lines / ~134 KB and grows every monthly cron run plus per targeted addition. ~52% is two embedded peer-plugin audits; the Executive Summary is accumulating dated intake blocks into a changelog. Restructure it into a stable-path index + sibling `competitive-intelligence/` shard directory, update all producer surfaces in lockstep (cron allowlist, persistence prompt, tests, agent contract, peer-plugin-audit seeding), and ship the pattern as an ADR + plugin reference doc for other Soleur users.

User-Impact: /dashboard/kb/product/competitive-intelligence.md
Fix-Size: 569 lines / 14 files

## Artifacts

- Brainstorm: `knowledge-base/project/brainstorms/2026-10-24-competitive-intel-doc-split-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-competitive-intel-doc-split/spec.md`
- Branch: `feat-competitive-intel-doc-split`
- Draft PR: #11017

## Acceptance criteria

- Index stays at `competitive-intelligence.md` (~150-220 lines): slim exec summary, all six tier overlap matrices, takeaways, new entrants, recommendations, cascade results, shard map
- Shards under `knowledge-base/product/competitive-intelligence/`: `audits/<owner>-<repo>.md` + `tier-<N>-<slug>.md`; minimal frontmatter (no `review_cadence`/`owner`/`depends_on`); `publishable:` field
- `COMPETITIVE_ANALYSIS_ALLOWED_PATHS` gains trailing-slash dir entry in the same PR as the split (no silent write-drop window)
- Agent output contract + skill + peer-plugin-audit reference updated; L207 no-parallel-files rule rewritten; ADR-094 `last_reviewed` violation fixed
- ADR + `living-kb-doc-sharding.md` convention doc committed; excludes append-only legal registers
- All qualifier/source URLs move with their claims (CLO qualifier-severance)
- Cron tests green; dashboard links resolve
