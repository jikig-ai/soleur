/**
 * Workflow fidelity contract — prevents Grok Build (and Claude) agents from
 * cherry-picking pipeline steps after `/go` routes to a registered skill, or
 * stopping mid-chain when a lifecycle skill is invoked standalone.
 *
 * Failure mode (#6325 session): `/go` routed to one-shot; the parent ran
 * worktree setup + inline implementation and stopped — skipping plan, review, ship.
 * Extension (#6320 lifecycle): same bypass at `/brainstorm`, `/plan`, `/work` entry.
 */

import type { Harness } from "./harness";

/** Skills that own a multi-phase pipeline — must be invoked, never inlined. */
export const PIPELINE_SKILLS = [
  "one-shot",
  "brainstorm",
  "drain-labeled-backlog",
  "drain-prs",
] as const;

export type PipelineSkill = (typeof PIPELINE_SKILLS)[number];

/** Exploration handoff after brainstorm completes (shortcut: one-shot when reqs clear). */
export const BRAINSTORM_CHILD_SKILLS = ["plan", "one-shot"] as const;

/** Planning prefix before the shared implementation tail. */
export const PLAN_PIPELINE_PREFIX = ["plan", "deepen-plan"] as const;

/** Shared implementation tail — one-shot Steps 3–8 and standalone `/work` Phase 4. */
export const IMPLEMENTATION_TAIL = [
  "work",
  "review",
  "qa",
  "compound",
  "ship",
] as const;

/** Child skills one-shot must invoke in order (Steps 1–7). */
export const ONE_SHOT_CHILD_SKILLS = [
  ...PLAN_PIPELINE_PREFIX,
  ...IMPLEMENTATION_TAIL,
] as const;

/** Standalone skills with mandatory successor invokes (not full orchestrators). */
export const HANDOFF_SKILLS = ["plan", "work", "review", "compound", "ship"] as const;

export type HandoffSkill = (typeof HANDOFF_SKILLS)[number];

/** Post-merge production verification — ship Step 3.8, one-shot Step 8 prerequisite. */
export const POST_MERGE_VERIFICATION_SKILLS = ["postmerge"] as const;

/** Emitted only after merge + release workflows + postmerge verification (one-shot Step 8). */
export const ONE_SHOT_DONE_MARKER = "<promise>DONE</promise>";

/** Sentinel markers skills/docs must retain — drift-guarded in tests. */
export const GO_POST_ROUTE_SENTINEL = "go-post-route";
export const ONE_SHOT_ANTI_BYPASS_SENTINEL = "one-shot-anti-bypass-protocol";
export const GROK_PRE_PUSH_GATE_SENTINEL = "grok-pre-push-gate";

/** Repo-relative path — run from root before `git push` under Grok Build. */
export const GROK_PRE_PUSH_GATE_SCRIPT = "plugins/soleur/scripts/grok-pre-push-gate.sh";
export const BRAINSTORM_ANTI_BYPASS_SENTINEL = "brainstorm-anti-bypass-protocol";
export const PLAN_ANTI_BYPASS_SENTINEL = "plan-anti-bypass-protocol";
export const WORK_ANTI_BYPASS_SENTINEL = "work-anti-bypass-protocol";
export const LIFECYCLE_HANDOFF_SENTINEL = "lifecycle-handoff-protocol";
export const SHIP_MERGE_DEPLOY_SENTINEL = "ship-merge-deploy-protocol";
export const POSTMERGE_HARNESS_SENTINEL = "postmerge-harness-protocol";

/** Re-export for workflow tests — BEHIND resync lives in pr-merge-poll.ts. */
export { PR_BEHIND_SYNC_SENTINEL } from "./pr-merge-poll";

export function isPipelineSkill(skill: string): skill is PipelineSkill {
  return (PIPELINE_SKILLS as readonly string[]).includes(skill);
}

export function isHandoffSkill(skill: string): skill is HandoffSkill {
  return (HANDOFF_SKILLS as readonly string[]).includes(skill);
}

/** Map /go routing labels to soleur skill names (soleur: prefix stripped at dispatch). */
export const GO_SKILL_ROUTES: Record<string, string> = {
  fix: "one-shot",
  implement: "one-shot",
  drain: "drain-labeled-backlog",
  "drain-prs": "drain-prs",
  review: "review",
  incident: "incident",
  default: "brainstorm",
};

export function resolveGoSkillRoute(label: string): string {
  return GO_SKILL_ROUTES[label] ?? GO_SKILL_ROUTES.default;
}

export function isOneShotRoute(label: string): boolean {
  return resolveGoSkillRoute(label) === "one-shot";
}

export function isBrainstormRoute(label: string): boolean {
  return resolveGoSkillRoute(label) === "brainstorm";
}

/** Mandatory successors when a handoff skill runs standalone (no parent orchestrator). */
export function mandatorySuccessors(skill: string): readonly string[] {
  switch (skill) {
    case "brainstorm":
      return BRAINSTORM_CHILD_SKILLS;
    case "plan":
      return ["work"];
    case "work":
      return ["review", "compound", "ship"];
    case "review":
      return ["compound"];
    case "compound":
      return ["ship"];
    case "ship":
      return [...POST_MERGE_VERIFICATION_SKILLS];
    default:
      return [];
  }
}

