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
// `permission-callback.ts`, and sandbox block copied from
// `agent-runner.ts:807-829`).

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
export function getPendingPromptRegistry(): PendingPromptRegistry {
  if (!_registry) _registry = new PendingPromptRegistry();
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
// silently producing a dead session.
const realSdkQueryFactoryStub: QueryFactory = (_args: QueryFactoryArgs) => {
  throw new Error(
    "cc-dispatcher: real-SDK queryFactory not yet wired (FLAG_CC_SOLEUR_GO path) — see #2853 Stage 2.12 completion",
  );
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
        leaderId: "system",
      });
    },
    onToolUse: (block) => {
      sendToClient(userId, {
        type: "tool_use",
        leaderId: "system",
        label: block.name,
      });
    },
    onWorkflowDetected: (_workflow) => {
      // Stage 3 emits a dedicated `workflow_started` WS event; for now
      // the sticky-workflow DB write in persistActiveWorkflow is the
      // single source of truth.
    },
    onWorkflowEnded: (end: WorkflowEnd) => {
      sendToClient(userId, {
        type: "session_ended",
        reason: end.status,
      });
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
    // drop. Emit structured WS error + mirror.
    reportSilentFallback(
      new Error(`interactive_prompt_response rejected: ${result.error}`),
      {
        feature: "cc-dispatcher",
        op: "interactive_prompt_response",
        extra: { userId, error: result.error },
      },
    );
    sendToClient(userId, {
      type: "error",
      message: `Interactive prompt response rejected: ${result.error}`,
    });
  }

  return result;
}

// Exported for test cleanup / horizontal-scale-out shim (V2).
export function __resetDispatcherForTests(): void {
  _registry = null;
  _rateLimiter = null;
  _runner = null;
  _runnerSendToClient = null;
}

export type { InteractivePromptEvent };
