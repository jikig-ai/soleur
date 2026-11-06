// pencil-repl-surface.mjs — the REPL contract between the adapter and
// @pen.dev/cli (`pen interactive --out <f> [--in <f>]`, measured on 0.3.13), as
// pure functions so bun tests need no MCP SDK. Imports: node:crypto (the count nonce)
// and stripAnsi from pencil-response-classify.mjs (the one ANSI definition).
//
// Why this exists (#11143): the adapter once sent `batch_design({ operations })`
// while the engine took `{ input }`; the engine dropped the unknown key and
// printed `OK`, so every design call "succeeded" and did nothing. Every REPL
// command line therefore flows through `formatReplCommand`, which refuses a
// tool or key that is not in the table below. The table is the signature list
// `pen interactive --help` prints for the REPL tools the adapter drives
// (`get_style` and `browser` exist in the engine but are deliberately absent:
// get_style was cut by CTO ruling 10, the adapter never emits browser).
// engine-contract-probe.sh diffs the table against the installed CLI on every
// pin bump; fixtures/pencil-stub-repl.mjs imports THIS table and prompt, so
// there is exactly one copy of the signature whitelist.
//
// Measured facts about the engine the adapter relies on (0.3.13):
//   * The prompt is `pen > ` once ANSI is stripped. The engine colours it even
//     on piped stdout: REPL_PROMPT_RAW is the exact byte string.
//   * ERROR replies (`Error: ### Failure ...`, `[ERROR] ...`, `Save failed: ...`,
//     `Unknown tool: ...`) arrive on STDERR; stdout carries only the blank line
//     and the prompt. Success replies (`OK ...`, `Saved <path>`, app state) are
//     on stdout. The adapter must merge both streams per command.
//   * The `batch_design` aliases `I`/`U`/... do not exist inside `execute`;
//     BATCH_DESIGN_PREAMBLE declares them with `var` on every call.
//   * `--out` alone still loads an EMPTY document, so planSpawn keeps supplying
//     `--in` for a non-empty `--out` (the #11143 hazard is unchanged).
//
// EXPORTS (the adapter wires these; do not re-implement them):
//   ReplContractError            thrown for every contract violation (never reaches the REPL)
//   REPL_SURFACE                 frozen table: tool -> allowed keys (execute, get_app_state, read_skill, save)
//   REPL_PROMPT / REPL_PROMPT_RAW   `pen > ` after ANSI strip / the raw coloured bytes
//   BATCH_DESIGN_PREAMBLE        the `var I=Insert,...;` alias line
//   NODE_FLOOR, compareVersions(a,b), nodeVersionOk(v)   Node 22.19.0 numeric floor. The adapter
//                                cannot import this (its own gate runs before any import), so it
//                                carries an inline copy; a parity test pins the copies together
//                                with check_deps.sh's three NODE_FLOOR_* variables.
//   formatReplCommand(tool, params)   the ONE formatter (refuses unknown tool/key)
//   buildBatchDesignCommand(operations)          execute({ input: "<preamble>\n<ops>" })
//   buildScreenshotCommand(nodeId)               execute({ input: 'TakeScreenshot(["id"])' })
//   buildExportCommand({nodeIds,outputDir,format,scale,quality})   execute Export(...)
//   buildVariablesCommand()                      execute Print(GetVariables())
//   buildEditorStateCommand()                    get_app_state()
//   buildReadSkillCommand(path?)                 read_skill(...)
//   buildSaveCommand()                           save()   (tests and the probe; the adapter's one emission
//                                                site is formatReplCommand("save", {}) inside guardedSave)
//   newCountNonce(), buildCountSnippet(nonce), buildCountCommand(nonce)   sentinel memory probe
//   countSnippetNonce(input)     recognises the snippet (the stub uses it)
//   parseCountReply(text, nonce) -> integer | null   exactly one `TOPLEVEL_COUNT:<nonce>:<n>` line
//   validateNodeId/NodeIds/ExportFormat/Scale/Quality/SkillPath/OutputDir   throw ReplContractError
//   MAX_NODE_IDS, EXPORT_FORMATS
//   redactionForms(secret), redactText(text, forms), createRollingRedactor(forms)
//                                a pure rolling-tail redactor: push(chunk) / flush()
//   heldPrefixLength(text, forms)   the unfinished credential prefix at the end of a reply
//   planSpawn({outFile, initialInFile, resumeInFile, probe})   `--in` decision

