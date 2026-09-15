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
        const created = { connection, session };
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
      await active.session.start(input.text);
      return active.connection.events.stream();
    },
    continue: async (_context: EngineRunContext, session: NativeSessionReference, input: EngineInput, lease: CodexCredentialLease) => {
      const active = await ensureRuntime(lease);
      await active.session.resume(session.resumeHandle, input.text);
      return active.connection.events.stream();
    },
    cancel: async (_context: EngineRunContext, _session: NativeSessionReference, _lease: CodexCredentialLease): Promise<"requested" | "confirmed"> => {
      throw unsupported();
    },
    reconcile: async (_context: EngineRunContext, _session: NativeSessionReference, _lease: CodexCredentialLease): Promise<EngineRunStatus> => {
      throw unsupported();
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
