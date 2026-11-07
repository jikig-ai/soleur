# Living KB doc sharding convention

Operational convention for splitting a growing curated knowledge-base doc into
a stable-path index + a sibling shard directory. Decision record: ADR-297
(`knowledge-base/engineering/architecture/decisions/ADR-297-living-kb-doc-sharding.md`).
Canonical instance: `knowledge-base/product/competitive-intelligence.md` +
`knowledge-base/product/competitive-intelligence/`.

## When to apply

Trigger: the doc reaches ~500 lines OR embeds ≥2 point-in-time records (audits,
intake blocks, incident annexes) OR accumulates an append-log inside a
synthesis section.

Do NOT apply to append-only registers whose correction discipline is
single-file `> **Superseded …**` cells (legal/compliance registers — ADR-297).

## Layout

- **Index** — the doc's *unchanged* path (`foo.md`). Living synthesis only:
  frontmatter, narrative summary, comparison matrices, takeaways,
  recommendations, and a `## Detail files` map.
- **Shard dir** — sibling `foo/` directory:
  - `audits/<owner>-<repo>.md` — dated audit records
  - `<axis>-<slug>.md` — per-subject detail (e.g. `tier-3-cofounder.md`)
  - `audit-log.md` — append-only log for outcomes that produced no shard
  - **Never `INDEX.md`** — `generate-kb-index.sh` excludes that name; every
    other shard auto-appears in generated indexes.

## Shard frontmatter schema

Minimal: `title`, `last_updated`, `publishable: internal|external`, plus a
subject key (`competitor` on `tier-*`, `target` (`owner/repo`) on `audits/*`).

**Never** `review_cadence`, `owner`, or `depends_on` on a shard —
`review-reminder.yml` scans all depths and would mint a monthly issue per
shard; review machinery stays on the index only.

`publishable:` semantics: `internal` = do-not-republish/do-not-cite in public
or marketing content (it is a guidance flag, not access control — the repo is
public; shards are published artifacts).

## Write-boundary rule

Producers writing under the shard dir must have BOTH allowlist entries when
matching is bare `startsWith`: `foo.md` AND `foo/` (trailing slash — a bare
`foo` stem would also match `foo-evil/`). Update the producer (allowlist,
prompt path list, output contract) in the SAME commit as the restructure —
otherwise shard writes are silently discarded while runs report green.

## Content rules

- **Slim cells:** index matrix/detail cells slim to the key differentiator +
  a `→ detail` link where a shard exists; keep fuller cells where none does.
- **Qualifier severance forbidden:** every `unverified`/`marketing`/
  `contradiction` flag and source URL moves WITH the claim it qualifies.
- **Depth-corrected links:** index→shard is `foo/<file>.md`; depth-1 shards
  back-link `../foo.md`; depth-2 shards (`audits/*`) back-link `../../foo.md`.
  Relocated `](../project/`-style links gain one `../` per level moved.
- **Orphan policy:** index links are the live set; shards are append-only
  dated records, never deleted by a run. A subject dropped from the index
  keeps its shard (dated record) and loses its index row.
- **Re-tier / rename:** if a subject's axis value changes (e.g. a competitor
  moves tier), `git mv` the shard to the new name and update the index link;
  do not leave a redirect stub.
- **Dual-shard interlinking:** when two shards cover the same subject (a
  `tier-*` detail file and an `audits/*` audit), link them to each other.
- **Migration rule:** the sharded layout is the mandated shape for ALL
  installs — on a repo whose doc was never split, the run writes the index
  and creates the needed shards; never produce write-only orphan shards.
