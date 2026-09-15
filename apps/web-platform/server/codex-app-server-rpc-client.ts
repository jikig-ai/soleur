import { decodeCodexJsonlLine, encodeCodexJsonl } from "./codex-app-server-jsonl";
import type { CodexRpcRequest } from "./codex-app-server-protocol";

export interface CodexRpcChannel {
  write(frame: string): Promise<void> | void;
}

export interface CodexRpcClientOptions {
  onNotification?: (message: Record<string, unknown>) => void;
  onServerRequest?: (message: Record<string, unknown>) => void;
  maxPending?: number;
}

export interface CodexRpcClient {
  request(request: CodexRpcRequest): Promise<Record<string, unknown>>;
  respond(id: string, result: Record<string, unknown>): Promise<void>;
  receiveLine(line: string): void;
  receive(message: unknown): void;
  close(reason?: unknown): void;
  pendingCount(): number;
}

interface PendingRequest {
  resolve: (result: Record<string, unknown>) => void;
  reject: (error: Error) => void;
}

function clientError(message: string, code: string): Error {
  return Object.assign(new Error(message), { code });
}

function sanitizeRpcError(value: unknown): Error {
  const record = value && typeof value === "object" ? value as Record<string, unknown> : null;
  const rawCode = record?.code;
  const code = typeof rawCode === "string" && /^[a-z0-9_-]{1,64}$/i.test(rawCode)
    ? `codex_rpc_${rawCode.toLowerCase()}`
    : "codex_rpc_error";
  return clientError("Codex RPC request failed", code);
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function assertResponseId(value: unknown): string {
  if (typeof value !== "string" || value.length < 1 || value.length > 128 || [...value].some((character) => {
    const codePoint = character.codePointAt(0)!;
    return codePoint <= 0x1f || codePoint === 0x7f || codePoint === 0x2028 || codePoint === 0x2029;
  })) {
    throw clientError("Codex RPC response identity is invalid", "codex_rpc_request_invalid");
  }
  return value;
}

export function createCodexRpcClient(
  channel: CodexRpcChannel,
  options: CodexRpcClientOptions = {},
): CodexRpcClient {
  const pending = new Map<string, PendingRequest>();
  const maxPending = options.maxPending ?? 128;
  let closed = false;

  const request = async (rpcRequest: CodexRpcRequest): Promise<Record<string, unknown>> => {
    if (closed) throw clientError("Codex RPC channel is closed", "codex_rpc_closed");
    if (pending.has(rpcRequest.id)) throw clientError("Codex RPC request is already in flight", "codex_rpc_request_in_flight");
    if (pending.size >= maxPending) throw clientError("Codex RPC request limit reached", "codex_rpc_backpressure");
    const frame = encodeCodexJsonl(rpcRequest);
    const response = new Promise<Record<string, unknown>>((resolve, reject) => {
      pending.set(rpcRequest.id, { resolve, reject });
    });
    try {
      await channel.write(frame);
    } catch {
      const entry = pending.get(rpcRequest.id);
      pending.delete(rpcRequest.id);
      entry?.reject(clientError("Codex RPC channel write failed", "codex_rpc_channel_error"));
    }
    return response;
  };

  const respond = async (id: string, result: Record<string, unknown>): Promise<void> => {
    if (closed) throw clientError("Codex RPC channel is closed", "codex_rpc_closed");
    if (!result || typeof result !== "object" || Array.isArray(result)) {
      throw clientError("Codex RPC response is invalid", "codex_rpc_message_invalid");
    }
    const frame = encodeCodexJsonl({ jsonrpc: "2.0", id: assertResponseId(id), result });
    try {
      await channel.write(frame);
    } catch {
      throw clientError("Codex RPC channel write failed", "codex_rpc_channel_error");
    }
  };

  const receive = (message: unknown): void => {
    const record = asRecord(message);
    if (!record) throw clientError("Codex RPC message is invalid", "codex_rpc_message_invalid");
    if (typeof record.method === "string") {
      if (record.id !== undefined) options.onServerRequest?.(record);
      else options.onNotification?.(record);
      return;
    }
    if (typeof record.id !== "string") return;
    const entry = pending.get(record.id);
    if (!entry) return;
    pending.delete(record.id);
    if (record.error !== undefined) {
      entry.reject(sanitizeRpcError(record.error));
      return;
    }
    const result = asRecord(record.result);
    if (!result) {
      entry.reject(clientError("Codex RPC result is invalid", "codex_rpc_message_invalid"));
      return;
    }
    entry.resolve(result);
  };

  const close = (reason?: unknown): void => {
    if (closed) return;
    closed = true;
    const error = reason instanceof Error
      ? reason
      : clientError("Codex RPC channel is closed", "codex_rpc_closed");
    for (const entry of pending.values()) entry.reject(error);
    pending.clear();
  };

  return {
    request,
    respond,
    receiveLine: (line) => receive(decodeCodexJsonlLine(line)),
    receive,
    close,
    pendingCount: () => pending.size,
  };
}
