---
title: "feat: Jaccard word similarity for cross-layer rule duplication detection"
type: feat
date: 2026-03-30
---

# feat: Jaccard Word Similarity for Cross-Layer Rule Duplication Detection

[Updated 2026-03-30 — scope reduced from all governance layers to AGENTS.md vs constitution.md per plan review consensus]

## Overview

Add Phase 2.5 to `scripts/rule-audit.sh` that detects suspected duplicate rules between AGENTS.md and constitution.md using Jaccard word similarity with stopword removal. Reports findings in the bi-weekly rule audit issue.

## Problem Statement / Motivation

The rule audit CI (#451, PR #1303) counts rules and validates hook-enforced annotations but cannot detect paraphrased duplicates across governance layers. At 313 always-loaded rules (exceeding the 300 CI threshold), cross-layer duplication from rewording is increasingly likely. Exact substring matching misses rules like "Never commit directly to main" vs "Do not commit to main branch."

## Proposed Solution

Add an inline `detect_duplicates()` function to `rule-audit.sh` that computes Jaccard coefficient on stopword-filtered word tokens between AGENTS.md and constitution.md rules. Uses the existing `comm -12` pattern from `stop-hook.sh:222-258`. Emits a markdown table of suspected duplicates (score >= 0.6) for inclusion in the issue body.

## Technical Considerations

### Scale

Scoped to always-loaded rules only (Tier 2-3). Agent/skill rules (Tier 4-5) are loaded on-demand — duplicates there don't cost context tokens.

| Layer | Rules |
|-------|-------|
| AGENTS.md | 63 |
| constitution.md | 251 |
| **Pairs** | **~15,800** |

15,800 comparisons complete trivially in bash with `comm -12` — no performance concerns.

### Why NOT agent/skill files

Agent descriptions (Tier 4) and skill instructions (Tier 5) are loaded on-demand. Cross-layer duplication between them is intentional context locality — you WANT a skill to restate relevant rules so the agent has them when invoked. Scanning them detects a different class of problem (stale copies) that can be addressed in a follow-up if needed.

### Stopword Strategy

Strip only articles, prepositions, pronouns, and conjunctions (~20 words). **Do NOT strip governance modals** (never, always, must, should) — these carry polarity. "Never push before merging" and "Always push before merging" are contradictory rules that would appear identical if modals are removed.

Stopword list: `a an the is are was were be been to of in for on at by with from as and or but if it its this that these those he she they them their what which who whom do does did not`

### Bash Pitfalls (from learnings)

- `grep '^- '` in a pipeline under `set -euo pipefail` exits 1 when no matches — append `|| true` (learning: `2026-03-03-set-euo-pipefail-upgrade-pitfalls`)
- `(( count++ ))` when count=0 exits 1 under `set -e` — use `count=$((count + 1))` (same learning)
- Rule text contains colons extensively — parse `grep -Hn` output as `field1:field2:everything_else`, not split on all colons

### Input Format

`grep -Hn '^- '` produces `filepath:lineno:rule_text` (colon-delimited). Since rule text contains colons, preprocess to TAB-delimited format:

```bash
grep -Hn '^- ' "$file" | sed "s|^$REPO_ROOT/||" | sed 's/^\([^:]*\):\([^:]*\):/\1\t\2\t/' > "$output"
```

This also relativizes paths for readable output in GitHub issues.

### Multi-line Rules

AGENTS.md rules often span multiple lines with `**Why:**` continuations. `grep '^- '` captures only the first line. This is acceptable — the rationale text is unique per rule and would dilute similarity scores.

### Known Limitation

Extraction pattern `^-` misses numbered list rules. This is acceptable for v1 as governance rules in AGENTS.md and constitution.md use bullet format exclusively.

## Implementation

### detect_duplicates() function

Add to `rule-audit.sh` (~30 lines) using the `comm -12` pattern from `stop-hook.sh:222-258`:

1. Extract `^-` rules from AGENTS.md and constitution.md with line numbers
2. For each AGENTS.md rule × constitution.md rule pair:
   - Tokenize both: lowercase, strip punctuation, remove stopwords
   - Skip if either has < 4 content words
   - Compute Jaccard via `comm -12` on sorted word lists
   - If score >= 0.6, add to results
3. Sort results by score descending
4. Format as markdown table

### Integration point

Insert Phase 2.5 between Phase 2 (hook extraction, ends at line ~106) and Phase 3 (issue body, starts at line ~108). Add "Suspected Duplicates" table to issue body after the broken hook references section (line ~160), before the Tier Model reference (line ~162).

## Alternative Approaches Considered

| Approach | Verdict | Rationale |
|----------|---------|-----------|
| Standalone awk script | Rejected (plan review) | Overkill for 15K pairs. Inline bash function is proportionate. |
| Full agent/skill scope | Rejected (plan review) | Tier 4-5 rules are on-demand; duplicates are intentional locality. |
| Claude API (semantic) | Deferred | Adds API key + cost for a bi-weekly informational report. |
| Embeddings (OpenAI) | Deferred | New vendor dependency. |
| Compound Phase 1.5 | Deferred | CI-only validates the approach first. |

## Acceptance Criteria

- [x] `detect_duplicates()` function added to `rule-audit.sh`
- [x] Compares AGENTS.md rules vs constitution.md rules using Jaccard on stopword-filtered tokens
- [x] Pairs with score >= 0.6 appear in a "Suspected Duplicates" markdown table in the issue body
- [x] Rules with < 4 content words after stopword removal are excluded
- [x] Dry-run mode (no `GH_TOKEN`) outputs the duplicates table to stdout
- [x] `rule-audit.yml` workflow requires no secret or permission changes
- [x] All tests pass

## Test Scenarios

### Acceptance Tests

- Given two rules "Never commit directly to main" and "Do not commit to main branch" in AGENTS.md and constitution.md respectively, when Jaccard is computed with stopwords removed, then score >= 0.6 and the pair appears in output
- Given two unrelated rules with Jaccard < 0.6, when comparison runs, then the pair does not appear (true negative)
- Given a rule containing colons (e.g., `Priority chain: (1) MCP tools, (2) CLI`), when input is parsed, then the rule text is not truncated at the first colon

### Edge Cases

- Given an empty governance file (0 rules), when extraction runs, then no errors occur
- Given a rule that has < 4 content words after stopword removal, when tokenization runs, then it is excluded

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO) — carry-forward from brainstorm

