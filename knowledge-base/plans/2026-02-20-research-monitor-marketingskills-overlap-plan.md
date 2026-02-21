---
title: Monitor coreyhaines31/marketingskills for Growth Overlap
type: research
date: 2026-02-20
issue: "#165"
---

# Monitor coreyhaines31/marketingskills for Growth Overlap

## Overview

Evaluate the coreyhaines31/marketingskills community plugin (8.2K stars, 26 skills) against our 4 marketing agents + 3 growth skills. Document overlap, note any borrowable techniques, and suggest a monitoring cadence. Triggered by the landscape discovery audit (commit fdbcc1c).

## Problem Statement

Our growth-related components operate in the same space as marketingskills. Our differentiation (Eleventy-specific, AEO focus, brand voice enforcement, lifecycle integration) is strong today, but the community toolkit is maturing. Without periodic monitoring we risk building features the community already provides or missing useful patterns.

## Technical Approach

### Phase 1: Catalog marketingskills plugin

1. Browse `coreyhaines31/marketingskills` on GitHub
2. Catalog all 26 skills: name, description, core capability
3. Read prompts and code of 3-5 skills closest to our growth/SEO/content space to understand quality and approach (code review, not full execution -- no test environment setup)

### Phase 2: Overlap analysis and pattern identification

1. Create overlap matrix comparing their 26 skills to our 7 marketing/growth components

   | Their Skill | Our Equivalent | Overlap | Differentiation |
   |---|---|---|---|
   | content-strategy | growth-strategist | High | We have AEO + brand voice |
   | ... | ... | ... | ... |

   Overlap levels: **High** (same core function), **Medium** (partial), **Low** (tangential), **None** (unique to them).

2. For each High/Medium overlap, note what they do differently and whether convergence is likely
3. Flag any interesting patterns or techniques in a "Technique Opportunities" column -- if nothing surfaces, document "none identified"

### Phase 3: Write learning document

1. Write `knowledge-base/learnings/2026-02-20-marketingskills-overlap-analysis.md` with YAML frontmatter, overlap matrix, technique findings, and a suggested quarterly monitoring cadence
2. Update issue #165 with artifact links

## Acceptance Criteria

- [x] All 29 skills cataloged with name, description, capability summary
- [x] Overlap matrix comparing their 29 skills to our 7 marketing/growth components
- [x] 5 representative skills reviewed (code/prompts read, not executed)
- [x] 3 borrowable techniques documented with attribution
- [x] Quarterly monitoring cadence noted in learning document
- [x] Learning document written to `knowledge-base/learnings/`

## Non-Goals

- Installing marketingskills as a dependency
- Building automated monitoring tooling
- Adopting entire skills wholesale
- Creating new agents or skills for this

## Output Artifacts

1. **Learning document:** `knowledge-base/learnings/2026-02-20-marketingskills-overlap-analysis.md`
2. **Issue #165 updated** with completion status

## Version Bump

No plugin files modified. No version bump needed.

## References

- coreyhaines31/marketingskills: https://github.com/coreyhaines31/marketingskills
- Landscape audit: `knowledge-base/learnings/2026-02-19-full-landscape-discovery-audit.md`
- Related: #154 (CMO agent exploration), #165 (this issue)
