// Lazy singletons + orchestration layer for the Command Center
// `/soleur:go` runner. ws-handler delegates here; this module owns the
// per-process PendingPromptRegistry, StartSessionRateLimiter, and
// SoleurGoRunner instances.
//
// `realSdkQueryFactory` binds the real-SDK `query()` from
// `@anthropic-ai/claude-agent-sdk` — this is the always-on production
// cc-soleur-go runner. Originally gated behind FLAG_CC_SOLEUR_GO=1; the
// flag was retired in #3270 once the soak window (ADR-022) confirmed the
// new path. See plan
// `2026-04-27-feat-stage-2-12-real-sdk-query-factory-binding-plan.md`.
//
// V2 follow-ups tracked in #2853 backlog (V2-13: tier-classify in-process
// MCP servers for cc-soleur-go path — referenced in factory body).

import { randomUUID } from "crypto";
import path from "path";

import type { Query } from "@anthropic-ai/claude-agent-sdk";
import { query as sdkQuery } from "@anthropic-ai/claude-agent-sdk";

import { applyPrefillGuard } from "./agent-prefill-guard";

import type { WSMessage, Conversation, AttachmentRef } from "@/lib/types";
import { KeyInvalidError, STATUS_LABELS } from "@/lib/types";
import { persistAndDownloadAttachments } from "./attachment-pipeline";

/**
 * Runtime allowlist for `Conversation["status"]`. Mirrors the type union
 * `"active" | "waiting_for_user" | "completed" | "failed"` and is derived
 * from `STATUS_LABELS` so a future status added to the type and labels
 * map flows through automatically.
 */
const CONVERSATION_STATUS_VALUES = new Set(Object.keys(STATUS_LABELS));
import {
  createSoleurGoRunner,
  type SoleurGoRunner,
  type QueryFactory,
  type QueryFactoryArgs,
  type DispatchEvents,
  type WorkflowEnd,
} from "./soleur-go-runner";
import { readCcCostCaps } from "./cc-cost-caps";
import { WORKFLOW_END_USER_MESSAGES } from "./cc-workflow-end-messages";
import { persistTurnCost } from "./cost-writer";
import { PendingPromptRegistry } from "./pending-prompt-registry";
import {
  createStartSessionRateLimiter,
  type StartSessionRateLimiter,
} from "./start-session-rate-limit";
import {
  handleInteractivePromptResponse,
  pruneTombstonesFor,
  type HandleInteractivePromptResponseResult,
} from "./cc-interactive-prompt-response";
type InteractivePromptEvent = Extract<WSMessage, { type: "interactive_prompt" }>;
type InteractivePromptResponse = Extract<WSMessage, { type: "interactive_prompt_response" }>;
import {
  type ConversationRouting,
  type WorkflowName,
} from "./conversation-routing";
import {
  reportSilentFallback,
  mirrorWithDebounce,
  mirrorP0Deduped,
  __resetMirrorDebounceForTests,
} from "./observability";
import { CC_ROUTER_TIER3_DENYLIST } from "./tool-tiers";
import { updateConversationFor } from "./conversation-writer";
import {
  getUserServiceTokens,
  patchWorkspacePermissions,
} from "./agent-runner";
// PR-C §2.11 (#3244): BYOK lease wrap on realSdkQueryFactory — the
// plaintext API key fetch surface moves from `getUserApiKey(userId)`
// (which returns a bare string) to `lease.getApiKey()` inside
// `runWithByokLease`. Closes #3392 (cc-dispatcher BYOK item).
import { runWithByokLease } from "./byok-lease";
import { getFreshTenantClient } from "@/lib/supabase/tenant";
import {
  fetchUserWorkspacePath,
  resolveConciergeDocumentContext,
  _resetWorkspacePathCacheForTests,
} from "./kb-document-resolver";
import type { DocumentExtractMeta } from "./kb-document-resolver";
import type { PdfExtractErrorClass } from "./pdf-text-extract";

// Re-export so existing call sites keep working.
export { resolveConciergeDocumentContext } from "./kb-document-resolver";
import { buildAgentQueryOptions } from "./agent-runner-query-options";
import { buildToolUseWSMessage } from "./tool-labels";
import {
  getBashApprovalCache,
  _resetBashApprovalCacheForTests,
} from "./permission-callback-bash-batch";
import {
  createCanUseTool,
  type CanUseToolDeps,
} from "./permission-callback";
import { abortableReviewGate, type AgentSession } from "./review-gate";
import { sendToClient as defaultSendToClient } from "./ws-handler";
import { notifyOfflineUser } from "./notifications";
import { createChildLogger } from "./logger";

const log = createChildLogger("cc-dispatcher");

// Non-routable internal leader id reserved for cc-soleur-go path
// audit-log attribution. Used by `createCanUseTool` (R-AC14), the WS
// `stream`/`tool_use` events emitted from `dispatchSoleurGo`, and the
// `reportSilentFallback` extra in the sandbox-startup mirror branch.
//
// Source of truth lives in `@/lib/cc-router-id` so client-safe modules
// (leader-avatar.tsx, etc.) can import the same literal without dragging
// pino + supabase service client into the browser bundle.
export { CC_ROUTER_LEADER_ID } from "@/lib/cc-router-id";
import { CC_ROUTER_LEADER_ID } from "@/lib/cc-router-id";

// Sentry mirror debounce (`mirrorWithDebounce`) lives in `./observability`
// (#3369). Per-(userId, errorClass) 5-minute TTL prevents a misconfigured
// prod (1 QPS = 86k events/day per failure mode) from flooding Sentry.

/**
 * Read CC_MCP_ALLOWLIST and return the cc-router's mcpServers config (#2909).
 *
 * Phase 1 deny-by-default scaffolding (this PR): returns `{}` for empty /
 * unset / whitespace-only env. Throws plain Error if any short-name in the
 * env resolves to a member of `CC_ROUTER_TIER3_DENYLIST` (the 3 Plausible
 * tools — cross-tenant credentials by construction). Phase 1 does NOT yet
 * build a populated `soleur_platform` server even when valid non-denylist
 * names are present — promotion is Phase 2 (#3722).
 *
 * Denylist-check-first ordering is pinned: a mixed env value like
 * `"foo,plausible_create_site"` throws with the Plausible name in the
 * message regardless of position. Future unknown-name validation (Phase 2)
 * will fail-closed AFTER the denylist check.
 *
 * Exported for unit testability (`test/cc-mcp-tier-allowlist.test.ts`).
 *
 * @param env defaults to `process.env`; tests pass a synthetic record.
 */
export function readCcMcpAllowlist(
  env: Record<string, string | undefined> = process.env,
): Record<string, unknown> {
  const raw = env.CC_MCP_ALLOWLIST;
  if (raw === undefined || raw.trim() === "") return {};
  const names = raw
    .split(",")
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
  for (const name of names) {
    const fqn = `mcp__soleur_platform__${name}`;
    if (CC_ROUTER_TIER3_DENYLIST.has(fqn)) {
      throw new Error(
        `CC_MCP_ALLOWLIST contains permanent Tier 3 denylist tool "${name}" — see CC_ROUTER_TIER3_DENYLIST in tool-tiers.ts`,
      );
    }
  }
  // Phase 1: even with valid non-denylist names present, return {} —
  // building the populated soleur_platform server lives in Phase 2 (#3722).
  return {};
}

/**
 * Return true when the cc-router iterator observes a `tool_use` block
 * referencing a `mcp__soleur_platform__*` tool that is NOT in the registered
 * platform-tool list (#2909 FR2 — Candidate B per Kieran SDK-source read).
 *
 * Background: when `mcpServers` is empty (Phase 1 default), the Claude
 * Agent SDK rejects unknown `mcp__soleur_platform__*` calls at
 * model-validation time and `canUseTool` is NEVER invoked. The SDK
 * returns a `tool_result` error to the model with no Sentry signal — a
 * silent-failure surface that violates `cq-silent-fallback-must-mirror-to-sentry`.
 * The router's SDK iterator hook (`onToolUse`) is the only observable
 * surface; this helper is the predicate.
 *
 * Exported for unit testability.
 */
export function shouldMirrorUnregisteredPlatformToolUse(
  toolName: string,
  registeredPlatformToolNames: readonly string[],
): boolean {
  if (!toolName.startsWith("mcp__soleur_platform__")) return false;
  return !registeredPlatformToolNames.includes(toolName);
}

/**
 * Registered platform tool names for the cc-router (#2909 FR2 + Phase 2 #3722
 * promotion hook). Phase 1: empty — `mcpServers === {}` via `readCcMcpAllowlist()`.
 * Phase 2: populated from `CC_MCP_ALLOWLIST` allowlist outcome. Module-level
 * constant so the iterator hook's `shouldMirrorUnregisteredPlatformToolUse`
 * predicate has a single named place to read, preventing drift between the
 * allowlist source and the mirror predicate at Phase 2 promotion time.
 */
const CC_REGISTERED_PLATFORM_TOOL_NAMES: readonly string[] = [];

// Max length cap for `block.name` before passing to Sentry/pino. Defense-in-
// depth against future model regressions that might emit pathologically long
// tool names; the SDK validation gate constrains names to the registered
// catalog today, so this is bounded but not impossible.
const MAX_TOOL_NAME_LEN_FOR_LOG = 128;

/**
 * Sanitize a tool name for log emission (#2909 FR2): strip control chars +
 * Unicode line/paragraph separators (CWE-117 log injection defense-in-depth),
 * and length-cap. Pino's JSON serialization is the primary defense; this is
 * a belt-and-suspenders pass per the log-injection-unicode-line-separators
 * learning.
 */
function sanitizeToolNameForLog(name: string): string {
  return name
    .replace(/[\x00-\x1f\x7f\u2028\u2029]/g, "?")
    .slice(0, MAX_TOOL_NAME_LEN_FOR_LOG);
}

// Hoisted module-level sets (avoid per-call construction in
// `dispatchSoleurGo` / `handleInteractivePromptResponseCase`).
export type WorkflowEndStatus = WorkflowEnd["status"];
const TERMINAL_WORKFLOW_END_STATUSES: ReadonlySet<WorkflowEndStatus> = new Set<
  WorkflowEndStatus
