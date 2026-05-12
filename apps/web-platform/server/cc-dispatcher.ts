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
import { createServiceClient } from "@/lib/supabase/service";
import {
  createSoleurGoRunner,
  type SoleurGoRunner,
  type QueryFactory,
  type QueryFactoryArgs,
  type DispatchEvents,
  type WorkflowEnd,
} from "./soleur-go-runner";
import { readCcCostCaps } from "./cc-cost-caps";
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
import { updateConversationFor } from "./conversation-writer";
import {
  getUserApiKey,
  getUserServiceTokens,
  patchWorkspacePermissions,
} from "./agent-runner";
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

// #3603 W1 — Write-boundary tenant-isolation sentinel.
//
// cc-dispatcher.ts uses the service-role Supabase client (`supabase()` —
// see `createServiceClient` import) for the `messages` INSERT path, which
// **bypasses RLS on writes**. RLS catches reads only. A bug routing user A's
// dispatch with user B's `conversation_id` would write into B's conversation
// undetected. This helper is the single sentinel call site that every
// assistant-row write runs through.
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
// assistant-row write call site runs through the helper.
let _assertWriteScopeOverride:
  | ((u: string, c: string) => boolean)
  | null = null;

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
  _assertWriteScopeOverride = null;
}

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

/**
 * User-facing copy for each `WorkflowEndStatus`. Replaces the previous
 * ad-hoc `"Workflow ended (${status}) — retry to continue."` template
 * which leaked an internal status enum to the user.
 *
 * Type-level exhaustiveness: `Record<WorkflowEndStatus, string>` forces
 * every union variant to have an entry — adding a new status to the
 * runner without updating this map is a TS error here. The
 * `_exhaustive: never` rail below is belt-and-suspenders for the rare
 * case where the union is widened via an intersection.
 *
 * Empty string for `"completed"` — that branch is handled via the
 * terminal `session_ended` WS event and never produces a user-visible
 * error message; the empty string is intentional and asserted by the
 * snapshot test.
 */
export const WORKFLOW_END_USER_MESSAGES: Record<WorkflowEndStatus, string> = {
  completed: "",
  cost_ceiling:
    "This conversation reached the per-workflow cost cap. Start a new conversation to continue.",
  runner_runaway:
    "The agent went idle without finishing. Try sending another message to nudge it forward.",
  user_aborted: "Conversation stopped at your request.",
  idle_timeout:
    "This conversation was idle for too long and was closed. Start a new conversation to continue.",
  plugin_load_failure:
    "The agent could not start because a plugin failed to load. Try again shortly.",
  internal_error: "Something went wrong on our side. Try sending the message again.",
};

// Compile-time exhaustiveness rail. If a new variant lands in
// `WorkflowEnd["status"]` without an entry above, this assertion will
// fail (the type narrows to `never` for the missing key).
const _workflowEndExhaustive: Record<WorkflowEndStatus, string> =
  WORKFLOW_END_USER_MESSAGES;
