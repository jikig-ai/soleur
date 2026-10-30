# ADR-297: Living KB doc sharding — stable-path index + dated-record shards

## Status

Accepted — 2026-10-24 (#11032)

## Context

`knowledge-base/product/competitive-intelligence.md` reached 569 lines / ~134 KB:
~52% was two embedded peer-plugin audits, and the Executive Summary was
accumulating dated intake blocks into a changelog. The file is written by a
monthly cron (`cron-competitive-analysis`) behind a path allowlist
(`isPathAllowed` = bare `startsWith`), so any restructure that did not update
producer surfaces in the same commit would silently drop future writes.

## Decision

A growing curated KB doc splits into:

1. **A stable-path index** at the doc's *unchanged* path — the living
   synthesis: frontmatter (review machinery stays here, never on shards),
   narrative summary, comparison matrices, takeaways, recommendations, and a
   `## Detail files` map of the shard directory.
2. **A sibling `<doc-stem>/` shard directory** holding dated records and
   per-subject detail: `audits/<owner>-<repo>.md` for audits,
   `tier-<N>-<slug>.md`-style `<axis>-<slug>.md` files for per-subject detail,
   and an append-only `audit-log.md` for outcomes that produce no shard.

**Declared trigger** for applying this to another doc: ~500 lines OR ≥2
embedded point-in-time records OR an append-log accumulating inside a
synthesis section.

**Producer lockstep is part of the decision, not an implementation detail:**
every write surface that targets the doc (path allowlists, persistence prompts,
agent output contracts, audit procedures) updates in the same commit —
otherwise shard writes are silently discarded while runs report green. A
bare-`startsWith` allowlist needs BOTH the `doc.md` file entry AND the
`doc/` trailing-slash dir entry.

**Exclusions:** append-only legal/compliance registers
(`article-30-register.md`, `compliance-posture.md`, breach register) are NOT
sharded — they rely on single-file `> **Superseded …**` in-cell corrections
that sharding would break. No shard is ever named `INDEX.md`
(`generate-kb-index.sh` excludes that name at any depth; shards otherwise
auto-appear).

Full operational convention: `plugins/soleur/skills/competitive-analysis/references/living-kb-doc-sharding.md`.

## Alternatives Considered

- **Per-competitor-everything (dissolve the matrix into per-competitor
  files):** rejected — destroys the side-by-side comparison surface and the
  cascade extraction contract.
- **Per-tier shards:** rejected — forces retargeting of every consumer that
  reads "exec summary + tier from one file" for ~equal readability gain.
- **Move the index into the shard dir:** rejected — ~15 live `depends_on` /
  citation pointers, two test canaries, the dashboard URL, and top-level
  review scanners all key on the existing path.

## Consequences

- The monthly cron persists index + shard writes (allowlist carries both
  entries); `--max-turns` 45→60 covers index + N shard writes + cascade.
- `peer-plugin-audit` upserts `audits/<owner>-<repo>.md` + the index matrix
  row; the old "no parallel files" rule is superseded (one audit file per
  repo — the shard).
- Shards carry `publishable: internal|external` (formalizes the Sutra
  precedent) as a machine-readable do-not-republish gate for downstream
  cascades.
- Qualifier severance is forbidden: every `unverified`/`marketing` flag and
  source URL moves with the claim it qualifies (CLO requirement).

## Precedents

ADR-126 (artifact persistence contracts), ADR-151 (KB corpus loading),
ADR-200, ADR-235, ADR-266, ADR-094 (`last_reviewed` scanner-ownership).
