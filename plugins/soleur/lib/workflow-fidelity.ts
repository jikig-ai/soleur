/**
 * Workflow fidelity contract — prevents Grok Build (and Claude) agents from
 * cherry-picking pipeline steps after `/go` routes to a registered skill.
 *
 * Failure mode (#6325 session): `/go` routed to one-shot; the parent ran
 * worktree setup + inline implementation and stopped — skipping plan, review, ship.
 */

import type { Harness } from "./harness";

/** Skills that own a multi-phase pipeline — must be invoked, never inlined. */
export const PIPELINE_SKILLS = [
  "one-shot",
  "drain-labeled-backlog",
  "drain-prs",
] as const;

export type PipelineSkill = (typeof PIPELINE_SKILLS)[number];

/** Child skills one-shot must invoke in order (Steps 1–7). */
export const ONE_SHOT_CHILD_SKILLS = [
  "plan",
  "deepen-plan",
  "work",
  "review",
  "qa",
  "compound",
  "ship",
] as const;

/** Emitted only after PR merge + release checks (one-shot Step 8). */
export const ONE_SHOT_DONE_MARKER = "<promise>DONE</promise>";

/** Sentinel markers skills/docs must retain — drift-guarded in tests. */
export const GO_POST_ROUTE_SENTINEL = "go-post-route";
export const ONE_SHOT_ANTI_BYPASS_SENTINEL = "one-shot-anti-bypass-protocol";

export function isPipelineSkill(skill: string): skill is PipelineSkill {
  return (PIPELINE_SKILLS as readonly string[]).includes(skill);
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

/**
 * Markdown block appended to harness routing instructions.
 * Cite in go.md Step 2.1 (`<!-- workflow-fidelity:block:go-post-route:start -->`).
 */
export function workflowFidelityInstructions(harness: Harness): string {
  const invokeSurface =
    harness === "grok"
      ? "slash command (`/one-shot`, `/work`, `/review`, `/ship`, …)"
      : harness === "claude"
        ? "Skill tool (`soleur:<skill>`)"
        : "registered skill invocation";

  return [
    "**Workflow fidelity (never bypass)**",
    `- After \`/go\` routes to a pipeline skill (\`one-shot\`, \`drain-*\`), your **next action** MUST be that skill's ${invokeSurface} — not reading SKILL.md and executing steps selectively.`,
    `- **FORBIDDEN after routing to \`one-shot\`:** inline implementation (Write/Edit/Shell on product code) before Steps 1–8 complete; ending the turn after push/draft PR; reporting "done" without \`${ONE_SHOT_DONE_MARKER}\`.`,
    `- **one-shot deliverable:** merged PR. Draft PR (Step 0c) and pushed commits are mid-pipeline checkpoints only.`,
    `- **one-shot child skills (Grok):** invoke \`/plan\`, \`/work\`, \`/review\`, \`/ship\` — never substitute manual tool loops.`,
    "- Skill exit summaries (`## Work Phase Complete`, `## Code Review Complete`) are **continuation gates**, not turn boundaries.",
  ].join("\n");
}

/** Strengthen skill invocation text for pipeline skills. */
export function pipelineInvocationSuffix(skill: string): string {
  if (skill === "one-shot") {
    return (
      ` Run **all** Steps 0–8 to completion. ` +
      `Do NOT implement product code inline. ` +
      `Emit \`${ONE_SHOT_DONE_MARKER}\` only after merge.`
    );
  }
  if (isPipelineSkill(skill)) {
    return " Run the skill's full pipeline — do not stop after the first phase.";
  }
  return "";
}