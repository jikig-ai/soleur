// Lazy singletons + orchestration layer for the Command Center
// `/soleur:go` runner. ws-handler delegates here; this module owns the
// per-process PendingPromptRegistry, StartSessionRateLimiter, and
// SoleurGoRunner instances.
//
// Stage 2 of plan 2026-04-23-feat-cc-route-via-soleur-go-plan.md
// (tasks 2.12, 2.13, 2.14, 2.17). Real-SDK `queryFactory` wiring is
// STUBBED for this commit — the stub throws a controlled error so the
// runner's own catch path mirrors to Sentry, `FLAG_CC_SOLEUR_GO=0`
// production deploys never invoke it. Tracking follow-up: #2853
// Stage 2.12 completion (bind SDK `query()` with per-user apiKey,
// serviceTokens, plugin.json-derived MCP allowlist, `canUseTool` from
// `permission-callback.ts`, and the sandbox block used at the
// `agent-runner.ts` `query(...)` call site — search `sandbox: {` in
// that file).

import type { WSMessage } from "@/lib/types";
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

// Production `queryFactory` stub. See module header for the follow-up
// scope. Intentionally throws at first use so the runner's
// `reportSilentFallback` fires (observability preserved) instead of
// silently producing a dead session. Under FLAG_CC_SOLEUR_GO=0 (default)
// the stub is unreachable; if the flag flips on before the real factory
// lands, `_stubMirroredOnce` gates the Sentry mirror so a high-QPS
// misconfigured prod does not exhaust the Sentry event quota
// (performance-oracle P2-A).
let _stubMirroredOnce = false;
const realSdkQueryFactoryStub: QueryFactory = (_args: QueryFactoryArgs) => {
  const err = new Error(
    "cc-dispatcher: real-SDK queryFactory not yet wired (FLAG_CC_SOLEUR_GO path) — see #2853 Stage 2.12 completion",
  );
  if (!_stubMirroredOnce) {
    _stubMirroredOnce = true;
    reportSilentFallback(err, {
      feature: "cc-dispatcher",
      op: "realSdkQueryFactoryStub",
      extra: { oncePerProcess: true },
    });
  }
  throw err;
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
    queryFactory: realSdkQueryFactoryStub,
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
    sendToClient(userId, {
      type: "error",
      message: "Command Center router is unavailable — try again shortly.",
    });
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
  _stubMirroredOnce = false;
}