**Status:** reviewed
**Assessment:** CTO flagged false positive risk from shared domain vocabulary and recommended validating the approach before expanding scope. No architecture concerns with the chosen approach (pure bash, no new dependencies, no CI secret changes).

No Product/UX Gate — internal CI tooling with no user-facing impact.

## Dependencies & Risks

| Risk | Mitigation |
|------|------------|
| False positives from shared domain vocabulary | Conservative 0.6 threshold, keep polarity modals in comparison |
| Noisy reports train humans to ignore | Start conservative, tune threshold based on first few audit cycles |
| Colon parsing in rule text | TAB-delimited preprocessing avoids colon splitting |

## Success Metrics

- First bi-weekly run produces a non-empty "Suspected Duplicates" table with plausible matches
- False positive rate < 30% (assessed manually over first 3 cycles)
- Identifies at least 1 genuine cross-layer duplicate that can be consolidated

## References & Research

### Internal References

- Existing Jaccard implementation: `plugins/soleur/hooks/stop-hook.sh:222-258`
- Rule-audit script: `scripts/rule-audit.sh` (Phase 2.5 insertion after line 106)
- Issue body insertion: `scripts/rule-audit.sh:160-162`
- CI workflow: `.github/workflows/rule-audit.yml`
- Brainstorm: `knowledge-base/project/brainstorms/2026-03-30-semantic-rule-matching-brainstorm.md`

### Related Work

- Parent issue: #451 (rule audit CI — closed, implemented)
- Feature issue: #1304 (semantic rule matching)
- PR: #1303 (rule audit CI implementation)
