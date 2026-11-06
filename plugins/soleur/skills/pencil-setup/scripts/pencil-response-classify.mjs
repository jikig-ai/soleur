// pencil-response-classify.mjs — pure response classifier for the pen.dev REPL
// (@pen.dev/cli 0.3.13).
// Extracted so it can be unit-tested without importing the adapter (which
// pulls in @modelcontextprotocol/sdk and cannot load in a bare test env).

// CSI sequences: any parameter bytes (digits, `;`, `:` and the private prefixes `<=>?`) and
// any final byte (`@`..`~`), so `ESC[?25l`, `ESC[38:2:1:2:3m` and `ESC[3~` all go. THE one
// definition: the adapter, the save gate and the REPL surface import stripAnsi from here.
const ANSI_ESCAPE = /\x1b\[[0-9;?:<=>]*[@-~]/g;

// REPL responses are bounded in practice. Cap before classification so a
// pathological multi-MB response can't spin the `^`-anchored multiline
// regexes over an arbitrarily long scan.
const CLASSIFY_MAX_BYTES = 64 * 1024;

// @pen.dev/cli 0.3.13 prints every failure on stderr, wrapped in colour codes
// (stripped before these run): red `Error: ### Failure during operation
// execution` plus `[ERROR] ...` lines, red `Save failed: <reason>`, yellow
// `Unknown tool: <name>`. All are anchored to a line start so a node name echoed
// back in a reply cannot trip them mid-line.
const ERROR_PATTERNS = [
  /^Error:/m,
  /^\[ERROR\]/m,
  /^Invalid properties:/m,
  // A tool the engine does not have. It once classified as success and the
  // auto-save ran after it (#11143).
  /^Unknown tool:/m,
  // A failed save prints only this line (no `Saved`, no `[ERROR]`).
  /^Save failed:/m,
  // Auth-failure responses. Start-of-line anchored (multiline flag) so a node
  // name echoed back ("Unauthorized state") or a frame title cannot trip the
  // gate. The engine's own `[ERROR] Authentication required ...` line is
  // already covered by the `[ERROR]` pattern above.
  /^Invalid API key\b/im,
  /^Unauthorized\b/im,
  /^HTTP 401\b/im,
];

// A successful `execute` reply starts with `OK`, a get_app_state reply with its
// title; neither can be an error. Their later `## ...` sections carry text the
// agent controls (node names, printed values), and a node name containing a
// newline can put `Error:` at a line start, so only the header part before the
// first section is scanned for those two shapes.
function scannedPart(text) {
  const first = text.split("\n", 1)[0].trim();
  if (first !== "OK" && first !== "# Current App State") return text;
  const section = text.search(/\n## /);
  return section === -1 ? text : text.slice(0, section);
}

export function stripAnsi(str) {
  return str.replace(ANSI_ESCAPE, "");
}

// A stream stripper for chunked output: an escape sequence cut at a chunk boundary is held and
// finished by the next chunk, so no half sequence is left to split a credential across the
// pieces a redactor sees. push(chunk) returns the stripped text that is complete now; the
// unfinished tail (at most a few bytes of one escape) is dropped at the end of the stream.
export function createAnsiStripper() {
  let carry = "";
  return {
    push(chunk) {
      const text = stripAnsi(carry + String(chunk ?? ""));
      carry = "";
      const i = text.lastIndexOf("\x1b");
      if (i !== -1 && text.length - i <= 64 && /^\x1b(\[[0-9;?:<=>]*)?$/.test(text.slice(i))) {
        carry = text.slice(i);
        return text.slice(0, i);
      }
      return text;
    },
  };
}

export function classifyResponse(raw) {
  const input = String(raw ?? "");
  const bounded = input.length > CLASSIFY_MAX_BYTES ? input.slice(0, CLASSIFY_MAX_BYTES) : input;
  const text = stripAnsi(bounded).trim();
  const scanned = scannedPart(text);
  const isError = ERROR_PATTERNS.some((pattern) => pattern.test(scanned));
  return { text, isError };
}
