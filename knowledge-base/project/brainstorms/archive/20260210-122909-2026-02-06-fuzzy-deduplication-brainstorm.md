# Fuzzy Deduplication for /sync Command

**Date:** 2026-02-06
**Status:** Ready for planning
**GitHub Issue:** #12

## What We're Building

Enhance the `/sync` command to detect **near-duplicate** entries, not just exact matches. The feature will:

1. **Detect similarity** using a hybrid approach: string similarity (Jaccard on n-grams) as a fast first pass, then Claude embeddings for semantic matching on uncertain candidates
2. **Group similar findings** together for user review
3. **Apply to both** new findings AND existing knowledge-base entries (full dedup)
4. **Present merge options**: merge into single entry, keep separate, or skip all

## Why This Approach

### Hybrid Similarity (String + Embeddings)

**Decision:** Use Jaccard similarity first, Claude embeddings for candidates above a low threshold.

**Rationale:**
- String similarity catches obvious textual variations cheaply (zero API cost)
- Embeddings handle semantic duplicates that string matching misses
- Cost-efficient: only call embedding API for ~10-20% of comparisons
- No new dependencies - Claude API already required for the agent

**Alternatives considered:**
- Embeddings-first: More accurate but slower and costly for large knowledge-bases
- String-only: Fast but misses semantic duplicates ("use const" vs "prefer const over let")

### Grouped Presentation UX

**Decision:** Show clusters of similar items together in the review phase.

**Rationale:**
- Natural mental model for users (see all related items at once)
- Enables "merge" action that combines similar rules
- Fits the existing review flow (Phase 2 of /sync)

### Configurable Threshold

**Decision:** CLI flag `--similarity-threshold 0.8` with sensible default.

**Rationale:**
- Different projects have different tolerance for "similar"
- Allows tuning without code changes
- Default 0.8 works for most cases (from testing)

### Full Dedup Scope

**Decision:** Detect duplicates within existing knowledge-base entries too.

**Rationale:**
- Knowledge-base accumulates cruft over time
- Users want to clean up existing duplicates, not just prevent new ones
- Adds modest complexity but high value

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Similarity method | Hybrid (string + embeddings) | Balance cost, speed, accuracy |
| String algorithm | Jaccard on word n-grams | Simple, effective for text |
| Embedding source | Claude API | No new dependencies |
| UX flow | Grouped presentation | Natural clustering, merge support |
| Threshold | Configurable (default 0.8) | Flexibility without code changes |
| Scope | Full dedup (new + existing) | Clean up accumulated cruft |

## Open Questions

1. **Embedding caching:** Should we cache embeddings for existing entries to avoid re-computing on every run? Likely yes for performance.

2. **Merge strategy:** When merging similar rules, which one becomes the "canonical" version? Options:
   - User picks during review
   - AI suggests best wording
   - Keep the longer/more detailed one

3. **Performance at scale:** For large knowledge-bases (1000+ entries), should we add a `--skip-dedup` flag for faster runs?

## Success Criteria

- [ ] Near-duplicate detection with configurable threshold
- [ ] Grouped presentation in review phase
- [ ] Merge, keep-separate, and skip-all actions
- [ ] No false positives on intentionally different rules
- [ ] Runs in <30 seconds for typical knowledge-base (<100 entries)

## Next Steps

Run `/soleur:plan` to create implementation tasks.
