---
feature: feat-geo-aeo-research
plan: knowledge-base/plans/2026-02-20-feat-geo-aeo-methodology-plan.md
issue: "#164"
---

# Tasks: GEO/AEO Methodology Enhancement

## Phase 1: Core Implementation

### 1.1 Update growth-strategist agent with GEO techniques

- [ ] Rename AEO section heading to "GEO/AEO Content Audit"
- [ ] Add prioritization note (citations > statistics > quotations > definitions > readability; keyword stuffing negative)
- [ ] Add source citations check
- [ ] Add statistics and specificity check
- [ ] Update agent description frontmatter to mention GEO

### 1.2 Update seo-aeo-analyst agent with AI crawler access

- [ ] Update AI Discoverability row in checklist table to include robots.txt AI crawlers
- [ ] Add fourth bullet to Step 2 AI Discoverability for robots.txt AI bot verification
- [ ] Specify bot names: GPTBot, PerplexityBot, ClaudeBot, Google-Extended

### 1.3 Update validate-seo.sh with AI bot checks

- [ ] Add robots.txt existence check
- [ ] Add per-bot block detection with end-of-line anchored grep
- [ ] Add limitation comment about grep -A1 approach
- [ ] Verify script still exits 0 when all checks pass

### 1.4 Update growth skill Task prompts and descriptions

- [ ] Update `aeo` sub-command table description to mention GEO
- [ ] Update `aeo` sub-command Task prompt to include source citations and statistics checks
- [ ] Update `fix` sub-command Task prompt to mention GEO/AEO gaps

## Phase 2: Verification

### 2.1 Run tests and validate

- [ ] `bun test` passes
- [ ] validate-seo.sh works against a mock site directory
- [ ] Verify grep does not false-positive on partial paths like Disallow: /private/

## Phase 3: Ship

### 3.1 Version bump (PATCH)

- [ ] plugin.json version bumped
- [ ] CHANGELOG.md updated
- [ ] README.md counts verified (no new components, just modifications)
