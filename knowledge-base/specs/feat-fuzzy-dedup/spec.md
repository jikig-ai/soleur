# Fuzzy Deduplication for /sync Command

**Feature:** feat-fuzzy-dedup
**Created:** 2026-02-06
**Status:** Draft (v1 - Simplified)
**GitHub Issue:** #12

## Problem Statement

The `/sync` command currently only detects exact duplicates when adding new entries to the knowledge-base. Near-duplicates like "use const" vs "prefer const over let" slip through review.

## Goals

1. Detect near-duplicate findings using word-based similarity
2. Prompt user to skip duplicates before standard review
3. Keep implementation simple (~50 lines in sync.md)

## Non-Goals (Deferred to v2+)

- Semantic/embedding-based similarity (Claude lacks embed endpoint)
- Clustering/grouping multiple similar items
- CLI flags for threshold configuration
- Merge UX (combining entries into one)
- Caching embeddings or similarity results
- Existing-vs-existing comparison
- New skill directory or TypeScript files

## Functional Requirements

| ID | Requirement |
|----|-------------|
| FR1 | Compute word-based Jaccard similarity between new findings and existing entries |
| FR2 | Prompt user when similarity > 0.8 threshold |
| FR3 | Allow user to Skip (discard) or Keep (proceed to Accept/Skip/Edit) |
| FR4 | Apply to constitution.md rules and learnings files |

## Technical Requirements

| ID | Requirement |
|----|-------------|
| TR1 | Implement inline in sync.md (no new files) |
| TR2 | Use Jaccard coefficient on word tokens |
| TR3 | Hardcode 0.8 threshold |
| TR4 | Complete check in <5 seconds for typical knowledge-base |

## User Story

**As a** developer running `/sync`
**I want** to be alerted when a finding looks similar to something existing
**So that** I can avoid adding redundant rules

**Acceptance criteria:**
- Findings with >0.8 word similarity show "Skip duplicate?" prompt
- User can skip or proceed to standard review
- Dissimilar findings proceed directly to Accept/Skip/Edit

## Technical Design

### Jaccard Similarity

```
jaccard(a, b) = |intersection(words_a, words_b)| / |union(words_a, words_b)|
```

- Tokenize by whitespace
- Lowercase all tokens
- Compare word sets

### Integration Point

Modify sync.md Phase 2 (Review):
1. Before presenting finding, compute similarity against existing entries
2. If max similarity > 0.8, show duplicate prompt
3. If user skips, continue to next finding
4. If user keeps, proceed with Accept/Skip/Edit

## Open Questions (Resolved)

1. ~~Embedding approach~~ - Deferred. String similarity is sufficient for v1.
2. ~~Merge strategy~~ - Deferred. Just skip or don't skip.
3. ~~CLI flags~~ - Deferred. Hardcode sensible defaults.

## References

- [GitHub Issue #12](https://github.com/jikig-ai/soleur/issues/12)
- [Brainstorm Document](../../brainstorms/2026-02-06-fuzzy-deduplication-brainstorm.md)
- [Implementation Plan](../../plans/2026-02-06-feat-fuzzy-deduplication-plan.md)
