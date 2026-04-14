---
title: kb-search frontmatter faceting
date: 2026-04-14
status: complete
issue: 2211
---

# kb-search Frontmatter Faceting

## What We're Building

Add `--tag` and `--category` flags to the `kb-search` skill so agents can filter `knowledge-base/project/learnings/` by YAML frontmatter facets, cutting result-set noise when cross-referencing. Extend `scripts/generate-kb-index.sh` to emit two sibling autocomplete artifacts (`_tags.txt`, `_categories.txt`). Update compound-capture's Related Docs Finder guidance to suggest faceted queries.

## Why This Approach

- **Grep is not the bottleneck.** 386 learnings / 1.9 MB. Grep finds 240 matches in 15 ms. Query latency is fine.
- **Result-set noise is.** Agents cross-referencing during `/compound` get flooded by keyword matches that span unrelated domains.
- **Frontmatter already exists.** `tags:` and `category:` are present on all 120+ validated learnings (validated via `compound-capture/references/yaml-schema.md`). Faceting is the 80/20 — no new infra, no vector DB.
- **Revisit BM25 + embeddings only if corpus grows past ~3,000 files or typical queries return 500+ matches.**

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Validation strictness | Warn-but-accept + case-insensitive match | Most token-efficient for agent consumers. Silent empties cause retry loops; strict enums force full valid list into SKILL.md context on every invocation. Warn-but-accept returns "did you mean X, Y, Z?" on miss — one round-trip to resolution. |
| Autocomplete artifact format | Two plain-text files (`knowledge-base/_tags.txt`, `_categories.txt`) | Sorted unique values, one per line. Zero deps (no jq). `grep -Fx` friendly. Tiny diff surface. <2KB each so agents can load inline. |
| Compound integration | Docs-only update to `compound-capture/SKILL.md` Step 3 | Adds guidance showing the `--tag`/`--category` pattern. Agent decides when to use faceted vs plain grep at runtime. No coupling between compound and kb-search internals. |
| Query semantics | Single `--tag` and/or `--category` combined with optional keyword (AND) | Matches issue example `/kb-search --category performance-issues csrf`. Multi-tag or OR logic deferred — not in AC, no current demand. |
| Normalization scope | None applied to source files | Warn-but-accept + case-insensitive comparison tolerates corpus drift (mixed casing, ~50 freeform categories). Retroactive cleanup tracked separately if signal degrades. |
| Frontmatter parser | Reuse existing `awk '/^---$/{c++; next} c==1'` idiom | Documented in `2026-03-12-directory-driven-content-discovery-frontmatter-parsing.md`. No new YAML dep; `sed` range expressions are known-broken (body `---` leaks). |
| Perf budget | Preserve `xargs -P4 -n100` batching in `generate-kb-index.sh` | Script was optimized 33.6s → 1.27s in `2026-04-07-bash-file-processing-parallel-xargs-optimization.md`. Must stay under 5s pre-commit budget. |

## Open Questions

None blocking. Follow-on considerations (not in scope):

- Should Claude-ranked grep (top-5 reranking via haiku) be added after faceting ships? — **Defer** per issue; revisit only if users complain after faceting lands.
- Should the asymmetry between compound-capture's `problem_type` enum and general learnings' freeform `category` be reconciled? — **Not in this feature's scope**; file separately if it becomes friction.
- Should tags/categories be retroactively normalized? — **Defer**; warn-but-accept handles drift.

## Non-Goals

- No vector DB, no embeddings, no BM25 index
- No new runtime dependencies (stay on Node + Bash)
- No replacement of `grep` as the underlying search mechanism
- No strict enum validation of tag/category values
- No retroactive frontmatter cleanup across the learnings corpus
- No multi-tag OR/AND logic beyond a single `--tag` value

## Acceptance Criteria

From issue #2211, unchanged:

- [ ] `kb-search` accepts `--category` and `--tag` flags
- [ ] On miss, returns a warn-but-accept "did you mean?" suggestion sourced from `_tags.txt` / `_categories.txt` (case-insensitive)
- [ ] `scripts/generate-kb-index.sh` emits `_tags.txt` and `_categories.txt` as sibling artifacts
- [ ] Compound's Related Docs Finder (compound-capture Step 3) documents the faceted query pattern
- [ ] Documentation updated in `kb-search/SKILL.md`
- [ ] Index generation stays under 5s pre-commit budget (current: 1.27s)

## Effort Estimate

~5 hours. All changes stay in existing scripts and skill files. No migrations, no new dependencies.

## Reusable Patterns

- **awk frontmatter parsing**: `2026-03-12-directory-driven-content-discovery-frontmatter-parsing.md`
- **Parallel xargs for file processing**: `2026-04-07-bash-file-processing-parallel-xargs-optimization.md`
- **Bulk YAML migration pitfalls (schema drift tolerance)**: `2026-03-05-bulk-yaml-frontmatter-migration-patterns.md`
