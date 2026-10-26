// pencil-stub-repl.mjs — stand-in for `pen interactive` (@pen.dev/cli 0.3.13) used by
// the adapter integration tests. A stub encodes our BELIEF about the engine, so every
// reply shape here is pinned to a transcript captured from the real engine
// (fixtures/pen-0.3.13-transcript.txt, replayed by pencil-stub-transcript.test.ts);
// engine-contract-probe.sh is the live oracle. There is exactly ONE copy of the REPL
// signature whitelist: this file imports the table and the prompt from
// pencil-repl-surface.mjs. It exits 64 on an unknown key of a known tool (the real
// engine silently drops it, which is how #11143 hid), and answers `Unknown tool:` for
// any name outside the table.
//
// Measured behaviour reproduced: `pen > ` prompt (coloured even on a pipe); success
// replies on stdout; EVERY failure on stderr with a blank line on stdout; `--out`
// alone loads an EMPTY document; an unparseable `--in` is fatal; no PEN_CLI_KEY is
// fatal; `execute` runs the script in a persistent sandbox with the DSL host functions
// (Insert, Update, Get, Print, TakeScreenshot, Export, ...), rolls a failed block
// back, and lints collapsed frames into an `## issues detected:` block. Approximate:
// SyntaxError wording (QuickJS says `expecting ';'`; the stub always says that),
// layout linting beyond collapsed frames, and `[user visible]` tags.
//
// Side channels, because the adapter hands the child a scrubbed environment. Each is
// `<out>[.<tag>].<ext>` (lib/stub-tag.mjs; the tag comes from the STUB_TAG wrapper so two
// sessions on one path do not share them):
//   <out>.log    every command line received; one ARGS line, one ENVKEYS line (env
//                key NAMES only), one CWD line per start; COUNT lines for probes
//   <out>.pid    the child's pid (the test kills it to simulate a crash)
//   <out>.flags  JSON read at start and before each command:
//     loadEmpty         ignore the --in document (the engine's silent empty load)
//     invalidAsEmpty    legacy 0.2.9: an unparseable --in loads empty with an [ERROR] line
//     exitOnStart       exit 1 before the first prompt (a failed respawn)
//     slowExitMs        take this long to exit after SIGTERM (a slow old child)
//     startDelayMs      delay the first prompt by this long (a slow new child)
//     bigExecute        pad execute replies past 64 KiB (a large design)
//     failSave          save() prints the measured `Save failed: EACCES...` shape and writes nothing
//     saveReply         text printed verbatim instead of `Saved <path>` ("" prints nothing)
//     saveWrites        false: save() does not write the file
//     countForgery      wrongNonce | duplicate | missing: tamper with the count-probe reply
//     rewriteOnStart    <doc>: write --out after loading --in and before the first prompt
//     rewriteOnProbe    <doc>: write --out just before answering the count probe
//                       (<doc> is an object, JSON-encoded, or a string, written raw)
//     echoKey           true: an execute error on stderr that echoes PEN_CLI_KEY;
//                       "stdout": the same text as a stdout reply
//     echoKeySplit      the key goes to stderr in two chunks 50 ms apart on each execute
// It reads stdin to EOF-or-exit (a stub that stops draining makes pipefail suites flake
// on EPIPE).

import { createInterface } from "node:readline";
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { randomBytes, randomUUID } from "node:crypto";
import { dirname, join } from "node:path";
import vm from "node:vm";
import {
  BATCH_DESIGN_PREAMBLE,
  REPL_PROMPT_RAW,
  REPL_SURFACE,
  countSnippetNonce,
} from "../../skills/pencil-setup/scripts/pencil-repl-surface.mjs";
import { sideFile } from "../lib/stub-tag.mjs";

