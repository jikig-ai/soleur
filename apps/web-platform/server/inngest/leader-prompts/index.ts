// Leader-prompt registry for the Anthropic-SDK leader loop (PR-B #4379).
//
// Each action class has a per-class module exporting a `LeaderPromptModule`.
// The Inngest function `agent-on-spawn-requested` resolves the module at
// loop start from `action_sends.action_class` and uses it to assemble the
// system prompt, user prompt, tool surface, and model selection.
//
// Load-bearing invariants (per ADR-042):
//   - tools: per-class enumerated allowlist; the dispatcher rejects any
//     out-of-allowlist tool call from the model with
//     `failure_reason = "leader_tool_invalid"`.
//   - model: per-class routing (Sonnet for reasoning-shape classes,
//     Haiku for classification-shape classes) for cost/latency.
//   - maxTurns: flat 8 (the secondary backstop; the primary gate is the
//     per-spawn cost ceiling — see ADR-041).
//   - maxTokens: 4096 (per turn — physical token-budget bound).
//   - promptVersion: developer-maintained `v{maj}.{min}.{patch}` string;
//     bump on any material edit to systemPrompt / userPromptTemplate /
//     tools. NOT source-hashed (Node major-version stability — Kieran M6).
//
// SSOT constant: PER_SPAWN_COST_CEILING_CENTS lives here (per learning
// 2026-05-06-cap-coupling-between-adjacent-prs.md). Drift-guard test
// in constants-ssot.test.ts forbids hand-rolled `260` / `$2.60` literals
// in this directory and the Inngest function file.

// Re-export constants + types from ./constants for back-compat. Per-class
// modules import from ./constants directly to avoid the cycle.
export {
  PER_SPAWN_COST_CEILING_CENTS,
  LEADER_MAX_TURNS,
  LEADER_MAX_TOKENS,
  SONNET_MODEL,
  HAIKU_MODEL,
} from "./constants";
export type {
  AnthropicModelId,
  LeaderActionClass,
  AnthropicToolDef,
  ClassInput,
  LeaderPromptModule,
} from "./constants";

import type { LeaderActionClass, LeaderPromptModule } from "./constants";

// Module imports — each per-class module follows the same shape.
import { engineeringPrReviewPending } from "./engineering.pr_review_pending";
import { engineeringCiFailed } from "./engineering.ci_failed";
import { triageP0p1Issue } from "./triage.p0p1_issue";
import { securityCveAlert } from "./security.cve_alert";
import { knowledgeKbDrift } from "./knowledge.kb_drift";

/**
 * The registry. Exactly 5 classes per AC2. The registry covers every
 * `LeaderActionClass` value — exhaustiveness asserted by the sentinel
 * test prompt-version-stability.test.ts.
 */
export const LEADER_PROMPTS: Record<LeaderActionClass, LeaderPromptModule> = {
  "engineering.pr_review_pending": engineeringPrReviewPending,
  "engineering.ci_failed": engineeringCiFailed,
  "triage.p0p1_issue": triageP0p1Issue,
  "security.cve_alert": securityCveAlert,
  "knowledge.kb_drift": knowledgeKbDrift,
} as const;

export function getLeaderPromptModule(
  actionClass: LeaderActionClass,
): LeaderPromptModule {
  const module = LEADER_PROMPTS[actionClass];
  if (!module) {
    throw new Error(`leader-prompts: unknown action class ${actionClass}`);
  }
  return module;
}