>([
  "completed",
  "user_aborted",
  "idle_timeout",
  "plugin_load_failure",
  "internal_error",
]);

// #3603 W2 — statuses that trigger the assistant-text abort flush. Mirrors
// the legacy contract at `agent-runner.ts:2044-2055` (writes any non-completed
// terminal status as `status: "aborted"`). Co-located with
// `TERMINAL_WORKFLOW_END_STATUSES` so the file has one canonical
// exhaustiveness rail per status-set. The `_abortFlushExhaustive` rail below
// is the type-level proof that this set covers every non-`completed`
// variant — adding a new `WorkflowEnd` variant without listing it here is a
// TS error.
const ABORT_FLUSH_STATUSES: ReadonlySet<WorkflowEndStatus> = new Set<
  WorkflowEndStatus
>([
  "cost_ceiling",
  "runner_runaway",
  "user_aborted",
  "idle_timeout",
  "plugin_load_failure",
  "internal_error",
]);

// Compile-time exhaustiveness rail for `ABORT_FLUSH_STATUSES`.
// `Exclude<WorkflowEndStatus, "completed">` is exactly the set of non-completed
// statuses; this type assignment forces the keys above to cover that set.
type AbortFlushStatus = Exclude<WorkflowEndStatus, "completed">;
const _abortFlushExhaustive: Record<AbortFlushStatus, true> = {
  cost_ceiling: true,
  runner_runaway: true,
  user_aborted: true,
  idle_timeout: true,
  plugin_load_failure: true,
  internal_error: true,
};
void _abortFlushExhaustive;

// #3642 F7 — Single source of truth for `op` slugs emitted via
// `reportSilentFallback` / `mirrorWithDebounce` / `mirrorP0Deduped` from
// this file. Hoisting these literals prevents drift between the production
// emit site and the test-suite assertions (e.g., an `op` rename in code
// would silently pass the test if the test still hard-codes the old
// literal). Test-file imports re-use this constant via the same module
// path. Registry of slugs is documented in `observability.ts:161-170`.
export const CC_OP_SLUGS = {
  saveAssistant: "save-assistant-message-failed",
  saveAssistantAborted: "save-assistant-message-aborted-failed",
  usageOrphanDropped: "usage_orphan_dropped",
  ccPersistUsageOn: "cc-persist-usage-on",
  persistUserMessage: "persist-user-message",
} as const;

// #3640 F2 — Discriminated `PersistMode` replaces the per-dispatch
// `AssistantPersistMode` string literal + `AssistantPersistOpts` interface
// pair. Module-scope so #3641 type-rail move is a no-op (the type already
// lives outside the `dispatchSoleurGo` closure). The `usage` field is
// keyed inside each variant so a future `aborted` variant can drop the
// `usage` field entirely without an `undefined`-vs-`null` ambiguity.
export type PersistMode =
  | { kind: "complete"; usage: { costUsd: number } | null }
  | { kind: "aborted"; usage: { costUsd: number } | null };

// #3639 F1 — Encapsulates the four mutable per-turn cells previously
// held as `let` bindings inside `dispatchSoleurGo` (the
// `latestAssistantText` accumulator, the `assistantTurnPersisted` abort
// flag, the `currentTurnIndex` counter, and the `pendingTurnUsage`
// cost-capture). One class owns reset-symmetry as a class invariant —
// `reset()` is the only path that clears all four; every mutator method
// is paired with the field it mutates so a future change that touches
// only 3 of 4 fields is caught at code-review time.
//
// Method contracts (call sites in `dispatchSoleurGo` events block):
// - `setText(text)` — `onText` writes the latest streamed text (REPLACE
//   semantic per chat-state-machine.ts:477 + W8). Named `setText` rather
//   than `appendText` since the semantic is a complete-replace, not an
//   append (review #3670 — naming clarity).
// - `captureUsage(turnIdx, costUsd)` — `onResult` stages cost telemetry
//   tagged with `turnIdx`. A stale `onResult` tagged against a previous
//   turn is dropped at consume time by `consumeMatchedUsage`.
// - `consumeForComplete()` — `onTextTurnEnd` happy path: snapshot text +
//   matched usage, clear both cells, bump turn index. Snapshot happens
//   SYNCHRONOUSLY before `saveAssistantMessage` yields the microtask so
//   a turn-N+1 `onResult` arriving on the same iterator yield cannot
//   overwrite turn N's snapshot. Returns `null` when the turn is already
//   aborted — the abort branch is the single authoritative writer once
//   `_aborted` flips true.
// - `consumeForAbort()` — `onWorkflowEnded` abort branch: returns text +
//   matched usage and marks the turn as persisted (so a late
//   `onTextTurnEnd` is a no-op) when text is present; returns
//   `{ kind: "orphan" }` when text is absent but usage was captured (W4
//   orphan); returns `{ kind: "none" }` when neither is present.
// - `currentTurnIndex()` — read of `_currentTurnIndex` for `onResult`
//   to tag `captureUsage` with the active turn.
// - `reset()` — test seam; clears all four fields. Reset-symmetry is a
//   class invariant (production never resets — per-`dispatchSoleurGo`
//   instances are GC'd at dispatch end). Kept for `__getStateForTests`-
//   style override paths and to document the "cells move together"
//   invariant in code rather than prose.
export class TurnPersistenceState {
  private _latestAssistantText = "";
  private _aborted = false;
  private _currentTurnIndex = 0;
  private _pendingTurnUsage: { turnIndex: number; costUsd: number } | null =
    null;

  /** `onText` — REPLACE the accumulator (W8 invariant). Named `setText`
   *  rather than `appendText` because the semantic is a complete-replace
   *  per chat-state-machine.ts:477 — review #3670 (naming clarity). */
  setText(text: string): void {
    this._latestAssistantText = text;
  }

  /** `onResult` — stage per-turn cost tagged with the active turn. */
  captureUsage(turnIdx: number, costUsd: number): void {
    this._pendingTurnUsage = { turnIndex: turnIdx, costUsd };
  }

  /** Active turn index (for `onResult` to tag `captureUsage`). */
  currentTurnIndex(): number {
    return this._currentTurnIndex;
  }

  /**
   * `onTextTurnEnd` happy path. Snapshots text + matched usage,
   * synchronously clears the accumulator + pendingUsage, and bumps the
   * turn index. Returns `null` when there's nothing to persist.
   */
  consumeForComplete(): { text: string; usage: { costUsd: number } | null } | null {
    if (this._aborted) return null;
    const turnSnapshot = this._currentTurnIndex;
    const turnUsage =
      this._pendingTurnUsage?.turnIndex === turnSnapshot
        ? this._pendingTurnUsage
        : null;
    const text = this._latestAssistantText;
    this._latestAssistantText = "";
    this._pendingTurnUsage = null;
    this._currentTurnIndex = turnSnapshot + 1;
    return {
      text,
      usage: turnUsage ? { costUsd: turnUsage.costUsd } : null,
    };
  }

  /**
   * `onWorkflowEnded` abort branch. Three outcomes:
   * - `{ kind: "text"; text; usage }` — text present, abort row should
   *   be written. Marks turn as persisted (suppresses late onTextTurnEnd).
   * - `{ kind: "orphan" }` — text absent but usage was captured (W4
   *   orphan). Caller fires `mirrorP0Deduped`. Clears pendingUsage.
   * - `{ kind: "none" }` — neither text nor usage; no-op.
   */
  consumeForAbort():
    | { kind: "text"; text: string; usage: { costUsd: number } | null }
    | { kind: "orphan" }
    | { kind: "none" } {
    if (this._latestAssistantText.length > 0) {
      const turnUsage =
        this._pendingTurnUsage?.turnIndex === this._currentTurnIndex
          ? this._pendingTurnUsage
          : null;
      const text = this._latestAssistantText;
      this._latestAssistantText = "";
      this._pendingTurnUsage = null;
      this._aborted = true;
      return {
        kind: "text",
        text,
        usage: turnUsage ? { costUsd: turnUsage.costUsd } : null,
      };
    }
    if (this._pendingTurnUsage) {
      this._pendingTurnUsage = null;
      return { kind: "orphan" };
    }
    return { kind: "none" };
  }

  /** Reset-symmetry invariant: clears ALL four fields. */
  reset(): void {
    this._latestAssistantText = "";
    this._aborted = false;
    this._currentTurnIndex = 0;
    this._pendingTurnUsage = null;
  }
}

// #3640 F4 — Build the `messages` INSERT row from a `PersistMode`. Module-
// scope helper keeps `saveAssistantMessage`'s body ≤ 20 LoC; pure function
// (no I/O), so the assistant-row schema can evolve in one place.
function buildRow(
  mode: PersistMode,
  text: string,
  conversationId: string,
): Record<string, unknown> {
  // #3603 W4 — gated single-read site for `CC_PERSIST_USAGE`. The hot-path
  // env read is intentional: enables runtime rollback flip without a
  // process restart, load-bearing for a GDPR-rollback scenario after PR-C.
  // Exact-match `"true"` only — any other truthy string keeps the flag
  // off (defense-in-depth against a half-set Doppler value). Default-off
  // at merge per AC9/AC11.
  const flagOn = process.env.CC_PERSIST_USAGE === "true";
  if (flagOn) _observeCcPersistUsageFirstTrue();
  const usageColumn =
    flagOn && mode.usage ? { cost_usd: mode.usage.costUsd } : null;

  const row: Record<string, unknown> = {
    id: randomUUID(),
    conversation_id: conversationId,
    role: "assistant",
    content: text,
    tool_calls: null,
    leader_id: CC_ROUTER_LEADER_ID,
    usage: usageColumn,
  };
  // Omit `status` for the normal completion path — migration 040's
  // DEFAULT of `'complete'` applies. Only the abort branch writes
  // `status: "aborted"` explicitly.
  switch (mode.kind) {
    case "complete":
      break;
    case "aborted":
      row.status = "aborted";
      break;
    default: {
      const _exhaustive: never = mode;
      void _exhaustive;
    }
  }
  return row;
}

