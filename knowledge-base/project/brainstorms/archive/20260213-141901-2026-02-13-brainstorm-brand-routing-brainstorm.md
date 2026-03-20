# Brainstorm: Integrate Brand-Architect into Brainstorm Workflow

**Date:** 2026-02-13
**Issue:** #76
**Status:** Decided

## What We're Building

Add domain-aware routing to `/soleur:brainstorm` Phase 0 so that brand/marketing requests are detected and routed to the `brand-architect` agent instead of running the generic brainstorm flow.

## Why This Approach

The brand-architect agent already has a complete 5-phase interactive workshop that produces a structured brand guide. Running it through the generic brainstorm flow would create redundant artifacts (brainstorm doc + brand guide). Instead, brainstorm acts as a router — it detects the domain, sets up the worktree and issue, then hands off to the specialist agent.

## Key Decisions

### 1. Component Type: Agent + brainstorm routing (not a skill)

Brand-architect stays as an agent at `agents/marketing/brand-architect.md`. Users access it through `/soleur:brainstorm`, not a direct slash command. Rationale: it's a workshop that requires human intent, and brainstorm is the natural entry point for "I want to define something."

### 2. Detection: Keyword matching + user confirmation

Phase 0 scans the feature description for brand/marketing keywords. If matched, it presents an AskUserQuestion offering the brand workshop. User always decides — no auto-routing.

**Keywords (broad set):** brand, branding, brand identity, brand guide, voice and tone, visual identity, marketing, logo, tagline, brand workshop.

### 3. Flow Control: Handoff + worktree only

When brand workshop is selected:
1. Create worktree + GitHub issue (Phase 3/3.6)
2. Hand off to brand-architect agent via Task tool inside the worktree
3. Brand guide (`knowledge-base/overview/brand-guide.md`) is the output artifact
4. Skip brainstorm doc — brand guide IS the deliverable

### 4. Extensibility: Lightweight pattern

Add a "Specialized Domain Routing" section in Phase 0 with brand as the first entry. Structured so adding future domains is copy-paste obvious, but no framework or abstraction. YAGNI.

## Open Questions

- None — all decisions resolved.

## Approach Summary

Modify `plugins/soleur/commands/soleur/brainstorm.md` to add a new Phase 0 section between "clear requirements" check and Phase 1. The section:

1. Defines a keyword list per domain (starting with brand/marketing)
2. Checks feature description against keywords
3. If match: AskUserQuestion offering the specialized workshop
4. If accepted: worktree + issue setup, then Task tool handoff to the agent
5. If declined: continue normal brainstorm flow

No new files needed — this is a modification to an existing command.
