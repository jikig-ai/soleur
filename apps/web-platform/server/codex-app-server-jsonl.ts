const MAX_CODEX_FRAME_BYTES = 1_048_576;

function frameError(message: string, code: "codex_rpc_frame_invalid" | "codex_rpc_frame_too_large"): Error {
  return Object.assign(new Error(message), { code });
}

function byteLength(value: string): number {
  return new TextEncoder().encode(value).byteLength;
}

function assertFrameSize(value: string): void {
  if (byteLength(value) > MAX_CODEX_FRAME_BYTES) {
    throw frameError("Codex RPC frame is too large", "codex_rpc_frame_too_large");
  }
}

function parseFrame(value: string): Record<string, unknown> {
  const trimmed = value.endsWith("\r") ? value.slice(0, -1) : value;
  if (trimmed.length === 0) throw frameError("Codex RPC frame is blank", "codex_rpc_frame_invalid");
  assertFrameSize(trimmed);
  let parsed: unknown;
  try {
    parsed = JSON.parse(trimmed);
  } catch {
    throw frameError("Codex RPC frame is not valid JSON", "codex_rpc_frame_invalid");
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw frameError("Codex RPC frame must be a JSON object", "codex_rpc_frame_invalid");
  }
  return parsed as Record<string, unknown>;
}

/** Serialize one App Server JSON-RPC message as a single JSONL frame. */
export function encodeCodexJsonl(message: unknown): string {
  if (!message || typeof message !== "object" || Array.isArray(message)) {
    throw frameError("Codex RPC frame must be a JSON object", "codex_rpc_frame_invalid");
  }
  let serialized: string;
  try {
    serialized = JSON.stringify(message);
  } catch {
    throw frameError("Codex RPC frame cannot be serialized", "codex_rpc_frame_invalid");
  }
  assertFrameSize(serialized);
  return `${serialized}\n`;
}

/** Parse one JSONL line, accepting either a trailing LF or CRLF delimiter. */
export function decodeCodexJsonlLine(line: string): Record<string, unknown> {
  if (typeof line !== "string") throw frameError("Codex RPC frame is invalid", "codex_rpc_frame_invalid");
  const withoutLf = line.endsWith("\n") ? line.slice(0, -1) : line;
  return parseFrame(withoutLf);
}

/** Reassemble arbitrary stdio chunks into ordered JSONL messages. */
export async function* decodeCodexJsonlStream(
  chunks: AsyncIterable<string>,
): AsyncIterable<Record<string, unknown>> {
  let buffer = "";
  for await (const chunk of chunks) {
    if (typeof chunk !== "string") throw frameError("Codex RPC chunk is invalid", "codex_rpc_frame_invalid");
    buffer += chunk;
    let newline = buffer.indexOf("\n");
    while (newline !== -1) {
      const line = buffer.slice(0, newline);
      buffer = buffer.slice(newline + 1);
      yield parseFrame(line);
      newline = buffer.indexOf("\n");
    }
    assertFrameSize(buffer);
  }
  if (buffer.length > 0) yield parseFrame(buffer);
}
