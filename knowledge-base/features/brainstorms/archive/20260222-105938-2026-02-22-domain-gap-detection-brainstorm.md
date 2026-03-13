# Brainstorm: Domain Leader Capability Gap Detection

**Date:** 2026-02-22
**Issue:** #234
**Status:** Complete
**Approach:** Lightweight prompt addition (Option A)

## What We're Building

Adding capability gap detection to all 5 domain leader agents (CTO, CMO, COO, CPO, CLO) during brainstorm participation. Each domain leader will include a dedicated "Capability Gaps" section in their assessment output, identifying missing agents or skills needed for the proposed work.

The brainstorm command will consolidate all domain leader gaps into a single "Capability Gaps" section in the brainstorm document. The `/plan` command Phase 1.5 will reference this consolidated list to prioritize registry searches via `agent-finder` and `functional-discovery`.

This is advisory only -- no agents/skills are installed during brainstorm. Installation remains in `/plan` Phase 1.5 where it already works.

## Why This Approach

- **YAGNI:** Brainstorm is about WHAT to build, not HOW. Agent installation is operational and belongs in planning.
- **Infrastructure exists:** `agent-finder` and `functional-discovery` already handle registry queries, trust filtering, and installation during `/plan` Phase 1.5/1.5b.
- **Session boundary:** Plugin loader discovers agents at session start. Mid-session installs are invisible until restart, making brainstorm-time installation impractical.
- **Simplicity:** ~10 lines added per domain leader, ~15 lines in brainstorm command, ~5 lines in plan command. No new agents, skills, or infrastructure.
- **LLM-native:** Domain leaders and `/plan` are both LLMs -- they can read natural language gap descriptions without needing structured protocols.

## Key Decisions

1. **Advisory only, not operational** -- Domain leaders note gaps; they do not install anything. Installation stays in `/plan` Phase 1.5.
2. **All 5 domain leaders** -- Each leader assesses gaps in their own domain (CMO notes missing marketing agents, COO notes missing ops agents, etc.).
3. **Dedicated section** -- Each domain leader adds a "Capability Gaps" section to their brainstorm assessment output, separate from other concerns.
4. **Consolidated in brainstorm doc** -- The brainstorm command aggregates all domain leader gaps into one "Capability Gaps" section in the brainstorm document.
5. **Handoff to /plan** -- `/plan` Phase 1.5 reads the brainstorm document's gap list to guide `agent-finder` and `functional-discovery` registry searches.
6. **Approach A (lightweight prompts)** -- No structured protocols, no new agents. Simple prompt additions to existing agent files.

## Scope

### In Scope
- Add gap detection instructions to all 5 domain leader agent .md files
- Add gap consolidation step to brainstorm command after domain leader assessments
- Add brainstorm gap reference to `/plan` Phase 1.5
- Update brainstorm document template to include "Capability Gaps" section (when domain leaders participate)

### Out of Scope
- Agent/skill installation during brainstorm
- New agents or skills for gap detection
- Structured gap protocols or tokens
- Registry query changes
- Changes to `agent-finder` or `functional-discovery` agents

## Open Questions

None -- all key decisions resolved during brainstorm dialogue.

## CTO Assessment Summary

The CTO identified that:
- The existing plan.md flow already handles discovery well via Phase 1.5/1.5b
- Moving installation to brainstorm would create duplicate discovery paths, token budget pressure, and session-boundary visibility issues
- Option A (advisory only) is the lowest-risk approach that addresses the core need: surfacing gaps earlier in the workflow
- The existing 3-tier trust model (Anthropic > Verified > Community/discarded) should not be duplicated; it stays in agent-finder

## Changes Required

| File | Change |
|------|--------|
| `agents/engineering/cto.md` | Add Capability Gaps section to brainstorm assessment instructions |
| `agents/marketing/cmo.md` | Add Capability Gaps section to brainstorm assessment instructions |
| `agents/operations/coo.md` | Add Capability Gaps section to brainstorm assessment instructions |
| `agents/product/cpo.md` | Add Capability Gaps section to brainstorm assessment instructions |
| `agents/legal/clo.md` | Add Capability Gaps section to brainstorm assessment instructions |
| `commands/soleur/brainstorm.md` | Add gap consolidation step after domain leader assessments; add Capability Gaps section to brainstorm document template |
| `commands/soleur/plan.md` | Add brainstorm gap reference to Phase 1.5 context |