// #3640 F4 — Mirror a `messages` INSERT failure through `mirrorWithDebounce`.
// The op-slug is picked by `mode.kind` so the `op` + `errorClass` (dedupe
// key) match — drift between them would silently split the Sentry stream.
function mirrorInsertError(
  error: unknown,
  mode: PersistMode,
  userId: string,
  conversationId: string,
  fullText: string,
): void {
  // Symmetric with `buildRow`'s exhaustiveness rail (review #3670): assign
  // to a `never`-typed local and use a sentinel return so the compile
  // error fires at the switch, not at the (never-reached) IIFE return.
  let opSlug: string;
  switch (mode.kind) {
    case "complete":
      opSlug = CC_OP_SLUGS.saveAssistant;
      break;
    case "aborted":
      opSlug = CC_OP_SLUGS.saveAssistantAborted;
      break;
    default: {
      const _exhaustive: never = mode;
      void _exhaustive;
      opSlug = CC_OP_SLUGS.saveAssistant; // unreachable; compile error if PersistMode gains a variant
    }
  }
  // Route through `mirrorWithDebounce` (per-(userId, errorClass) 5-min TTL)
  // — a misconfigured Supabase RLS for one user could otherwise emit one
  // Sentry event per assistant turn (10 turns/conv × 100 active convs =
  // 1000 events/hr).
  mirrorWithDebounce(
    error,
    {
      feature: "cc-dispatcher",
      op: opSlug,
      extra: { userId, conversationId, length: fullText.length },
    },
    userId,
    opSlug,
  );
}

// #3603 W1 — Write-boundary tenant-isolation sentinel.
//
// Post-PR-C, cc-dispatcher.ts writes via tenant-scoped clients
// (`getFreshTenantClient(userId)`). RLS on `messages` enforces the FK-join
// through `conversations.user_id`, but a bug routing user A's dispatch with
// user B's `conversation_id` could still produce a structurally-legal write
// (A's JWT, A-owned `conversation_id`) that misroutes payload. This helper
// is the single sentinel call site that every assistant-row write runs
// through.
//
// At HEAD the SDK callback shape (`DispatchEvents` in `soleur-go-runner.ts`)
// does NOT carry payload-derived `user_id` / `conversation_id`, so the
// dispatch closure is the only source of truth — the sentinel returns `true`
// unconditionally and is essentially a placeholder. Its load-bearing role is
// **forward**: when a future SDK callback exposes payload identifiers, the
// helper signature gains those params and a mismatch check + `mirrorP0Deduped`
// call goes inside this function — a single edit point.
//
// Returns `boolean` rather than throwing: the call sites are
// `void saveAssistantMessage(...)` (fire-and-forget at lines ~1129 and ~1163);
// throwing across the `void` boundary turns into an unhandled promise rejection.
// Halt is `if (!assertWriteScope(...)) return;`.
function assertWriteScope(
  dispatchUserId: string,
  dispatchConversationId: string,
): boolean {
  if (_assertWriteScopeOverride) {
    return _assertWriteScopeOverride(dispatchUserId, dispatchConversationId);
  }
  // Sentinel: no payload source exists today, so the dispatch closure
  // identity IS the write scope. Always-true.
  return true;
}

// Test seam — never use in production. The sentinel returns `true`
// unconditionally; tests force `false` via this hook to prove every
// assistant-row write call site runs through the helper. The exported
// setter/resetter functions (#3641 — relocated) live in the bottom-of-
// file test-seam block alongside `__resetDispatcherForTests` and
// `__setCcRunnerForTests` so all test-only exports cluster in one place.
let _assertWriteScopeOverride:
  | ((u: string, c: string) => boolean)
  | null = null;

// #3603 PR-A2 review H4 — `CC_PERSIST_USAGE=true` is the trigger for a new
// GDPR-regulated persisted category (Art. 13(3) prior-disclosure surface).
// Mirror the FIRST observation per process via `reportSilentFallback` so
// post-hoc Art. 33 evidence ("when did this process start writing
// messages.usage?") doesn't depend on Doppler audit-log correlation. The
// pino + Sentry payload from `reportSilentFallback` carries a server-side
// timestamp + `feature` tag; aggregation by `op: CC_OP_SLUGS.ccPersistUsageOn`
// gives the operator a per-process flip timeline.
let _ccPersistUsageFirstTrueObserved = false;
function _observeCcPersistUsageFirstTrue(): void {
  if (_ccPersistUsageFirstTrueObserved) return;
  _ccPersistUsageFirstTrueObserved = true;
  reportSilentFallback(null, {
    feature: "cc-dispatcher",
    op: CC_OP_SLUGS.ccPersistUsageOn,
    message:
      "CC_PERSIST_USAGE=true observed for first time in this process — messages.usage writes are now active",
    extra: {
      // Anchors the 72h Art. 33 clock to a server-side timestamp the
      // operator can correlate against Doppler change events.
      first_observed_at: new Date().toISOString(),
    },
  });
}

// Test seam — reset the once-observed flag so multiple unit tests can
// exercise the breadcrumb path without cross-test bleed. Never call from
// production code.
export function __resetCcPersistUsageObservationForTests(): void {
  _ccPersistUsageFirstTrueObserved = false;
}

type InteractivePromptResponseError =
  | "invalid_payload"
  | "invalid_response"
  | "kind_mismatch"
  | "already_consumed"
  | "not_found";
const MIRROR_INTERACTIVE_RESPONSE_ERRORS: ReadonlySet<
  InteractivePromptResponseError
> = new Set<InteractivePromptResponseError>([
  "invalid_payload",
  "invalid_response",
  "kind_mismatch",
]);

// ---------------------------------------------------------------------------
// Singletons
// ---------------------------------------------------------------------------

let _registry: PendingPromptRegistry | null = null;
let _reaperInterval: ReturnType<typeof setInterval> | null = null;
const REAPER_INTERVAL_MS = 5 * 60 * 1000;

/**
 * Tool-surface configuration for the cc-soleur-go router.
 *
 * Two SDK options govern tool surface, with DIFFERENT semantics
 * (sdk.d.ts:855-892):
 *   - `allowedTools`: AUTO-APPROVE list — pre-approves without canUseTool.
 *   - `disallowedTools`: HARD-BLOCK list — removes from model context entirely.
 *   - `tools`: closed allowlist of available built-ins (alternative to
 *     disallowedTools).
 *
 * The cc-router's primary job is to dispatch via the Skill tool to a routed
 * sub-skill; it never needs Edit or Write itself, so those stay hard-blocked.
 *
 * Bash routing (#3338 → #3344). Bash was originally hard-blocked alongside
 * Edit/Write because it triggered a `find . -name "*.pdf"` / `apt-get install
 * poppler-utils` modal cascade when the agent tried to summarize a large PDF
 * (review-gate modals popping in the end-user Concierge surface). Two
 * structural mitigations have since landed and made the hard-block over-broad:
 *
 *   - #3338 PDF Read 24 MB ceiling — large PDFs route through the gated
 *     directive instead of the inline-Read path that triggered the cascade.
 *   - #3430 page-count gate on the PDF soft-route — large PDFs are
 *     classified before the agent attempts inline read.
 *
 * Bash now routes through `canUseTool` and shares the legacy path's
 * `safe-bash` allowlist (`apps/web-platform/server/safe-bash.ts`). Read-only
 * KB-exploration verbs (`pwd`, `ls`, `cat`, `head`, `tail`, `wc`, `git
 * status/log/diff/show/branch/rev-parse`, `echo`, etc.) auto-approve with no
 * modal; verbs NOT in the allowlist (including `find`/`grep`/`rg`/`apt-get` —
 * intentionally omitted per the omission rationale at the top of
 * `safe-bash.ts` because they accept `-exec` and
 * could shell out) still route to `review_gate`. The structural mitigations
 * above prevent the cascade triggers, and the allowlist covers the verbs the
 * cc-router actually emits during KB exploration. See Closes #3344.
 *
 * The auto-approve list (`CC_PATH_ALLOWED_TOOLS`) is kept as a separate
 * concern: it eliminates a `canUseTool` round-trip for read-only tools
 * (Read, Glob, Grep, LS, NotebookRead, TodoWrite, ExitPlanMode) the cc-router
 * legitimately uses on its own. This is auto-approve, not restriction.
 *
 * Routed sub-skills load their own toolset via the soleur plugin and the
 * legacy domain-leader path (`agent-runner.ts startAgentSession`), so the
 * Edit/Write narrowing is scoped to the cc-router only — exploration within
 * routed workflows is unaffected.
 */
const CC_PATH_ALLOWED_TOOLS: readonly string[] = [
  "Read",
  "Glob",
  "Grep",
  "LS",
  "NotebookRead",
  "TodoWrite",
  "ExitPlanMode",
];

/**
 * Tools removed from the cc-router's surface entirely. Adds to the
 * canonical `[WebSearch, WebFetch]` shared with the legacy path.
 *
 * Bash was removed from this list in #3344 — see the routing rationale on
 * the doc-comment block above. Bash now routes through `canUseTool` and
 * shares the legacy path's `safe-bash` allowlist + review_gate fallback.
 */
const CC_PATH_DISALLOWED_TOOLS: readonly string[] = ["Edit", "Write"];

export function getPendingPromptRegistry(): PendingPromptRegistry {
  if (_registry) return _registry;
  _registry = new PendingPromptRegistry();
  // Schedule TTL reaper. Without this the registry's `reap()` would
  // never run in production (performance-oracle P1-B). Keyed by registry
  // instance so a test-time `__resetDispatcherForTests` clears the
  // interval too. `.unref()` keeps the timer from blocking graceful
  // shutdown.
  _reaperInterval = setInterval(() => {
    try {
      if (_registry) {
        _registry.reap();
        // After record TTL-expire, wholesale-clear the tombstone set.
        // Any consume-response arriving for a reaped key surfaces as
        // `not_found` (acceptable — the prompt genuinely aged out).
        pruneTombstonesFor(_registry);
      }
    } catch (err) {
      reportSilentFallback(err, {
        feature: "cc-dispatcher",
        op: "registryReaperInterval",
      });
    }
  }, REAPER_INTERVAL_MS);
  _reaperInterval.unref();
  return _registry;
}

let _rateLimiter: StartSessionRateLimiter | null = null;
export function getCcStartSessionRateLimiter(): StartSessionRateLimiter {
  if (!_rateLimiter) _rateLimiter = createStartSessionRateLimiter();
  return _rateLimiter;
}