import { randomBytes } from "node:crypto";
import { stripAnsi } from "./pencil-response-classify.mjs";

export class ReplContractError extends Error {
  constructor(message) {
    super(message);
    this.name = "ReplContractError";
  }
}

// tool -> allowed parameter keys. `save` is the REPL's own command and takes none.
export const REPL_SURFACE = Object.freeze({
  execute: Object.freeze(["description", "editId", "edits", "input"]),
  get_app_state: Object.freeze([]),
  read_skill: Object.freeze(["path"]),
  save: Object.freeze([]),
});

// Prompt after ANSI stripping, and the exact bytes the engine writes (it
// colours the prompt even when stdout is a pipe: measured on 0.3.13).
export const REPL_PROMPT = "pen > ";
export const REPL_PROMPT_RAW = "\x1b[36mpen\x1b[39m \x1b[2m>\x1b[22m ";

// `execute` does not define the short aliases Desktop-style scripts use
// (`I(...)`, `U(...)`: ReferenceError, measured). `var`, not `const`, so a
// preamble that runs on every call can re-declare them.
export const BATCH_DESIGN_PREAMBLE =
  "var I=Insert,U=Update,C=Copy,R=Replace,M=Move,D=Delete,G=Generate;";

// @pen.dev/cli requires Node >= 22.19.0 (engines.node). Numeric compare:
// a string compare orders 22.9.0 after 22.19.0. The adapter's inline gate and
// check_deps.sh repeat these three numbers (parity test: pencil-repl-surface.test.ts).
export const NODE_FLOOR = Object.freeze([22, 19, 0]);

export function compareVersions(a, b) {
  for (let i = 0; i < 3; i++) {
    const x = Number(a[i] ?? 0);
    const y = Number(b[i] ?? 0);
    if (x !== y) return x < y ? -1 : 1;
  }
  return 0;
}

export function nodeVersionOk(version, floor = NODE_FLOOR) {
  const m = /^v?(\d+)\.(\d+)\.(\d+)/.exec(String(version ?? ""));
  if (!m) return false;
  return compareVersions([Number(m[1]), Number(m[2]), Number(m[3])], floor) >= 0;
}

// JSON.stringify leaves DEL, the C1 range (U+0080..U+009F, which includes NEL
// U+0085) and U+2028/U+2029 literal; a line-splitting engine (readline treats
// some of them as line ends) would see one command as two. Escape them all.
// Written in escape notation (cq-regex-unicode-separators-escape-only).
function jsonLine(value) {
  return JSON.stringify(value).replace(/[\u007f-\u009f\u2028\u2029]/g, (ch) =>
    "\\u" + ch.charCodeAt(0).toString(16).padStart(4, "0")
  );
}

export function formatReplCommand(toolName, params) {
  if (!Object.hasOwn(REPL_SURFACE, toolName)) {
    throw new ReplContractError(`Unknown tool: ${toolName} (not in the @pen.dev/cli REPL surface)`);
  }
  const given = {};
  for (const [k, v] of Object.entries(params ?? {})) {
    if (v !== undefined) given[k] = v;
  }
  const allowed = REPL_SURFACE[toolName];
  for (const k of Object.keys(given)) {
    if (!allowed.includes(k)) {
      throw new ReplContractError(
        `${toolName}: unexpected parameter '${k}' (allowed: ${allowed.join(", ") || "none"})`
      );
    }
  }

  if (toolName === "execute") {
    if (!("input" in given) && !("edits" in given)) {
      throw new ReplContractError("execute: 'input' must be a non-empty string");
    }
    if ("input" in given && (typeof given.input !== "string" || given.input.trim() === "")) {
      throw new ReplContractError("execute: 'input' must be a non-empty string");
    }
    const keys = Object.keys(given);
    if (keys.length === 1 && keys[0] === "input") return `execute({ input: ${jsonLine(given.input)} })`;
    return `execute(${jsonLine(given)})`;
  }

  if (Object.keys(given).length === 0) return `${toolName}()`;
  return `${toolName}(${jsonLine(given)})`;
}

