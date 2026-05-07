// Thread-shape prefill guard shared between the cc-soleur-go
// (`realSdkQueryFactory`) and legacy (`startAgentSession`) Agent SDK
// call sites. Issue #3250.
//
// Concierge default + every domain-leader default is `claude-sonnet-4-6`
// (see `agent-runner-query-options.ts:114`). Anthropic's 4.6+ family
// rejects assistant-terminated message arrays with HTTP 400 "model does
// not support assistant message prefill". The Agent SDK's persisted
// session at `~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl` ends
// on `assistant` after any of: idle-reaper teardown, wall-clock
// runaway, cost-ceiling abort, container restart mid-stream. On the
// next `query({ options: { resume: <id> } })` the SDK forwards that
// thread shape to Anthropic and the user sees the raw 400 in the
// response bubble.
//
// The guard probes `getSessionMessages(resumeSessionId, { dir })` once
// at SDK call construction. If the trailing entry is
// `type: "assistant"`, drop `resume:` (the SDK starts a fresh
// server-side session; the runner's caller pushes the new user prompt
// verbatim) and emit one Sentry warn under
// `op: "prefill-guard"`. Empty-history and probe-failure paths are
// observable under distinct ops so a Sentry filter on the exact
// `op:prefill-guard` reports actual guard fires (not measurement noise).
//
// Positive-match polarity (`last.type === "assistant"`, not
// `last.type !== "user"`) so future SDK SessionMessage variants
// (e.g. `system`, `tool_result`) default to pass-through rather than a
// forced drop. See plan
// `2026-05-05-fix-cc-concierge-prefill-on-resume-plan.md` §"Sharp Edges".

import {
  getSessionMessages,
  type SessionMessage,
} from "@anthropic-ai/claude-agent-sdk";

import { warnSilentFallback } from "./observability";

/**
 * Sentry feature tag for the call site. Cc-soleur-go uses
 * `"cc-concierge"`; the legacy domain-leader path uses
 * `"agent-runner"`. Distinguishes the two surfaces in dashboards
 * without forcing a shared umbrella tag.
 */
export type PrefillGuardFeature = "cc-concierge" | "agent-runner";

export interface ApplyPrefillGuardArgs {
  /**
   * `undefined` = cold start with no prior session. The guard
   * short-circuits and returns `{ safeResumeSessionId: undefined }`
   * with no Sentry emission.
   */
  resumeSessionId: string | undefined;
  /**
   * Workspace cwd passed verbatim to `getSessionMessages` as `dir`.
   * The SDK looks up persisted sessions under
   * `~/.claude/projects/<encoded(cwd)>/`; passing the wrong dir
   * silently returns `[]` (false negative). Drift-guarded by the
   * helper's tests.
   */
  workspacePath: string;
  userId: string;
  conversationId: string;
  feature: PrefillGuardFeature;
  /**
   * Optional Sentry-tag attribution for the legacy path. On the cc
   * path the leader is the synthetic `"cc_router"`; on legacy it is
   * the actual domain leader id.
   */
  leaderId?: string;
}

/**
 * Discriminator for the WS `context_reset` event. `prefill-guard` is the
 * generic "assistant-terminated history" branch; `tool_use_orphan` is the
 * narrower branch where the trailing assistant message contained a
 * `tool_use` content block — model must NOT execute "yes do that" without
 * re-confirmation by name. See plan
 * `2026-05-07-feat-prefill-guard-context-reset-signal-plan.md` §1.3.
 */
export type ContextResetReason = "prefill-guard" | "tool_use_orphan";

export interface ApplyPrefillGuardResult {
  /**
   * `args.resumeSessionId` unchanged when the persisted session is
   * user-terminated (the common case), `undefined` when the guard
   * fires on an assistant-terminated thread. Pass through to
   * `buildAgentQueryOptions({ resumeSessionId: ... })`.
   */
  safeResumeSessionId: string | undefined;
  /**
   * Single-turn notice the caller appends to `systemPrompt` ONLY for the
   * SDK call this guard is gating. Populated only when the guard fires
   * (assistant-terminated history). Caller MUST NOT persist across turns
   * — multi-turn accumulation would compound noise into the model context.
   * `undefined` on cold start, user-final, empty history, probe failure.
   * See #3269.
   */
  contextResetNotice?: string;
  /**
   * Discriminator for the user-side WS `context_reset` event. Source of
   * truth for `reason` on the wire — the caller MUST pass this through to
   * `sendToClient(userId, { type: "context_reset", reason, conversationId })`
   * verbatim. Populated only when the guard fires; `undefined` otherwise.
   * Drives copywriter-approved render variants in `chat-surface.tsx`.
   */
  reason?: ContextResetReason;
}

/**
 * Generic context-reset notice — used when the trailing assistant message
 * is plain text (or non-array content). Trimmed to model directive only
 * per copywriter constraint (no "Note:" / "due to" / jargon).
 */
const CONTEXT_RESET_NOTICE_GENERIC =
  "Prior conversation context was reset. Treat the user's next message as standalone; ask for clarification if it references earlier turns.";

/**
 * Tool-aware variant — used when the trailing assistant message contained a
 * `tool_use` content block. Model must NOT execute any action without
 * explicit re-confirmation by name (CLO authorization-audit-trail floor).
 */
const CONTEXT_RESET_NOTICE_TOOL_USE_ORPHAN =
  "Prior conversation context was reset. The previous turn proposed a tool action you no longer have context on. Do NOT execute any action without explicit re-confirmation by name — ask the user to restate which action they want to run.";

