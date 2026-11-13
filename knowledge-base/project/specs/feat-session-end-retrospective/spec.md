---
title: session-end retrospective skill — fresh-context transcript analysis
issue: 12532
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Spec: session-end retrospective skill

## Overview

Implement the session-end retrospective skill (issue #12532) in two phases. Phase 1: degraded-run forensics (fresh-context agent + run-health ledger + pending-operator proposals on errored runs). Phase 2: broader session-mining (every session end, tiered trigger, raw transcript, proposals + new-component issues + learnings/glossary/tests).

See brainstorm: `knowledge-base/project/brainstorms/2026-11-10-session-retrospective-compound-brainstorm.md`.

## User-Brand Impact

- **Artifact:** the session-retrospective-compound skill and its forensic analysis agent
- **Vector:** worst-case data exposure / silent failure / trust breach — a retrospective that leaks prompt/secret content into proposals, or silently mutates skills without operator approval
- **Threshold:** single-user incident

## Key Decisions

See brainstorm Key Decisions table.

## Capability Gaps (prerequisites)

1. Run-health artifact emission in one-shot/test-fix-loop
2. Fail-closed redaction gate for proposal output
3. Cross-harness session-end trigger

## Non-Goals (Phase 1)

- Clustering/dedup across sessions
- Auto-application of any proposal
- In-session scaffolding of new agents/skills
- Real-time session-end firing on non-Claude-Code harnesses
