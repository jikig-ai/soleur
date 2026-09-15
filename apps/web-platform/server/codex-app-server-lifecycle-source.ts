import type {
  EngineInput,
  EngineRunContext,
  EngineRunStatus,
  NativeSessionReference,
} from "./agent-engine-contract";
import type { CodexCredentialLease, CodexAppServerEventSource } from "./codex-code-adapter";
import { createCodexAppServerSession, type CodexAppServerSession } from "./codex-app-server-session";
import type { CodexAppServerStdioConnection } from "./codex-app-server-stdio";
import { createCodexReplayEvent, translateCodexPersistedItem, translateCodexPersistedTurn } from "./codex-code-message-translator";

export interface CodexAppServerLifecycleSourceOptions {
  open(lease: CodexCredentialLease): Promise<CodexAppServerStdioConnection>;
  nextRequestId: () => string;
  cwd?: string;
}

interface RuntimeConnection {
  connection: CodexAppServerStdioConnection;
  session: CodexAppServerSession;
  thread: NativeSessionReference | null;
  turnId: string | null;
}

function assertLease(lease: CodexCredentialLease): void {
  if (!Number.isFinite(lease.expiresAt) || lease.expiresAt <= Date.now()) {
    throw Object.assign(new Error("Codex credential lease expired"), { code: "codex_credential_expired" });
  }
}

function statusType(value: unknown): string | null {
  if (typeof value === "string") return value;
  if (value && typeof value === "object" && !Array.isArray(value)) {
    const type = (value as { type?: unknown }).type;
    return typeof type === "string" ? type : null;
  }
  return null;
}

function reconcileStatus(result: Record<string, unknown>, expectedThreadId: string): EngineRunStatus {
  const rawThread = result.thread;
  if (!rawThread || typeof rawThread !== "object" || Array.isArray(rawThread)) {
    throw Object.assign(new Error("Codex reconciliation result is invalid"), { code: "codex_reconcile_invalid" });
  }
  const thread = rawThread as { id?: unknown; status?: unknown; turns?: unknown };
  if (thread.id !== expectedThreadId || !Array.isArray(thread.turns)) {
    throw Object.assign(new Error("Codex reconciliation thread is invalid"), { code: "codex_reconcile_invalid" });
  }
  const latest = thread.turns.at(-1);
  const latestStatus = latest && typeof latest === "object" && !Array.isArray(latest)
    ? statusType((latest as { status?: unknown }).status)
    : null;
  if (latestStatus === "inProgress" || latestStatus === "running") return "running";
  if (latestStatus === "waiting" || latestStatus === "needsApproval") return "waiting";
  if (latestStatus === "completed") return "completed";
  if (latestStatus === "interrupted" || latestStatus === "cancelled" || latestStatus === "canceled") return "cancelled";
  if (latestStatus === "failed" || latestStatus === "error") return "failed";
  if (statusType(thread.status) === "systemError") return "failed";
  if (statusType(thread.status) === "active") return "running";
  return "queued";
}

const REPLAY_APPROVAL_STATUSES = new Set(["awaitingApproval", "approvalRequired", "needsApproval", "waiting"]);

function replayItems(items: unknown[]): ReturnType<typeof createCodexReplayEvent>[] {
  const replay = [] as ReturnType<typeof createCodexReplayEvent>[];
  for (const item of items) {
    if (!item || typeof item !== "object" || Array.isArray(item)) {
      throw Object.assign(new Error("Codex replay item is invalid"), { code: "codex_replay_invalid" });
    }
    const itemRecord = item as Record<string, unknown>;
    const translated = translateCodexPersistedItem(item);
    const type = typeof itemRecord.type === "string" ? itemRecord.type : null;
    const approvalWaiting = type === "commandExecution" && REPLAY_APPROVAL_STATUSES.has(statusType(itemRecord.status) ?? "");
    const commandOutcome = type === "commandExecution" && (statusType(itemRecord.status) === "completed" || statusType(itemRecord.status) === "failed");
    const mcpOutcome = type === "mcpToolCall" && (statusType(itemRecord.status) === "completed" || statusType(itemRecord.status) === "failed");
    const dynamicOutcome = type === "dynamicToolCall" && (statusType(itemRecord.status) === "completed" || statusType(itemRecord.status) === "failed");
    const collabOutcome = type === "collabToolCall" && (statusType(itemRecord.status) === "completed" || statusType(itemRecord.status) === "failed");
    const reviewLifecycle = type === "enteredReviewMode" || type === "exitedReviewMode";
    const compactionLifecycle = type === "contextCompaction";
    const webSearchActivity = type === "webSearch";
    const imageViewActivity = type === "imageView";
    const functionOutputActivity = type === "functionCallOutput";
    const userMessageActivity = type === "userMessage";
    if ((type === "agentMessage" || type === "plan" || type === "fileChange" || reviewLifecycle || compactionLifecycle || webSearchActivity || imageViewActivity || functionOutputActivity || userMessageActivity || approvalWaiting || commandOutcome || mcpOutcome || dynamicOutcome || collabOutcome) && translated.length === 0) {
      throw Object.assign(new Error("Codex replay item is malformed"), { code: "codex_replay_invalid" });
    }
    for (const event of translated) replay.push(createCodexReplayEvent(event));
  }
  return replay;
}

