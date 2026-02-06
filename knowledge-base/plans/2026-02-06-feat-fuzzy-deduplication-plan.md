---
title: "feat: Fuzzy deduplication for /sync command"
type: feat
date: 2026-02-06
---

# feat: Fuzzy Deduplication for /sync Command

## Overview

Add near-duplicate detection to the `/sync` command using simple word-based similarity. When a new finding is similar to an existing entry, prompt the user to skip it.

## Problem Statement

The `/sync` command only detects exact duplicates (sync.md:119-124). Near-duplicates like "use const" vs "prefer const over let" slip through, causing redundant rules to accumulate.

## Proposed Solution

Add ~50 lines to sync.md's Review phase. Before presenting each finding, check if it's similar to any existing entry. If similarity > 0.8, show both and ask "Skip this duplicate? (y/n)".

**No new files. No new dependencies. No CLI flags.**

```
Phase 2: Review
    ↓
    For each finding:
      1. Compute Jaccard similarity against existing entries
      2. If any similarity > 0.8:
         - Show: "This looks similar to: [existing]"
         - Ask: "Skip? (y/n)"
      3. If not skipped, proceed with Accept/Skip/Edit as usual
```

## Technical Design

### Jaccard Similarity

Word-based Jaccard coefficient on lowercased text:

```
jaccard(a, b) = |intersection(words_a, words_b)| / |union(words_a, words_b)|
```

**Why Jaccard:**
- Simple to implement (5-10 lines)
- Catches textual variations ("use const" vs "always use const")
- No external dependencies
- Fast enough for <100 entries

### Comparison Scope

- New findings vs existing constitution rules (same section)
- New findings vs existing learnings
- No existing-vs-existing (users can run manually if needed)

### Threshold

Hardcoded at 0.8. Tuned through testing:
- 0.8 catches obvious rewording
- Low false positive rate on intentionally different rules

## Acceptance Criteria

- [x] New findings are checked against existing entries before review
- [x] Similar findings (>0.8 Jaccard) prompt "Skip this duplicate?"
- [x] User can skip or proceed with standard Accept/Skip/Edit flow
- [x] No new files created
- [x] No new CLI flags
- [ ] Completes in <5 seconds for typical knowledge-base (to verify at runtime)

## Implementation

### Changes to sync.md

**Location:** `plugins/soleur/commands/soleur/sync.md`

**Additions (~50 lines):**

1. Add Jaccard similarity function definition (agent instruction)
2. Before Review loop, load existing entries
3. In Review loop, add similarity check before presenting finding
4. Add "Skip duplicate?" prompt with AskUserQuestion

### Pseudocode

```markdown
## Phase 2: Review

Before presenting findings, load existing entries:
- Parse constitution.md for rules (bullet points under Always/Never/Prefer)
- List learnings files and extract titles

For each finding:
  1. Compute Jaccard similarity against existing entries
  2. Find most similar existing entry

  If similarity > 0.8:
    Present: "This finding looks similar to an existing entry."
    Show: [new finding text]
    Show: "Similar to: [existing entry text]"
    Use AskUserQuestion: "Skip this duplicate?" with options:
      - Skip (don't add)
      - Keep (proceed to Accept/Skip/Edit)

    If user chooses Skip, continue to next finding

  3. Present finding with Accept/Skip/Edit options (existing flow)
```

## What This Does NOT Include (v1 Scope)

Per reviewer feedback, these are deferred:

- **Embeddings/semantic similarity:** Claude doesn't have an embed endpoint. String similarity catches 90%+ of real duplicates.
- **Clustering:** Pairwise comparison is sufficient. No union-find.
- **CLI flags:** Sensible defaults. Add flags only if users request.
- **Caching:** No performance problem to solve at <100 entries.
- **New skill directory:** Inline in sync.md where it belongs.
- **Full dedup (existing-vs-existing):** Users can manually review.
- **Merge UX:** Just skip or don't skip. Merging adds complexity.

## Success Criteria

- Catches textual variations ("use const" vs "always use const")
- No false positives on intentionally different rules
- Zero new dependencies
- Implementation fits in ~50 lines of sync.md additions

## Testing

1. Run /sync with a finding similar to existing rule
2. Verify prompt appears with both texts
3. Verify "Skip" removes finding from review
4. Verify "Keep" proceeds to standard Accept/Skip/Edit
5. Verify dissimilar findings don't trigger prompt

## References

- GitHub Issue: #12
- Brainstorm: `knowledge-base/brainstorms/2026-02-06-fuzzy-deduplication-brainstorm.md`
- Spec: `knowledge-base/specs/feat-fuzzy-dedup/spec.md`
- Current sync: `plugins/soleur/commands/soleur/sync.md:119-124`
