import type {
  EngineInput,
  EngineRunContext,
  EngineRunStatus,
  NativeSessionReference,
} from "./agent-engine-contract";
import type { CodexCredentialLease, CodexAppServerEventSource } from "./codex-code-adapter";
import { createCodexAppServerSession, type CodexAppServerSession } from "./codex-app-server-session";
import type { CodexAppServerStdioConnection } from "./codex-app-server-stdio";

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

function unsupported(): Error {
  return Object.assign(new Error("Codex App Server operation is not supported by this source"), {
    code: "codex_operation_unsupported",
  });
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
    resumeFromCursor: async (_context: EngineRunContext, _cursor: string | null, _lease: CodexCredentialLease) => {
      throw unsupported();
    },
    respondToApproval: async (_context: EngineRunContext, requestId: string, decision: "allow" | "deny", lease: CodexCredentialLease) => {
      const active = await ensureRuntime(lease);
      await active.session.respondToApproval(requestId, decision);
    },
    erase: async (_context: EngineRunContext, _session: NativeSessionReference, _lease: CodexCredentialLease): Promise<"confirmed" | "unsupported"> => "unsupported",
    dispose: async () => {
      const active = runtime;
      runtime = null;
      opening = null;
      if (active) await active.connection.dispose();
    },
  };
}
