// pencil-response-classify.mjs — pure response classifier for the Pencil REPL.
// Extracted so it can be unit-tested without importing the adapter (which
// pulls in @modelcontextprotocol/sdk and cannot load in a bare test env).

const ANSI_ESCAPE = /\x1b\[[0-9;]*[a-zA-Z]/g;

const ERROR_PATTERNS = [
  /^Error:/m,
  /^\[ERROR\]/m,
  /^Invalid properties:/m,
  // Auth-failure responses from the pencil REPL. Pre-fix, these passed
  // through as "success" text, and the adapter's auto-save ran against a
  // mutation that had already failed, producing a 0-byte .pen file.
  /`pencil login`/i,
  /\bInvalid API key\b/i,
  /\bUnauthorized\b/i,
  /\bHTTP 401\b/i,
];

export function stripAnsi(str) {
  return str.replace(ANSI_ESCAPE, "");
}

export function classifyResponse(raw) {
  const text = stripAnsi(String(raw ?? "")).trim();
  const isError = ERROR_PATTERNS.some((pattern) => pattern.test(text));
  return { text, isError };
}