function replayHistory(result: Record<string, unknown>): ReturnType<typeof createCodexReplayEvent>[] {
  const data = result.data;
  if (!Array.isArray(data) || data.length > 100) {
    throw Object.assign(new Error("Codex replay history result is invalid"), { code: "codex_replay_invalid" });
  }
  const replay = [] as ReturnType<typeof createCodexReplayEvent>[];
  for (const turn of data) {
    if (!turn || typeof turn !== "object" || Array.isArray(turn)) {
      throw Object.assign(new Error("Codex replay turn is invalid"), { code: "codex_replay_invalid" });
    }
    const turnRecord = turn as Record<string, unknown>;
    if (turnRecord.items !== undefined && !Array.isArray(turnRecord.items)) {
      throw Object.assign(new Error("Codex replay items are invalid"), { code: "codex_replay_invalid" });
    }
    replay.push(...replayItems(turnRecord.items ?? []));
    const turnEvents = translateCodexPersistedTurn(turn);
    if (turnRecord.id !== undefined && turnRecord.status !== undefined && turnEvents.length === 0) {
      throw Object.assign(new Error("Codex replay turn is malformed"), { code: "codex_replay_invalid" });
    }
    for (const event of turnEvents) replay.push(createCodexReplayEvent(event));
  }
  return replay;
}

/** Compose the negotiated stdio connection with neutral start/continue calls. */
export function createCodexAppServerLifecycleSource(
  options: CodexAppServerLifecycleSourceOptions,
): CodexAppServerEventSource {
  let runtime: RuntimeConnection | null = null;
  let opening: Promise<RuntimeConnection> | null = null;

  const ensureRuntime = async (lease: CodexCredentialLease): Promise<RuntimeConnection> => {
    assertLease(lease);
    if (runtime) return runtime;
    if (!opening) {
      opening = (async () => {
        const connection = await options.open(lease);
        const session = createCodexAppServerSession(connection.client, {
          nextRequestId: options.nextRequestId,
          cwd: options.cwd,
        });
        const created = { connection, session, thread: null, turnId: null };
        runtime = created;
        return created;
      })().catch((error) => {
        opening = null;
        throw error;
      });
    }
    return opening;
  };

  return {
    start: async (_context: EngineRunContext, input: EngineInput, lease: CodexCredentialLease) => {
      const active = await ensureRuntime(lease);
      const turn = await active.session.start(input.text);
      active.thread = turn.thread;
      active.turnId = turn.turnId;
      return active.connection.events.stream();
    },
    continue: async (_context: EngineRunContext, session: NativeSessionReference, input: EngineInput, lease: CodexCredentialLease) => {
      const active = await ensureRuntime(lease);
      const turn = await active.session.resume(session.resumeHandle, input.text);
      active.thread = turn.thread;
      active.turnId = turn.turnId;
      return active.connection.events.stream();
    },
    cancel: async (_context: EngineRunContext, session: NativeSessionReference, lease: CodexCredentialLease): Promise<"requested" | "confirmed"> => {
      const active = await ensureRuntime(lease);
      if (!active.thread || active.thread.resumeHandle !== session.resumeHandle || !active.turnId) {
        throw Object.assign(new Error("Codex active turn is unavailable"), { code: "codex_turn_missing" });
      }
      const result = await active.session.interrupt(active.thread.resumeHandle, active.turnId);
      if (Object.keys(result).length > 0) {
        throw Object.assign(new Error("Codex interrupt acknowledgement is invalid"), { code: "codex_cancel_ack_invalid" });
      }
      return "requested";
    },
    reconcile: async (_context: EngineRunContext, session: NativeSessionReference, lease: CodexCredentialLease): Promise<EngineRunStatus> => {
      const active = await ensureRuntime(lease);
      const result = await active.session.readThread(session.resumeHandle);
      return reconcileStatus(result, session.resumeHandle);
    },
    resumeFromCursor: async (_context: EngineRunContext, cursor: string | null, lease: CodexCredentialLease) => {
      const active = await ensureRuntime(lease);
      if (!active.thread) {
        throw Object.assign(new Error("Codex replay thread is unavailable"), { code: "codex_thread_missing" });
      }
      const result = await active.session.listTurns(active.thread.resumeHandle, {
        cursor,
        sortDirection: "asc",
        itemsView: "full",
      });
      return (async function* () {
        for (const event of replayHistory(result)) yield event;
      })();
    },
    respondToApproval: async (_context: EngineRunContext, requestId: string, decision: "allow" | "deny", lease: CodexCredentialLease) => {
      const active = await ensureRuntime(lease);
      await active.session.respondToApproval(requestId, decision);
    },
    erase: async (_context: EngineRunContext, session: NativeSessionReference, lease: CodexCredentialLease): Promise<"confirmed" | "unsupported"> => {
      const active = await ensureRuntime(lease);
      const result = await active.session.deleteThread(session.resumeHandle);
      if (Object.keys(result).length > 0) {
        throw Object.assign(new Error("Codex thread deletion acknowledgement is invalid"), { code: "codex_erase_ack_invalid" });
      }
      if (active.thread?.resumeHandle === session.resumeHandle) {
        active.thread = null;
        active.turnId = null;
      }
      return "confirmed";
    },
    dispose: async () => {
      const active = runtime;
      runtime = null;
      opening = null;
      if (active) await active.connection.dispose();
    },
  };
}