// ---------------------------------------------------------------------------
// Validators. Everything the agent controls is checked here before it is
// embedded in an `execute` snippet or handed to the engine.

export const NODE_ID_RE = /^[A-Za-z0-9_-]{1,100}$/;
export const MAX_NODE_IDS = 50;
export const EXPORT_FORMATS = Object.freeze(["png", "jpeg", "webp", "pdf"]);
const SKILL_PATH_RE = /^(guide\/)?[a-z0-9-]+\.md$/;
const MAX_SKILL_PATH = 100;
const MAX_OUTPUT_DIR = 4096;

export function validateNodeId(id) {
  if (typeof id !== "string" || !NODE_ID_RE.test(id)) {
    throw new ReplContractError("node id must match ^[A-Za-z0-9_-]{1,100}$");
  }
  return id;
}

export function validateNodeIds(ids) {
  if (!Array.isArray(ids) || ids.length < 1 || ids.length > MAX_NODE_IDS) {
    throw new ReplContractError(`nodeIds must be an array of 1 to ${MAX_NODE_IDS} ids`);
  }
  return ids.map(validateNodeId);
}

export function validateExportFormat(format) {
  if (format === undefined) return "png";
  if (typeof format !== "string" || !EXPORT_FORMATS.includes(format)) {
    throw new ReplContractError(`format must be one of ${EXPORT_FORMATS.join(", ")}`);
  }
  return format;
}

export function validateScale(scale) {
  if (scale === undefined) return undefined;
  if (typeof scale !== "number" || !Number.isFinite(scale) || scale < 0.1 || scale > 8) {
    throw new ReplContractError("scale must be a finite number from 0.1 to 8");
  }
  return scale;
}

export function validateQuality(quality) {
  if (quality === undefined) return undefined;
  if (typeof quality !== "number" || !Number.isInteger(quality) || quality < 1 || quality > 100) {
    throw new ReplContractError("quality must be an integer from 1 to 100");
  }
  return quality;
}

export function validateSkillPath(path) {
  if (path === undefined) return undefined;
  if (typeof path !== "string" || path.length > MAX_SKILL_PATH || !SKILL_PATH_RE.test(path)) {
    throw new ReplContractError("read_skill path must match ^(guide/)?[a-z0-9-]+\\.md$");
  }
  return path;
}

// Shape only (absolute, bounded, no control characters). Containment inside the
// allowed roots, symlink refusal and mkdir are the adapter's containedDir().
export function validateOutputDir(dir) {
  const ok =
    typeof dir === "string" &&
    dir.length > 0 &&
    dir.length <= MAX_OUTPUT_DIR &&
    (dir.startsWith("/") || /^[A-Za-z]:[\\/]/.test(dir)) &&
    !/[\u0000-\u001f\u007f-\u009f\u2028\u2029]/.test(dir);
  if (!ok) {
    throw new ReplContractError("outputDir must be an absolute path (no control characters, at most 4096 chars)");
  }
  return dir;
}

// ---------------------------------------------------------------------------
// Builders: each returns one REPL line.

export function buildBatchDesignCommand(operations) {
  if (typeof operations !== "string" || operations.trim() === "") {
    throw new ReplContractError("batch_design: 'operations' must be a non-empty string");
  }
  return formatReplCommand("execute", { input: `${BATCH_DESIGN_PREAMBLE}\n${operations}` });
}

export function buildScreenshotCommand(nodeId) {
  const id = validateNodeId(nodeId);
  return formatReplCommand("execute", { input: `TakeScreenshot([${JSON.stringify(id)}])` });
}

