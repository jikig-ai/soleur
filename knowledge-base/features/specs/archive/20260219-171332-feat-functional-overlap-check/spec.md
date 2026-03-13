# Spec: Functional Overlap Detection

**Issue:** #155
**Branch:** feat-functional-overlap-check
**Date:** 2026-02-19

## Problem Statement

The agent-finder detects stack gaps (missing technology coverage) but not functional overlap (community tools that do what you're about to build). This leads to redundant development when community registries already have relevant skills/agents.

## Goals

- G1: Surface functionally similar community tools during brainstorm (informational)
- G2: Surface functionally similar community tools during plan with install/skip actions
- G3: Share registry query infrastructure between agent-finder and the new discovery agent
- G4: Maintain graceful degradation -- registry failures never block workflows

## Non-Goals

- Replacing existing stack-gap detection in agent-finder
- Auto-installing community tools without user consent
- Building NLP/embedding-based similarity scoring
- Adding inspect/reference actions (install/skip only)

## Functional Requirements

- FR1: New `functional-discovery` agent in `agents/engineering/discovery/`
- FR2: Agent accepts feature description text, generates 2-3 search queries, queries registries
- FR3: Results filtered through existing trust model (Tier 1: Anthropic, Tier 2: Verified, Tier 3: Discard)
- FR4: Brainstorm integration: light check in Phase 1.1, results shown as context alongside repo research
- FR5: Plan integration: Phase 1.5b after stack-gap check, install/skip flow via AskUserQuestion
- FR6: Shared registry query script extracted from agent-finder, callable by both agents

## Technical Requirements

- TR1: Registry APIs: api.claude-plugins.dev (`/api/skills/search?q=`), claudepluginhub.com (`/api/plugins?q=`), Anthropic marketplace JSON
- TR2: 5-second timeout per registry query (consistent with agent-finder)
- TR3: Max 5 suggestions presented per check (consistent with agent-finder)
- TR4: Deduplication across registries by name+author key (consistent with agent-finder)

## Files to Create/Modify

### New files
- `agents/engineering/discovery/functional-discovery.md` -- new agent
- `skills/agent-finder/scripts/registry-query.sh` (or similar) -- shared registry infrastructure

### Modified files
- `agents/engineering/discovery/agent-finder.md` -- refactor to use shared script
- `commands/soleur/plan.md` -- add Phase 1.5b functional overlap check
- `commands/soleur/brainstorm.md` -- add light check in Phase 1.1

## Acceptance Criteria

- [ ] Running `/soleur:brainstorm` on "build a content strategy skill" surfaces community content-strategy tools
- [ ] Running `/soleur:plan` on the same topic offers install/skip for found tools
- [ ] Stack-gap detection continues working unchanged
- [ ] Registry failures produce warnings, not errors
- [ ] Plugin version bumped, CHANGELOG and README updated
