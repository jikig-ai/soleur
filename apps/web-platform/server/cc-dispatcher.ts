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

import type { PermissionMode, Query } from "@anthropic-ai/claude-agent-sdk";
import { query as sdkQuery } from "@anthropic-ai/claude-agent-sdk";

import type { WSMessage } from "@/lib/types";
import { KeyInvalidError } from "@/lib/types";
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
import type {
  InteractivePromptEvent,
  InteractivePromptResponse,
} from "./cc-interactive-prompt-types";
import {
  type ConversationRouting,
  type WorkflowName,
} from "./conversation-routing";
import { reportSilentFallback } from "./observability";
import {
  getUserApiKey,
  getUserServiceTokens,
  patchWorkspacePermissions,
} from "./agent-runner";
import { buildAgentSandboxConfig } from "./agent-runner-sandbox-config";
import { buildAgentEnv } from "./agent-env";
import { createSandboxHook } from "./sandbox-hook";
import {
  createCanUseTool,
  type CanUseToolDeps,
} from "./permission-callback";
import { abortableReviewGate, type AgentSession } from "./review-gate";
import { sendToClient as defaultSendToClient } from "./ws-handler";
import { notifyOfflineUser } from "./notifications";
import { createChildLogger } from "./logger";

const log = createChildLogger("cc-dispatcher");

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
//   - `leaderId: "cc_router"` — non-routable internal leader for
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

async function fetchUserWorkspacePath(userId: string): Promise<string> {
  const { data, error } = await supabase()
    .from("users")
    .select("workspace_path")
    .eq("id", userId)
    .single();
  if (error || !data?.workspace_path) {
    throw new Error("Workspace not provisioned");
  }
  return data.workspace_path as string;
}

export const realSdkQueryFactory: QueryFactory = (args: QueryFactoryArgs): Query => {
  // Async work happens inside an IIFE that builds the Query; the SDK's
  // `query()` is itself synchronous (it returns an async iterator that
  // lazily starts the subprocess). We therefore wrap the per-user
  // fetches in a thenable that forwards to `sdkQuery` after credentials
  // resolve. The runner's `queryFactory` contract returns `Query`
  // synchronously, so we materialize the async work via Promise.all
  // inside the factory's call site (which is itself awaited by
  // `soleur-go-runner.ts dispatch`'s try/catch around `queryFactory`).
  //
  // QueryFactory is typed as `(args) => Query`. The runner calls it
  // synchronously and then iterates the returned Query asynchronously.
  // To bridge BYOK + workspace fetches that ARE async, we throw an
  // error path is naturally caught by the runner's queryFactory catch
  // block (which mirrors to Sentry per `cq-silent-fallback-must-mirror-to-sentry`).
  //
  // Implementation: this thunk wraps `sdkQuery` in a deferred-start
  // shape — the inner `query()` is invoked once user data resolves.
  // We yield a Query proxy that defers iteration until the inner
  // query is built.
  return buildDeferredQuery(args);
};

