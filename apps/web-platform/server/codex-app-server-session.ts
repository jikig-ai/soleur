import type { NativeSessionReference } from "./agent-engine-contract";
import { normalizeCodexThreadReference } from "./codex-code-adapter";
import {
  createCodexApprovalResponseRequest,
  createCodexThreadReadRequest,
  createCodexThreadResumeRequest,
  createCodexThreadStartRequest,
  createCodexThreadDeleteRequest,
  createCodexThreadItemsListRequest,
  createCodexThreadTurnsListRequest,
  createCodexTurnInterruptRequest,
  createCodexTurnStartRequest,
  type CodexThreadItemsListOptions,
  type CodexThreadTurnsListOptions,
} from "./codex-app-server-protocol";
import { createCodexAppServerHandshake } from "./codex-app-server-handshake";
import type { CodexRpcClient } from "./codex-app-server-rpc-client";

export interface CodexAppServerSessionClient {
  request(request: Parameters<CodexRpcClient["request"]>[0]): ReturnType<CodexRpcClient["request"]>;
  notify(notification: Parameters<CodexRpcClient["notify"]>[0]): ReturnType<CodexRpcClient["notify"]>;
  respond(id: string, result: Record<string, unknown>): Promise<void>;
}

export interface CodexAppServerSessionOptions {
  nextRequestId: () => string;
  cwd?: string;
}

export interface CodexAppServerTurn {
  thread: NativeSessionReference;
  turnId: string;
}

export interface CodexAppServerSession {
  initialize(): Promise<Record<string, unknown>>;
  start(input: string, signal?: AbortSignal): Promise<CodexAppServerTurn>;
  resume(threadId: string, input: string, signal?: AbortSignal): Promise<CodexAppServerTurn>;
  readThread(threadId: string): Promise<Record<string, unknown>>;
  listTurns(threadId: string, options?: CodexThreadTurnsListOptions): Promise<Record<string, unknown>>;
  listItems(threadId: string, options?: CodexThreadItemsListOptions): Promise<Record<string, unknown>>;
  deleteThread(threadId: string): Promise<Record<string, unknown>>;
  interrupt(threadId: string, turnId: string): Promise<Record<string, unknown>>;
  respondToApproval(requestId: string, decision: "allow" | "deny"): Promise<void>;
}

function sessionError(message: string, code: string): Error {
  return Object.assign(new Error(message), { code });
}

function assertActive(signal?: AbortSignal): void {
  if (signal?.aborted) {
    throw sessionError("Codex turn was cancelled before provider dispatch", "codex_turn_cancelled");
  }
}

function extractThread(result: Record<string, unknown>): NativeSessionReference {
  const thread = result.thread;
  if (!thread || typeof thread !== "object" || Array.isArray(thread)) {
    throw sessionError("Codex thread result is invalid", "codex_thread_invalid");
  }
  return normalizeCodexThreadReference(thread);
}

function extractTurnId(result: Record<string, unknown>): string {
  const turn = result.turn;
  const id = turn && typeof turn === "object" && !Array.isArray(turn)
    ? (turn as { id?: unknown }).id
    : undefined;
  if (
    typeof id !== "string" ||
    id.length < 1 ||
    id.length > 256 ||
    [...id].some((character) => {
      const point = character.codePointAt(0)!;
      return point <= 0x1f || point === 0x7f || point === 0x2028 || point === 0x2029;
    })
  ) {
    throw sessionError("Codex turn identity is invalid", "codex_turn_invalid");
  }
  return id;
}

/**
 * Owns the App Server negotiation and thread lifecycle for one provider
 * channel. Callers receive only neutral thread/turn identities.
 */
export function createCodexAppServerSession(
  client: CodexAppServerSessionClient,
  options: CodexAppServerSessionOptions,
): CodexAppServerSession {
  let initialization: Promise<Record<string, unknown>> | null = null;
  let thread: NativeSessionReference | null = null;
  let threadStart: Promise<NativeSessionReference> | null = null;

  const ensureInitialized = (): Promise<Record<string, unknown>> => {
    if (!initialization) {
      initialization = createCodexAppServerHandshake(client, options.nextRequestId()).catch((error) => {
        initialization = null;
        throw error;
      });
    }
    return initialization;
  };

  const ensureThread = async (): Promise<NativeSessionReference> => {
    if (thread) return thread;
    if (!threadStart) {
      threadStart = (async () => {
        const result = await client.request(createCodexThreadStartRequest(options.nextRequestId(), { cwd: options.cwd }));
        const created = extractThread(result);
        thread = created;
        return created;
      })().catch((error) => {
        threadStart = null;
        throw error;
      });
    }
    return threadStart;
  };

  const startTurn = async (activeThread: NativeSessionReference, input: string): Promise<CodexAppServerTurn> => {
    const result = await client.request(createCodexTurnStartRequest(options.nextRequestId(), activeThread.resumeHandle, input));
    return { thread: activeThread, turnId: extractTurnId(result) };
  };

  return {
    initialize: ensureInitialized,
    start: async (input, signal) => {
      assertActive(signal);
      await ensureInitialized();
      assertActive(signal);
      const activeThread = await ensureThread();
      assertActive(signal);
      return startTurn(activeThread, input);
    },
    resume: async (threadId, input, signal) => {
      assertActive(signal);
      await ensureInitialized();
      assertActive(signal);
      const result = await client.request(createCodexThreadResumeRequest(options.nextRequestId(), threadId));
      assertActive(signal);
      const resumed = extractThread(result);
      thread = resumed;
      threadStart = Promise.resolve(resumed);
      assertActive(signal);
      return startTurn(resumed, input);
    },
    readThread: async (threadId) => {
      await ensureInitialized();
      return client.request(createCodexThreadReadRequest(options.nextRequestId(), threadId, true));
    },
    listTurns: async (threadId, listOptions) => {
      await ensureInitialized();
      return client.request(createCodexThreadTurnsListRequest(options.nextRequestId(), threadId, listOptions));
    },
    listItems: async (threadId, listOptions) => {
      await ensureInitialized();
      return client.request(createCodexThreadItemsListRequest(options.nextRequestId(), threadId, listOptions));
    },
    deleteThread: async (threadId) => {
      await ensureInitialized();
      const result = await client.request(createCodexThreadDeleteRequest(options.nextRequestId(), threadId));
      if (thread?.resumeHandle === threadId) {
        thread = null;
        threadStart = null;
      }
      return result;
    },
    interrupt: async (threadId, turnId) => {
      await ensureInitialized();
      return client.request(createCodexTurnInterruptRequest(options.nextRequestId(), threadId, turnId));
    },
    respondToApproval: async (requestId, decision) => {
      const response = createCodexApprovalResponseRequest(requestId, decision);
      await client.respond(response.id, response.result);
    },
  };
}