const argv = process.argv.slice(2);
if (argv[0] !== "interactive") {
  process.stderr.write("stub: expected 'interactive'\n");
  process.exit(2);
}
const flag = (names) => {
  const i = argv.findIndex((a) => names.includes(a));
  return i === -1 ? null : argv[i + 1] ?? null;
};
const outFile = flag(["--out", "-o"]);
const inFile = flag(["--in", "-i"]);
if (!outFile) {
  process.stderr.write("stub: --out is required in headless mode\n");
  process.exit(2);
}

const log = (line) => appendFileSync(sideFile(outFile, "log"), line + "\n");
const flags = () => {
  try {
    return JSON.parse(readFileSync(sideFile(outFile, "flags"), "utf8"));
  } catch {
    return {};
  }
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ANSI as the real engine writes it on a pipe (measured).
const ESC = "\x1b[";
const bold = (s) => `${ESC}1m${s}${ESC}22m`;
const dim = (s) => `${ESC}2m${s}${ESC}22m`;
const red = (s) => `${ESC}31m${s}${ESC}39m`;
const yellow = (s) => `${ESC}33m${s}${ESC}39m`;
const green = (s) => `${ESC}32m${s}${ESC}39m`;

log(`ARGS ${argv.join(" ")}`);
log(`ENVKEYS ${Object.keys(process.env).sort().join(",")}`);
log(`CWD ${process.cwd()}`);
writeFileSync(sideFile(outFile, "pid"), String(process.pid));

// Auth: a missing (or empty) key is fatal, before anything else (measured).
if (!process.env.PEN_CLI_KEY) {
  process.stderr.write('[ERROR] Authentication required. Run "pen login" or set PEN_CLI_KEY environment variable.\n');
  process.exit(1);
}
if (flags().exitOnStart) {
  process.stderr.write("stub: exitOnStart flag set\n");
  process.exit(1);
}
const slowExitMs = Number(flags().slowExitMs ?? 0);
if (slowExitMs > 0) process.on("SIGTERM", () => setTimeout(() => process.exit(0), slowExitMs));

process.stdout.write("[INFO] Starting pen.dev (headless)...\n");

// ---------------------------------------------------------------------------
// Document state.

let nodes = [];
let fileToken = randomUUID();
let variables = {};

const writeDoc = (path, doc) => writeFileSync(path, typeof doc === "string" ? doc : JSON.stringify(doc));

if (inFile) {
  if (!existsSync(inFile)) {
    process.stderr.write(`Input file not found: ${inFile}\n`);
    process.exit(1);
  }
  if (!flags().loadEmpty) {
    const text = readFileSync(inFile, "utf8");
    let doc;
    try {
      doc = JSON.parse(text.replace(/^﻿/, ""));
    } catch (e) {
      if (flags().invalidAsEmpty) {
        process.stderr.write(`[ERROR] Input file is not a valid .pen: ${inFile}\n`);
      } else {
        // measured on 0.3.13: the CLI exits instead of loading it empty
        process.stderr.write(
          `[ERROR] Error loading scene graph: DocumentParseError: Failed to parse "file://${inFile}": SyntaxError: ${e.message}\n` +
            `[ERROR] Fatal error: Error: Failed to open document: ${inFile}\n    at stub (file:///stub-repl.mjs:1:1)\n`
        );
        process.exit(1);
      }
    }
    if (doc) {
      nodes = Array.isArray(doc.children) ? doc.children : [];
      if (typeof doc.fileToken === "string") fileToken = doc.fileToken;
    }
  }
}
if (flags().rewriteOnStart !== undefined) writeDoc(outFile, flags().rewriteOnStart);

process.stdout.write(
  "[INFO] Ready.\n\n" +
    `${bold("pen.dev Interactive Shell")}\n` +
    `${dim(`File: ${outFile}`)}\n` +
    `${dim('Type tool calls like: read_skill({ path: "pen-schema.md" })')}\n` +
    `${dim("Type save() to save, exit() to quit.")}\n\n`
);
const startDelayMs = Number(flags().startDelayMs ?? 0);
if (startDelayMs > 0) setTimeout(() => process.stdout.write(REPL_PROMPT_RAW), startDelayMs);
else process.stdout.write(REPL_PROMPT_RAW);

// ---------------------------------------------------------------------------
// Replies. stdout carries success text; every failure goes to stderr and stdout
// carries only a blank line, then the prompt.

const reply = (stdoutText = null) => {
  if (stdoutText !== null) process.stdout.write(stdoutText);
  process.stdout.write(`\n${REPL_PROMPT_RAW}`);
};
const fail = (stderrText) => {
  process.stderr.write(stderrText);
  reply();
};

const newId = () => {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  const bytes = randomBytes(5);
  return Array.from(bytes, (b) => alphabet[b % alphabet.length]).join("");
};

function appState() {
  const entries = nodes.map(
    (n, i) => `\`${n.id}\` (${n.type ?? "frame"}): ${n.name ?? n.type ?? "frame"} [${i === 0 ? "user visible" : "outside viewport"}]`
  );
  return (
    "# Current App State\n\n" +
    "Use your best judgement based on the app state whether the user task relates to the canvas, the browser or both.\n\n" +
    "## Canvas Editor\n\n" +
    `- Currently active canvas editor: \`${outFile}\`\n` +
    "- Selected nodes: No nodes are selected\n" +
    `- Top-level nodes: ${entries.length ? entries.join(", ") : "The document is empty (no top-level nodes)"}\n` +
    "- Reusable components: No reusable components found\n\n" +
    "## Integrated Browser\n\n" +
    "- The integrated browser in the app is closed currently, use the `browser` tool to open it if you want to access a live website.\n" +
    "- Browser nodes on the canvas (type \"browser\") are driven by passing their node id as the browser tool's \"nodeId\".\n\n" +
    "## Account\n" +
    "- Signed in to pen.dev: yes"
  );
}

// read_skill: the stub serves its own synthetic markdown (the vendor's text is not
// copied here); only the set of readable names and the failure shape are measured.
const SKILL_FILES = new Set([
  "pen-schema.md",
  "execute.md",
  "generate.md",
  "scripts-and-shaders.md",
  ...["components", "code", "design-system", "landing-page", "mobile-app", "slides", "table", "tailwind", "web-app"].map((g) => `guide/${g}.md`),
]);

function readSkill(path) {
  if (path === undefined) {
    return `---\nname: pen-dev\n---\n\n# pen.dev (stub skill index)\n\n${[...SKILL_FILES].map((f) => `- ./${f}`).join("\n")}`;
  }
  if (!SKILL_FILES.has(path)) {
    const file = join(dirname(dirname(process.argv[1])), "dist/out/skills/pen-dev", path);
    const msg = `ENOENT: no such file or directory, open '${file}'`;
    return {
      stderr:
        `[WARN] [IPC] request 'read-skill-file' failed after 1ms: [Error: ${msg}] {\n  errno: -2,\n  code: 'ENOENT',\n  syscall: 'open',\n  path: '${file}'\n}\n` +
        `[WARN] [IPC] sent request 'read-skill-file' was rejected after 2ms: HANDLER_ERROR ${msg}\n` +
        `${red(`Error: ${msg}`)}\n`,
    };
  }
  const text = path === "execute.md" ? "# execute (stub)\n\nDSL grammar: Insert, Update, Copy, Replace, Move, Delete, Generate, Get, Print, ..." : `# ${path} (stub skill page)`;
  return `---\nname: pen-dev\n---\n\n${text}\n\n- a prompt-shaped line follows for framing tests\n${"pen > "}this line starts with the prompt text`;
}

// ---------------------------------------------------------------------------
// execute: a persistent sandbox with the DSL host functions.

const ALIASES = new Set(["I", "U", "C", "R", "M", "D", "G"]);
const TINY_PNG =
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==";

class HostError extends Error {
  constructor(kind, message) {
    super(message);
    this.hostKind = kind;
  }
}

const findNode = (id, list = nodes) => {
  for (const n of list) {
    if (n.id === id) return n;
    const inner = findNode(id, n.children ?? []);
    if (inner) return inner;
  }
  return null;
};
const removeNode = (id, list = nodes) => {
  const i = list.findIndex((n) => n.id === id);
  if (i !== -1) return list.splice(i, 1)[0];
  for (const n of list) {
    const got = removeNode(id, n.children ?? []);
    if (got) return got;
  }
  return null;
};
const need = (id) => {
  const n = findNode(String(id));
  if (!n) throw new HostError("missing-node", `Failed to find a node with id ${id}`);
  return n;
};

let block = null; // state of the execute block in flight
const printed = () => block.printed;

const host = {
  Insert(parent, props = {}) {
    const target = parent === "document" ? null : need(parent);
    const node = { ...props, id: newId() };
    if (props.id !== undefined) block.idRewrites.push([String(props.id), node.id]);
    node.children = Array.isArray(props.children) ? props.children : [];
    (target ? (target.children ??= []) : nodes).push(node);
    block.created.push(node);
    return node.id;
  },
  Update(id, props = {}) {
    Object.assign(need(id), props, { id: String(id) });
  },
  Copy(id, parent, props = {}) {
    const src = need(id);
    const copy = { ...JSON.parse(JSON.stringify(src)), ...props, id: newId() };
    (parent === undefined || parent === "document" ? nodes : (need(parent).children ??= [])).push(copy);
    block.created.push(copy);
    return copy.id;
  },
  Replace(id, props = {}) {
    const n = need(id);
    for (const k of Object.keys(n)) if (k !== "id") delete n[k];
    Object.assign(n, props, { id: String(id), children: props.children ?? [] });
    return n.id;
  },
  Move(id, parent, index) {
    const n = need(id);
    removeNode(n.id);
    const list = parent === undefined || parent === "document" ? nodes : (need(parent).children ??= []);
    list.splice(index === undefined ? list.length : index, 0, n);
  },
  Delete(ids) {
    for (const id of Array.isArray(ids) ? ids : [ids]) {
      need(id);
      removeNode(String(id));
    }
  },
  Generate() {
    throw new HostError("unsupported", "Generate is not available in the stub");
  },
  Get(visitor) {
    if (typeof visitor !== "function") throw new Error("Get requires a visitor function");
    const walk = (list) => {
      for (const n of list) {
        let skip = false;
        visitor({ ...n, children: undefined }, { skipChildren: () => (skip = true) });
        if (!skip) walk(n.children ?? []);
      }
    };
    walk(nodes);
  },
  Print(...args) {
    printed().push(args.map((a) => (typeof a === "string" ? a : a === undefined ? "undefined" : JSON.stringify(a))).join(" "));
  },
  GetVariables: () => ({ variables }),
  SetVariables(v) {
    variables = { ...variables, ...(v?.variables ?? v) };
  },
  FindEmptySpace: () => ({ x: 0, y: 0 }),
  TakeScreenshot(ids) {
    const list = (Array.isArray(ids) ? ids : [ids]).map(String);
    for (const id of list) need(id);
    block.screenshots = list.map((id) => ({ nodeId: id, image: TINY_PNG, mimeType: "image/png" }));
  },
  Export(ids, format = "png", dir, options) {
    const list = (Array.isArray(ids) ? ids : [ids]).map(String);
    for (const id of list) need(id);
    if (typeof dir !== "string") throw new Error("Export: outputDir must be a string");
    if (options !== undefined && (typeof options !== "object" || options === null)) throw new Error("Export: options must be an object");
    mkdirSync(dir, { recursive: true });
    for (const id of list) {
      const file = join(dir, `${id}.${format}`);
      writeFileSync(file, Buffer.from(TINY_PNG, "base64"));
      printed().push(`Exported ${file}`);
    }
  },
};

const sandbox = vm.createContext({});
sandbox.document = "document";
for (const [name, fn] of Object.entries(host)) {
  // wrap so a thrown host error remembers which call it came from
  sandbox[name] = (...args) => {
    const index = block.ops++; // the engine numbers operations from the first statement of the block
    try {
      return fn(...args);
    } catch (e) {
      if (e && typeof e === "object" && !e.hostCall) {
        e.hostCall = name;
        e.opIndex = index;
      }
      throw e;
    }
  };
}
const BUILTIN = new Set(Object.keys(sandbox));
let lastVar = "root";

// Source text of the first call to `name(` in the script, parentheses balanced.
function callText(input, name) {
  const start = input.indexOf(`${name}(`);
  if (start === -1) return `${name}(...)`;
  let depth = 0;
  let quote = null;
  for (let i = start + name.length; i < input.length; i++) {
    const ch = input[i];
    if (quote) {
      if (ch === "\\") i++;
      else if (ch === quote) quote = null;
    } else if (ch === '"' || ch === "'" || ch === "`") quote = ch;
    else if (ch === "(") depth++;
    else if (ch === ")" && --depth === 0) return input.slice(start, i + 1);
  }
  return input.slice(start);
}

const EDIT_ADVICE =
  "- IMPORTANT: Fix this by calling `execute` again with the `edits` parameter instead of regenerating the whole snippet";

function failureBlock(body) {
  const editId = Array.from(randomBytes(6), (b) => "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"[b % 62]).join("");
  return (
    `${red(
      "Error: ### Failure during operation execution\n\n#### Errors in the input code:\n```\n" +
        body +
        "\n```\n\n- All operations in this block have been rolled back.\n" +
        EDIT_ADVICE +
        `\n- \`editId\`: "${editId}"`
    )}\n`
  );
}

const lintFrames = (created, held) => {
  const out = [];
  for (const n of created) {
    if ((n.type ?? "frame") !== "frame" || n.width !== undefined || n.height !== undefined || (n.children ?? []).length > 0) continue;
    const ref = held.get(n.id) ?? n.id;
    for (const axis of ["vertical", "horizontal"]) {
      out.push(
        `- Collapsed size: node '${ref}' uses 'fit_content' sizing on the ${axis} axis but has no children to size from, so its ${axis} size collapses to zero and the node becomes invisible. Add children, or give it a fixed size or 'fill_container' sizing.`
      );
    }
  }
  return out;
};

function runExecute(input) {
  const before = JSON.parse(JSON.stringify(nodes));
  const beforeKeys = new Set(Object.keys(sandbox));
  block = { printed: [], created: [], idRewrites: [], screenshots: null, ops: input.startsWith(BATCH_DESIGN_PREAMBLE) ? 7 : 0 };
  const lastLine = input.trim().split("\n").at(-1);
  const toolUse = `[batch-design][tool-use-${Date.now()}${Math.floor(Math.random() * 1000)}]`;

  try {
    vm.runInContext(input, sandbox, { timeout: 5000 });
  } catch (e) {
    nodes = before;
    if (e && e.hostKind) {
      const call = callText(input, e.hostCall ?? "Insert");
      process.stderr.write(
        `[ERROR] ${toolUse} failed to execute operation: ${call} $${e.opIndex} [Error]: ${e.message}\n` +
          "    at stub (file:///stub-repl.mjs:1:1)\n    at Generator.next (<anonymous>) {\n" +
          `  kind: '${e.hostKind}'\n}\n` +
          `[ERROR] ${toolUse} tool call failed (- \`${call}\`: Error: ${e.message})\n` +
          failureBlock(`- \`${call}\`: Error: ${e.message}`)
      );
      return reply();
    }
    const name = e?.name ?? "Error";
    let message = String(e?.message ?? e);
    if (name === "SyntaxError") message = "expecting ';'";
    const ref = /^(\w+) is not defined$/.exec(message);
    if (ref) message = `'${ref[1]}' is not defined`;
    const detail = `Failed to execute: ${name}: ${message}\n  at: \`${lastLine}\``;
    process.stderr.write(
      `[ERROR] ${toolUse} failed to execute JavaScript: ${name}: ${message}\n  at: \`${lastLine}\`\n` +
        `[ERROR] ${toolUse} tool call failed (${detail})\n` +
        failureBlock(detail)
    );
    return reply();
  }

  // which globals now hold a node id, and the newest user variable
  const held = new Map();
  for (const [k, v] of Object.entries(sandbox)) if (typeof v === "string" && block.created.some((n) => n.id === v)) held.set(v, k);
  const fresh = Object.keys(sandbox).filter((k) => !beforeKeys.has(k) && !BUILTIN.has(k) && !ALIASES.has(k) && sandbox[k] !== undefined);
  if (fresh.length) lastVar = fresh[fresh.length - 1];

  let text = `OK\n\nGlobal variables (e.g. ${lastVar}) carry over to subsequent calls!\n`;
  if (block.idRewrites.length) {
    text += `\nInvalid \`id\` properties were replaced with new generated IDs. Use these new ids from now on:\n${block.idRewrites
      .map(([from, to]) => `- "${from}": "${to}"`)
      .join("\n")}\n`;
  }
  if (block.created.length) {
    text +=
      "\n## Created nodes by name\nIds are strings - quote them when used in code. Entries marked `(= variable)` are also held by that global variable, usable directly in later calls:\n```\n" +
      block.created.map((n) => `"${n.name ?? n.type ?? "frame"}": "${n.id}"${held.has(n.id) ? ` (= ${held.get(n.id)})` : ""}`).join("\n") +
      "\n```\n";
  }
  if (block.screenshots) {
    text +=
      `\nScreenshots taken of nodes: ${block.screenshots.map((s) => s.nodeId).join(", ")}\n\n` +
      "Analyze the attached screenshots that they satisfy the requirements. Verify there is no broken, collapsed, or overflowing layout issue.\n\n" +
      JSON.stringify(block.screenshots, null, 2);
  } else if (block.printed.length) {
    text += `\n## Print output\n${block.printed.join("\n")}\n`;
  }
  const issues = lintFrames(block.created, held);
  if (issues.length) text += `\n## issues detected:\n${issues.join("\n")}\n\n\nReview these issues and attempt to resolve them in subsequent calls.\n`;
  if (flags().bigExecute && countSnippetNonce(input) === null) text += `\n## Print output\n${"x".repeat(70_000)}\n`;
  return reply(`${text}\n`);
}