// ---------------------------------------------------------------------------
// ccBashGates — Option A synthetic-AgentSession registry for the
// cc-soleur-go path's Bash review-gate.
//
// `permission-callback.ts createCanUseTool` requires an `AgentSession`
// (with `reviewGateResolvers: Map<gateId, {resolve, options}>`) and a
// `controllerSignal: AbortSignal`. The cc-soleur-go runner does NOT use
// `AgentSession` for its lifecycle (it tracks `activeQueries` itself).
// We synthesize a per-`query()` session inside `realSdkQueryFactory` and
// register it here so ws-handler `review_gate_response` can route Bash
// gate responses by routing kind without touching the legacy
// `activeSessions` Map in `agent-runner.ts`.
//
// Composite-key invariant (R8): mirrors `pending-prompt-registry.ts`
// `makePendingPromptKey` — `${userId}:${conversationId}:${gateId}`.
// Cross-user lookup MUST silently deny.
// ---------------------------------------------------------------------------

interface CcBashGateRecord {
  userId: string;
  conversationId: string;
  gateId: string;
  session: AgentSession;
}

const _ccBashGates = new Map<string, CcBashGateRecord>();

function makeCcBashGateKey(
  userId: string,
  conversationId: string,
  gateId: string,
): string {
  return `${userId}:${conversationId}:${gateId}`;
}

/**
 * Register the synthetic AgentSession owning a Bash review-gate so
 * ws-handler `review_gate_response` can later resolve it via
 * `resolveCcBashGate`. Called from `realSdkQueryFactory`'s
 * `canUseTool` Bash branch (via the synthetic session bridge).
 */
export function registerCcBashGate(args: {
  userId: string;
  conversationId: string;
  gateId: string;
  session: AgentSession;
}): void {
  const key = makeCcBashGateKey(args.userId, args.conversationId, args.gateId);
  _ccBashGates.set(key, {
    userId: args.userId,
    conversationId: args.conversationId,
    gateId: args.gateId,
    session: args.session,
  });
}

/**
 * Resolve a pending Bash review-gate for the cc-soleur-go path. Returns
 * true on a successful single-use resolve; false on missing record OR
 * cross-user lookup (silent denial — never reveal that the record exists
 * but belongs to another user). Mirrors `resolveReviewGate` in
 * `agent-runner.ts` semantics, scoped to the cc path.
 */
export function resolveCcBashGate(args: {
  userId: string;
  conversationId: string;
  gateId: string;
  selection: string;
}): boolean {
  const key = makeCcBashGateKey(args.userId, args.conversationId, args.gateId);
  const record = _ccBashGates.get(key);
  if (!record) return false;
  // R8: composite-key cross-user prompt collision — defense-in-depth.
  if (record.userId !== args.userId) return false;
  const entry = record.session.reviewGateResolvers.get(args.gateId);
  if (!entry) {
    _ccBashGates.delete(key);
    return false;
  }
  try {
    entry.resolve(args.selection);
  } catch (err) {
    reportSilentFallback(err, {
      feature: "cc-dispatcher",
      op: "resolveCcBashGate",
      extra: {
        userId: args.userId,
        conversationId: args.conversationId,
        gateId: args.gateId,
      },
    });
    return false;
  }
  record.session.reviewGateResolvers.delete(args.gateId);
  _ccBashGates.delete(key);
  return true;
}

/**
 * Drain all ccBashGates entries for a conversation. Called from the
 * runner's close paths (`closeConversation`, `reapIdle`) so a Bash
 * gate that was awaiting resolution at conversation-close time does
 * not leak. Also called proactively when a conversation supersedes.
 */
export function cleanupCcBashGatesForConversation(
  userId: string,
  conversationId: string,
): void {
  const prefix = `${userId}:${conversationId}:`;
  for (const key of Array.from(_ccBashGates.keys())) {
    if (key.startsWith(prefix)) {
      const record = _ccBashGates.get(key);
      if (record) {
        // Abort awaiting resolvers so the canUseTool promise rejects
        // (rather than hanging until TTL).
        try {
          record.session.abort.abort(
            new Error("Conversation closed before Bash gate resolved"),
          );
        } catch {
          // best-effort
        }
      }
      _ccBashGates.delete(key);
    }
  }
  // Drain the per-(userId, conversationId) Bash batched-approval cache
  // (#2921). Without this, granted prefixes survive conversation
  // close/reap and could auto-approve on the NEXT conversation if the
  // ws layer reuses the same conversationId (it doesn't today, but
  // defense-in-depth: the cache lifetime should never exceed the
  // conversation lifetime).
  getBashApprovalCache(userId, conversationId).revoke();
}

// ---------------------------------------------------------------------------
// realSdkQueryFactory — Stage 2.12 binding (unconditional since #3270).
//
// Builds a real `Query` per cold conversation. Mirrors
// `agent-runner.ts startAgentSession` `query({ options })` shape with
// these omissions/changes:
//   - `mcpServers: {}` for V1 — V2-13 (#2909) tracks tier-classification
//     of in-process MCP servers (kb_share / conversations / github /
//     plausible) for the cc-soleur-go path before widening.
//   - `disallowedTools: ["WebSearch", "WebFetch"]` — parity with
//     legacy runner (R7).
//   - `leaderId: CC_ROUTER_LEADER_ID` — non-routable internal leader for
//     audit-log attribution.
//   - Synthetic `AgentSession` per Option A (Open Design Question in
//     plan §"Bash Review-Gate Bridge"); registered in `_ccBashGates`
//     so ws-handler `review_gate_response` can resolve via
//     `resolveCcBashGate`.
//
// Idempotency: `patchWorkspacePermissions` is safe to run on every
// cold-Query construction. The runner's queryFactory call site
// (`soleur-go-runner.ts createSoleurGoRunner.dispatch`) only invokes
// the factory once per cold conversation; reused dispatches skip.
// ---------------------------------------------------------------------------

// `fetchUserWorkspacePath`, `resolveConciergeDocumentContext`, and the
// per-process workspace memo were extracted to `./kb-document-resolver`
// so this orchestration module no longer owns filesystem responsibilities
// alongside SDK Query construction, MCP wiring, BYOK token resolution,
// bash-approval, and rate-limiting. Both modules share the workspace
// memo via the resolver's exported helper.

/**
 * Build a real SDK `Query` for one cold cc-soleur-go conversation. Async
 * because workspace path + BYOK key + service tokens are DB-resident.
 * Errors flow up to `soleur-go-runner.ts dispatch`'s `await
 * deps.queryFactory(...)` try/catch — KeyInvalidError there is mapped
 * to `errorCode: "key_invalid"` by `dispatchSoleurGo` (R10);
 * sandbox-startup substring is mirrored here under
 * `feature: "agent-sandbox"` for Sentry tag-filtering parity with the
 * legacy runner. All three DB fetches run in parallel.
 */
