---
title: kb-search frontmatter faceting
date: 2026-04-14
issue: 2211
branch: feat-kb-search-faceting
status: draft
---

# Spec: kb-search Frontmatter Faceting

## Problem Statement

The `kb-search` skill is grep-only across `knowledge-base/`. On the learnings corpus (386 files, 1.9 MB), grep is fast (~15 ms) but returns noisy result sets when cross-referencing during `/compound`. Agents waste tokens filtering irrelevant matches. The real friction is result-set noise, not query latency — vector/BM25 approaches are overkill at this corpus size and carry high adoption cost.

Learning files already carry validated YAML frontmatter (`tags`, `category`) but no existing tooling consumes those fields for filtering.

## Goals

1. Agents can filter `kb-search` results by `--tag` and `--category` before grep runs, cutting noise in related-docs lookups.
2. When an agent passes an invalid tag/category, they get a "did you mean?" hint in one round-trip (token-efficient).
3. The existing `/kb-search <keyword>` plain path stays unchanged — no breaking change.
4. Compound's Related Docs Finder documents the faceted-query pattern so future invocations use it when applicable.
5. Index generation stays under the pre-commit perf budget (currently 1.27s).

## Non-Goals

- No vector DB, embeddings, or BM25 index.
- No new runtime dependencies (stay on Node + Bash).
- No replacement of `grep` as the underlying search mechanism.
- No strict enum enforcement of tag/category values.
- No retroactive normalization of existing learning frontmatter.
- No multi-tag OR/AND logic beyond a single `--tag` value per query.

## Functional Requirements

- **FR1** — `kb-search` accepts `--tag <value>` flag. Matches files where the frontmatter `tags:` array contains `<value>` (case-insensitive).
- **FR2** — `kb-search` accepts `--category <value>` flag. Matches files where frontmatter `category:` equals `<value>` (case-insensitive).
- **FR3** — `--tag` and `--category` can combine with each other and with a positional keyword argument (AND semantics). Example: `/kb-search --category performance-issues csrf`.
- **FR4** — When `--tag` or `--category` is passed with a value not present in the autocomplete artifacts, the skill returns: (a) an empty result block AND (b) a "did you mean?" line listing the top-3 closest existing values by Levenshtein or substring match.
- **FR5** — When `--tag` or `--category` matches, the skill returns matching files in the same format as the existing keyword search output (title + path).
- **FR6** — `scripts/generate-kb-index.sh` emits two sibling artifacts: `knowledge-base/_tags.txt` and `knowledge-base/_categories.txt`. Each contains sorted unique values, one per line, lowercased.
- **FR7** — `kb-search` SKILL.md documents both flags with at least one example per flag plus one combined example.
- **FR8** — `compound-capture/SKILL.md` Step 3 documents the faceted-query pattern and when to prefer it over raw grep.

## Technical Requirements

- **TR1** — Frontmatter parsing reuses the established `awk '/^---$/{c++; next} c==1'` idiom (per `2026-03-12-directory-driven-content-discovery-frontmatter-parsing.md`). No new YAML dependency. No `sed` range expressions (known-broken with body `---`).
- **TR2** — `generate-kb-index.sh` extension must preserve the existing `xargs -P4 -n100` parallel batching (per `2026-04-07-bash-file-processing-parallel-xargs-optimization.md`). Total runtime must stay under 5s on the current corpus (baseline: 1.27s).
- **TR3** — Tag/category matching is case-insensitive via lowercasing both the user input and the stored values at comparison time.
- **TR4** — Autocomplete artifacts (`_tags.txt`, `_categories.txt`) must be under 5 KB each at current corpus size. They are committed to git (regenerated deterministically).
- **TR5** — `kb-search` behaves identically to current behavior when no `--tag`/`--category` flag is passed. No new runtime dependencies reachable from the default path.
- **TR6** — Tolerate known corpus drift: learnings with missing or malformed `tags:`/`category:` fields are silently skipped during index generation, not errored (per `2026-03-05-bulk-yaml-frontmatter-migration-patterns.md`).

## Out of Scope (tracked elsewhere if needed)

- Reconciling the `problem_type` enum (compound-capture) vs freeform `category` (general learnings) asymmetry.
- Claude-ranked grep / haiku reranking over the top-N results.
- Per-file reverse lookup index (tag → list of files) for faster agent traversal.
- Retroactive normalization pass across existing learning frontmatter.

## Test Scenarios

- **TS1** — `/kb-search --tag eager-loading n+1` returns only learnings with `eager-loading` in frontmatter tags AND matching `n+1` content.
- **TS2** — `/kb-search --category performance-issues csrf` filters to performance-issues category first.
- **TS3** — `/kb-search --tag EAGER-LOADING n+1` (uppercase) returns the same results as TS1 (case-insensitive).
- **TS4** — `/kb-search --tag nonexistent-xyz` returns empty results plus a "did you mean?" line listing 3 closest existing tags.
- **TS5** — `/kb-search csrf` (no flags) behaves identically to pre-change kb-search.
- **TS6** — `scripts/generate-kb-index.sh` produces `_tags.txt` and `_categories.txt` with sorted unique lowercased values, and runtime stays under 5s.
- **TS7** — A malformed learning file (missing `tags:` field) does not break index generation; it is skipped silently.

## Acceptance Criteria (from #2211)

- [ ] `kb-search` accepts `--category` and `--tag` flags
- [ ] On miss, warn-but-accept "did you mean?" from `_tags.txt` / `_categories.txt` (case-insensitive)
- [ ] `scripts/generate-kb-index.sh` emits `_tags.txt` and `_categories.txt` as sibling artifacts
- [ ] Compound's Related Docs Finder documents the faceted query pattern
- [ ] Documentation updated in `kb-search/SKILL.md`
- [ ] Index generation stays under 5s pre-commit budget (current: 1.27s)

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-04-14-kb-search-faceting-brainstorm.md`
- Existing skill: `plugins/soleur/skills/kb-search/SKILL.md`
- Index generator: `scripts/generate-kb-index.sh`
- Frontmatter schema: `plugins/soleur/skills/compound-capture/references/yaml-schema.md`
- Related docs finder: `plugins/soleur/skills/compound-capture/SKILL.md` (Step 3)
- Reusable awk idiom: `knowledge-base/project/learnings/2026-03-12-directory-driven-content-discovery-frontmatter-parsing.md`
- Perf pattern: `knowledge-base/project/learnings/2026-04-07-bash-file-processing-parallel-xargs-optimization.md`
- Schema drift tolerance: `knowledge-base/project/learnings/2026-03-05-bulk-yaml-frontmatter-migration-patterns.md`
