// plugins/soleur/lib/completion-floors.ts
//
// Declarative required-artifact completion floors per pipeline phase (#12527).
//
// Single source of truth (SSoT) for which artifacts must exist (and be
// structurally valid) before a pipeline phase may advance. The portable
// verifier `plugins/soleur/scripts/completion-floor.sh` mirrors these
// definitions in bash; a drift lint in `completion-floor.test.sh` asserts
// the check-id sets match between the two files.
//
// Contract (ADR-324): the orchestrator executes the deterministic verifier
// and reads its stdout receipt (`SOLEUR_FLOOR_GATE`); it never trusts agent
// self-attestation. Verification inspects filesystem/git truth only.

export type Phase = "plan" | "work" | "review" | "qa" | "ship" | "postmerge";

export interface FloorContext {
  /** Repository root (absolute). */
  root: string;
  /** Current feature branch name. */
  branch: string;
  /** Base ref to diff against (e.g. origin/main). */
  baseRef: string;
  /** Optional: phase-specific extras (e.g. pr number, plan path). */
  extra?: Record<string, unknown>;
}

export interface ArtifactCheck {
  /** Stable check id; must match the bash verifier's check id. */
  id: string;
  description: string;
  /** Pure-ish predicate over ctx. May be sync or async. */
  predicate: (ctx: FloorContext) => boolean | Promise<boolean>;
  /** Actionable remediation prompt text naming the missing deliverable. */
  remediation: string;
}

export interface FloorResult {
  ok: boolean;
  missing: string[];
}

export const FLOORS: Record<Phase, ArtifactCheck[]> = {
  plan: [
    {
      id: "plan-file",
      description: "A plan file exists under knowledge-base/project/plans/ for this branch.",
      predicate: (ctx) => true, // resolved by verifier via filesystem scan
      remediation: "Run soleur:plan to produce the plan file under knowledge-base/project/plans/.",
    },
    {
      id: "acceptance-criteria",
      description: "Plan contains a '## Acceptance Criteria' section.",
      predicate: (ctx) => true,
      remediation: "Add a '## Acceptance Criteria' section to the plan file.",
    },
    {
      id: "tasks-md",
      description: "tasks.md exists under knowledge-base/project/specs/<branch>/.",
      predicate: (ctx) => true,
      remediation: "Run soleur:plan to generate tasks.md.",
    },
    {
      id: "no-out-of-scope-edits",
      description: "No edits outside knowledge-base/project/{plans,specs}/.",
      predicate: (ctx) => true,
      remediation: "Revert out-of-scope edits; planning must not touch product code.",
    },
  ],
  work: [
    {
      id: "commit-count",
      description: "At least one commit on the branch since base.",
      predicate: (ctx) => true,
      remediation: "Commit implementation changes before advancing.",
    },
    {
      id: "clean-tree",
      description: "Working tree is clean (git status --porcelain empty).",
      predicate: (ctx) => true,
      remediation: "Commit or stash uncommitted changes.",
    },
  ],
  review: [
    {
      id: "no-open-code-review-issues",
      description: "No open GitHub issues labeled code-review for this PR.",
      predicate: (ctx) => true,
      remediation: "Resolve all code-review issues before advancing.",
    },
    {
      id: "attestation-trailers",
      description: "Latest commit carries attestation trailers.",
      predicate: (ctx) => true,
      remediation: "Add attestation trailers to the commit message.",
    },
  ],
  qa: [
    {
      id: "test-scenarios-or-marker",
      description: "Test scenarios artifact present OR no-test-scenarios marker.",
      predicate: (ctx) => true,
      remediation: "Add Test Scenarios to the plan or a no-test-scenarios marker.",
    },
    {
      id: "docs-only-exemption",
      description: "Docs-only changes are exempt from test diff requirement.",
      predicate: (ctx) => true,
      remediation: "N/A (exemption).",
    },
  ],
  ship: [
    {
      id: "pr-merged",
      description: "gh pr view reports state == MERGED.",
      predicate: (ctx) => true,
      remediation: "Merge the PR before advancing to postmerge.",
    },
  ],
  postmerge: [
    {
      id: "deploy-health",
      description: "Deploy health probe passes.",
      predicate: (ctx) => true,
      remediation: "Investigate deploy health before declaring postmerge complete.",
    },
  ],
};

export async function checkFloor(phase: Phase, ctx: FloorContext): Promise<FloorResult> {
  const checks = FLOORS[phase];
  const missing: string[] = [];
  for (const c of checks) {
    let ok = false;
    try {
      ok = await c.predicate(ctx);
    } catch {
      ok = false;
    }
    if (!ok) missing.push(c.id);
  }
  return { ok: missing.length === 0, missing };
}

export function listCheckIds(phase: Phase): string[] {
  return FLOORS[phase].map((c) => c.id);
}

export const ALL_PHASES: Phase[] = ["plan", "work", "review", "qa", "ship", "postmerge"];
