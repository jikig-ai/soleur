// The pure matcher for the Claude CLI's own authentication-failure replies. PERMANENT product code: the diagnostic in
// ./agent-auth-failure.ts (temporary, #11085) and the user-facing rewrite in ./agent-auth-user-message.ts both call it, so it
// lives outside the file the #11085 removal checklist deletes (the checklist in ./agent-auth-mode.ts keeps this module).
//
// It imports no Sentry, no probe and no diagnostic module (test/agent-auth-import-boundary.test.ts pins that). The text arm
// needs a CLI-set field (the `<synthetic>` model or `is_api_error_message`), which the model cannot set: a tenant who makes
// the model reply with the exact CLI string must not be able to forge a hit. The structured `authentication_failed` code is
// alone sufficient.

import { CLI_AUTH_FAILURE_REPLIES, SDK_AUTHENTICATION_FAILED, type CliAuthFailureKind } from "./claude-error-signatures";
import { createChildLogger } from "./logger";

export type AgentAuthMatchKind = CliAuthFailureKind | "structured";

export type Rec = Record<PropertyKey, unknown>;
export const isRec = (v: unknown): v is Rec => typeof v === "object" && v !== null && !Array.isArray(v);


const MAX_REPLY_LENGTH = 200;
/** The model id the CLI stamps on messages it authors itself (measured from the real binary's stream). */
const CLI_SYNTHETIC_MODEL = "<synthetic>";

/** Cheap-first: type, then length, then the anchored regexes (no nested or overlapping quantifiers). */
function classifyReplyText(text: unknown): CliAuthFailureKind | null {
  if (typeof text !== "string") return null;
  if (text.length > MAX_REPLY_LENGTH) return null;
  const whole = text.trim();
  for (const { kind, pattern } of CLI_AUTH_FAILURE_REPLIES) {
    if (pattern.test(whole)) return kind;
  }
  return null;
}

/** The text of a message whose content is exactly ONE text block (a tool_use or a second block disqualifies it). */
function onlyTextBlock(inner: Rec): unknown {
  const content = inner.content;
  if (!Array.isArray(content) || content.length !== 1) return undefined;
  const block: unknown = content[0];
  return isRec(block) && block.type === "text" ? block.text : undefined;
}

/**
 * Classify one SDK stream message. Returns a closed `match_kind` or null; the returned value is never derived from the
 * message text (it is a member of a fixed list), so it can never carry the body.
 *
 * Text is classified FIRST and the structured code is the fallback, so `match_kind` keeps its variants (the real stream
 * carries BOTH the text and `error: "authentication_failed"` on the same message, so structured-first would flatten every
 * event to "structured"). The text arm of an assistant message additionally needs a CLI-set field, see the header.
 */
export function matchAgentAuthFailure(message: unknown): AgentAuthMatchKind | null {
  try {
    if (!isRec(message)) return null;
    if (message.type === "assistant") {
      const inner = message.message;
      if (isRec(inner) && (inner.model === CLI_SYNTHETIC_MODEL || message.is_api_error_message === true)) {
        const kind = classifyReplyText(onlyTextBlock(inner));
        if (kind !== null) return kind;
      }
      return message.error === SDK_AUTHENTICATION_FAILED ? "structured" : null;
    }
    if (message.type === "result") {
      return message.is_error === true ? classifyReplyText(message.result) : null;
    }
    return null;
  } catch {
    // A throwing getter on a hostile message object: the matcher must never throw into a runner loop.
    warnMatcherFaultOnce();
    return null;
  }
}

let matcherFaultWarned = false;
/** One constant-text warn per process: a hostile or malformed message is visible without ever becoming an event. */
function warnMatcherFaultOnce(): void {
  if (matcherFaultWarned) return;
  matcherFaultWarned = true;
  try {
    createChildLogger("auth-failure-matcher").warn("auth-failure matcher: unreadable message skipped");
  } catch {
    // The logger is unavailable (a partial mock): nothing more to do.
  }
}


/** Test seam: re-arm the matcher's one-per-process warn. */
export function __resetAgentAuthMatchWarnForTests(): void {
  matcherFaultWarned = false;
}