export const realSdkQueryFactory: QueryFactory = async (
  args: QueryFactoryArgs,
): Promise<Query> => {
  // PR-C §2.11 (#3244): wrap body in `runWithByokLease` so the plaintext
  // Anthropic key is zeroized on exit and captured-leak attempts throw
  // `ByokLeaseError{cause:"escape"}`. Mirrors agent-runner.ts's
  // startAgentSession pattern at :863 + sendUserMessage routing at
  // :2360. By the time this body returns the Query AsyncGenerator,
  // `sdkQuery({apiKey, ...})` below has already passed the key into the
  // SDK's internal state — the lease's finally-zeroize fires after the
  // SDK has captured what it needs.
  return runWithByokLease(args.userId, async (lease): Promise<Query> => {
    // Plan §2.11 canonical pattern (mirrors agent-runner.ts:2361):
    // hoist `await lease.getApiKey()` OUT of `Promise.all` so the
    // `string | Promise<string>` union in `getApiKey`'s return type
    // does not surface awkwardly through `Promise.all`'s array element
    // inference. `buildAgentQueryOptions.apiKey: string` consumes the
    // unwrapped value.
    const apiKey = await lease.getApiKey();
    const [workspacePath, serviceTokens] = await Promise.all([
      fetchUserWorkspacePath(args.userId),
      getUserServiceTokens(args.userId),
    ]);

  // Workspace-permissions patch and the #3250 prefill-guard probe both
  // depend on `workspacePath` but not on each other — parallelize so the
  // probe doesn't add latency to cold-start dispatch. See plan
  // §"Sharp Edges" and `agent-prefill-guard.ts` for the guard contract.
  const [, prefillGuardResult] = await Promise.all([
    patchWorkspacePermissions(workspacePath),
    applyPrefillGuard({
      resumeSessionId: args.resumeSessionId,
      workspacePath,
      userId: args.userId,
      conversationId: args.conversationId,
      feature: "cc-concierge",
      leaderId: CC_ROUTER_LEADER_ID,
    }),
  ]);
  const {
    safeResumeSessionId,
    contextResetNotice,
    reason: contextResetReason,
  } = prefillGuardResult;

  // #3269 — context-reset signal. The notice is appended to systemPrompt
  // for THIS SDK call only (single-turn; not persisted across turns).
  // The WS event is the user-side signal; emitted exactly once per guard
  // fire. SDK retries are internal to the returned Query AsyncGenerator
  // (sdk.d.ts:1678-1681) and re-enter `query()`, not the factory — so
  // `applyPrefillGuard` is naturally per-fire and a single emit suffices.
  if (contextResetReason) {
    defaultSendToClient(args.userId, {
      type: "context_reset",
      reason: contextResetReason,
      conversationId: args.conversationId,
    });
  }
  const effectiveSystemPrompt = contextResetNotice
    ? `${args.systemPrompt}\n\n${contextResetNotice}`
    : args.systemPrompt;

  const pluginPath = path.join(workspacePath, "plugins", "soleur");

  // Synthetic AgentSession — the only place in the cc path where an
  // AgentSession exists. Registered into `_ccBashGates` per Bash
  // review-gate (Option A). The controller is bound to the Query
  // lifetime; closeConversation/reapIdle abort it.
  const controller = new AbortController();
  const session: AgentSession = {
    abort: controller,
    reviewGateResolvers: new Map(),
    sessionId: null,
  };

  const ccDeps: CanUseToolDeps = {
    abortableReviewGate: (ccSession, gateId, signal, timeoutMs, options) => {
      // Register BEFORE awaiting the resolver so a synchronous
      // `resolveCcBashGate` from a concurrent ws frame cannot race.
      registerCcBashGate({
        userId: args.userId,
        conversationId: args.conversationId,
        gateId,
        session: ccSession,
      });
      return abortableReviewGate(ccSession, gateId, signal, timeoutMs, options);
    },
    sendToClient: defaultSendToClient,
    notifyOfflineUser,
    // Per-(userId, conversationId) Bash command-prefix batched-approval
    // cache (#2921). Wired only on the cc path; the legacy runner stays
    // at the 2-option Bash gate. Revoked from
    // `cleanupCcBashGatesForConversation` so a closed/reaped conversation
    // doesn't leak grants.
    bashApprovalCache: getBashApprovalCache(args.userId, args.conversationId),
    // Real conversation-status write — replaces the prior no-op (#2920).
    // Delegates to the typed wrapper which enforces the R8 composite-key
    // invariant (`.eq("id", convId).eq("user_id", args.userId)`) and
    // mirrors errors to Sentry via `reportSilentFallback` per
    // `cq-silent-fallback-must-mirror-to-sentry`.
    //
    // The closure shape `(convId, status) => Promise<void>` is preserved
    // so `permission-callback.ts`'s 6 deps-injected call sites get
    // transitive R8 coverage with zero churn at the deps interface.
    updateConversationStatus: async (convId: string, status: string) => {
      // Runtime guard: protect against deps-injected callers passing a
      // status literal not in Conversation["status"]. The wrapper would
      // otherwise hand an invalid enum to Postgres which rejects the write
      // — and the closure's `Promise<void>` shape would swallow the error.
      if (!CONVERSATION_STATUS_VALUES.has(status)) {
        reportSilentFallback(null, {
          feature: "cc-dispatcher",
          op: "updateConversationStatus",
          message: `invalid conversation status: ${status}`,
          extra: { userId: args.userId, conversationId: convId, status },
        });
        return;
      }
      // Pause/resume the runner's runaway wall-clock based on whether
      // the conversation is awaiting a user response. The status
      // transitions are the source of truth: `"waiting_for_user"` →
      // pause; `"active"` → resume. Other statuses (`"completed"`,
      // `"failed"`) leave the timer untouched (the runner closes via
      // `onWorkflowEnded`/`closeConversation`). The `_runner` is
      // guaranteed populated here because this closure only runs from
      // inside an SDK Query that the runner already constructed.
      if (_runner) {
        if (status === "waiting_for_user") {
          _runner.notifyAwaitingUser(convId, true);
        } else if (status === "active") {
          _runner.notifyAwaitingUser(convId, false);
        }
      }
      await updateConversationFor(
        args.userId,
        convId,
        {
          status: status as Conversation["status"],
          last_active: new Date().toISOString(),
        },
        {
          feature: "cc-dispatcher",
          op: "updateConversationStatus",
          extra: { status },
          // Status transitions drive permission-callback waiting_for_user
          // events; a 0-rows write would emit a prompt for a deleted/
          // archived row that the UI no longer shows.
          expectMatch: true,
        },
      );
    },
  };

  try {
    // Build SDK options through the shared `buildAgentQueryOptions`
    // helper (#2922). Drift between this cc path and the legacy
    // `agent-runner.ts startAgentSession` is guarded by
    // `agent-runner-query-options.test.ts`.
    //
    // V2-13 Phase 1 (#2909): `readCcMcpAllowlist()` reads CC_MCP_ALLOWLIST
    // and returns `{}` for empty/unset (current behavior preserved bit-for-bit),
    // throws on Tier 3 denylist short-names (3 Plausible tools — permanent,
    // shared service-token cross-tenant credentials). Promotion of non-denylist
    // tools is Phase 2 (#3722, blocked-by Stage 6 #2939).
    return sdkQuery({
      prompt: args.prompt,
      options: buildAgentQueryOptions({
        workspacePath,
        pluginPath,
        apiKey,
        serviceTokens,
        systemPrompt: effectiveSystemPrompt,
        resumeSessionId: safeResumeSessionId,
        mcpServers: readCcMcpAllowlist(),
        // #3338 — auto-approve the cc-router's read-only tool surface so they
        // don't pay a canUseTool round-trip per call. This is auto-approve,
        // not restriction — see CC_PATH_ALLOWED_TOOLS doc comment.
        allowedTools: [...CC_PATH_ALLOWED_TOOLS],
        // #3338 — HARD-BLOCK Bash/Edit/Write at the SDK level so the model
        // cannot emit them (no review_gate modal can appear). Merged with
        // the canonical [WebSearch, WebFetch] disallowed list.
        extraDisallowedTools: CC_PATH_DISALLOWED_TOOLS,
        // SubagentStart sanitizer override: cc strips control chars +
        // U+2028/U+2029 (per learning
        // 2026-04-17-log-injection-unicode-line-separators.md) and
        // tags `ccPath: true` for audit-log filtering.
        subagentStartPayloadOverride: {
          sanitizer: (v: unknown) =>
            String(v ?? "")
              .replace(/[\x00-\x1f\x7f\u2028\u2029]/g, " ")
              .slice(0, 200),
          extraLogFields: { ccPath: true },
          logMessage: "Subagent started (cc-soleur-go)",
        },
        canUseTool: createCanUseTool({
          userId: args.userId,
          conversationId: args.conversationId,
          // R-AC14: non-undefined leaderId so `logPermissionDecision`
          // attributes the cc path. `CC_ROUTER_LEADER_ID` is a
          // non-routable leader id reserved for this purpose.
          leaderId: CC_ROUTER_LEADER_ID,
          workspacePath,
          platformToolNames: [],
          pluginMcpServerNames: [],
          repoOwner: "",
          repoName: "",
          session,
          controllerSignal: controller.signal,
          deps: ccDeps,
        }),
      }),
    });
  } catch (err) {
    // Mirror the "sandbox required but unavailable" branch in
    // agent-runner.ts startAgentSession's catch (feature:
    // "agent-sandbox", op: "sdk-startup"). Other inner throws bubble up
    // to the runner's own queryFactory catch (which mirrors under
    // `feature: "soleur-go-runner"`).
    const errMsg = err instanceof Error ? err.message : String(err);
    if (errMsg.includes("sandbox required but unavailable")) {
      mirrorWithDebounce(
        err,
        {
          feature: "agent-sandbox",
          op: "sdk-startup",
          extra: {
            userId: args.userId,
            conversationId: args.conversationId,
            leaderId: CC_ROUTER_LEADER_ID,
          },
        },
        args.userId,
        "agent-sandbox:sdk-startup",
      );
    }
    throw err;
  }
  }); // end runWithByokLease
};

let _runner: SoleurGoRunner | null = null;
let _runnerSendToClient:
  | ((userId: string, message: WSMessage) => boolean)
  | null = null;

/**
 * Obtain the process-wide SoleurGoRunner. First invocation wires it to
 * the given `sendToClient` (ws-handler's already-exported helper).
 * Subsequent invocations with a DIFFERENT sendToClient is an error:
 * the runner captures its WS-emit closure at first construction.
 */
/**
 * `true` when the cc-soleur-go runner already owns a live `Query` for the
 * given conversation (warm path). Callers use this to skip work that the
 * cold-Query construction already did — most importantly,
 * `resolveConciergeDocumentContext` reads the user's open document into
 * the system prompt at cold dispatch only; subsequent turns reuse the
 * baked prompt, so the per-turn `readFile` + workspace lookup is
 * pure-overhead. Returns `false` when no runner exists yet.
 */
export function hasActiveCcQuery(conversationId: string): boolean {
  if (!_runner) return false;
  return _runner.hasActiveQuery(conversationId);
}

export function getSoleurGoRunner(
  sendToClient: (userId: string, message: WSMessage) => boolean,
): SoleurGoRunner {
  if (_runner) {
    if (_runnerSendToClient !== sendToClient) {
      reportSilentFallback(
        new Error(
          "getSoleurGoRunner: re-init with different sendToClient — the runner's WS-emit closure is captured at first call",
        ),
        { feature: "cc-dispatcher", op: "getSoleurGoRunner" },
      );
    }
    return _runner;
  }
  _runnerSendToClient = sendToClient;
  _runner = createSoleurGoRunner({
    queryFactory: realSdkQueryFactory,
    pendingPrompts: getPendingPromptRegistry(),
    emitInteractivePrompt: (userId, event) => {
      // Stage 2 emits the feature-local shape. Stage 3 extends WSMessage
      // with the full discriminated sub-union; until then, cast at the
      // wire boundary.
      sendToClient(userId, event as unknown as WSMessage);
    },
    // Drain `_ccBashGates` from EVERY internal close path. Without this
    // hook, `runner.reapIdle()` and `runner.closeConversation()` close
    // the Query without firing `onWorkflowEnded`, so the dispatch-side
    // cleanup in `onWorkflowEnded` is never reached and the gate
    // registry leaks. The runner fires this BEFORE `activeQueries.delete`.
    onCloseQuery: ({ conversationId, userId }) =>
      cleanupCcBashGatesForConversation(userId, conversationId),
    defaultCostCaps: readCcCostCaps(),
  });
  return _runner;
}

// ---------------------------------------------------------------------------
// Orchestration
// ---------------------------------------------------------------------------

