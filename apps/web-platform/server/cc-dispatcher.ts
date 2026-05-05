// Lazy singletons + orchestration layer for the Command Center
// `/soleur:go` runner. ws-handler delegates here; this module owns the
// per-process PendingPromptRegistry, StartSessionRateLimiter, and
// SoleurGoRunner instances.
//
// Stage 2.12 — bind real-SDK `query()` from `@anthropic-ai/claude-agent-sdk`
// inside `realSdkQueryFactory`. Behind FLAG_CC_SOLEUR_GO=0 in prod
// (default) this code path is unreachable; in dev (FLAG_CC_SOLEUR_GO=1)
// the runner actually invokes the SDK end-to-end. See plan
// `2026-04-27-feat-stage-2-12-real-sdk-query-factory-binding-plan.md`.
//
// V2 follow-ups tracked in #2853 backlog (V2-13: tier-classify in-process
// MCP servers for cc-soleur-go path — referenced in factory body).

import path from "path";

import type { Query } from "@anthropic-ai/claude-agent-sdk";
import { query as sdkQuery } from "@anthropic-ai/claude-agent-sdk";

import type { WSMessage, Conversation } from "@/lib/types";
import { KeyInvalidError, STATUS_LABELS } from "@/lib/types";

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
import { reportSilentFallback } from "./observability";
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

// Re-export so existing call sites keep working.
export { resolveConciergeDocumentContext } from "./kb-document-resolver";
import { buildAgentQueryOptions } from "./agent-runner-query-options";
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

// ---------------------------------------------------------------------------
// Sentry mirror debounce — per (userId, errorClass) 5-minute TTL.
// Prevents a misconfigured prod (1 QPS = 86k events/day per failure
// mode) from flooding Sentry when `realSdkQueryFactory` or
// `dispatchSoleurGo` catch repeatedly mirrors the same class for one
// user. First report mirrors; subsequent reports within the window are
// dropped. The error still propagates to the client unchanged — only
// the Sentry write is debounced.
// ---------------------------------------------------------------------------

const MIRROR_DEBOUNCE_MS = 5 * 60 * 1000;
const _mirrorLastReportedAt = new Map<string, number>();

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

function mirrorWithDebounce(
  err: unknown,
  ctx: Parameters<typeof reportSilentFallback>[1],
  userId: string,
  errorClass: string,
): void {
  const key = `${userId}:${errorClass}`;
  const now = Date.now();
  const last = _mirrorLastReportedAt.get(key);
  if (last !== undefined && now - last < MIRROR_DEBOUNCE_MS) {
    return;
  }
  _mirrorLastReportedAt.set(key, now);
  reportSilentFallback(err, ctx);
}

// ---------------------------------------------------------------------------
// Singletons
// ---------------------------------------------------------------------------

let _registry: PendingPromptRegistry | null = null;
let _reaperInterval: ReturnType<typeof setInterval> | null = null;
const REAPER_INTERVAL_MS = 5 * 60 * 1000;

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
// realSdkQueryFactory — Stage 2.12 binding (replaces the prior stub
// that throw-mirrored to Sentry under FLAG_CC_SOLEUR_GO).
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

  // Defense-in-depth: strip stale pre-approved file-tool entries from
  // the workspace's `.claude/settings.json` so they cannot bypass
  // `canUseTool` (permission chain step 4 before step 5). Idempotent.
  // Async per #2918 — the lock keyed on workspacePath prevents the
  // legacy + cc paths from racing on the same workspace.
  await patchWorkspacePermissions(workspacePath);

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
        systemPrompt: args.systemPrompt,
        resumeSessionId: args.resumeSessionId,
        mcpServers: {},
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
    userMessage,
    currentRouting,
    sessionId,
    sendToClient,
    persistActiveWorkflow,
    artifactPath,
    documentKind,
    documentContent,
  } = args;

  const runner = getSoleurGoRunner(sendToClient);

  const events: DispatchEvents = {
    onText: (text) => {
      sendToClient(userId, {
        type: "stream",
        content: text,
        partial: true,
        leaderId: CC_ROUTER_LEADER_ID,
      });
    },
    onToolUse: (block) => {
      sendToClient(userId, {
        type: "tool_use",
        leaderId: CC_ROUTER_LEADER_ID,
        label: block.name,
      });
    },
    onTextTurnEnd: () => {
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
    onResult: (_result) => {
      // Usage totals bubble via `usage_update`; wire in Stage 3 when
      // the aggregate conversation cost reader lands.
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
      sendToClient(userId, {
        type: "error",
        message: "Command Center router is unavailable — try again shortly.",
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
  _mirrorLastReportedAt.clear();
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