export function buildExportCommand({ nodeIds, outputDir, format, scale, quality } = {}) {
  const ids = validateNodeIds(nodeIds);
  const fmt = validateExportFormat(format);
  const dir = validateOutputDir(outputDir);
  const options = {};
  const s = validateScale(scale);
  const q = validateQuality(quality);
  if (s !== undefined) options.scale = s;
  if (q !== undefined) options.quality = q;
  const tail = Object.keys(options).length > 0 ? `,${JSON.stringify(options)}` : "";
  return formatReplCommand("execute", {
    input: `Export(${JSON.stringify(ids)},${JSON.stringify(fmt)},${JSON.stringify(dir)}${tail})`,
  });
}

export function buildVariablesCommand() {
  return formatReplCommand("execute", { input: "Print(GetVariables())" });
}

export function buildEditorStateCommand() {
  return formatReplCommand("get_app_state", {});
}

export function buildReadSkillCommand(path) {
  const p = validateSkillPath(path);
  return formatReplCommand("read_skill", p === undefined ? {} : { path: p });
}

export function buildSaveCommand() {
  return formatReplCommand("save", {});
}

// ---------------------------------------------------------------------------
// Sentinel memory probe: a read-only snippet that prints the number of
// top-level nodes tagged with a per-call nonce, so text from a previous reply
// (a node name, a read_skill page) cannot forge it.

const NONCE_RE = /^[0-9a-f]{32}$/;
const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
// One self-contained IIFE using only Get and Print: a prior script that declared
// `var n,c,Print` or left globals behind cannot change what it counts. The
// literal is split so that the source echoed back in an engine error never
// contains a complete count line.
const COUNT_PRE = '(function(){var k=0;Get(function(n,c){c.skipChildren();k++;});Print("TOPLEVEL_COUNT:"+"';
const COUNT_POST = '"+":"+k);})();';
const COUNT_SNIPPET_RE = new RegExp(`^${escapeRe(COUNT_PRE)}([0-9a-f]{32})${escapeRe(COUNT_POST)}$`);

export function newCountNonce() {
  return randomBytes(16).toString("hex");
}

export function buildCountSnippet(nonce) {
  if (typeof nonce !== "string" || !NONCE_RE.test(nonce)) {
    throw new ReplContractError("count nonce must be 32 lowercase hex characters");
  }
  return `${COUNT_PRE}${nonce}${COUNT_POST}`;
}

export function buildCountCommand(nonce) {
  return formatReplCommand("execute", { input: buildCountSnippet(nonce) });
}

// The nonce when `input` is exactly the adapter's count snippet, else null.
export function countSnippetNonce(input) {
  const m = COUNT_SNIPPET_RE.exec(String(input ?? ""));
  return m ? m[1] : null;
}

// The top-level node count carried by a reply to the count snippet, or null.
// Exactly one line `TOPLEVEL_COUNT:<this nonce>:<digits>` on an `OK` reply;
// zero lines, two lines, another nonce or an error reply all give null.
export function parseCountReply(text, nonce) {
  if (typeof nonce !== "string" || !NONCE_RE.test(nonce)) return null;
  const lines = stripAnsi(String(text ?? "")).split(/\r?\n/);
  const first = lines.find((l) => l.trim() !== "");
  if (first === undefined || first.trim() !== "OK") return null;
  const re = new RegExp(`^TOPLEVEL_COUNT:${nonce}:(\\d{1,9})$`);
  const hits = lines.filter((l) => re.test(l));
  if (hits.length !== 1) return null;
  return Number(re.exec(hits[0])[1]);
}

// ---------------------------------------------------------------------------
// Redaction. `redactionForms` lists the spellings a credential can take in
// engine output; the rolling redactor holds back a tail so a value split
// across two stderr chunks is still replaced.

const REDACTED = "<redacted>";
const MIN_FORM_LENGTH = 4;