export interface DispatchSoleurGoArgs {
  userId: string;
  conversationId: string;
  userMessage: string;
  currentRouting: ConversationRouting;
  sessionId?: string | null;
  sendToClient: (userId: string, message: WSMessage) => boolean;
  persistActiveWorkflow: (workflow: WorkflowName | null) => Promise<void>;
  /**
   * KB Concierge document context. The ws-handler resolves these from the
   * open KB document (start_session `pendingContext` for first turn,
   * `conversations.context_path` lookup for subsequent turns) and passes
   * them through. The runner threads them into `buildSoleurGoSystemPrompt`
   * which mirrors the legacy `agent-runner.ts` injection (PDFs get a
   * Read directive; text inlines content up to 50KB).
   */
  artifactPath?: string;
  documentKind?: "pdf" | "text";
  documentContent?: string;
  /**
   * 2026-05-06 follow-up to #3338. Set by `resolveConciergeDocumentContext`
   * when the in-process PDF extractor surfaced a typed failure class. The
   * runner emits `buildPdfUnreadableDirective` (content-grounded reply)
   * instead of `buildPdfGatedDirective` (apt-get-cascade-prone Read path).
   */
  documentExtractError?: PdfExtractErrorClass;
  /**
   * 2026-05-07 follow-up to #3429. Per-failure metadata. Currently only
   * `numPages` (interpolated by `buildPdfTooLongDirective` for the
   * page-count gate's "I see {N} pages" copy). Without plumbing through
   * here, the runner reads `?? 0` and the user sees "I see 0 pages" on
   * every triggering case. Caught by the user-impact-reviewer review of
   * PR #3430.
   */
  documentExtractMeta?: DocumentExtractMeta;
  /**
   * 2026-05-06 follow-up — Bug A1 fix. Resolved workspace path threaded
   * from the ws-handler through `runner.dispatch` →
   * `buildSoleurGoSystemPrompt` so PDF gated + text-too-large directives
   * can inject workspace-absolute Read paths. Required by the SDK Read
   * tool's `file_path` "absolute path" contract; passing relative paths
   * triggered the sandbox-deny path that produced the user-facing
   * "outside my workspace boundary" reply (#3376).
   */
  workspacePath?: string;
  /**
   * Attachment refs uploaded via the chat-input paperclip flow. When
   * non-empty, `dispatchSoleurGo` (a) inserts a `messages` row to
   * satisfy the `message_attachments.message_id` FK, (b) calls the
   * shared attachment-pipeline helper to persist metadata + download
   * files into `<workspace>/attachments/<convId>/`, and (c) augments
   * `userMessage` with the resulting `attachmentContext` text so the
   * agent can `Read` the on-disk paths. Mirrors the legacy
   * `agent-runner.ts:sendUserMessage` flow exactly. See #3254.
   */
  attachments?: AttachmentRef[];
  /**
   * #3266 — fire-and-forget hook that the dispatcher invokes after a
   * successful `persistCcSessionId` and after a `clearCcSessionId`. The
   * ws-handler uses it to mutate the in-process `ClientSession.sessionId`
   * cache so a subsequent chat-case warm-cache turn forwards the
   * just-persisted value (instead of the stale `null` seeded on
   * materialization). Without this, runner-reap-during-live-WS scenarios
   * use `args.sessionId = null` on the next cold-Query construction,
   * defeating the prefill guard's history-probe branch. Receives `null`
   * on the stale-clear path.
   */
  onSessionIdPersisted?: (sessionId: string | null) => void;
}

/**
 * #3266 — persist the SDK-emitted `session_id` back to
 * `conversations.session_id` so the next cold-Query construction (server
 * restart, idle reap, container restart) seeds `args.sessionId` and the
 * runner can `resume:` the SDK session. The write is fire-and-forget
 * because the user's current turn does NOT depend on it landing; failures
 * mirror to Sentry via `updateConversationFor` and the next turn's
 * in-memory `state.sessionId` covers the warm-Query case.
 */
async function persistCcSessionId(args: {
  userId: string;
  conversationId: string;
  sessionId: string;
}): Promise<void> {
  const { ok, error } = await updateConversationFor(
    args.userId,
    args.conversationId,
    { session_id: args.sessionId },
    {
      feature: "cc-dispatcher",
      op: "persist-session-id",
      expectMatch: true,
    },
  );
  if (!ok) {
    // updateConversationFor already mirrors to Sentry; log here only for
    // cross-debugging with legacy `agent-runner.ts` parity.
    log.error(
      { conversationId: args.conversationId, err: error },
      "cc-dispatcher: failed to persist session_id",
    );
  }
}

/**
 * #3266 R7 — clear a stale `conversations.session_id` after the SDK
 * rejects `resume:` for a non-KeyInvalidError reason (missing session
 * file, schema drift). Without this, the next cold-Query retries the
 * same bad session_id indefinitely. Mirrors the legacy
 * `agent-runner.ts` stale-clear behavior.
 */
async function clearCcSessionId(args: {
  userId: string;
  conversationId: string;
}): Promise<void> {
  // Default `expectMatch: false` — a concurrent close/archive race
  // (legitimate 0-rows outcome) is silent success here, matching legacy
  // `agent-runner.ts` stale-clear parity. The composite-key invariant
  // (`.eq("id", ...).eq("user_id", ...)`) is enforced inside the wrapper
  // regardless. Real DB errors still mirror to Sentry.
  const { ok, error } = await updateConversationFor(
    args.userId,
    args.conversationId,
    { session_id: null },
    {
      feature: "cc-dispatcher",
      op: "clear-stale-session-id",
    },
  );
  if (!ok) {
    log.error(
      { conversationId: args.conversationId, err: error },
      "cc-dispatcher: failed to clear stale session_id",
    );
  }
}

/**
 * One-liner ws-handler wiring for the soleur-go chat path. Builds the
 * runner events and forwards them to the WS client using the existing
 * `stream` / `tool_use` / `session_ended` WSMessage variants for
 * backwards compatibility (Stage 3 will add dedicated `workflow_*`
 * events).
 */