function formatSkillList(skills: readonly string[], harness: Harness): string {
  if (harness === "grok") {
    return skills.map((s) => `\`/${s}\``).join(", ");
  }
  if (harness === "claude") {
    return skills.map((s) => `\`soleur:${s}\``).join(", ");
  }
  return skills.join(", ");
}

/**
 * Markdown block appended to harness routing instructions.
 * Cite in go.md Step 2.1 (`<!-- workflow-fidelity:block:go-post-route:start -->`).
 */
export function workflowFidelityInstructions(harness: Harness): string {
  const invokeSurface =
    harness === "grok"
      ? "slash command (`/brainstorm`, `/one-shot`, `/plan`, `/work`, `/review`, `/ship`, …)"
      : harness === "claude"
        ? "Skill tool (`soleur:<skill>`)"
        : "registered skill invocation";

  const brainstormNext = formatSkillList(BRAINSTORM_CHILD_SKILLS, harness);
  const workTail = formatSkillList(
    ["review", "qa", "compound", "ship"] as const,
    harness,
  );

  const lines = [
    "**Workflow fidelity (never bypass)**",
    `- After \`/go\` routes to a pipeline skill (\`one-shot\`, \`brainstorm\`, \`drain-*\`), your **next action** MUST be that skill's ${invokeSurface} — not reading SKILL.md and executing steps selectively.`,
    `- **FORBIDDEN after routing to \`brainstorm\`:** product code (Write/Edit/Shell); ending after spec/brainstorm doc without handoff. **REQUIRED next:** ${brainstormNext}.`,
    `- **FORBIDDEN after routing to \`one-shot\`:** inline implementation before Steps 1–8 complete; ending after push/draft PR; reporting "done" without \`${ONE_SHOT_DONE_MARKER}\`.`,
    `- **FORBIDDEN on standalone \`plan\` / \`work\`:** implementing or pushing without the mandated successor chain. \`plan\` → \`/work\`; \`work\` → ${workTail}.`,
    `- **Merge → deploy (never ask the operator):** after \`/ship\` queues merge, YOU poll through release workflows and invoke \`/postmerge\` — do not ask "want me to monitor?" or end the turn at MERGED.`,
    `- **\`${ONE_SHOT_DONE_MARKER}\` gate:** emit ONLY after merge + release workflows + \`/postmerge\` verification complete — not at draft PR, not at merge alone.`,
    `- **Deliverables:** brainstorm = artifacts + handoff; plan = plan file + \`/work\`; work/one-shot = **merged PR + healthy deploy**. Draft PRs are checkpoints only.`,
    "- Skill exit summaries (`## Work Phase Complete`, `## Review Phase Complete`) are **continuation gates**, not turn boundaries.",
  ];

  if (harness === "grok") {
    lines.push(
      `- **Before \`git push\`:** run \`bash ${GROK_PRE_PUSH_GATE_SCRIPT}\` from repo root (local CI parity: \`test-all.sh\` + fast required checks + \`grok-fidelity\`). Abort push on non-zero exit; do not wait for CI.`,
    );
  }

  return lines.join("\n");
}

/** Strengthen skill invocation text for pipeline and handoff skills. */
export function pipelineInvocationSuffix(skill: string): string {
  if (skill === "one-shot") {
    return (
      ` Run **all** Steps 0–8 to completion. ` +
      `Do NOT implement product code inline. ` +
      `Poll merge→deploy yourself; invoke /postmerge after /ship. ` +
      `Emit \`${ONE_SHOT_DONE_MARKER}\` only after postmerge completes.`
    );
  }
  if (skill === "brainstorm") {
    return (
      " Run the full brainstorm pipeline to completion. " +
      "Do NOT write product code. " +
      "Hand off via /plan or /one-shot when exploration is done."
    );
  }
  if (skill === "plan") {
    return (
      " Run the full plan pipeline. " +
      "Do NOT implement product code inline — invoke /work when the plan artifact is ready."
    );
  }
  if (skill === "work") {
    return (
      " Run implementation then the post-work tail (/review → /compound → /ship → /postmerge). " +
      "Do NOT stop after push — merged PR + deploy verification is the deliverable."
    );
  }
  if (skill === "ship") {
    return (
      " Poll merge and release workflows to completion; invoke /postmerge before cleanup. " +
      "Do NOT ask the operator to monitor — you own the wait."
    );
  }
  if (skill === "postmerge") {
    return " Run all postmerge phases through Phase 7 report — production health gate.";
  }
  if (isPipelineSkill(skill)) {
    return " Run the skill's full pipeline — do not stop after the first phase.";
  }
  if (isHandoffSkill(skill)) {
    const next = mandatorySuccessors(skill);
    if (next.length > 0) {
      return ` When standalone, invoke next: /${next.join(", /")} — do not end the turn at artifacts.`;
    }
  }
  return "";
}