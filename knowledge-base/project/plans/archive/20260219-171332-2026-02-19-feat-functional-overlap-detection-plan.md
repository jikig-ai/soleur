---
title: "feat: Extend agent-finder with functional overlap detection"
type: feat
date: 2026-02-19
issue: "#155"
version-bump: MINOR
---

# feat: Extend agent-finder with functional overlap detection

[Updated 2026-02-19 after plan review -- simplified from 6 phases to 3]

## Overview

Add functional overlap detection to the discovery system so community tools with similar capabilities are surfaced during planning, before redundant development begins. This complements the existing stack-gap detection (which checks for missing technology coverage) by checking for missing functional coverage.

## Problem Statement / Motivation

During growth-strategist development (#152), multiple community SEO/content-strategy tools existed across registries but weren't surfaced because the current discovery only checks `stack:` frontmatter gaps. This is a frequent pain point -- as the registry ecosystem grows, the cost of building something that already exists increases.

## Proposed Solution

Two changes:

1. **Functional-discovery agent** -- new agent that searches registries using the feature description, applies trust filtering, and presents install/skip results
2. **Plan command integration** -- Phase 1.5b in `/soleur:plan` spawns the new agent after the existing stack-gap check

## Technical Approach

### Architecture

```
/soleur:plan (Phase 1.5b)
         |
         v
  functional-discovery agent
         |
    (inline curl x3 registries, 5s timeout each)
         |
         v
  Trust filter + deduplicate + check already-installed
         |
         v
  Install / Skip per item
  (AskUserQuestion multiSelect, max 5 results)
```

### Implementation Phases

#### Phase 1: Functional-Discovery Agent

Create `plugins/soleur/agents/engineering/discovery/functional-discovery.md`.

**Frontmatter:** Must include name, description (third person), model field, and example block with user/assistant/commentary dialogue. Follow the exact format of `agent-finder.md`.

**Input from spawning command:**
- `feature_description`: the plan feature description text

**Agent flow:**

1. **Query registries:** Use the feature description as the search term. Query all 3 registries with inline curl commands (copy pattern from agent-finder Step 1). 5-second timeout per registry. Run all queries in parallel.

   Registries:
   - `api.claude-plugins.dev/api/skills/search?q=${QUERY}&limit=10`
   - `claudepluginhub.com/api/plugins?q=${QUERY}`
   - `raw.githubusercontent.com/anthropics/claude-plugins-official/main/.claude-plugin/marketplace.json` (filtered client-side)

2. **Trust filter:** Apply the same 3-tier model as agent-finder:
   - Tier 1 (Anthropic): always surface
   - Tier 2 (Verified / stars >= 10): always surface
   - Tier 3 (Community): discard

3. **Deduplicate:** By name + author (case-insensitive). If same artifact in multiple registries, keep highest-trust source.

4. **Check already installed:** Scan `plugins/soleur/agents/community/` and `plugins/soleur/skills/community-*/` for matching names. Filter out already-installed artifacts.

5. **Present results** (max 5): AskUserQuestion with multiSelect -- install/skip per item. Show name, source, trust tier, description (200 chars).

6. **Install approved:** Same flow as agent-finder Steps 4a-4d (fetch, validate, add provenance frontmatter, write to disk).

7. **Report:** Summary of results (N found, M installed, X skipped, registries queried Y/3).

**Error handling** (copy from agent-finder):
- Timeout or connection error: treat registry as zero results, continue with others
- HTTP 401/403: log warning, skip registry
- Malformed JSON: treat as zero results
- All registries fail: report "All registries unreachable. Continuing." and return
- Zero results after filtering: report "No community overlap found. Continuing." -- no user prompt

Files:
- Create: `plugins/soleur/agents/engineering/discovery/functional-discovery.md`

#### Phase 2: Integrate into Plan Command

Add Phase 1.5b to `commands/soleur/plan.md`, immediately after existing Phase 1.5 (stack-gap check).

**Phase 1.5b: Functional Overlap Check**

1. Extract the feature description from `<feature_description>` tag
2. Spawn functional-discovery agent:

```
Task functional-discovery: "Feature description: [text].
Search community registries for skills/agents with similar functionality
and present install/skip suggestions."
```

3. Handle results:
   - If artifacts installed: announce "Installed N community artifacts. They will be available in subsequent commands."
   - If all skipped or zero results: continue silently
   - If agent failed (network errors): continue silently (graceful degradation)

**Always runs** -- unlike Phase 1.5 which is conditional on stack gaps. Any feature could have community overlap regardless of technology stack. The 5-second timeout per registry keeps latency bounded.

Files:
- Modify: `plugins/soleur/commands/soleur/plan.md` (add Phase 1.5b section, ~25 lines)

#### Phase 3: Version Bump and Documentation

- MINOR version bump (new agent)
- Update `plugin.json`, `CHANGELOG.md`, `README.md` (plugin)
- Update root `README.md` badge
- Update `.github/ISSUE_TEMPLATE/bug_report.yml` placeholder
- Verify agent count in plugin.json description
- Note: agents auto-discover via `docs/_data/agents.js` filesystem walk -- no manual docs registration needed

Files:
- Modify: `plugins/soleur/.claude-plugin/plugin.json`
- Modify: `plugins/soleur/CHANGELOG.md`
- Modify: `plugins/soleur/README.md`
- Modify: `README.md` (root)
- Modify: `.github/ISSUE_TEMPLATE/bug_report.yml`

## Alternative Approaches Considered

1. **Shared registry query script** -- Extract curl logic into a bash script for both agents. Rejected: premature extraction with only one consumer. Defer to v2 if needed.
2. **Extend agent-finder instead of new agent** -- Add a second input parameter to agent-finder. Rejected: user chose clean separation during brainstorm. Different trigger mechanisms (file signatures vs. feature description) warrant separate agents.
3. **Brainstorm integration** -- Add informational check during brainstorm Phase 1.1. Deferred to v2: the pain point (#152) was during planning, and "inform-only" mode adds noise without actionable output.
4. **LLM query generation** -- Have the LLM generate 2-3 focused queries instead of using the raw description. Deferred to v2: the fallback (raw description) is simpler and has fewer failure modes. If search quality is poor, add query generation later.

## Acceptance Criteria

- [ ] `functional-discovery.md` agent queries 3 registries using the feature description
- [ ] Results filtered by trust tier, deduplicated, already-installed filtered out
- [ ] Install/skip presented via AskUserQuestion (max 5 results, multiSelect)
- [ ] Approved artifacts installed with provenance frontmatter
- [ ] `/soleur:plan` Phase 1.5b spawns functional-discovery after stack-gap check
- [ ] Existing stack-gap detection (Phase 1.5) continues working unchanged
- [ ] Registry failures produce warnings, never block workflows
- [ ] Agent frontmatter includes example block with user/assistant/commentary
- [ ] Version bumped, CHANGELOG/README updated

## Test Scenarios

- Given a feature description "build a content strategy skill", when functional-discovery runs during plan, then community content-strategy tools from registries are surfaced with install/skip options
- Given a feature description with no community overlap (e.g., "add internal project config"), when functional-discovery runs, then "No community overlap found" is reported and planning continues
- Given all 3 registries are unreachable, when functional-discovery runs, then a warning is logged and planning continues unblocked
- Given 1 of 3 registries times out, when functional-discovery runs, then results from the 2 available registries are presented
- Given an already-installed community plugin matches a search result, when results are presented, then the already-installed plugin is filtered out
- Given a result appears in 2 registries with different trust tiers, when deduplication runs, then the highest-trust version is kept

## Dependencies & Risks

**Dependencies:**
- Registry APIs (`api.claude-plugins.dev`, `claudepluginhub.com`) must remain available and maintain current response formats
- Anthropic marketplace JSON must remain at current GitHub raw URL

**Risks:**
- Registry search with raw feature descriptions may yield noisy results (mitigated: trust filtering removes low-quality; v2 can add LLM query generation)
- Always-on check adds latency to every plan run (mitigated: 5s timeout, parallel with other plan steps)

## Non-Goals

- Replacing existing stack-gap detection in agent-finder
- Auto-installing without user consent
- NLP/embedding-based similarity scoring
- Shared registry script extraction (v2)
- Brainstorm integration (v2)
- LLM query generation (v2)
- Cross-phase state persistence
- Retry logic for failed registries

## References & Research

- Current agent-finder: `plugins/soleur/agents/engineering/discovery/agent-finder.md`
- Plan command Phase 1.5: `plugins/soleur/commands/soleur/plan.md:131-172`
- Triggering issue: #155, triggered by #152 (growth-strategist)
- Prior agent-finder work: PR #130, issue #55
- Learning: skill-creator overlap (`knowledge-base/learnings/technical-debt/2026-02-12-skill-creator-overlap.md`)
- Learning: plan review catches consolidation (`knowledge-base/learnings/workflow-patterns/2026-02-14-plan-review-agent-consolidation.md`)
- Learning: external agent discovery patterns (`knowledge-base/learnings/implementation-patterns/2026-02-18-external-agent-discovery-plugin-loader-patterns.md`)