export async function dispatchSoleurGo(
  args: DispatchSoleurGoArgs,
): Promise<void> {
  const {
    userId,
    conversationId,
    userMessage: rawUserMessage,
    currentRouting,
    sessionId,
    sendToClient,
    persistActiveWorkflow,
    artifactPath,
    documentKind,
    documentContent,
    documentExtractError,
    documentExtractMeta,
    workspacePath: callerWorkspacePath,
    attachments,
    onSessionIdPersisted,
  } = args;

  // Verify conversation ownership AND bump `last_active` in a single
  // round-trip. `updateConversationFor` with `expectMatch: true` runs the
  // UPDATE scoped to (id, user_id) and returns `ok: false` when zero rows
  // matched — that's our 404 signal. Sentry mirroring on failure happens
  // inside the wrapper, so we only translate to the throw here. Routes
  // through the canonical wrapper per the R8 lint rule.
  const ownership = await updateConversationFor(
    userId,
    conversationId,
    { last_active: new Date().toISOString() },
    {
      feature: "cc-dispatcher",
      op: "verify-conversation-ownership",
      expectMatch: true,
    },
  );
  if (!ownership.ok) {
    throw new Error("Conversation not found");
  }

  // #3254 — persist a `messages` row for every cc turn so
  // `message_attachments.message_id` can be FK'd. The legacy single-leader
  // path has always done this in `agent-runner.ts:sendUserMessage`; the
  // cc path silently dropped attachments because no parent message existed.
  // The SDK's session-id resume mechanism still owns transcript replay
  // for the agent — these rows are for attachment metadata durability and
  // for `api-messages.ts` history hydration on tab reload.
  //
  // #3603 W1 — same write-boundary sentinel as `saveAssistantMessage`.
  // User-content rows carry PII; a misrouted dispatch persisting User A's
  // text into User B's conversation is the same Art. 33/34 surface as the
  // assistant row. Throws (rather than the assistant path's `return`)
  // because this insert is awaited and a halt here cleanly aborts the
  // dispatch via the existing user-INSERT-failure path below.
  if (!assertWriteScope(userId, conversationId)) {
    throw new Error(
      "cc-dispatcher: assertWriteScope halted user-message persistence",
    );
  }
  // PR-C §2.11 (#3244): tenant-scoped message INSERTs. RLS on `messages`
  // enforces FK-join to `conversations.user_id`; the `assertWriteScope`
  // sentinel above is the defense-in-depth layer. The implicit JWT mint
  // is the auth probe — see ws-handler `tenantFor` doc-comment.
  //
  // Wrap mint in try/catch so a transient RuntimeAuthError gets a
  // structured Sentry mirror before the throw bubbles into the outer
  // dispatch pipeline (the dispatch's existing user-INSERT-failure path
  // produces an unstructured generic error otherwise).
  let tenant: Awaited<ReturnType<typeof getFreshTenantClient>>;
  try {
    tenant = await getFreshTenantClient(userId);
  } catch (mintErr) {
    reportSilentFallback(mintErr, {
      feature: "cc-dispatcher",
      op: "tenant-mint.persistUserMessage",
      extra: { userId, conversationId },
    });
    throw mintErr;
  }
  const messageId = randomUUID();
  const { error: insertErr } = await tenant.from("messages").insert({
    id: messageId,
    conversation_id: conversationId,
    role: "user",
    content: rawUserMessage,
    tool_calls: null,
    leader_id: null,
  });
  if (insertErr) {
    reportSilentFallback(insertErr, {
      feature: "cc-dispatcher",
      op: CC_OP_SLUGS.persistUserMessage,
      extra: { userId, conversationId },
    });
    throw new Error(`Failed to save user message: ${insertErr.message}`);
  }

  // Persist attachment metadata + download files into the workspace.
  // Mirrors `agent-runner.ts:sendUserMessage` exactly via the shared
  // helper. On any per-file download failure, the helper omits that file
  // from the `attachmentContext` text — partial success is preferred over
  // a hard turn failure. Validation/INSERT errors propagate to the outer
  // dispatch catch, which mirrors via `mirrorWithDebounce` (no inner
  // try/catch — that would double-mirror and bypass the dispatch
  // debounce, flooding Sentry on a misconfigured Storage URL).
  // PR-D §3 (#3244 §4): tenant-scoped attachments. Reuse the `tenant` mint
  // from the persistUserMessage block above (same userId, same turn — minting
  // a second client would add an unnecessary RTT per Kieran P2-2). Storage
  // RLS in migration 019 (SELECT) + 045 (INSERT/UPDATE/DELETE) is now
  // load-bearing; the path-prefix check at attachment-pipeline.ts:83-86 is
  // defense-in-depth.
  let userMessage = rawUserMessage;
  if (attachments && attachments.length > 0) {
    const { attachmentContext } = await persistAndDownloadAttachments({
      supabase: tenant,
      userId,
      conversationId,
      messageId,
      attachments,
    });
    if (attachmentContext) {
      userMessage = `${rawUserMessage}\n\n${attachmentContext}`;
    }
  }

  const runner = getSoleurGoRunner(sendToClient);

  // Resolve workspace path in parallel with `runner.dispatch` so cold-start
  // LTFT (latency-to-first-token) does not pay an extra serial Supabase RTT.
  // The closure-shared `workspacePath` is filled by the `.then` below; in
  // production, `realSdkQueryFactory` (line 419) awaits the SAME memo before
  // the SDK Query can emit any block, so by the time `onToolUse` fires the
  // value is set. On warm dispatches the memo returns synchronously inside
  // `fetchUserWorkspacePath` and the `.then` resolves on the next microtask.
  // On failure, fall back to `undefined` — `buildToolLabel` still produces
  // the verbose label (just without the workspace-prefix scrub) and the
  // error is mirrored to Sentry per `cq-silent-fallback-must-mirror-to-sentry`.
  let workspacePath: string | undefined;
  void fetchUserWorkspacePath(userId)
    .then((wp) => {
      workspacePath = wp;
    })
    .catch((err) => {
      reportSilentFallback(err, {
        feature: "cc-dispatcher",
        op: "workspace-resolve",
        extra: { userId, conversationId },
      });
    });

  // #3639 F1 — Per-dispatch per-turn state cell. Wraps the four mutable
  // cells (text accumulator, abort flag, turn index, pending usage) so
  // reset-symmetry is a class invariant rather than four parallel
  // `let` declarations. Mirrors the REPLACE semantic at
  // `chat-state-machine.ts:477` (W8). See class doc-comment for the
  // method contract.
  const state = new TurnPersistenceState();

  // #3603 W4 — cc-path narrows the type-wide `Message.usage` shape to
  // cost-only on `'complete'` turns (Art. 5(1)(c) data-minimization). The
  // legacy agent-runner path emits the full `UsageSnapshot` (input_tokens,
  // output_tokens, cost_usd, completed_actions[]) on `'aborted'` turns —
  // see `Message.usage` doc-comment in `lib/types.ts`. `PersistMode` is
  // declared at module scope above (#3640 F2 + #3641 type-rail).
  async function saveAssistantMessage(
    mode: PersistMode,
    text: string,
  ): Promise<void> {
    // #3603 W1 — Cross-tenant write-boundary sentinel. cc-path uses
    // service-role for INSERT (RLS-bypass on writes). RLS catches reads;
    // this guard catches writes. Returns `false` only via the test seam
    // today (sentinel placeholder); load-bearing call site for a future
    // SDK-payload-derived identifier comparison. See `assertWriteScope`
    // module-level doc.
    if (!assertWriteScope(userId, conversationId)) return;

    // Empty-drop contract (PR-A1): an empty-text turn produces no row.
    // The state-class's `consumeForComplete` / `consumeForAbort` callers
    // already short-circuit on empty text, but guard here defensively so a
    // future caller can't silently produce an empty assistant row.
    if (!text) return;

    const row = buildRow(mode, text, conversationId);
    // PR-C §2.11 (#3244): tenant-scoped assistant-row INSERT. Reuses
    // the `tenant` minted at function entry (above the user-row INSERT).
    const { error } = await tenant.from("messages").insert(row);
    if (error) {
      mirrorInsertError(error, mode, userId, conversationId, text);
    }
  }

  const events: DispatchEvents = {
    onText: (text) => {
      // #3603 W8 — replace, not append. Mirrors chat-state-machine REPLACE
      // semantic so persisted content matches the UI's live render.
      // See `TurnPersistenceState.setText` for invariant + AC11 source.
      state.setText(text);
      sendToClient(userId, {
        type: "stream",
        content: text,
        partial: true,
        leaderId: CC_ROUTER_LEADER_ID,
      });
    },
    onToolUse: (block) => {
      // #2909 FR2 — silent-failure mirror for unregistered platform tools.
      // When `mcpServers === {}` (Phase 1 default), the Claude Agent SDK
      // rejects `mcp__soleur_platform__*` calls at model-validation time
      // and `canUseTool` is NEVER invoked. The model gets a `tool_result`
      // error with no Sentry signal — a silent-failure surface that violates
      // `cq-silent-fallback-must-mirror-to-sentry`. Mirror via
      // `mirrorWithDebounce` (per-(userId, errorClass) 5-min TTL) so a
      // misconfigured leader skill that loops on the same unregistered tool
      // cannot flood Sentry. Intrinsically scoped to cc-router because this
      // callback only fires from `dispatchSoleurGo` (legacy
      // `startAgentSession` is a separate path).
      if (shouldMirrorUnregisteredPlatformToolUse(block.name, CC_REGISTERED_PLATFORM_TOOL_NAMES)) {
        const safeToolName = sanitizeToolNameForLog(block.name);
        mirrorWithDebounce(
          null,
          {
            feature: "cc-mcp-tier",
            op: "unregistered-tool-invoked",
            message: `cc-router skill attempted unregistered platform tool ${safeToolName}`,
            extra: {
              toolName: safeToolName,
              toolUseId: block.toolUseId,
              userId,
              conversationId,
              leaderId: CC_ROUTER_LEADER_ID,
              mcpAllowlistConfigured: Boolean(process.env.CC_MCP_ALLOWLIST?.trim()),
            },
          },
          userId,
          "cc-mcp-tier:unregistered-tool",
        );
      }
      // `buildToolUseWSMessage` pins the #2138 invariant: the raw SDK tool
      // name is NOT placed on the wire (information-disclosure mitigation,
      // see PR #2115). Shared with `agent-runner.ts` so a future schema
      // change to `tool_use` flows through one edit, not two parallel ones.
      sendToClient(
        userId,
        buildToolUseWSMessage({
          name: block.name,
          input: block.input,
          workspacePath,
          leaderId: CC_ROUTER_LEADER_ID,
        }),
      );
    },
    onTextTurnEnd: () => {
      // #3603 W2 + W4 — `consumeForComplete` returns `null` if the turn was
      // already persisted via the abort path (silent no-op so a late
      // `onTextTurnEnd` cannot double-write or overwrite the aborted row).
      // Otherwise it snapshot-clear-bumps SYNCHRONOUSLY so a turn-N+1
      // `onResult` arriving on the same iterator yield cannot overwrite
      // turn N's snapshot.
      const consumed = state.consumeForComplete();
      if (consumed === null) return;
      // Fire-and-forget — user already saw the streamed text; helper mirrors on failure.
      void saveAssistantMessage(
        { kind: "complete", usage: consumed.usage },
        consumed.text,
      );
      // Per-turn boundary → terminal stream event for the cc_router bubble.
      // Without this, the client reducer keeps the bubble in
      // `state: "streaming"` (raw `whitespace-pre-wrap`), so markdown
      // (`**bold**`, `- ` bullets) renders as raw source. The
      // chat-state-machine `case "stream_end"` (chat-state-machine.ts:484-516)
      // already special-cases `cc_router` and transitions the bubble to
      // `state: "done"`, which engages MarkdownRenderer
      // (message-bubble.tsx:263).
      sendToClient(userId, {
        type: "stream_end",
        leaderId: CC_ROUTER_LEADER_ID,
      });
    },
    onWorkflowDetected: (_workflow) => {
      // Stage 3 emits a dedicated `workflow_started` WS event; for now
      // the sticky-workflow DB write in persistActiveWorkflow is the
      // single source of truth.
    },
    onWorkflowEnded: (end: WorkflowEnd) => {
      // #3603 W2 — flush partial assistant text as an `status: "aborted"` row
      // BEFORE the existing user-visible routing below. Mirrors the legacy
      // abort contract at `agent-runner.ts:2044-2055`. Skips on
      // `status: "completed"` because the normal `onTextTurnEnd` path
      // already wrote (or will write) the row. The `assistantTurnPersisted` flag
      // suppresses a late `onTextTurnEnd` arriving after this flush.
      // Use the typed `ABORT_FLUSH_STATUSES` set (exhaustively type-checked
      // via `_abortFlushExhaustive`) rather than a bare `!== "completed"` so
      // a future `WorkflowEnd` variant cannot silently route through abort
      // without a deliberate listing here.
      if (ABORT_FLUSH_STATUSES.has(end.status)) {
        const outcome = state.consumeForAbort();
        switch (outcome.kind) {
          case "text":
            // #3603 W4 text-present abort: state-class snapshot-clear-marks
            // SYNCHRONOUSLY so a late onTextTurnEnd cannot race the await.
            void saveAssistantMessage(
              { kind: "aborted", usage: outcome.usage },
              outcome.text,
            );
            break;
          case "orphan":
            // #3603 W4 orphan — usage captured but model produced ZERO text
            // (tool-only turn that then aborted). The empty-text path drops
            // the row (PR-A1 contract at `saveAssistantMessage` empty-drop);
            // P0-mirror the orphaned cost so operators can detect a runner
            // misconfiguration that strands cost telemetry. Dedup keyed on
            // `(userId, op, conversationId)` with 1h TTL.
            mirrorP0Deduped(new Error(CC_OP_SLUGS.usageOrphanDropped), {
              op: CC_OP_SLUGS.usageOrphanDropped,
              userId,
              conversationId,
            });
            break;
          case "none":
            break;
          default: {
            const _exhaustive: never = outcome;
            void _exhaustive;
          }
        }
      }
      // Architecture-F4: `session_ended` is terminal in `ws-client.ts`
      // (clears streams, disables input). Emitting it for RECOVERABLE
      // runner states (cost_ceiling, runner_runaway) would break
      // "user retries on next turn" UX. Stage 3 adds a dedicated
      // `workflow_ended` event; until then, route terminal statuses
      // to `session_ended` and recoverable statuses to a structured
      // error the client can surface without tearing down the
      // conversation.
      if (TERMINAL_WORKFLOW_END_STATUSES.has(end.status)) {
        sendToClient(userId, {
          type: "session_ended",
          reason: end.status,
        });
      } else if (end.status === "runner_runaway") {
        // Forward runaway diagnostics so an API client / agent can
        // distinguish idle-window from max-turn stalls and observe
        // which tool was last alive. Pino logs already capture this
        // server-side; the wire forwarding gives parity to consumers
        // without server log access. See #3225.
        sendToClient(userId, {
          type: "error",
          message: WORKFLOW_END_USER_MESSAGES[end.status],
          runnerRunawayReason: end.reason,
          runnerRunawayLastBlockKind: end.lastBlockKind,
          runnerRunawayLastBlockToolName: end.lastBlockToolName,
        });
      } else {
        sendToClient(userId, {
          type: "error",
          message: WORKFLOW_END_USER_MESSAGES[end.status],
        });
      }
      // Note: `_ccBashGates` cleanup is now handled centrally by the
      // runner's `onCloseQuery` hook (wired in `getSoleurGoRunner`),
      // which fires from `emitWorkflowEnded`/`reapIdle`/
      // `closeConversation`. No direct call needed here.
    },
    onResult: (result) => {
      // #3603 W4 — capture per-turn cost telemetry for attachment to the
      // assistant row that `onTextTurnEnd` writes. `totalCostUsd` is a
      // per-turn delta (`soleur-go-runner.ts` `handleResultMessage` —
      // `delta = msg.total_cost_usd ?? 0`), not a cumulative running total,
      // so the value is safe to attach verbatim. The `turnIndex` tag pins
      // capture to the active turn so a stale callback arriving after the
      // bump cannot misattribute to a later row.
      state.captureUsage(state.currentTurnIndex(), result.totalCostUsd);

      // Fire-and-forget per-turn cost write to the aggregation surface
      // (separate from messages.usage). Closes the cc-soleur-go path's
      // 60-90% under-count vs the Anthropic Console (#3626). The legacy
      // agent-runner.ts path uses the same helper. Turn termination must
      // not block on DB writes — `persistTurnCost` chains `.then()` for
      // error mirroring rather than awaiting; soleur-go-runner's onResult
      // try/catch covers the residual synchronous-throw surface.
      persistTurnCost(userId, conversationId, CC_ROUTER_LEADER_ID, result);
    },
    onSessionIdCaptured: (capturedSessionId) => {
      // #3266 — fire-and-forget DB persist + synchronous in-process cache
      // update. The cache update is load-bearing for the
      // runner-reap-but-WS-alive scenario: on the next chat-case turn the
      // ws-handler's warm-cache branch forwards `session.sessionId` to
      // `dispatchSoleurGo`, and a stale `null` would defeat the prefill
      // guard's history-probe activation. Fires synchronously BEFORE the
      // async DB write commits so the next turn can read the value even
      // if the user fires a follow-up before persistence lands.
      onSessionIdPersisted?.(capturedSessionId);
      void persistCcSessionId({
        userId,
        conversationId,
        sessionId: capturedSessionId,
      });
    },
  };

  try {
    await runner.dispatch({
      conversationId,
      userId,
      userMessage,
      currentRouting,
      events,
      persistActiveWorkflow,
      sessionId: sessionId ?? undefined,
      artifactPath,
      documentKind,
      documentContent,
      documentExtractError,
      documentExtractMeta,
      // 2026-05-06 Bug A1 fix — thread workspacePath through so the
      // runner builds the system prompt with workspace-absolute Read
      // instructions. Falls back to the locally-resolved value (set by
      // the `.then` above) when the caller didn't pre-resolve it.
      workspacePath: callerWorkspacePath ?? workspacePath,
    });
  } catch (err) {
    const errorClass =
      err instanceof KeyInvalidError
        ? "KeyInvalidError"
        : err instanceof Error
          ? err.constructor.name
          : "unknown";
    mirrorWithDebounce(
      err,
      {
        feature: "cc-dispatcher",
        op: "dispatch",
        extra: { conversationId, userId },
      },
      userId,
      `dispatch:${errorClass}`,
    );
    // R10 — KeyInvalidError surfaces with errorCode so the client can
    // prompt for a fresh BYOK key. Mirrors the KeyInvalidError →
    // errorCode: "key_invalid" branch in agent-runner.ts
    // handleSessionError. All other failures fall back to the generic
    // router-unavailable message without an errorCode.
    if (err instanceof KeyInvalidError) {
      sendToClient(userId, {
        type: "error",
        message: "Your API key is invalid — set up a fresh key to continue.",
        errorCode: "key_invalid",
      });
    } else {
      // #3266 R7 — stale-resume cleanup. The dispatch was attempted with
      // a persisted session_id but the runner rejected for a reason
      // other than KeyInvalidError. Plan §R7 documents this trade-off:
      // the predicate is broad ("any non-KeyInvalidError"), which means
      // a transient backend error (network blip, BYOK fetch failure,
      // workspace patch failure) will also clear a legitimate session_id
      // and force a cold-start on the next turn. Acceptable cost: the
      // SDK rebuilds from the persisted `messages` rows on next dispatch
      // and the prefill guard's history-probe handles assistant-
      // terminated threads — at most one turn of degraded latency.
      // Narrowing to typed SDK error classes is tracked separately and
      // is out of scope for the activation PR. Fire-and-forget; the
      // user-facing generic-error message lands either way. Update the
      // in-process cache alongside the DB write so the next chat-case
      // warm-cache turn does not forward the now-stale value.
      if (sessionId) {
        onSessionIdPersisted?.(null);
        void clearCcSessionId({ userId, conversationId });
      }
      sendToClient(userId, {
        type: "error",
        message: "Dashboard router is unavailable — try again shortly.",
      });
    }
    // Belt-and-suspenders: drain ccBashGates here too. The runner's
    // onCloseQuery hook covers normal close paths, but a dispatch-time
    // throw before the runner takes ownership of the Query may leave
    // stranded entries (e.g. concurrent register from a prior turn).
    cleanupCcBashGatesForConversation(userId, conversationId);
  }
}

