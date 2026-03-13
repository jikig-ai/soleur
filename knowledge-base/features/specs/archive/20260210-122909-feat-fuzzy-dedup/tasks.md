# Tasks: Fuzzy Deduplication for /sync Command

**Feature:** feat-fuzzy-dedup
**Plan:** [2026-02-06-feat-fuzzy-deduplication-plan.md](../../plans/2026-02-06-feat-fuzzy-deduplication-plan.md)

## Implementation Tasks

### 1. Add Similarity Check to sync.md

- [x] 1.1 Add Jaccard similarity instruction
  - Define word-based Jaccard coefficient calculation
  - Tokenize by whitespace, lowercase
  - Return similarity as decimal 0.0-1.0

- [x] 1.2 Load existing entries before Review phase
  - Parse constitution.md rules (bullet points under Always/Never/Prefer)
  - List learnings files and extract titles/content

- [x] 1.3 Add similarity check in Review loop
  - For each new finding, compute Jaccard against all existing entries
  - Track most similar entry and its score

- [x] 1.4 Add "Skip duplicate?" prompt
  - If similarity > 0.8, show new finding and similar existing entry
  - Use AskUserQuestion with Skip/Keep options
  - If Skip, continue to next finding without Accept/Skip/Edit

### 2. Testing

- [ ] 2.1 Test similar finding detection
  - Create knowledge-base with rule "Prefer const over let"
  - Run /sync with finding "Use const instead of let"
  - Verify duplicate prompt appears

- [ ] 2.2 Test Skip action
  - Select Skip when prompted
  - Verify finding is not written to knowledge-base

- [ ] 2.3 Test Keep action
  - Select Keep when prompted
  - Verify standard Accept/Skip/Edit flow continues

- [ ] 2.4 Test dissimilar findings
  - Run /sync with finding unrelated to existing rules
  - Verify no duplicate prompt, standard flow proceeds

### 3. Documentation

- [x] 3.1 Update plugin.json version (MINOR bump to 1.5.0)
- [x] 3.2 Add CHANGELOG.md entry
- [x] 3.3 Update README.md if needed (no changes needed)

## Acceptance Scenarios

### Scenario 1: Similar Finding Detected

```
Given: constitution.md has rule "Prefer const over let"
And: /sync finds "Use const instead of let for immutables"
When: Review phase begins
Then: Prompt shows both texts
And: User asked "Skip this duplicate?"
```

### Scenario 2: User Skips Duplicate

```
Given: Duplicate prompt is shown
When: User selects "Skip"
Then: Finding is not added to knowledge-base
And: Next finding is presented
```

### Scenario 3: User Keeps Finding

```
Given: Duplicate prompt is shown
When: User selects "Keep"
Then: Standard Accept/Skip/Edit options are shown
And: User can proceed to add the finding
```

### Scenario 4: No Duplicates Found

```
Given: New finding has <0.8 similarity to all existing entries
When: Review phase processes finding
Then: No duplicate prompt shown
And: Standard Accept/Skip/Edit flow proceeds
```

## Deferred (v2+)

Per reviewer feedback, these are explicitly out of scope:

- Semantic/embedding-based similarity
- CLI flags (--similarity-threshold, --full-dedup, --skip-dedup)
- Clustering/grouping of multiple similar items
- Merge UX (combining entries)
- Caching
- Existing-vs-existing comparison