export function redactionForms(secret) {
  if (typeof secret !== "string") return [];
  const trimmed = secret.trim();
  if (trimmed.length < MIN_FORM_LENGTH) return [];
  const b64 = Buffer.from(trimmed).toString("base64");
  const candidates = [
    secret,
    trimmed,
    JSON.stringify(trimmed).slice(1, -1),
    encodeURIComponent(trimmed),
    b64,
    b64.replace(/=+$/, ""),
    b64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, ""),
  ];
  const forms = [...new Set(candidates)].filter((f) => f.length >= MIN_FORM_LENGTH);
  return forms.sort((a, b) => b.length - a.length);
}

export function redactText(text, forms) {
  let out = String(text ?? "");
  for (const form of forms ?? []) {
    if (form) out = out.split(form).join(REDACTED);
  }
  return out;
}

// How many characters at the END of `text` are the start of a credential spelling that has
// not finished (a proper prefix of a form, at least MIN_FORM_LENGTH long): the part of a
// reply that must not be shown until the next piece proves it is not the rest of the key.
export function heldPrefixLength(text, forms) {
  const s = String(text ?? "");
  let best = 0;
  for (const form of forms ?? []) {
    if (!form) continue;
    for (let k = Math.min(form.length - 1, s.length); k >= Math.max(MIN_FORM_LENGTH, best + 1); k--) {
      if (s.endsWith(form.slice(0, k))) {
        best = k;
        break;
      }
    }
  }
  return best;
}

// push(chunk) returns the text that is safe to emit now; flush() returns the
// held-back tail (call it when the stream ends). Holds back at most
// (longest form - 1) characters, and never cuts through a match.
export function createRollingRedactor(forms) {
  const list = [...(forms ?? [])].filter(Boolean).sort((a, b) => b.length - a.length);
  const hold = list.length === 0 ? 0 : list[0].length - 1;
  let pending = "";

  const spansOf = (s) => {
    const spans = [];
    let i = 0;
    while (i < s.length) {
      const form = list.find((f) => s.startsWith(f, i));
      if (form) {
        spans.push([i, i + form.length]);
        i += form.length;
      } else {
        i++;
      }
    }
    return spans;
  };

  return {
    push(chunk) {
      const s = pending + String(chunk ?? "");
      if (list.length === 0) return s;
      let cut = Math.max(0, s.length - hold);
      for (const [start, end] of spansOf(s)) {
        if (start < cut && cut < end) cut = start;
      }
      pending = s.slice(cut);
      return redactText(s.slice(0, cut), list);
    },
    flush() {
      const rest = redactText(pending, list);
      pending = "";
      return rest;
    },
  };
}

// ---------------------------------------------------------------------------
// Decide the `--in` argument for one spawn of `pen interactive --out <outFile>`.
//
// `initialInFile` is the caller's explicit input (a template). The adapter
// passes it for the open_document spawn only and passes none on a respawn, so a
// respawn after a crash reloads `outFile` and a template can never overwrite
// saved edits.
// Without an explicit input, an existing non-empty `outFile` is reloaded:
// `--out` alone starts an EMPTY document and the next save would replace the
// file with 96 bytes (#11143; re-measured unchanged on 0.3.13).
//
// `resumeInFile` is the template a previous spawn of the SAME target loaded
// from. It applies only while `outFile` holds nothing saved: a child that dies
// before the first save would otherwise respawn empty and silently drop the
// template. Saved edits in `outFile` always win over it.
//
// `probe` is `{ exists(path): boolean, size(path): number }`, injected so this
// stays pure.
export function planSpawn({ outFile, initialInFile, resumeInFile = null, probe }) {
  if (initialInFile) {
    if (!probe.exists(initialInFile)) {
      throw new Error(`Input file not found: ${initialInFile}`);
    }
    return { inFile: initialInFile };
  }
  if (probe.exists(outFile) && probe.size(outFile) > 0) {
    return { inFile: outFile };
  }
  if (resumeInFile && probe.exists(resumeInFile)) {
    return { inFile: resumeInFile };
  }
  return { inFile: null };
}
