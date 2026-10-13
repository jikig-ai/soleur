# Semantic Rule Matching Brainstorm

**Date:** 2026-03-30
**Issue:** #1304 (deferred from #451)
**Status:** Decided
**Participants:** Founder, CTO

## What We're Building

A new Phase 2.5 in `scripts/rule-audit.sh` that detects suspected duplicate rules across all governance layers using Jaccard word similarity with stopword removal. This catches rewording with shared vocabulary that exact substring matching misses.

## Why This Approach

The rule audit CI (#451, PR #1303) shipped with exact grep-based counting and hook-enforced annotation extraction. The current rule count (313) exceeds the CI threshold (300), meeting the re-evaluation trigger for cross-layer duplicate detection. The issue #1304 listed 400 as the threshold, but the actual CI implementation uses 300.

Jaccard word similarity is the simplest viable approach:

- Pure bash/awk — no dependencies, no API keys, no new CI secrets
- Fast at current scale (~100K pairwise comparisons complete in seconds)
- Catches the 80% case: rules restated with shared vocabulary across layers
- Known limitation: misses true semantic paraphrases with entirely different vocabulary

The Claude API approach (true semantic matching) was considered but deferred — it adds cost, API key management, and infrastructure complexity for a bi-weekly informational report. Jaccard validates the need first.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Integration point | `rule-audit.sh` Phase 2.5 | CI-only, no session-time cost. Compound Phase 1.5 deferred. |
| Algorithm | Jaccard coefficient on word tokens | Pure bash, no dependencies, fast. Archived spec (#12) validated this approach. |
| Stopword removal | Yes — filter common English words | Domain terms inflate Jaccard scores without stopword filtering. |
| Scope | All governance layers | AGENTS.md, constitution.md, agents/\*\*/\*.md, skills/\*/SKILL.md |
| Extraction method | `grep '^- '` across all files | Consistent bullet-point format across all layers. |
| Threshold | 0.6 (conservative) | Reduces false positives from shared domain vocabulary. Can tune later. |
| Suppression | Skip `[hook-enforced]` and `[skill-enforced]` pairs | Intentional cross-layer duplication (defense-in-depth) should not be flagged. |
| Output | "Suspected Duplicates" table in issue body | File, line number, Jaccard score, truncated rule text for each pair. |
| False positive strategy | Conservative threshold + suppression annotations | Accept some false negatives over noisy reports that train humans to ignore them. |

## Non-Goals

- True semantic matching via embeddings or LLM (deferred — layer on later if Jaccard proves insufficient)
- Compound Phase 1.5 integration (CI-only for now)
- Automated rule retirement or migration suggestions
- Merge UX for combining duplicate rules
- Threshold configuration via CLI flags

## Open Questions

- **Stopword list scope**: Use a standard English stopword list or a domain-specific one that also removes terms like "must", "should", "always", "never"? Likely need both — standard English + governance-specific modals.
- **Minimum rule length**: Should very short rules (< 5 words after stopword removal) be excluded from comparison to reduce noise?

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** CTO flagged false positive risk from shared domain vocabulary (worktree, commit, hook appear in many unrelated rules), the need to suppress intentional duplicates (`[hook-enforced]` annotations), and recommended validating the false negative rate manually before building. The threshold is already met (313 > 300), and Jaccard in pure bash addresses the dependency and infrastructure concerns. The CTO also suggested capturing this as an ADR if the approach proves its value.