// ---------------------------------------------------------------------------
// Interactive-prompt response case
// ---------------------------------------------------------------------------

export function handleInteractivePromptResponseCase(args: {
  userId: string;
  payload: InteractivePromptResponse;
  sendToClient: (userId: string, message: WSMessage) => boolean;
}): HandleInteractivePromptResponseResult {
  const { userId, payload, sendToClient } = args;
  const registry = getPendingPromptRegistry();
  const runner = getSoleurGoRunner(sendToClient);

  const result = handleInteractivePromptResponse({
    registry,
    userId,
    payload,
    deliverToolResult: ({ conversationId, toolUseId, content }) => {
      runner.respondToToolUse({ conversationId, toolUseId, content });
    },
  });

  if (!result.ok) {
    // Per `cq-silent-fallback-must-mirror-to-sentry`: do NOT silently
    // drop. Emit structured WS error + mirror. Mirror only on server
    // bugs, not expected client states — `already_consumed` is a
    // benign retry after success (client already saw ok); mirroring
    // would amplify Sentry noise. `not_found` could be session
    // reset / container restart (also benign from server POV).
    if (
      MIRROR_INTERACTIVE_RESPONSE_ERRORS.has(
        result.error as InteractivePromptResponseError,
      )
    ) {
      reportSilentFallback(
        new Error(`interactive_prompt_response rejected: ${result.error}`),
        {
          feature: "cc-dispatcher",
          op: "interactive_prompt_response",
          extra: { userId, error: result.error },
        },
      );
    }
    sendToClient(userId, {
      type: "error",
      message: `Interactive prompt response rejected: ${result.error}`,
      errorCode: "interactive_prompt_rejected",
    });
  }

  return result;
}

// ---------------------------------------------------------------------------
// Test seams — exported for unit tests; do not call from production code.
// ---------------------------------------------------------------------------

/**
 * Inject a stub SoleurGoRunner so tests can drive `dispatchSoleurGo`
 * without booting the real factory + SDK subprocess. Pairs with
 * `__resetDispatcherForTests` (clears between tests).
 */
export function __setCcRunnerForTests(stub: SoleurGoRunner): void {
  _runner = stub;
  // Mark sendToClient sentinel so getSoleurGoRunner's identity check
  // does not warn when tests pass a fresh sendToClient mock.
  _runnerSendToClient = null;
}

// Exported for test cleanup only. Double-underscore + explicit suffix
// signals the contract: do not call from production code paths.
export function __resetDispatcherForTests(): void {
  if (_reaperInterval) {
    clearInterval(_reaperInterval);
    _reaperInterval = null;
  }
  _registry = null;
  _rateLimiter = null;
  _runner = null;
  _runnerSendToClient = null;
  _ccBashGates.clear();
  __resetMirrorDebounceForTests();
  // The bash batched-approval cache lives in a sibling module
  // (`permission-callback-bash-batch.ts`) and is keyed by
  // `${userId}:${conversationId}`. Without draining it here, a granted
  // prefix in test A can survive into test B (cross-file leak via the
  // module-level Map). Mirrors the centralization Fix 6 of PR #2954.
  _resetBashApprovalCacheForTests();
  // Drain the workspace-path memo so a `users.workspace_path` swap in
  // tests is observable. Lives in `kb-document-resolver.ts` for the same
  // reason as the bash cache: shared across files, drained centrally.
  _resetWorkspacePathCacheForTests();
}

/**
 * #3603 W1 invariant-7 — install a stub that lets tests force the
 * write-boundary sentinel to return `false` at specific call sites,
 * proving every assistant-row write runs through `assertWriteScope`.
 * #3641 — relocated from the inline declaration adjacent to
 * `assertWriteScope` to this bottom-of-file test-seam block so all
 * test-only exports cluster in one place.
 */
export function __setAssertWriteScopeForTests(
  fn: (u: string, c: string) => boolean,
): void {
  // Defense-in-depth (PR-A2 security review H3): refuse to install the
  // override outside a test environment. Without this guard a malicious /
  // accidentally-imported call site in a prod-bundle code path could neutralize
  // the sentinel for the process lifetime — module-singleton state with no
  // caller authentication. Vitest sets `NODE_ENV=test`; production sets `production`.
  if (process.env.NODE_ENV === "production") {
    throw new Error(
      "__setAssertWriteScopeForTests is not callable in production builds",
    );
  }
  _assertWriteScopeOverride = fn;
}

export function __resetAssertWriteScopeForTests(): void {
  // Defense-in-depth (review #3670): symmetric with the setter's
  // production-refusal guard. Today reset is harmless (null → null), but
  // the sentinel is anticipated to become load-bearing when SDK callbacks
  // expose payload identifiers — an unguarded resetter could then be
  // called from an accidental prod-bundle import path to neutralize an
  // installed override that does real cross-tenant comparison.
  if (process.env.NODE_ENV === "production") {
    throw new Error(
      "__resetAssertWriteScopeForTests is not callable in production builds",
    );
  }
  _assertWriteScopeOverride = null;
}
