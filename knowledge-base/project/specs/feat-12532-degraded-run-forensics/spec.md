---
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Spec: session-retrospective-compound

## Problem Statement

`compound` captures learnings from sessions, but its capture is **self-reported by the executing context** — the same context that made the errors. This self-report is unreliable (Phase 0.5 exists specifically because of this). Two mechanics are missing: (1) fresh-context forensics that correlates actual prompt text to failures using a separate agent, and (2) a degraded-run trigger that fires only on errored runs. Beyond these, Soleur has no mechanism to mine the full session transcript for workflow/agent/skill improvements, operator guidance, new component proposals, learning captures, glossary entries, or test additions — all of which are currently done by hand per incident.

## Goals

- G1: Create skill `session-retrospective-compound` that spawns a fresh-context agent to analyze session transcripts.
- G2: Tiered trigger: Stop hook (Claude Code) + pipeline final-step (all harnesses) + manual invocation (all harnesses).
- G3: Two-tier analysis: cheap triage agent first, deep analysis only if triage flags value.
- G4: Raw transcript input with scrubbed output (fail-closed redaction gate before persistence).
- G5: All structural changes emitted as pending-operator review items (heal-skill approve-before-apply). Never auto-applied.
- G6: New agents/skills filed as `forensics-proposal`-labeled GitHub issues for separate scoping.
- G7: Scope includes learnings, glossary entries, and test additions alongside workflow/agent/skill proposals.
- G8: Phased delivery: Phase 1 (degraded-run forensics) builds infrastructure; Phase 2 (broader session-mining) reuses it.

## Non-Goals

- Clustering/dedup across sessions (Phase 2)
- Auto-application of any proposal (always pending-operator)
- In-session scaffolding of new agents/skills (filed as issues instead)
- Real-time session-end firing on non-Claude-Code harnesses (pipeline final-step + manual only)
- Redaction of input transcript (raw in; only output is scrubbed)

## Functional Requirements

- FR1: The skill MUST spawn a fresh-context agent (never the executing context) to perform analysis.
- FR2: The skill MUST support three trigger modes: Stop hook (Claude Code), pipeline final-step (all), manual invocation (all).
- FR3: A cheap triage agent MUST run first and decide whether deep analysis is warranted.
- FR4: Deep analysis MUST receive the raw session transcript.
- FR5: All proposals MUST be scrubbed by a fail-closed redaction gate before persistence.
- FR6: All structural changes (workflow/agent/skill edits) MUST be emitted as pending-operator review items.
- FR7: New agent/skill proposals MUST be filed as GitHub issues with label `forensics-proposal`.
- FR8: The skill MUST also propose learning captures, glossary entries, and test additions.
- FR9: Proposals MUST NEVER be auto-applied, including under `--headless`.

## Technical Requirements

- TR1: Fresh-context agent must not have access to the executing context's conversation history (true fresh context).
- TR2: Run-health artifact emission (`run_health.json`, `phase_prompts/`) must be added to one-shot and test-fix-loop as a Phase 1 prerequisite.
- TR3: Redaction gate must be fail-closed (trip on any scrub failure, not silently pass).
- TR4: Scratch directory for staged prompts must be gitignored and TTL-purged.
- TR5: Proposal queue storage must align with heal-skill's diff + approve flow and eval-harness gating.
- TR6: Cloud mode (Devin) must degrade to sequential fallback with `Reviewed-Coverage: sequential-fallback` disclosure.
- TR7: AGPL-3.0 clean re-implementation — no source lifting from HephaestusNG. Clean-room spec-driven implementation.

## Open Questions (carried from brainstorm)

- Triage threshold calibration (what signals warrant deep analysis)
- Proposal queue storage location and format
- Fresh-context agent identity and model tier
- Eval/validation approach for measuring proposal quality
- Cost budget per session
- Retention period for scratch dir and proposal queue
- Article 30 register amendment scope (CLO)

## User-Brand Impact

- **Artifact:** the session-retrospective-compound skill and its forensic analysis agent
- **Vector:** worst-case data exposure / silent failure / trust breach for the named artifact
- **Threshold:** single-user incident