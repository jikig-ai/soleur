// Constants for the leader-prompt registry. Extracted from index.ts to
// avoid circular imports — index.ts imports per-class modules, which
// import these constants. If the constants lived in index.ts, the
// per-class modules would resolve `undefined` at evaluation time because
// the cycle root has not completed evaluating yet.

/**
 * Layer 2 cap (ADR-041): per-spawn ceiling in REAL cents of the founder's own
 * Anthropic spend — not a token/work budget that happens to be denominated in
 * cents. The number is rendered back to the founder verbatim by
 * `costBreakerCopy` in server/notifications.ts ("You spent $X of your $2.60
 * per-run spending limit — your own Anthropic credits"), so it is a dollar
 * promise before it is a knob. Work is bounded elsewhere: Layer 3
 * (LEADER_MAX_TURNS × LEADER_MAX_TOKENS) caps the loop physically, ≈$0.33
 * worst-case at current rates — ~8x below this ceiling.
 *
 * 260 = $2.60. Raised from the brainstorm-locked $2.00 by ~30% in #5849: the
 * Opus-4.7-family tokenizer emits ~1.0–1.35x more tokens for the same text, so
 * an equivalent leader run genuinely costs ~30% more real dollars and holding
 * $2.00 would have truncated runs mid-loop. That bump deliberately raised the
 * operator's real exposure; it was taken when $3/$15 was believed to be Sonnet
 * 5's standard rate, so it re-set a dollar promise — it did not make this
 * constant token-denominated.
 *
 * It does NOT move when MODEL_PRICING moves. #7774 corrected the Sonnet row to
 * $2/$10 (the scheduled 2026-09-01 increase was cancelled), so $2.60 attributed
 * is now $2.60 billed; previously it was ~$1.73 — the ceiling silently enforced
 * a third less than its own label and than the copy the founder was shown.
 * Scaling 260 → 173 to "preserve work" would ratify that $1.73 as policy when
 * nobody chose it, and would hard-code a retired price ratio into a user-visible
 * dollar figure. A genuinely tighter per-click promise is a separate decision
 * that amends ADR-041.
 *
 * SSOT: nothing forbids hand-rolled `260` / `$2.60` literals. The only guard is
 * the value pin "PER_SPAWN_COST_CEILING_CENTS SSOT constant equals 260" in
 * test/server/inngest/leader-prompts/prompt-version-stability.test.ts. Earlier
 * text here and ADR-041's sentinel table both cite a `constants-ssot.test.ts`
 * that has never existed in this repo.
 */
export const PER_SPAWN_COST_CEILING_CENTS = 260;

/** Flat 8-turn ceiling (Layer 3 backstop per ADR-041). */
export const LEADER_MAX_TURNS = 8;

/** Per-turn max-tokens bound (passed to anthropic.messages.create). */
export const LEADER_MAX_TOKENS = 4096;

/** Anthropic model ids. */
export const SONNET_MODEL = "claude-sonnet-5" as const;
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