/**
 * Typed runtime guard: does the SDK `SessionMessage.message` (typed
 * `unknown` per `sdk.d.ts:2563`) contain a `tool_use` content block? Per
 * Anthropic SDK semantics, `content` is `string | ContentBlock[]` and
 * `tool_use` only appears in the array form. Any unrecognized shape
 * (null, undefined, non-object, missing `content`, content of wrong type)
 * returns `false` and the caller degrades to the generic notice — never
 * throws. Plan §1.2.
 */
function isToolUseTrailing(message: unknown): boolean {
  if (typeof message !== "object" || message === null) return false;
  if (!("content" in message)) return false;
  const content = (message as { content: unknown }).content;
  if (!Array.isArray(content)) return false;
  return content.some(
    (block) =>
      typeof block === "object" &&
      block !== null &&
      "type" in block &&
      (block as { type: unknown }).type === "tool_use",
  );
}

/**
 * Strip absolute filesystem paths out of a probe error before forwarding
 * it to Sentry. The SDK's `getSessionMessages` reads
 * `~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl` via `fs.readFile`,
 * so an `ENOENT` surfaces with the full container path embedded.
 * Passing the raw `Error` to `Sentry.captureException` would land the
 * container's `HOME` and encoded-cwd layout in Sentry — not exploitable
 * by a remote attacker but information disclosure to anyone with Sentry
 * read access. Replace `'/<absolute>'` and bare ` /<path>` with
 * `<path>` so only the diagnostic shape (errno, syscall) survives.
 *
 * Returns a fresh `Error` that preserves `name` and `code` (when
 * present) so Sentry's group-by-fingerprint still works.
 */
function sanitizeProbeError(err: unknown): Error {
  if (!(err instanceof Error)) {
    return new Error(`prefill-guard probe failed: ${String(err).slice(0, 200)}`);
  }
  const sanitizedMessage = err.message
    .replace(/'\/[^']*'/g, "'<path>'")
    .replace(/(?<=[\s:])\/[^\s'"]+/g, "<path>");
  const sanitized = new Error(sanitizedMessage);
  sanitized.name = err.name;
  const code = (err as { code?: unknown }).code;
  if (typeof code === "string") {
    (sanitized as Error & { code: string }).code = code;
  }
  return sanitized;
}

/**
 * Probe the persisted session for a given `resumeSessionId` and decide
 * whether to forward `resume:` to the SDK. Safe to await in parallel
 * with other workspace-prep work via `Promise.all` — the helper's only
 * input dependencies are `workspacePath` and `resumeSessionId`.
 *
 * Probe failures (SDK regression, FS outage) emit a distinct warn op
 * and pass `resume:` through unchanged, so the helper cannot block
 * the conversation. The probe error is sanitized before forwarding to
 * Sentry to avoid leaking absolute filesystem paths.
 */
export async function applyPrefillGuard(
  args: ApplyPrefillGuardArgs,
): Promise<ApplyPrefillGuardResult> {
  if (!args.resumeSessionId) {
    return { safeResumeSessionId: undefined };
  }

  const baseExtra: Record<string, unknown> = {
    userId: args.userId,
    conversationId: args.conversationId,
    resumeSessionId: args.resumeSessionId,
    workspacePath: args.workspacePath,
  };
  if (args.leaderId) baseExtra.leaderId = args.leaderId;

  let history: SessionMessage[];
  try {
    history = await getSessionMessages(args.resumeSessionId, {
      dir: args.workspacePath,
    });
  } catch (err) {
    warnSilentFallback(sanitizeProbeError(err), {
      feature: args.feature,
      op: "prefill-guard-probe-failed",
      extra: baseExtra,
    });
    // Pass `resume:` unchanged so an SDK regression in
    // `getSessionMessages` cannot block the conversation. The Sentry
    // warn under `op:prefill-guard-probe-failed` is the operational
    // signal needed to escalate.
    return { safeResumeSessionId: args.resumeSessionId };
  }

  if (history.length === 0) {
    // Empty history for a known resumeSessionId is suspicious — the id
    // was emitted by the SDK on a prior turn, so an empty list means
    // either the session file was rotated/deleted, or `dir` is wrong.
    // Pass `resume:` through (Anthropic accepts empty conversation +
    // new user message) and emit a distinct op for `dir`-arg drift
    // detection.
    warnSilentFallback(null, {
      feature: args.feature,
      op: "prefill-guard-empty-history",
      message:
        "Persisted session has zero messages — possible dir-arg drift or missing session file",
      extra: baseExtra,
    });
    return { safeResumeSessionId: args.resumeSessionId };
  }

  const last = history[history.length - 1];
  if (last && last.type === "assistant") {
    warnSilentFallback(null, {
      feature: args.feature,
      op: "prefill-guard",
      message:
        "Persisted session ends with assistant — dropping resume to prevent 400",
      extra: {
        ...baseExtra,
        lastType: last.type,
        historyLength: history.length,
      },
    });
    const toolUseOrphan = isToolUseTrailing(last.message);
    return {
      safeResumeSessionId: undefined,
      contextResetNotice: toolUseOrphan
        ? CONTEXT_RESET_NOTICE_TOOL_USE_ORPHAN
        : CONTEXT_RESET_NOTICE_GENERIC,
      reason: toolUseOrphan ? "tool_use_orphan" : "prefill-guard",
    };
  }

  return { safeResumeSessionId: args.resumeSessionId };
}
