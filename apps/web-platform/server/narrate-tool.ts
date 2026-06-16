// In-process MCP tools that let the Soleur Concierge deliberately EMIT
// user-facing narration: a transient live status line (`narrate`) and a
// durable per-turn summary box (`summarize`). feat-reasoning-chat-boxes (#5370).
//
// DESIGN — pure validate-and-return (mirrors buildC4ConciergeTools /
// buildConversationsTools): these tools capture ONLY `userId` and do NOT emit
// frames or insert rows. They validate + length-cap the agent's text and return
// an ack. The SIDE EFFECT (redact → `reasoning_narration` frame / `turn_summary`
// row + buffered frame, with the abort-state drop-guard) lives in the
// cc-dispatcher `onToolUse` handler (`emitNarration()`), which is the only scope
// with `sendToClient`, the dispatch abort signal, and `conversationId` in hand.
// Keeping the tool pure means it is trivially unit-testable and cannot leak the
// emit machinery into the SDK tool-handler thread.
//
// SECURITY: `message`/`summary` are length-capped HERE at the tool boundary
// (security C-2 — uncapped agent text = stored-payload / replay-buffer bloat
// DoS). The cap is a hard zod `.max()`; the emit path additionally byte-caps as
// defense-in-depth. Redaction is NOT done here — it is the emit boundary's job
// (single choke point), so the tool never sees a half-scrubbed value.
import { tool } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod/v4";

export const NARRATE_TOOL = "narrate";
export const SUMMARIZE_TOOL = "summarize";

// Fully-qualified names as they appear on the SDK wire (`block.name` in
// onToolUse + the auto-approve allowlist + TOOL_TIER_MAP keys).
export const NARRATE_TOOL_FQN = `mcp__soleur_platform__${NARRATE_TOOL}`;
export const SUMMARIZE_TOOL_FQN = `mcp__soleur_platform__${SUMMARIZE_TOOL}`;

// Char caps at the tool boundary. A live status line is one short sentence; a
// turn summary is a short plain-language outcome. Generous enough that real
// narration is never rejected, tight enough to bound the wire/stored payload.
export const NARRATE_MESSAGE_MAX_CHARS = 600;
export const SUMMARIZE_SUMMARY_MAX_CHARS = 2000;

// Emit-boundary UTF-8 byte cap (defense-in-depth beyond the char cap above).
// Comfortably holds the 2000-char summary worst case (4 bytes/char) while
// bounding the wire/stored/replay-buffer payload (security C-2). Applied in
// cc-dispatcher `emitNarration()` before redaction.
export const NARRATION_TEXT_CAP_BYTES = 8192;

type ToolTextResponse = {
  content: Array<{ type: "text"; text: string }>;
  isError?: true;
};

function textResponse(payload: unknown, isError = false): ToolTextResponse {
  const body: ToolTextResponse = {
    content: [{ type: "text", text: JSON.stringify(payload) }],
  };
  if (isError) body.isError = true;
  return body;
}

export interface BuildNarrationToolsOpts {
  /** Captured in closure for parity with the other tool factories + audit
   *  attribution. The emit/insert side-effect (cc-dispatcher onToolUse) is the
   *  scope that actually uses identity; the tool itself is pure. */
  userId: string;
}

/**
 * Build the `narrate` + `summarize` tools. Returns an array so the caller can
 * spread it into `createSdkMcpServer`. Both handlers are pure: validate, cap,
 * ack. No emit, no DB write — that lives in cc-dispatcher `emitNarration()`.
 */
export function buildNarrationTools(_opts: BuildNarrationToolsOpts) {
  return [
    tool(
      NARRATE_TOOL,
      "Show the user a SHORT, plain-language live status line describing what " +
        "you are doing RIGHT NOW (e.g. \"Looking into your billing settings…\", " +
        "\"Drafting the reply…\"). This is transient — it is replaced by your " +
        "next narrate call and disappears when the turn ends; it is NOT saved. " +
        "Call it at meaningful milestones during a longer turn so the user is " +
        "never staring at a silent spinner. Plain language only — never include " +
        "internal identifiers, file paths, skill names, issue numbers, or any " +
        "entity outside this user's own context.",
      {
        message: z
          .string()
          .min(1)
          .max(NARRATE_MESSAGE_MAX_CHARS)
          .describe("Short plain-language status, one sentence."),
      },
      async (args: { message: string }) => {
        // Pure: the dispatcher's onToolUse emits the reasoning_narration frame
        // from block.input. Here we only confirm receipt to the model.
        return textResponse({ ok: true, shown: args.message.length });
      },
    ),
    tool(
      SUMMARIZE_TOOL,
      "When you have SUCCESSFULLY completed a substantive turn, call this ONCE " +
        "with a short plain-language summary of the OUTCOME (e.g. \"Fixed the " +
        "side panel so it stays open on mobile.\"). It is saved as a permanent " +
        "confirmed box in the user's chat history. Call it AT MOST ONCE per " +
        "turn, and ONLY on success — never on an aborted, errored, or trivial " +
        "turn. Plain language only — never include internal identifiers, file " +
        "paths, skill names, issue numbers, or any entity outside this user's " +
        "own context.",
      {
        summary: z
          .string()
          .min(1)
          .max(SUMMARIZE_SUMMARY_MAX_CHARS)
          .describe("Short plain-language outcome, 1-2 sentences."),
      },
      async (args: { summary: string }) => {
        // Pure: the dispatcher's onToolUse redacts + inserts the turn_summary
        // row and emits the buffered frame (dropping if the turn aborted).
        return textResponse({ ok: true, saved: args.summary.length });
      },
    ),
  ];
}