void _workflowEndExhaustive;

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
 * Hard-block list for the cc-soleur-go path (#3338).
 *
 * Two SDK options govern tool surface, with DIFFERENT semantics
 * (sdk.d.ts:855-892):
 *   - `allowedTools`: AUTO-APPROVE list — pre-approves without canUseTool.
 *   - `disallowedTools`: HARD-BLOCK list — removes from model context entirely.
 *   - `tools`: closed allowlist of available built-ins (alternative to
 *     disallowedTools).
 *
 * The cc-router's job is to dispatch via the Skill tool to a routed sub-skill;
 * it never needs Bash, Edit, or Write itself. We add Bash/Edit/Write to
 * `disallowedTools` so the model literally cannot emit them — without this,
 * Bash falls through to `canUseTool` and pops the review_gate modal in the
 * end-user Concierge surface (the bug this PR fixes).
 *
 * The auto-approve list (`CC_PATH_ALLOWED_TOOLS`) is kept as a separate
 * concern: it eliminates a `canUseTool` round-trip for read-only tools
 * (Read, Glob, Grep, LS, NotebookRead, TodoWrite, ExitPlanMode) the cc-router
 * legitimately uses on its own. This is auto-approve, not restriction.
 *
 * Routed sub-skills load their own toolset via the soleur plugin and the
 * legacy domain-leader path (`agent-runner.ts startAgentSession`), so this
 * narrowing is scoped to the cc-router only — exploration within routed
 * workflows is unaffected.
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
 */
const CC_PATH_DISALLOWED_TOOLS: readonly string[] = ["Bash", "Edit", "Write"];

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

let _supabase: ReturnType<typeof createServiceClient> | null = null;
function supabase() {
  if (!_supabase) _supabase = createServiceClient();
  return _supabase;
}

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
  const [workspacePath, apiKey, serviceTokens] = await Promise.all([
    fetchUserWorkspacePath(args.userId),
    getUserApiKey(args.userId),
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
    // V1 — empty MCP allowlist. V2-13 (#2909) tracks
    // tier-classification of `kb_share_*`, `conversations_*`,
    // `github_*`, `plausible_*` for this path before widening.
    return sdkQuery({
      prompt: args.prompt,
      options: buildAgentQueryOptions({
        workspacePath,
        pluginPath,
        apiKey,
        serviceTokens,
        systemPrompt: effectiveSystemPrompt,
        resumeSessionId: safeResumeSessionId,
        mcpServers: {},
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
  const messageId = randomUUID();
  const { error: insertErr } = await supabase().from("messages").insert({
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
  let userMessage = rawUserMessage;
  if (attachments && attachments.length > 0) {
    const { attachmentContext } = await persistAndDownloadAttachments({
      supabase: supabase(),
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

  // Holds the LATEST SDKAssistantMessage emission for this turn. Mirrors
  // the chat-state-machine REPLACE semantic at `chat-state-machine.ts:477`
  // (`applyStreamEvent` case "stream") so DB hydration on tab reload
  // matches what the user saw live. #3603 W8 — pre-2026-05-12 the
  // accumulator concatenated all emissions (`+=`); AC11 verification
  // on conversation 36df3694 surfaced the drift between persisted content
  // and live UI. Invariant: the value at the instant `onTextTurnEnd`
  // fires (or `onWorkflowEnded` flushes for the abort path) is what
  // persists. No reordering, no merge.
  let latestAssistantText = "";
  // #3603 W2 — flushed by `onWorkflowEnded` for non-`completed` statuses
  // so a late `onTextTurnEnd` (in-flight SDK callback after abort fires)
  // cannot double-write or overwrite the abort row. Closure-scoped per
  // dispatch invocation; fresh `false` for each `dispatchSoleurGo` call.
  let assistantTurnPersisted = false;
  // #3603 W4 — per-turn cost telemetry captured pre-`onTextTurnEnd`.
  // `currentTurnIndex` is the closure-scoped turn counter; `pendingTurnUsage`
  // holds the cost captured by `onResult` tagged with the turnIndex active at
  // capture time, so a stale `onResult` interleaved across microtasks cannot
  // attach to a later turn. Both reset by `onTextTurnEnd` (snapshot-clear-bump
  // synchronously before the save's await) and by the abort path so an
  // orphaned usage cannot bleed into a subsequent callback.
  let currentTurnIndex = 0;
  let pendingTurnUsage: { turnIndex: number; costUsd: number } | null = null;

  // #3603 W4 — cc-path narrows the type-wide `Message.usage` shape to
  // cost-only on `'complete'` turns (Art. 5(1)(c) data-minimization). The
  // legacy agent-runner path emits the full `UsageSnapshot` (input_tokens,
  // output_tokens, cost_usd, completed_actions[]) on `'aborted'` turns —
  // see `Message.usage` doc-comment in `lib/types.ts`.
  type AssistantPersistMode = "complete" | "aborted";
  interface AssistantPersistOpts {
    mode: AssistantPersistMode;
    usage?: { costUsd: number } | null;
  }

  async function saveAssistantMessage(opts: AssistantPersistOpts): Promise<void> {
    // #3603 W1 — Cross-tenant write-boundary sentinel. cc-path uses
    // service-role for INSERT (RLS-bypass on writes). RLS catches reads;
    // this guard catches writes. Returns `false` only via the test seam
    // today (sentinel placeholder); load-bearing call site for a future
    // SDK-payload-derived identifier comparison. See `assertWriteScope`
    // module-level doc.
    if (!assertWriteScope(userId, conversationId)) return;

    // Snapshot-then-reset must precede `await` so a turn N+1 `onText` cannot
    // mutate `fullText` while this insert is in flight (single async loop
    // serializes onText/onTextTurnEnd, but the await yields the microtask).
    const fullText = latestAssistantText;
    latestAssistantText = "";
    if (!fullText) return;

    // #3603 W4 — gated single-read site for `CC_PERSIST_USAGE`. The hot-path
    // env read is intentional: enables runtime rollback flip without a
    // process restart, load-bearing for a GDPR-rollback scenario after PR-C.
    // Exact-match `"true"` only — any other truthy string keeps the flag
    // off (defense-in-depth against a half-set Doppler value). Default-off
    // at merge per AC9/AC11.
    const flagOn = process.env.CC_PERSIST_USAGE === "true";
    // #3603 PR-A2 review H4 — first-true observation per process gives the
    // Art. 33 72h-clock a "when did we start collecting" evidence anchor,
    // independent of when the Doppler flip happened. Module-scoped boolean
    // ensures we mirror once, not on every persist call.
    if (flagOn) _observeCcPersistUsageFirstTrue();
    const usageColumn =
      flagOn && opts.usage ? { cost_usd: opts.usage.costUsd } : null;

    const row: Record<string, unknown> = {
      id: randomUUID(),
      conversation_id: conversationId,
      role: "assistant",
      content: fullText,
      tool_calls: null,
      leader_id: CC_ROUTER_LEADER_ID,
      usage: usageColumn,
    };
    // Omit `status` for the normal completion path — migration 040's
    // DEFAULT of `'complete'` applies. Only the abort branch writes
    // `status: "aborted"` explicitly.
    if (opts.mode === "aborted") {
      row.status = "aborted";
    }

    // Hoisted op slug so `mirrorWithDebounce` receives the same value for
    // both `op` and `errorClass` (the dedupe key) — drift between them
    // would silently split the Sentry dedupe stream.
    const opSlug = opts.mode === "aborted"
      ? CC_OP_SLUGS.saveAssistantAborted
      : CC_OP_SLUGS.saveAssistant;

    const { error } = await supabase().from("messages").insert(row);
    if (error) {
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
  }

  const events: DispatchEvents = {
    onText: (text) => {
      // #3603 W8 — replace, not append. Mirrors chat-state-machine REPLACE
      // semantic so persisted content matches the UI's live render.
      // See accumulator declaration comment above for invariant + AC11 source.
      latestAssistantText = text;
      sendToClient(userId, {
        type: "stream",
        content: text,
        partial: true,
        leaderId: CC_ROUTER_LEADER_ID,
      });
    },
    onToolUse: (block) => {
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
      // #3603 W2 — a late `onTextTurnEnd` after `onWorkflowEnded` has already
      // flushed an abort row would double-write or, worse, overwrite the
      // "aborted" status row with a "complete" one. Silent no-op:
      // user already saw the partial text (rendered live; abort row hydrates).
      if (assistantTurnPersisted) {
        // silent: turn was already persisted via the abort path
        return;
      }
      // #3603 W4 — snapshot-clear-bump SYNCHRONOUSLY before the save's
      // microtask yield. Without this, a turn-N+1 `onResult` arriving on the
      // same iterator yield could overwrite `pendingTurnUsage` before we
      // read it, attaching turn N+1's cost to turn N's row.
      const turnSnapshot = currentTurnIndex;
      const turnUsage =
        pendingTurnUsage?.turnIndex === turnSnapshot ? pendingTurnUsage : null;
      pendingTurnUsage = null;
      currentTurnIndex = turnSnapshot + 1;
      // Fire-and-forget — user already saw the streamed text; helper mirrors on failure.
      void saveAssistantMessage({
        mode: "complete",
        usage: turnUsage ? { costUsd: turnUsage.costUsd } : null,
      });
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
        if (latestAssistantText.length > 0) {
          // #3603 W4 — text-present abort: capture the per-turn usage tagged
          // to the active turn index, then clear pendingTurnUsage so a late
          // onTextTurnEnd cannot re-attach the stale value. Set
          // `assistantTurnPersisted = true` SYNCHRONOUSLY so the late onTextTurnEnd
          // cannot race the await microtask.
          const turnUsage =
            pendingTurnUsage?.turnIndex === currentTurnIndex
              ? pendingTurnUsage
              : null;
          pendingTurnUsage = null;
          assistantTurnPersisted = true;
          void saveAssistantMessage({
            mode: "aborted",
            usage: turnUsage ? { costUsd: turnUsage.costUsd } : null,
          });
        } else if (pendingTurnUsage) {
          // #3603 W4 orphan — usage captured but model produced ZERO text
          // (tool-only turn that then aborted). The empty-text path drops
          // the row (PR-A1 contract at `saveAssistantMessage` empty-drop);
          // P0-mirror the orphaned cost so operators can detect a runner
          // misconfiguration that strands cost telemetry. Dedup keyed on
          // `(userId, op, conversationId)` with 1h TTL.
          pendingTurnUsage = null;
          mirrorP0Deduped(new Error(CC_OP_SLUGS.usageOrphanDropped), {
            op: CC_OP_SLUGS.usageOrphanDropped,
            userId,
            conversationId,
          });
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
      pendingTurnUsage = { turnIndex: currentTurnIndex, costUsd: result.totalCostUsd };

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