function buildDeferredQuery(args: QueryFactoryArgs): Query {
  // The real SDK `Query` is an AsyncIterable + .close() + .interrupt() etc.
  // We expose a minimal proxy that lazily resolves the inner Query
  // before delegating each method.
  let innerPromise: Promise<Query> | null = null;

  const ensureInner = (): Promise<Query> => {
    if (innerPromise) return innerPromise;
    innerPromise = (async (): Promise<Query> => {
      const workspacePath = await fetchUserWorkspacePath(args.userId);
      const [apiKey, serviceTokens] = await Promise.all([
        getUserApiKey(args.userId),
        getUserServiceTokens(args.userId),
      ]);

      // Defense-in-depth: strip stale pre-approved file-tool entries
      // from the workspace's `.claude/settings.json` so they cannot
      // bypass `canUseTool` (permission chain step 4 before step 5).
      // Idempotent.
      patchWorkspacePermissions(workspacePath);

      const pluginPath = path.join(workspacePath, "plugins", "soleur");

      // Synthetic AgentSession — the only place in the cc path where
      // an AgentSession exists. Registered into `_ccBashGates` per
      // Bash review-gate (Option A). The controller is bound to the
      // Query lifetime; closeConversation/reapIdle abort it.
      const controller = new AbortController();
      const session: AgentSession = {
        abort: controller,
        reviewGateResolvers: new Map(),
        sessionId: null,
      };

      // Bridge `permission-callback.ts createCanUseTool` Bash branch
      // into the cc-soleur-go review-gate transport. The callback
      // emits `review_gate` via deps.sendToClient and awaits a
      // `resolveCcBashGate(...)` resolution; we register the synthetic
      // session under the gateId so ws-handler can find it.
      //
      // The deps below mirror the legacy runner's `CanUseToolDeps` shape;
      // `abortableReviewGate` is the same module-level helper. The
      // cc-side wiring augments it with a registration callback so the
      // synthetic session is discoverable via `_ccBashGates` for the
      // duration of the gate.
      const ccDeps: CanUseToolDeps = {
        abortableReviewGate: (
          ccSession,
          gateId,
          signal,
          timeoutMs,
          options,
        ) => {
          // Register BEFORE creating the awaitable promise so a
          // synchronous `resolveCcBashGate` cannot race. The promise
          // body inside `abortableReviewGate` synchronously sets the
          // `reviewGateResolvers` entry too — registration is purely
          // about routing the WS response back to this synthetic
          // session.
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
        updateConversationStatus: async (_convId: string, _status: string) => {
          // V1: cc-soleur-go path does not write conversation status
          // for review-gate transitions. The runner already handles
          // workflow lifecycle via `onWorkflowEnded`. Future V2 may
          // add a "waiting_for_user"/"active" toggle here.
        },
      };

      try {
        return sdkQuery({
          prompt: args.prompt,
          options: {
            cwd: workspacePath,
            model: "claude-sonnet-4-6",
            permissionMode: "default",
            // settingSources: [] — defense-in-depth alongside
            // `patchWorkspacePermissions`. Prevents the SDK from
            // loading project `.claude/settings.json` whose
            // `permissions.allow` would bypass `canUseTool`.
            settingSources: [],
            includePartialMessages: true,
            ...(args.resumeSessionId ? { resume: args.resumeSessionId } : {}),
            systemPrompt: args.systemPrompt,
            env: buildAgentEnv(apiKey, serviceTokens),
            // R7 — mirror legacy runner. WebSearch/WebFetch denied so
            // the router cannot fetch arbitrary URLs.
            disallowedTools: ["WebSearch", "WebFetch"],
            // V1 — empty MCP allowlist. V2-13 (#2909) tracks
            // tier-classification of `kb_share_*`, `conversations_*`,
            // `github_*`, `plausible_*` for this path before widening.
            mcpServers: {},
            sandbox: buildAgentSandboxConfig(workspacePath),
            plugins: [{ type: "local" as const, path: pluginPath }],
            hooks: {
              PreToolUse: [
                {
                  matcher: "Read|Write|Edit|Glob|Grep|LS|NotebookRead|NotebookEdit|Bash",
                  hooks: [createSandboxHook(workspacePath)],
                },
              ],
              SubagentStart: [
                {
                  hooks: [
                    async (input) => {
                      const subInput = input as Record<string, unknown>;
                      const sanitize = (v: unknown) =>
                        String(v ?? "").replace(/[\r\n]/g, " ").slice(0, 200);
                      log.info(
                        {
                          sec: true,
                          agentId: sanitize(subInput.agent_id),
                          agentType: sanitize(subInput.agent_type),
                          ccPath: true,
                        },
                        "Subagent started (cc-soleur-go)",
                      );
                      return {};
                    },
                  ],
                },
              ],
            },
            canUseTool: createCanUseTool({
              userId: args.userId,
              conversationId: args.conversationId,
              // R-AC14: non-undefined leaderId so `logPermissionDecision`
              // attributes the cc path. `cc_router` is a non-routable
              // leader id reserved for this purpose.
              leaderId: "cc_router",
              workspacePath,
              platformToolNames: [],
              pluginMcpServerNames: [],
              repoOwner: "",
              repoName: "",
              session,
              controllerSignal: controller.signal,
              deps: ccDeps,
            }),
          },
        });
      } catch (err) {
        // Mirror the `agent-runner.ts:1136-1141` precedent — tag the
        // sandbox-required-but-unavailable substring under
        // `feature: "agent-sandbox"`. Other inner throws bubble up to
        // the runner's own queryFactory catch (which mirrors under
        // `feature: "soleur-go-runner"`).
        const errMsg = err instanceof Error ? err.message : String(err);
        if (errMsg.includes("sandbox required but unavailable")) {
          reportSilentFallback(err, {
            feature: "agent-sandbox",
            op: "sdk-startup",
            extra: {
              userId: args.userId,
              conversationId: args.conversationId,
              leaderId: "cc_router",
            },
          });
        }
        throw err;
      }
    })();
    return innerPromise;
  };

  // Build the Query proxy. The runner only consumes `[Symbol.asyncIterator]`
  // and `.close()`; we forward both via the inner promise.
  const proxy: Query = {
    [Symbol.asyncIterator](): AsyncIterator<unknown> {
      let inner: AsyncIterator<unknown> | null = null;
      return {
        async next(): Promise<IteratorResult<unknown>> {
          if (!inner) {
            const q = await ensureInner();
            inner = (q as AsyncIterable<unknown>)[Symbol.asyncIterator]();
          }
          return inner.next();
        },
        async return(value?: unknown): Promise<IteratorResult<unknown>> {
          if (inner?.return) return inner.return(value);
          return { value: undefined, done: true };
        },
        async throw(e?: unknown): Promise<IteratorResult<unknown>> {
          if (inner?.throw) return inner.throw(e);
          throw e;
        },
      };
    },
    close: async () => {
      if (innerPromise) {
        try {
          const inner = await innerPromise;
          await inner.close();
        } catch (err) {
          // Best-effort close; surface unexpected errors.
          reportSilentFallback(err, {
            feature: "cc-dispatcher",
            op: "realSdkQueryFactory.close",
            extra: { userId: args.userId, conversationId: args.conversationId },
          });
        }
      }
    },
    interrupt: async () => {
      if (innerPromise) {
        const inner = await innerPromise;
        if (inner.interrupt) await inner.interrupt();
      }
    },
    setPermissionMode: async (mode: PermissionMode) => {
      if (innerPromise) {
        const inner = await innerPromise;
        if (inner.setPermissionMode) await inner.setPermissionMode(mode);
      }
    },
    setModel: async (model?: string) => {
      if (innerPromise) {
        const inner = await innerPromise;
        if (inner.setModel) await inner.setModel(model);
      }
    },
    supportedCommands: async () => {
      const inner = await ensureInner();
      return inner.supportedCommands();
    },
    supportedModels: async () => {
      const inner = await ensureInner();
      return inner.supportedModels();
    },
    mcpServerStatus: async () => {
      const inner = await ensureInner();
      return inner.mcpServerStatus();
    },
    // biome-ignore lint/suspicious/noExplicitAny: Query union surface differs by SDK minor
  } as any;

  // Trigger eager build so factory-time errors (BYOK fetch, sandbox
  // probe) propagate through the runner's own queryFactory catch
  // (which mirrors under `feature: "soleur-go-runner"`). Without this,
  // the inner failure would only fire on first `.next()` — too late
  // for the runner's per-conversation observability tag.
  void ensureInner().catch(() => {
    // Swallow here; the iterator's `.next()` will re-surface the same
    // error (the promise is cached). The runner's queryFactory catch
    // only wraps the SYNCHRONOUS factory call — async failures must
    // surface via the iterator path.
  });

  return proxy;
}

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
  } = args;

  const runner = getSoleurGoRunner(sendToClient);

  const events: DispatchEvents = {
    onText: (text) => {
      sendToClient(userId, {
        type: "stream",
        content: text,
        partial: true,
        leaderId: "cc_router",
      });
    },
    onToolUse: (block) => {
      sendToClient(userId, {
        type: "tool_use",
        leaderId: "cc_router",
        label: block.name,
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
      const TERMINAL: ReadonlySet<WorkflowEnd["status"]> = new Set<
        WorkflowEnd["status"]
      >([
        "completed",
        "user_aborted",
        "idle_timeout",
        "plugin_load_failure",
        "internal_error",
      ]);
      if (TERMINAL.has(end.status)) {
        sendToClient(userId, {
          type: "session_ended",
          reason: end.status,
        });
      } else {
        sendToClient(userId, {
          type: "error",
          message: `Workflow ended (${end.status}) — retry to continue.`,
        });
      }
      // Drain any cc Bash gates for the conversation — the synthetic
      // session is no longer reachable.
      cleanupCcBashGatesForConversation(userId, conversationId);
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
    });
  } catch (err) {
    reportSilentFallback(err, {
      feature: "cc-dispatcher",
      op: "dispatch",
      extra: { conversationId, userId },
    });
    // R10 — KeyInvalidError surfaces with errorCode so the client can
    // prompt for a fresh BYOK key (mirrors `agent-runner.ts:1149`).
    // All other failures fall back to the generic router-unavailable
    // message without an errorCode.
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
    // Drain cc Bash gates so a stranded synthetic session does not
    // hold a resolver open until TTL.
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
    const MIRROR: ReadonlySet<typeof result.error> = new Set<
      typeof result.error
    >(["invalid_payload", "invalid_response", "kind_mismatch"]);
    if (MIRROR.has(result.error)) {
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
}