// The count probe: optionally forged, answered from MEMORY (not disk).
function runCountProbe(nonce) {
  log(`COUNT nonce=${nonce} memory=${nodes.length}`);
  if (flags().rewriteOnProbe !== undefined) writeDoc(outFile, flags().rewriteOnProbe);
  const head = `OK\n\nGlobal variables (e.g. ${lastVar}) carry over to subsequent calls!\n`;
  const forgery = flags().countForgery;
  const other = randomBytes(16).toString("hex");
  const lines =
    forgery === "wrongNonce"
      ? [`TOPLEVEL_COUNT:${other}:${nodes.length}`]
      : forgery === "duplicate"
        ? [`TOPLEVEL_COUNT:${nonce}:${nodes.length}`, `TOPLEVEL_COUNT:${nonce}:${nodes.length + 1}`]
        : forgery === "missing"
          ? []
          : null;
  if (lines === null) return false;
  reply(`${head}${lines.length ? `\n## Print output\n${lines.join("\n")}\n` : ""}\n`);
  return true;
}

// ---------------------------------------------------------------------------
// save().

function doSave() {
  const f = flags();
  if (f.failSave) return saveFailure({ message: `EACCES: permission denied, open '${outFile}'`, errno: -13, code: "EACCES", syscall: "open", path: outFile });
  if (f.saveReply !== undefined) {
    if (f.saveWrites !== false) writeDoc(outFile, { version: "2.21", fileToken, children: nodes });
    return reply(f.saveReply === "" ? null : `${f.saveReply}\n`);
  }
  if (f.saveWrites !== false) {
    try {
      writeDoc(outFile, { version: "2.21", fileToken, children: nodes });
    } catch (err) {
      return saveFailure(err);
    }
  }
  return reply(`${green(`Saved ${outFile}`)}\n`);
}

function saveFailure(err) {
  const where = `'${err.path ?? outFile}'`;
  process.stderr.write(
    `[WARN] [IPC] request 'save-resource' failed after 2ms: [Error: ${err.message}] {\n  errno: ${err.errno},\n  code: '${err.code}',\n  syscall: '${err.syscall}',\n  path: ${where}\n}\n` +
      `[WARN] [IPC] sent request 'save-resource' was rejected after 3ms: HANDLER_ERROR ${err.message}\n` +
      `[ERROR] Headless editor error [Error: ${err.message}] {\n  code: 'HANDLER_ERROR',\n  name: 'IPCError'\n}\n` +
      `${red(`Save failed: ${err.message}`)}\n`
  );
  return reply();
}

// ---------------------------------------------------------------------------
// The command loop.

const rl = createInterface({ input: process.stdin });
rl.on("line", async (line) => {
  const cmd = line.trim();
  if (cmd === "") return reply();
  log(cmd);
  if (cmd === "exit()") process.exit(0);
  const m = /^([A-Za-z_][A-Za-z0-9_]*)\(([\s\S]*)\)$/.exec(cmd);
  if (!m) return fail(`${red(`Error: cannot parse '${cmd.slice(0, 80)}'`)}\n`);
  const [, tool, rest] = m;

  let args = {};
  if (rest.trim() !== "") {
    try {
      args = new Function(`return (${rest})`)();
    } catch (e) {
      return fail(`${red(`Error: bad arguments: ${e.message}`)}\n`);
    }
  }

  if (!Object.hasOwn(REPL_SURFACE, tool)) return fail(`${yellow(`Unknown tool: ${tool}`)}\n`);
  for (const k of Object.keys(args ?? {})) {
    if (!REPL_SURFACE[tool].includes(k)) {
      process.stderr.write(`stub: ${tool} got unexpected key '${k}'\n`);
      log(`REJECTED ${tool} key=${k}`);
      process.exit(64);
    }
  }

  if (tool === "save") return doSave();
  if (tool === "get_app_state") return reply(`${appState()}\n`);
  if (tool === "read_skill") {
    const got = readSkill(args.path);
    return typeof got === "string" ? reply(`${got}\n`) : fail(got.stderr);
  }

  // execute
  if (typeof args.input !== "string") return fail(`${red("Error: execute: the stub supports `input` only")}\n`);
  const f = flags();
  if (f.echoKeySplit) {
    const key = process.env.PEN_CLI_KEY ?? "";
    const half = Math.ceil(key.length / 2);
    process.stderr.write(`[WARN] retrying with credential ${key.slice(0, half)}`);
    await sleep(50);
    process.stderr.write(`${key.slice(half)} (end)\n`);
    await sleep(40);
  }
  if (f.echoKey) {
    const text = `Error: auth failed for key ${process.env.PEN_CLI_KEY}`;
    return f.echoKey === "stdout" ? reply(`${text}\n`) : fail(`${red(text)}\n`);
  }
  const nonce = countSnippetNonce(args.input);
  if (nonce !== null && runCountProbe(nonce) !== false) return;
  return runExecute(args.input);
});
rl.on("close", () => process.exit(0));
