import type {
  EngineAdapter,
  EngineEvent,
  EngineInput,
  EngineRunContext,
  EngineRunStatus,
  NativeSessionReference,
} from "./agent-engine-contract";

export const CODEX_ENGINE_ID = "codex" as const;
export type CodexAuthMode = "api-key" | "managed";

export interface CodexCredentialLease {
  readonly accessToken: string;
  readonly expiresAt: number;
}

export interface CodexAuthProvider {
  mode: CodexAuthMode;
  acquire(): Promise<CodexCredentialLease>;
  refresh(): Promise<CodexCredentialLease>;
  logout(): Promise<void>;
}

export interface CodexAuthBoundary {
  readonly mode: CodexAuthMode;
  acquire(): Promise<CodexCredentialLease>;
  refresh(): Promise<CodexCredentialLease>;
  logout(): Promise<void>;
}

function normalizeAuthError(error: unknown): Error {
  const code = (error as { code?: unknown } | null)?.code;
  if (code === "invalid_grant" || code === "revoked" || code === "unauthorized") {
    return Object.assign(new Error("Codex credentials are revoked"), { code: "codex_credentials_revoked" });
  }
  return error instanceof Error ? error : new Error("Codex authentication failed");
}

function validateLease(lease: CodexCredentialLease): CodexCredentialLease {
  if (!Number.isFinite(lease.expiresAt) || lease.expiresAt <= Date.now()) {
    throw Object.assign(new Error("Codex credential lease expired"), { code: "codex_credential_expired" });
  }
  if (!lease.accessToken.trim()) {
    throw Object.assign(new Error("Codex credential lease is empty"), { code: "codex_credential_invalid" });
  }
  return lease;
}

/**
 * Keeps Codex credentials behind a mode-stable adapter seam. Callers receive
 * only a short-lived lease; persistence and neutral engine contracts never see
 * the token or provider-specific login state.
 */
export function createCodexAuthBoundary(provider: CodexAuthProvider): CodexAuthBoundary {
  const mode = provider.mode;
  const assertStableMode = () => {
    if (provider.mode !== mode) {
      throw Object.assign(new Error("Codex auth mode changed during a session"), {
        code: "codex_auth_mode_changed",
      });
    }
  };

  return {
    mode,
    acquire: async () => {
      assertStableMode();
      try { return validateLease(await provider.acquire()); } catch (error) { throw normalizeAuthError(error); }
    },
    refresh: async () => {
      assertStableMode();
      try { return validateLease(await provider.refresh()); } catch (error) { throw normalizeAuthError(error); }
    },
    logout: async () => {
      assertStableMode();
      await provider.logout();
    },
  };
}

export interface CodexCodeAdapterTransport {
  start(context: EngineRunContext, input: EngineInput, lease: CodexCredentialLease): AsyncIterable<EngineEvent>;
  continue(context: EngineRunContext, session: NativeSessionReference, input: EngineInput, lease: CodexCredentialLease): AsyncIterable<EngineEvent>;
  cancel(context: EngineRunContext, session: NativeSessionReference, lease: CodexCredentialLease): Promise<"requested" | "confirmed">;
  reconcile(context: EngineRunContext, session: NativeSessionReference, lease: CodexCredentialLease): Promise<EngineRunStatus>;
  resumeFromCursor(context: EngineRunContext, cursor: string | null, lease: CodexCredentialLease): AsyncIterable<EngineEvent>;
  respondToApproval(context: EngineRunContext, requestId: string, decision: "allow" | "deny", lease: CodexCredentialLease): Promise<void>;
  erase(context: EngineRunContext, session: NativeSessionReference, lease: CodexCredentialLease): Promise<"confirmed" | "unsupported">;
  dispose(): Promise<void>;
}

/** Codex stays disabled until qualification; this wrapper only defines the provider seam. */
export function createCodexCodeAdapter(
  transport: CodexCodeAdapterTransport,
  auth: CodexAuthBoundary,
): EngineAdapter {
  async function* stream<T extends AsyncIterable<EngineEvent>>(load: () => Promise<T>): AsyncIterable<EngineEvent> {
    yield* await load();
  }
  return {
    start: (context, input) => stream(async () => transport.start(context, input, await auth.acquire())),
    continue: (context, session, input) => stream(async () => transport.continue(context, session, input, await auth.acquire())),
    cancel: async (context, session) => transport.cancel(context, session, await auth.acquire()),
    reconcile: async (context, session) => transport.reconcile(context, session, await auth.acquire()),
    resumeFromCursor: (context, cursor) => stream(async () => transport.resumeFromCursor(context, cursor, await auth.acquire())),
    respondToApproval: async (context, requestId, decision) => transport.respondToApproval(context, requestId, decision, await auth.acquire()),
    erase: async (context, session) => transport.erase(context, session, await auth.acquire()),
    dispose: () => transport.dispose(),
  };
}

export type CodexCodeAdapter = EngineAdapter;
