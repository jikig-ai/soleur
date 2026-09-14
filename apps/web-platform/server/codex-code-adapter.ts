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

export function codexAuthMetadata(mode: CodexAuthMode, lease: CodexCredentialLease): { mode: CodexAuthMode; expiresAt: number } {
  return { mode, expiresAt: lease.expiresAt };
}

export function normalizeCodexCancellation(result: "cancelled" | "accepted" | "unknown"): "requested" | "confirmed" {
  return result === "cancelled" ? "confirmed" : "requested";
}

export interface CodexUsageSnapshot {
  inputTokens: number;
  outputTokens: number;
  cost?: { amount: number; currency: string };
}

export function sanitizeCodexError(error: unknown): Error {
  const candidate = error as { code?: unknown } | null;
  const code = typeof candidate?.code === "string" && /^[a-z0-9_-]{1,64}$/i.test(candidate.code)
    ? candidate.code
    : "codex_provider_error";
  return Object.assign(new Error("Codex provider request failed"), { code });
}

export function validateCodexEvent(event: EngineEvent, expectedRunId: string): EngineEvent {
  if (event.runId !== expectedRunId || !event.eventId || !Number.isInteger(event.sequence) || event.sequence < 1) {
    throw Object.assign(new Error("Codex event does not match the bound run"), { code: "codex_event_invalid" });
  }
  return event;
}

export function assertCodexEndpoint(endpoint: string, allowedHosts: readonly string[]): string {
  try {
    const url = new URL(endpoint);
    if (url.protocol !== "https:" || url.username || url.password || !allowedHosts.some((host) => host.toLowerCase() === url.hostname.toLowerCase())) {
      throw new Error("Codex egress denied");
    }
    return url.toString();
  } catch {
    throw Object.assign(new Error("Codex egress denied"), { code: "codex_egress_denied" });
  }
}

export function normalizeCodexUsageEvent(
  runId: string,
  eventId: string,
  sequence: number,
  snapshot: CodexUsageSnapshot,
): EngineEvent {
  return {
    runId,
    eventId,
    sequence,
    payload: {
      type: "usage",
      usage: {
        native: [
          { unit: "input_tokens", value: snapshot.inputTokens },
          { unit: "output_tokens", value: snapshot.outputTokens },
        ],
        cost: snapshot.cost
          ? { provenance: "reported", amount: snapshot.cost.amount, currency: snapshot.cost.currency }
          : { provenance: "unavailable" },
      },
    },
  };
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

function isCodexAuthRecoveryError(error: unknown): boolean {
  const code = (error as { code?: unknown } | null)?.code;
  return code === "codex_credential_expired"
    || code === "codex_credentials_revoked"
    || code === "unauthorized"
    || code === "invalid_grant"
    || code === "revoked";
}

export async function runWithCodexRecovery<T>(
  auth: CodexAuthBoundary,
  operation: (lease: CodexCredentialLease) => Promise<T>,
): Promise<T> {
  let lease = await auth.acquire();
  try {
    return await operation(lease);
  } catch (error) {
    if (!isCodexAuthRecoveryError(error)) throw error;
    lease = await auth.refresh();
    return operation(lease);
  }
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
  let loggedOut = false;
  const assertStableMode = () => {
    if (provider.mode !== mode) {
      throw Object.assign(new Error("Codex auth mode changed during a session"), {
        code: "codex_auth_mode_changed",
      });
    }
  };
  const assertActive = () => {
    if (loggedOut) {
      throw Object.assign(new Error("Codex credentials have been logged out"), { code: "codex_credentials_logged_out" });
    }
  };

  return {
    mode,
    acquire: async () => {
      assertStableMode();
      assertActive();
      try { return validateLease(await provider.acquire()); } catch (error) { throw normalizeAuthError(error); }
    },
    refresh: async () => {
      assertStableMode();
      assertActive();
      try { return validateLease(await provider.refresh()); } catch (error) { throw normalizeAuthError(error); }
    },
    logout: async () => {
      assertStableMode();
      if (loggedOut) return;
      await provider.logout();
      loggedOut = true;
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

function normalizeCodexThreadId(value: unknown): string {
  if (
    typeof value !== "string" ||
    value.length < 1 ||
    value.length > 256 ||
    [...value].some((character) => {
      const codePoint = character.codePointAt(0)!;
      return codePoint <= 0x1f || codePoint === 0x7f || codePoint === 0x2028 || codePoint === 0x2029;
    })
  ) {
    throw Object.assign(new Error("Codex thread identity is invalid"), { code: "codex_thread_invalid" });
  }
  return value;
}

/** Preserve App Server thread.id and thread.sessionId as separate opaque values. */
export function normalizeCodexThreadReference(thread: unknown): NativeSessionReference {
  if (!thread || typeof thread !== "object") {
    throw Object.assign(new Error("Codex thread identity is invalid"), { code: "codex_thread_invalid" });
  }
  const record = thread as { id?: unknown; sessionId?: unknown };
  const resumeHandle = normalizeCodexThreadId(record.id);
  const sessionId = record.sessionId == null ? null : normalizeCodexThreadId(record.sessionId);
  return { resumeHandle, sessionId };
}

/** Codex stays disabled until qualification; this wrapper only defines the provider seam. */
export function createCodexCodeAdapter(
  transport: CodexCodeAdapterTransport,
  auth: CodexAuthBoundary,
): EngineAdapter {
  async function* stream<T extends AsyncIterable<EngineEvent>>(load: (lease: CodexCredentialLease) => Promise<T>, runId: string): AsyncIterable<EngineEvent> {
    let lease: CodexCredentialLease;
    try { lease = await auth.acquire(); } catch (error) { throw sanitizeCodexError(error); }
    let refreshed = false;
    let lastSequence = 0;
    while (true) {
      try {
        for await (const event of await load(lease)) {
          const validated = validateCodexEvent(event, runId);
          if (validated.sequence <= lastSequence) {
            throw Object.assign(new Error("Codex event sequence is stale or duplicated"), {
              code: "codex_event_sequence_invalid",
            });
          }
          lastSequence = validated.sequence;
          yield validated;
        }
        return;
      } catch (error) {
        if (!refreshed && lastSequence === 0 && isCodexAuthRecoveryError(error)) {
          try { lease = await auth.refresh(); } catch (refreshError) { throw sanitizeCodexError(refreshError); }
          refreshed = true;
          continue;
        }
        throw sanitizeCodexError(error);
      }
    }
  }
  const call = async <T>(operation: (lease: CodexCredentialLease) => Promise<T>): Promise<T> => {
    try {
      return await runWithCodexRecovery(auth, operation);
    } catch (error) { throw sanitizeCodexError(error); }
  };
  return {
    start: (context, input) => stream(async (lease) => transport.start(context, input, lease), context.runId),
    continue: (context, session, input) => stream(async (lease) => transport.continue(context, session, input, lease), context.runId),
    cancel: async (context, session) => call((lease) => transport.cancel(context, session, lease)),
    reconcile: async (context, session) => call((lease) => transport.reconcile(context, session, lease)),
    resumeFromCursor: (context, cursor) => stream(async (lease) => transport.resumeFromCursor(context, cursor, lease), context.runId),
    respondToApproval: async (context, requestId, decision) => call((lease) => transport.respondToApproval(context, requestId, decision, lease)),
    erase: async (context, session) => call((lease) => transport.erase(context, session, lease)),
    dispose: () => transport.dispose(),
  };
}

export type CodexCodeAdapter = EngineAdapter;
