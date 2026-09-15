export interface CodexRpcRequest {
  readonly jsonrpc: "2.0";
  readonly id: string;
  readonly method: string;
  readonly params: Record<string, unknown>;
}

export interface CodexRpcNotification {
  readonly jsonrpc: "2.0";
  readonly method: string;
  readonly params: Record<string, unknown>;
}

export interface CodexRpcResponse {
  readonly jsonrpc: "2.0";
  readonly id: string;
  readonly result: Record<string, unknown>;
}

const MAX_RPC_ID_LENGTH = 128;
const MAX_THREAD_ID_LENGTH = 256;
const MAX_CWD_LENGTH = 4096;
const MAX_INPUT_LENGTH = 16_384;

function hasUnsafeCharacter(value: string): boolean {
  return [...value].some((character) => {
    const codePoint = character.codePointAt(0)!;
    return codePoint <= 0x1f || codePoint === 0x7f || codePoint === 0x2028 || codePoint === 0x2029;
  });
}

function assertRpcId(value: unknown): string {
  if (typeof value !== "string" || value.length < 1 || value.length > MAX_RPC_ID_LENGTH || hasUnsafeCharacter(value)) {
    throw Object.assign(new Error("Codex RPC request identity is invalid"), { code: "codex_rpc_request_invalid" });
  }
  return value;
}

function assertThreadId(value: unknown): string {
  if (typeof value !== "string" || value.length < 1 || value.length > MAX_THREAD_ID_LENGTH || hasUnsafeCharacter(value)) {
    throw Object.assign(new Error("Codex thread identity is invalid"), { code: "codex_thread_invalid" });
  }
  return value;
}

function assertInput(value: unknown): string {
  if (typeof value !== "string" || value.length < 1 || value.length > MAX_INPUT_LENGTH || hasUnsafeCharacter(value)) {
    throw Object.assign(new Error("Codex turn input is invalid"), { code: "codex_rpc_input_invalid" });
  }
  return value;
}

function assertCwd(value: unknown): string {
  if (typeof value !== "string" || value.length < 1 || value.length > MAX_CWD_LENGTH || !value.startsWith("/") || hasUnsafeCharacter(value)) {
    throw Object.assign(new Error("Codex working directory is invalid"), { code: "codex_rpc_cwd_invalid" });
  }
  return value;
}

function request(id: unknown, method: string, params: Record<string, unknown>): CodexRpcRequest {
  return { jsonrpc: "2.0", id: assertRpcId(id), method, params };
}

/** Build the server handshake; credentials are supplied out of band by the source. */
export function createCodexInitializeRequest(id: string): CodexRpcRequest {
  return request(id, "initialize", { clientInfo: { name: "soleur-web", version: "1" } });
}

export function createCodexInitializedNotification(): CodexRpcNotification {
  return { jsonrpc: "2.0", method: "initialized", params: {} };
}

export function createCodexThreadStartRequest(id: string, options: { cwd?: string } = {}): CodexRpcRequest {
  return request(id, "thread/start", options.cwd === undefined ? {} : { cwd: assertCwd(options.cwd) });
}

export function createCodexThreadResumeRequest(id: string, threadId: string): CodexRpcRequest {
  return request(id, "thread/resume", { threadId: assertThreadId(threadId) });
}

export function createCodexThreadReadRequest(id: string, threadId: string, includeTurns = false): CodexRpcRequest {
  return request(id, "thread/read", { threadId: assertThreadId(threadId), includeTurns });
}

export function createCodexTurnStartRequest(id: string, threadId: string, input: string): CodexRpcRequest {
  return request(id, "turn/start", {
    threadId: assertThreadId(threadId),
    input: [{ type: "text", text: assertInput(input) }],
  });
}

export function createCodexTurnInterruptRequest(id: string, threadId: string, turnId: string): CodexRpcRequest {
  return request(id, "turn/interrupt", {
    threadId: assertThreadId(threadId),
    turnId: assertThreadId(turnId),
  });
}

/** Translate neutral allow/deny decisions to the App Server command vocabulary. */
export function createCodexApprovalResponseRequest(id: string, decision: "allow" | "deny"): CodexRpcResponse {
  return {
    jsonrpc: "2.0",
    id: assertRpcId(id),
    result: { decision: decision === "allow" ? "accept" : "decline" },
  };
}
