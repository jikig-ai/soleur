// pencil-response-classify.mjs — pure response classifier for the Pencil REPL.
// Extracted so it can be unit-tested without importing the adapter (which
// pulls in @modelcontextprotocol/sdk and cannot load in a bare test env).

const ANSI_ESCAPE = /\x1b\[[0-9;]*[a-zA-Z]/g;

// REPL responses are bounded in practice. Cap before classification so a
// pathological multi-MB response can't spin the `^`-anchored multiline
// regexes over an arbitrarily long scan.
const CLASSIFY_MAX_BYTES = 64 * 1024;

const ERROR_PATTERNS = [
  /^Error:/m,
  /^\[ERROR\]/m,
  /^Invalid properties:/m,
  // Auth-failure responses from the pencil REPL. Anchored to start-of-line
  // (via multiline flag) for `Unauthorized` / `HTTP 401` / `Invalid API key`
  // so a node name echoed back in `batch_get` output ("Unauthorized state")
  // or a user-supplied frame title can't trip the gate. The backtick-
  // delimited `pencil login` form is pencil-CLI-authored and does not
  // appear in user content.
  /`pencil login`/i,
  /^Invalid API key\b/im,
  /^Unauthorized\b/im,
  /^HTTP 401\b/im,
];

export function stripAnsi(str) {
  return str.replace(ANSI_ESCAPE, "");
}

export function classifyResponse(raw) {
  const input = String(raw ?? "");
  const bounded = input.length > CLASSIFY_MAX_BYTES ? input.slice(0, CLASSIFY_MAX_BYTES) : input;
  const text = stripAnsi(bounded).trim();
  const isError = ERROR_PATTERNS.some((pattern) => pattern.test(text));
  return { text, isError };
}
