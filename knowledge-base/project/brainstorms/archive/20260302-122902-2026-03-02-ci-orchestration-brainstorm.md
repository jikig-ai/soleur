# Multi-Agent CI Orchestration Brainstorm

**Date:** 2026-03-02
**Issue:** #333
**Prerequisite:** #330 (CLOSED -- base competitive-intelligence agent exists)
**Participants:** CTO (technical assessment)

## What We're Building

Extend the existing `competitive-intelligence` agent to cascade updates to four downstream specialist agents after producing its base CI report. When the CI agent finishes writing `knowledge-base/overview/competitive-intelligence.md`, it automatically spawns:

1. **growth-strategist** -- re-run content gap analysis against updated competitor list
2. **pricing-strategist** -- refresh competitive pricing matrix
3. **deal-architect** -- update battlecards with new competitor data
4. **programmatic-seo-specialist** -- flag comparison pages that need regeneration

Each specialist runs independently. One failing doesn't block others. After all specialists complete, the CI agent appends a consolidated Cascade Results section to the CI report.

## Why This Approach

### Orchestration in the CI Agent Body (not the skill, not CPO)

The orchestration logic lives as a **Phase 2: Cascade** in `competitive-intelligence.md` itself.

**Why not the skill?** The invocation hierarchy is Skill -> Agent -> Agent. Skills are user-facing entry points; agents own execution and delegation. The competitive-analysis skill stays thin (user interaction + agent spawn). The fan-out pattern from `/soleur:work` confirms agents coordinate other agents via Task tool.

**Why not CPO?** Adding cascade to CPO creates a mandatory hop and breaks direct invocation paths (brainstorm domain config invokes CI directly, not through CPO). The cascade should work regardless of who invoked the CI agent.

**Cross-domain note:** The CI agent (Product domain) directly spawns Marketing agents (growth-strategist, pricing-strategist, programmatic-seo-specialist) and a Sales agent (deal-architect). This crosses domain boundaries intentionally for speed and directness. If the pattern doesn't hold as more specialists are added, refactor to delegate through CMO/CRO.

### Always Automatic (no second opt-in)

The cascade always runs after the base report. No user prompt, no selection of which specialists to trigger. The user already opted in by invoking competitive analysis. This keeps the workflow simple and ensures downstream artifacts stay current.

### Minimal Approach (no normalized data contract)

Specialists read the existing structured CI report directly from `knowledge-base/overview/competitive-intelligence.md`. The report already has overlap matrices with consistent columns (Competitor | Our Equivalent | Overlap | Differentiation | Convergence Risk). No intermediate normalization layer. If cross-specialist inconsistency becomes a problem, add normalization later. YAGNI.

### Consolidated Cascade Summary

After all specialists complete, the CI agent appends a `## Cascade Results` section to the CI report showing: which specialists ran, what each produced/updated, any failures, and what needs manual attention. Single source of truth.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Where orchestration lives | CI agent body (Phase 2) | Matches CMO/CPO delegation pattern; follows Skill -> Agent -> Agent hierarchy |
| Cascade trigger mode | Always automatic | No second opt-in; user consented by invoking competitive analysis |
| Data flow | File-based (specialists read CI report from disk) | Established pattern; avoids 4x context duplication from prompt injection |
| Cross-domain spawning | Direct (with explicit acknowledgment) | Speed/simplicity over architectural purity; refactor later if needed |
| Failure handling | Independent; fan-out pattern from /soleur:work | Spawn all in parallel, report failures, offer sequential retry |
| Output consolidation | Append Cascade Results to CI report | Single source of truth for what changed |
| Approach | Minimal (Approach A) | 1 file edit; no normalization layer; YAGNI |

## Open Questions

- **Specialist autonomous mode:** Do all 4 specialists handle CI-triggered invocation gracefully today, or do some have interactive gates that assume user presence? (Learning #4: workshop agents as subagents require manual gate relay.)
- **Output locations:** Where exactly does each specialist write? Need to verify each agent's output contract before implementation.
- **Stale artifact detection:** Should the cascade skip specialists whose artifacts are already up-to-date? Deferred -- always-run is simpler for v1.
- **Consistency audit:** Should the CI agent cross-check specialist outputs for terminology consistency? Deferred -- add if inconsistency emerges.

## CTO Assessment Summary

- **Orchestration pattern risk:** Low. Task tool fan-out is established.
- **Data flow risk:** Low. File-based is the norm.
- **Token budget risk:** Low. 4 isolated agents, within max-5 limit.
- **Cross-domain coupling risk:** High. Acknowledged and accepted for v1 with explicit documentation.
- **Specialist readiness risk:** Medium. Downstream agents may need prompt adjustments for autonomous CI-triggered mode.

## Relevant Learnings

- Parallel agents on main cause merge conflicts -- enforce isolation (non-overlapping file sets)
- Fan-out pattern: max 5 agents, lead-coordinated commits, subagents do NOT commit
- Parallel subagent CSS class mismatch -- future risk if normalization is needed
- Workshop agents as subagents require manual gate relay -- verify specialists run autonomously
- Skills cannot invoke skills -- orchestration must live in agent, not skill
- Consolidation principle -- Phase 2 of existing agent, not a new agent
