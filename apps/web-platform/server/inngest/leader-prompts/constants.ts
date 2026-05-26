// Constants for the leader-prompt registry. Extracted from index.ts to
// avoid circular imports — index.ts imports per-class modules, which
// import these constants. If the constants lived in index.ts, the
// per-class modules would resolve `undefined` at evaluation time because
// the cycle root has not completed evaluating yet.

/**
 * Layer 2 cap (ADR-041): per-spawn cost ceiling in cents.
 * 200 cents = $2.00 USD. Locked by brainstorm Key Decisions table.
 *
 * SSOT — drift-guard test in constants-ssot.test.ts forbids hand-rolled
 * `200` or `$2.00` literals in scoped paths.
 */
export const PER_SPAWN_COST_CEILING_CENTS = 200;

/** Flat 8-turn ceiling (Layer 3 backstop per ADR-041). */
export const LEADER_MAX_TURNS = 8;

/** Per-turn max-tokens bound (passed to anthropic.messages.create). */
export const LEADER_MAX_TOKENS = 4096;

/** Anthropic model ids. */
export const SONNET_MODEL = "claude-sonnet-4-6" as const;
export const HAIKU_MODEL = "claude-haiku-4-5-20251001" as const;

export type AnthropicModelId = typeof SONNET_MODEL | typeof HAIKU_MODEL;

/** Per-class action discriminator (mirrors ActionClass from scope-grants). */
export type LeaderActionClass =
  | "engineering.pr_review_pending"
  | "engineering.ci_failed"
  | "triage.p0p1_issue"
  | "security.cve_alert"
  | "knowledge.kb_drift";

/**
 * Minimal Anthropic tool definition shape. Mirrors the per-class `tools`
 * arg passed to `anthropic.messages.create`. SDK-version-agnostic.
 */
export interface AnthropicToolDef {
  name: string;
  description: string;
  input_schema: {
    type: "object";
    properties: Record<string, unknown>;
    required?: string[];
  };
}

/** Per-class input shape passed to `userPromptTemplate`. */
export interface ClassInput {
  actionClass: LeaderActionClass;
  sourceRef: string;
  owner?: string;
  repo?: string;
  number?: number;
  scrubbedContent?: string;
}

export interface LeaderPromptModule {
  systemPrompt: string;
  userPromptTemplate: (input: ClassInput) => string;
  tools: AnthropicToolDef[];
  model: AnthropicModelId;
  maxTurns: typeof LEADER_MAX_TURNS;
  maxTokens: typeof LEADER_MAX_TOKENS;
  /**
   * Developer-maintained version string. Bump on any material edit to
   * systemPrompt / userPromptTemplate / tools. Pinned to
   * action_sends.prompt_version at loop start for in-flight replay
   * determinism across leader-prompt edits.
   */
  promptVersion: `v${number}.${number}.${number}`;
}
