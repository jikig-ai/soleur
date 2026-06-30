// Bundled web copy of the canonical `.claude/phase-surface-map.json` (#5768,
// ADR-070 lever 1 / #5772). The `.claude/` directory is NOT shipped into the
// web container (Dockerfile copies only public/, .next/, dist/server/,
// next.config.mjs, and the vendored plugin), so the web SDK phase-surface hook
// cannot read the canonical map at runtime — it imports this bundled `.ts`
// const, which is always compiled into `dist/server` regardless of build
// mechanism.
//
// EDIT BOTH FILES IN LOCKSTEP. `test/phase-surface-map-parity.test.ts`
// deep-equals this object against the canonical JSON (the `_comment` key
// excluded) and fails CI on any drift (ADR-053 three-coupling pattern).
//
// The map is FQN-keyed (`soleur:work`) because the CLI Skill tool emits FQNs.
// The web Concierge emits BARE names (`work`); `phase-surface-hook.ts`
// normalizes bare→FQN at lookup time. Do not re-key this copy to bare names —
// that would break the byte-faithful parity with the canonical JSON.

export interface PhaseSurface {
  relevant_skills: readonly string[];
  relevant_agents: readonly string[];
  not_live_note: string;
}

export interface PhaseSurfaceMap {
  skill_to_phase: Readonly<Record<string, string>>;
  phase_to_surface: Readonly<Record<string, PhaseSurface>>;
}

// Typed as the WIDE `PhaseSurfaceMap` (string-indexable Records) so the hook can
// look up a runtime-derived key; the object literal still pins the exact values
// the parity test asserts against the canonical JSON.
export const PHASE_SURFACE_MAP: PhaseSurfaceMap = {
  skill_to_phase: {
    "soleur:brainstorm": "brainstorm",
    "soleur:brainstorm-techniques": "brainstorm",
    "soleur:plan": "plan",
    "soleur:deepen-plan": "plan",
    "soleur:plan-review": "plan",
    "soleur:work": "work",
    "soleur:atdd-developer": "work",
    "soleur:test-fix-loop": "work",
    "soleur:resolve-todo-parallel": "work",
    "soleur:review": "review",
    "soleur:qa": "review",
    "soleur:resolve-pr-parallel": "review",
    "soleur:ship": "ship",
    "soleur:preflight": "ship",
    "soleur:merge-pr": "ship",
    "soleur:postmerge": "ship",
  },
  phase_to_surface: {
    brainstorm: {
      relevant_skills: ["soleur:brainstorm", "soleur:brainstorm-techniques", "soleur:plan"],
      relevant_agents: ["cto", "cpo", "repo-research-analyst", "learnings-researcher"],
      not_live_note:
        "implementation/ship skills (work, review, ship, merge-pr) are not relevant yet — decide WHAT before HOW.",
    },
    plan: {
      relevant_skills: ["soleur:plan", "soleur:deepen-plan", "soleur:plan-review", "soleur:spec-templates"],
      relevant_agents: ["architecture-strategist", "code-simplicity-reviewer", "spec-flow-analyzer", "repo-research-analyst"],
      not_live_note:
        "deploy/ship/merge skills are not relevant yet — produce the plan + tasks before implementing.",
    },
    work: {
      relevant_skills: ["soleur:work", "soleur:atdd-developer", "soleur:test-fix-loop", "soleur:resolve-todo-parallel", "soleur:qa"],
      relevant_agents: ["code-simplicity-reviewer", "security-sentinel"],
      not_live_note: "ship/merge skills come after review — finish implementation + tests first.",
    },
    review: {
      relevant_skills: ["soleur:review", "soleur:qa", "soleur:resolve-pr-parallel"],
      relevant_agents: ["architecture-strategist", "security-sentinel", "code-quality-analyst"],
      not_live_note: "ship/merge skills run after review findings are resolved.",
    },
    ship: {
      relevant_skills: ["soleur:ship", "soleur:preflight", "soleur:merge-pr", "soleur:postmerge", "soleur:changelog"],
      relevant_agents: [],
      not_live_note: "this is the terminal phase — commit, push, PR, merge, verify deploy.",
    },
  },
};
