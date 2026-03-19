# Feature: Passive Domain Leader Routing

## Problem Statement

Domain leader routing currently only triggers at task initiation time (via `/soleur:go` -> brainstorm Phase 0.5). When a user mentions domain-relevant information mid-conversation -- expenses, legal obligations, marketing opportunities, engineering decisions -- the relevant domain leader is never consulted.

## Goals

- Detect domain-relevant signals in any user message, at any point in the conversation
- Auto-route to the appropriate domain leader without user confirmation
- Execute routing as a non-blocking background task that doesn't interrupt the primary workflow
- Maintain consistency by removing the confirmation gate from brainstorm Phase 0.5 too

## Non-Goals

- Hook-based keyword detection (regresses to pattern matching the project moved away from)
- New configuration files (reuse existing domain config table)
- Skill-embedded routing (would only fire during active workflows)
- Per-domain signal keyword lists (rely on LLM semantic assessment instead)

## Functional Requirements

### FR1: AGENTS.md Passive Routing Rule

A behavioral rule in AGENTS.md instructs the agent to assess every user message for domain relevance using the existing domain config table. When a signal is detected, the relevant domain leader is spawned as a background Task agent.

### FR2: Auto-Route Without Confirmation

Both the new passive routing and the existing brainstorm Phase 0.5 routing auto-fire without `AskUserQuestion` confirmation. The user is not asked permission before a domain leader is consulted.

### FR3: Background Execution with Inline Summary

Domain leaders spawned by passive routing run as background agents. The primary task continues uninterrupted. When the background agent completes, a brief summary is woven into the next response.

### FR4: All 8 Domain Leaders Supported

Routing covers all 8 domains: Marketing (CMO), Engineering (CTO), Operations (COO), Product (CPO), Legal (CLO), Sales (CRO), Finance (CFO), Support (CCO).

## Technical Requirements

### TR1: AGENTS.md Rule Size

The rule must be concise (3-4 lines) to respect the lean AGENTS.md convention. Complex logic lives in the referenced domain config file, not inline.

### TR2: Domain Config Table Reuse

The existing `brainstorm-domain-config.md` provides domain-to-leader mapping and task prompts. No new config files are created.

### TR3: Brainstorm Phase 0.5 Consistency

The brainstorm SKILL.md Phase 0.5 is updated to remove `AskUserQuestion` confirmation gates, making domain leader routing auto-fire consistently.
