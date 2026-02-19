# Learning: Functional Overlap Discovery Agent Pattern

## Problem
During growth-strategist development (#152), community tools for SEO/content-strategy existed across registries but were never surfaced. The existing agent-finder only detects stack gaps (Flutter, Rust) via file signatures, not functional overlap (tools that do similar things to what's being planned).

## Solution
Created a dedicated `functional-discovery` agent that searches community registries using the feature description as search keywords. Integrated into `/soleur:plan` as Phase 1.5b (after stack-gap check, before external research).

Key design choices:
- **Separate agent, not mode parameter**: Different trigger mechanisms (file signatures vs. keyword search) and different presentation needs justified a separate agent from the start
- **Feature description as search term**: The simplest approach works -- no need for LLM-generated queries or NLP keyword extraction. The raw feature description passed to registry search APIs is sufficient
- **Always-run in plan**: Unlike stack-gap check (conditional on file signatures), functional overlap runs on every plan since every feature could overlap with community tools
- **Graceful degradation**: Registry failures continue silently, same as agent-finder pattern

## Key Insight
Plan review consistently shrinks brainstorm scope by 30-50%. In this case, three parallel reviewers (DHH, Simplicity, Quality) unanimously agreed to cut:
1. Shared registry script (premature extraction -- only 2 consumers)
2. Agent-finder refactor (zero user value -- reorganizing existing code)
3. Brainstorm integration (scope creep -- plan integration alone delivers the value)

The brainstorm decided on a 3-agent approach with shared scripts. Plan review collapsed it to 1 new agent + 1 command edit. The simpler version ships faster and can be extended later if needed.

## Tags
category: implementation-patterns
module: plugin-discovery
