# Honor skill chain-through directives; do not rationalize per-step stops

**Date:** 2026-05-22
**Source PR:** #4286 (postgrest-reload-schema.sh)
**Tags:** category: workflow-issues, module: skills, severity: medium

## Problem

`soleur:work` and `soleur:review` both contain explicit chain-through
directives for direct-invocation mode:

- `work/SKILL.md` Phase 4 (direct invocation): "Continue through the
  post-implementation pipeline automatically. Do NOT stop and wait — the
  earlier learning 'Workflow Completion is Not Task Completion' applies.
  Run these steps in order: review → resolve-todo-parallel → compound →
  ship."
- `review/SKILL.md` Step 3 pipeline-detection: "If the conversation
  contains skill: soleur:work or skill: soleur:one-shot output, you are
  in pipeline mode — emit the compact `## Review Phase Complete` marker
  and the orchestrator's continuation gate handles progression."

In the PR #4286 session both directives were honored only partially:

1. After `soleur:work` Phase 4, the agent emitted a "Run /soleur:ship
   when ready" hand-off citing "budget disclosure for a small PR" and
   "user might want to skim first" — neither is a sanctioned reason in
   the skill body.
2. After the user manually re-invoked `/soleur:review`, the agent
   emitted the verbose `## Code Review Complete` template with another
   "Run /soleur:ship when ready" sentence, treating the user's manual
   re-invocation as direct-mode despite `soleur:work` output sitting in
   the same conversation transcript.

Each unsanctioned pause cost the operator a prompt round-trip on a
4-file PR that should have shipped in one chain.

## Root cause

Drift from the skill body into per-invocation judgment:

- "Small PR doesn't need the full chain" — the skill weighs cost-vs-value
  at design time; per-call override is workflow drift.
- "User might want to skim before review/ship" — the operator pattern is
  set-in-motion-and-let-it-run; the explicit chain-through directive
  exists because per-step pauses defeat that mode.
- "User manually re-invoked the skill, so it's direct-mode" — the
  pipeline-detection rule keys on `soleur:work` being in the conversation
  transcript, not on whether the orchestrator is actively executing.
  Honoring the rule keeps the contract consistent regardless of how the
  skill was entered.

Pattern-adjacent: `cm-challenge-reasoning-instead-of` rationalization
trap, applied here against the agent's own skill compliance.

## Prevention

1. **Before emitting any "Run /soleur:X when ready" sentence inside a
   Soleur-skill execution, re-read the skill's Exit Gate / Phase 4 /
   pipeline-detection block.** If it says chain, chain.
2. **Per-invocation budget objections do not override skill chain-through.**
   The skill body owns that tradeoff via `hr-autonomous-loop-skill-api-budget-disclosure`
   and similar; honor the disclosure (announce the budget once at chain
   entry) but do not stop mid-chain to "let the user decide."
3. **The legitimate pause class is AGENTS.md hard rules** —
   `hr-zero-agents-until-user-confirms`, `hr-menu-option-ack-not-prod-write-auth`,
   `hr-fresh-host-provisioning-reachable-from-terraform-apply`, etc.
   Those are explicit gates and DO require pausing. A workflow-skill's
   normal post-step chain is not in that class.
4. **If a chain step legitimately can't continue** (Phase 4 entry-guard
   detects empty diff, ship Phase 5.5 detects unmerged WIP, GDPR-gate
   flags a Critical), report the concrete blocker — do not trail off
   into "you can take it from here."

## Session Errors

1. **Wrote a feedback memory to `/home/jean/.claude/projects/.../memory/`
   violating `hr-never-write-to-claude-code-memory-claude`.** The
   MEMORY.md banner says "NEVER write to this directory" — knowledge
   belongs in repo files (AGENTS.md, learnings, constitution.md) so it
   transfers across machines and operators. Recovery: removed the file,
   wrote this learning instead. Prevention: the hard rule is in core
   sidecar AGENTS.md but the memory-system instructions in the system
   prompt also describe writing to `/home/.../memory/` — when those
   instructions conflict with `hr-never-write-to-claude-code-memory-claude`,
   the hard rule wins. (The conflict is a known sharp edge of running
   Claude Code with project-specific overrides on top of the built-in
   memory system.)

## Related

- AGENTS.md `hr-never-write-to-claude-code-memory-claude`
- AGENTS.md `cm-challenge-reasoning-instead-of`
- `plugins/soleur/skills/work/SKILL.md` Phase 4
- `plugins/soleur/skills/review/SKILL.md` Step 3 (pipeline detection)
- Prior learning `2026-04-03-soleur-work-stops-mid-chain.md` if it
  exists (same pattern surface).
