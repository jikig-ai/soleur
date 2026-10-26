#!/usr/bin/env node

// pencil-mcp-adapter.mjs — MCP server bridging Claude Code to the pen.dev interactive REPL
// Architecture: Claude Code <-(MCP stdio)-> this adapter <-(stdin/stdout REPL)-> `pen interactive`
// (@pen.dev/cli 0.3.13, pinned in check_deps.sh and scripts/pen-cli/).
//
// The agent-facing `mcp__pencil__*` tool names are stable (hooks and prose are keyed on
// them); each live tool is translated onto the engine's REPL (`execute`, `get_app_state`,
// `read_skill`, `save`) through pencil-repl-surface.mjs, and tools the engine cannot honour
// are registered as removed-tool stubs with an actionable hint (pencil-error-enrichment.mjs).
//
// The Node-version gate, argv defense, and the credential hard-fail run BEFORE any module
// imports so a broken registration exits with a clear adapter-authored error instead of
// ERR_MODULE_NOT_FOUND from the MCP SDK. All imports are dynamic (`await import`) for the
// same reason — static imports resolve during module parsing, before any top-level
// statement runs. Rule: cq-pencil-mcp-silent-drop-diagnosis-checklist.

// --- Node version gate (numeric: a string compare orders 22.9.0 after 22.19.0) ---

const NODE_FLOOR = [22, 19, 0];
{
  const have = process.version.slice(1).split(".").map((n) => parseInt(n, 10) || 0);
  let below = false;
  for (let i = 0; i < 3; i++) {
    if (have[i] !== NODE_FLOOR[i]) {
      below = have[i] < NODE_FLOOR[i];
      break;
    }
  }
  if (below) {
    process.stderr.write(
      `[pencil-adapter] ERROR: Node >= ${NODE_FLOOR.join(".")} required (@pen.dev/cli needs it), got ${process.version}.\n` +
        "[pencil-adapter] Run `bash plugins/soleur/skills/pencil-setup/scripts/check_deps.sh` to find or install a supported Node, then re-register.\n"
    );
    process.exit(1);
  }
}

// --- Defense-in-depth: parse -e KEY=VALUE from argv ---
// If `claude mcp add` passes -e flags as args instead of env vars (e.g., -e placed after
// the -- separator), inject the credential into process.env. Only the two credential
// names are honoured; argv is visible to other local users, so a key that arrives this
// way is called out (value-free).

let keyFromArgv = false;
for (let i = 2; i < process.argv.length; i++) {
  if (process.argv[i] === "-e" && i + 1 < process.argv.length) {
    const eqIdx = process.argv[i + 1].indexOf("=");
    if (eqIdx > 0) {
      const name = process.argv[i + 1].slice(0, eqIdx);
      const val = process.argv[i + 1].slice(eqIdx + 1);
      if (name === "PEN_CLI_KEY" || name === "PENCIL_CLI_KEY") {
        if (!(process.env[name] ?? "").trim()) {
          process.env[name] = val;
          keyFromArgv = true;
        }
      } else {
        process.stderr.write(
          `[pencil-adapter] ignoring -e ${name.replace(/[^A-Za-z0-9_]/g, "?").slice(0, 40)}: only PEN_CLI_KEY and PENCIL_CLI_KEY are accepted\n`
        );
      }
    }
    i++; // skip the value arg
  }
}
if (keyFromArgv) {
  process.stderr.write(
    "[pencil-adapter] WARN: the credential arrived on argv (-e), and argv is visible to other local users. " +
      "Register with -e BEFORE -- so it travels in the environment instead.\n"
  );
}

// --- Credential: resolved ONCE, then removed from process.env ---
// PEN_CLI_KEY wins; PENCIL_CLI_KEY is the deprecated fallback (same value, still works).
// An empty or whitespace-only value counts as unset. Runs BEFORE the MCP SDK import so
// the exit message is adapter-authored. A missing key used to be a stderr warning that
// let the adapter boot and every REPL mutation return an auth error the auto-save ran
// over — producing 0-byte .pen files the caller mistook for success (#2630).

const API_KEY = (process.env.PEN_CLI_KEY ?? "").trim() || (process.env.PENCIL_CLI_KEY ?? "").trim();
const KEY_FROM_FALLBACK = !(process.env.PEN_CLI_KEY ?? "").trim() && API_KEY !== "";
delete process.env.PEN_CLI_KEY;
delete process.env.PENCIL_CLI_KEY;

if (!API_KEY) {
  process.stderr.write(
    "[pencil-adapter] ERROR: PEN_CLI_KEY not set. Refusing to start.\n" +
      "[pencil-adapter] (PENCIL_CLI_KEY is accepted as a deprecated fallback; an empty value counts as unset.)\n" +
      "[pencil-adapter] If you used `claude mcp add`, ensure -e appears BEFORE --\n" +
      "[pencil-adapter] Run `/soleur:pencil-setup` to re-register with a valid key.\n"
  );
  process.exit(1);
}
if (KEY_FROM_FALLBACK) {
  process.stderr.write(
    "[pencil-adapter] WARN: PENCIL_CLI_KEY is deprecated; register the same value as PEN_CLI_KEY. Using it for now.\n"
  );
}

// --- Dynamic imports (deferred so the gates above run first) ---
//
// Wrapped in try/catch so a missing `node_modules/@modelcontextprotocol/sdk` (e.g., after
// a drifted install that copied the adapter but not its deps) surfaces as an
// adapter-authored error rather than an unhandledRejection trace.

let McpServer, StdioServerTransport, z, nodeSpawn;
let existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, statSync, writeFileSync;
let openSync, closeSync, fstatSync, readSync, fsConstants;
let basename, dirname, isAbsolute, join, resolve, sep;
let homedir, tmpdir;
let enrichErrorMessage, removedToolHint, REMOVED_TOOL_NAMES, sanitizeFilename, classifyResponse, stripAnsi;
let runGuardedSave, diskTopLevelCount, memoryTopLevelCount, DISK_UNRECOGNIZED, fingerprintState, savedReplyPath, hash8;
let formatReplCommand, planSpawn, REPL_PROMPT;
let buildBatchDesignCommand, buildScreenshotCommand, buildExportCommand, buildVariablesCommand;
let buildEditorStateCommand, buildReadSkillCommand, newCountNonce, buildCountCommand;
let validateNodeIds, validateExportFormat, validateScale, validateQuality, validateOutputDir;
let redactionForms, redactText, createRollingRedactor;

try {
  ({ McpServer } = await import("@modelcontextprotocol/sdk/server/mcp.js"));
  ({ StdioServerTransport } = await import("@modelcontextprotocol/sdk/server/stdio.js"));
  ({ z } = await import("zod"));
  ({ spawn: nodeSpawn } = await import("node:child_process"));
  ({
    existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, statSync, writeFileSync,
    openSync, closeSync, fstatSync, readSync, constants: fsConstants,
  } = await import("node:fs"));
  ({ basename, dirname, isAbsolute, join, resolve, sep } = await import("node:path"));
  ({ homedir, tmpdir } = await import("node:os"));
  ({ enrichErrorMessage, removedToolHint, REMOVED_TOOL_NAMES } = await import("./pencil-error-enrichment.mjs"));
  ({ sanitizeFilename } = await import("./sanitize-filename.mjs"));
  ({ classifyResponse, stripAnsi } = await import("./pencil-response-classify.mjs"));
  ({
    runGuardedSave,
    diskTopLevelCount,
    memoryTopLevelCount,
    DISK_UNRECOGNIZED,
    fingerprintState,
    savedReplyPath,
    hash8,
  } = await import("./pencil-save-gate.mjs"));
  ({
    formatReplCommand,
    planSpawn,
    REPL_PROMPT,
    buildBatchDesignCommand,
    buildScreenshotCommand,
    buildExportCommand,
    buildVariablesCommand,
    buildEditorStateCommand,
    buildReadSkillCommand,
    newCountNonce,
    buildCountCommand,
    validateNodeIds,
    validateExportFormat,
    validateScale,
    validateQuality,
    validateOutputDir,
    redactionForms,
    redactText,
    createRollingRedactor,
  } = await import("./pencil-repl-surface.mjs"));
} catch (err) {
  process.stderr.write(
    `[pencil-adapter] ERROR: dependency import failed: ${err?.message ?? err}\n` +
    "[pencil-adapter] The installed adapter at ~/.local/share/pencil-adapter may be\n" +
    "[pencil-adapter] missing node_modules or out of sync with repo. Re-run:\n" +
    "[pencil-adapter]   bash plugins/soleur/skills/pencil-setup/scripts/copy_adapter.sh\n" +
    "[pencil-adapter] or re-run /soleur:pencil-setup to refresh the install.\n"
  );
  process.exit(1);
}

// --- Small helpers ---

// Every stderr line and tool-result fragment built from engine or model text goes through
// these: a node name or a CLI error must not forge a log line (control characters,
// U+0085/U+2028/U+2029) or carry the credential.
function oneLine(value) {
  return String(value ?? "").replace(/[\u0000-\u001f\u007f\u0085\u2028\u2029]+/g, " ").trim();
}

const REDACT_FORMS = redactionForms(API_KEY);

// Raw, trimmed, JSON-escaped, URL-encoded and base64 spellings of the credential.
function redactKey(value) {
  return redactText(String(value ?? ""), REDACT_FORMS);
}

// Untruncated reply text. classifyResponse() caps its text at 64 KiB for the error-pattern
// scan; anything that PARSES a reply (the count line, the screenshot JSON) reads this.
function rawText(raw) {
  return stripAnsi(String(raw ?? "")).trim();
}

const MAX_PEN_BYTES = 64 * 1024 * 1024;

// The bytes of `file`, or null when it does not exist. Opened O_RDONLY|O_NOFOLLOW (a
// symlink swapped in after open_document is an error, not a read through the link) and
// O_NONBLOCK (a FIFO opens instead of hanging), then fstat'd on the descriptor: a
// regular file of at most 64 MiB. Every other error propagates, because "could not read
// it" is not "nothing there to protect".
function readBytesOrNull(file) {
  let fd;
  try {
    fd = openSync(file, fsConstants.O_RDONLY | fsConstants.O_NOFOLLOW | fsConstants.O_NONBLOCK);
  } catch (err) {
    if (err?.code === "ENOENT") return null;
    throw err;
  }
  try {
    const st = fstatSync(fd);
    if (!st.isFile()) throw Object.assign(new Error(`${file} is not a regular file`), { code: "ENOTFILE" });
    if (st.size > MAX_PEN_BYTES) throw Object.assign(new Error(`${file} is larger than 64 MiB`), { code: "E2BIG" });
    const buf = Buffer.allocUnsafe(st.size);
    let off = 0;
    while (off < st.size) {
      const n = readSync(fd, buf, off, st.size - off, off);
      if (n === 0) break;
      off += n;
    }
    return buf.subarray(0, off);
  } finally {
    closeSync(fd);
  }
}

// Separator-bounded containment: `p` equals `base` or sits under it ("/a/bc" is not in "/a/b").
function isInside(base, p) {
  return p === base || p.startsWith(base.endsWith(sep) ? base : base + sep);
}

// realpath of the deepest EXISTING ancestor plus the missing tail.
function nearestRealpath(p) {
  let cur = resolve(p);
  const rest = [];
  for (;;) {
    try {
      return join(realpathSync(cur), ...rest.reverse());
    } catch (err) {
      if (err?.code !== "ENOENT" && err?.code !== "ENOTDIR") throw err;
      const parent = dirname(cur);
      if (parent === cur) throw err;
      rest.push(basename(cur));
      cur = parent;
    }
  }
}

// One canonical spelling of a file path: realpath of its directory plus its basename. The
// baseline, the fresh read, the engine's --out and the `Saved <path>` comparison all use it.
function canonicalFile(p) {
  return join(nearestRealpath(dirname(p)), basename(p));
}

// The engine writes through symlinks (measured on 0.2.9) and the sentinel reads through
// them too, so a link from a project's design.pen to an unrelated file would turn one edit
// into an overwrite of that file. Only plain .pen files; the returned path is canonical.
function penPath(value, label) {
  const abs = resolve(value);
  if (!abs.toLowerCase().endsWith(".pen")) {
    throw new Error(`${label} must be a .pen file (got ${abs})`);
  }
  try {
    if (lstatSync(abs).isSymbolicLink()) {
      throw new Error(`${label} ${abs} is a symlink; refusing (the engine writes through links)`);
    }
  } catch (err) {
    if (err?.code !== "ENOENT") throw err;
  }
  return canonicalFile(abs);
}

// --- Contained output directories (exports and screenshots) ---
//
// Allowed roots: the realpath of process.cwd() and of the open document's directory,
// minus "/" and $HOME themselves. The requested directory must sit inside a root on a
// separator boundary; below the root every existing component is lstat'd and a symlink
// is refused; missing components are created one at a time and re-checked. A symlink
// ABOVE the root (a /tmp-style alias of it) is followed only when it leads into the root.

function allowedRoots() {
  let home = null;
  try {
    home = realpathSync(homedir());
  } catch {
    // no home: nothing extra to exclude
  }
  const roots = [];
  const add = (p) => {
    if (!p) return;
    let real;
    try {
      real = realpathSync(p);
    } catch {
      return;
    }
    if (real === sep || real === home || roots.includes(real)) return;
    roots.push(real);
  };
  add(process.cwd());
  if (pencilProcess.outputFile) add(dirname(pencilProcess.outputFile));
  return roots;
}

function tryContain(abs, root) {
  const outside = (msg) => ({ ok: false, kind: "outside", msg });
  const parts = abs.split(sep).filter(Boolean);
  let cur = sep;
  const missing = [];
  for (let i = 0; i < parts.length; i++) {
    const next = join(cur, parts[i]);
    let st;
    try {
      st = lstatSync(next);
    } catch (err) {
      if (err?.code === "ENOENT") {
        missing.push(...parts.slice(i));
        break;
      }
      return outside(String(err?.code ?? err));
    }
    if (st.isSymbolicLink()) {
      if (isInside(root, next)) return { ok: false, kind: "symlink", msg: `${next} is a symlink` };
      let resolved;
      try {
        resolved = realpathSync(next);
      } catch {
        return outside(`${next} is a dangling link`);
      }
      if (!(isInside(root, resolved) || isInside(resolved, root))) return outside(`${next} leads outside`);
      cur = resolved;
      continue;
    }
    if (!st.isDirectory()) return outside(`${next} is not a directory`);
    cur = next;
  }
  const target = join(cur, ...missing);
  if (!isInside(root, target)) return outside(`${target} is not inside ${root}`);
  let at = cur;
  for (const part of missing) {
    at = join(at, part);
    try {
      mkdirSync(at);
    } catch (err) {
      if (err?.code !== "EEXIST") return outside(String(err?.code ?? err));
    }
    const st = lstatSync(at);
    if (st.isSymbolicLink() || !st.isDirectory()) return { ok: false, kind: "symlink", msg: `${at} is not a plain directory` };
  }
  return { ok: true, dir: target };
}

function containedDir(requested) {
  const abs = resolve(requested);
  const roots = allowedRoots();
  const failures = [];
  for (const root of roots) {
    const r = tryContain(abs, root);
    if (r.ok) return r.dir;
    failures.push(r);
  }
  const link = failures.find((f) => f.kind === "symlink");
  if (link) throw new Error(`outputDir ${abs} refused: ${oneLine(link.msg)} (symlinked components are not followed)`);
  throw new Error(
    `outputDir ${abs} is outside the allowed directories (${roots.length ? roots.join(", ") : "none: the working directory is / or $HOME and no document is open"}); choose a directory inside the project or next to the open .pen file`
  );
}

// --- Screenshot persistence ---

const SHOT_EXT = { "image/png": "png", "image/jpeg": "jpg", "image/webp": "webp" };

function saveScreenshot(base64Data, mimeType, nodeId) {
  const penFile = pencilProcess.outputFile;
  if (!penFile) return null;
  const dir = containedDir(join(dirname(penFile), "screenshots"));
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
  const base = `${sanitizeFilename(String(nodeId)) || "node"}-${timestamp}`;
  const bytes = Buffer.from(base64Data, "base64");
  for (let n = 0; n < 5; n++) {
    const filePath = join(dir, `${base}${n ? `-${n}` : ""}.${SHOT_EXT[mimeType] ?? "png"}`);
    try {
      writeFileSync(filePath, bytes, { flag: "wx" });
      return filePath;
    } catch (err) {
      if (err?.code !== "EEXIST") throw err;
    }
  }
  throw new Error("could not pick an unused screenshot file name");
}

// --- Binary resolution ---
//
// The credential goes to exactly one program, so the program is identified before it is
// spawned. Resolved only inside ~/.local/share/pen-cli (the lockfile-pinned prefix
// check_deps.sh installs): the package's name must be @pen.dev/cli, its declared bin.pen
// target must sit inside the package directory, and the realpath of .bin/pen must EQUAL
// that target. No PATH walk, never the `pencil` name. The caller spawns the returned
// REALPATH with `node`, so a link swapped before a respawn is not followed. A version
// other than the pin only warns.
const PEN_CLI_PIN = "0.3.13";

function findPenBinary() {
  const prefix = join(homedir(), ".local", "share", "pen-cli");
  const fail = (why) =>
    new Error(
      `pen CLI not found or not trusted (${why}); run \`bash plugins/soleur/skills/pencil-setup/scripts/check_deps.sh\` or /soleur:pencil-setup to install @pen.dev/cli@${PEN_CLI_PIN}`
    );
  let pkgDir;
  try {
    pkgDir = realpathSync(join(prefix, "node_modules", "@pen.dev", "cli"));
  } catch {
    throw fail("@pen.dev/cli is not installed under ~/.local/share/pen-cli");
  }
  let pkg;
  try {
    pkg = JSON.parse(readFileSync(join(pkgDir, "package.json"), "utf8"));
  } catch {
    throw fail("its package.json is unreadable");
  }
  if (pkg?.name !== "@pen.dev/cli") throw fail("the package name is not @pen.dev/cli");
  const declaredRel = pkg?.bin && typeof pkg.bin === "object" ? pkg.bin.pen : undefined;
  if (typeof declaredRel !== "string" || declaredRel === "") throw fail("the package declares no pen bin");
  let declared;
  try {
    declared = realpathSync(resolve(pkgDir, declaredRel));
  } catch {
    throw fail("the declared pen bin is missing");
  }
  if (!isInside(pkgDir, declared)) throw fail("the declared pen bin resolves outside the package directory");
  let linked;
  try {
    linked = realpathSync(join(prefix, "node_modules", ".bin", "pen"));
  } catch {
    throw fail(".bin/pen is missing");
  }
  if (linked !== declared) throw fail(".bin/pen does not point at the package's declared pen bin");
  if (pkg.version !== PEN_CLI_PIN) {
    process.stderr.write(
      `[pencil-adapter] WARN: @pen.dev/cli version ${oneLine(pkg.version)} differs from the pin ${PEN_CLI_PIN}; run check_deps.sh to re-install the pinned version\n`
    );
  }
  return declared;
}

// PENCIL_BINARY keeps its name. Only the registrant can set it (stub tests use it), but it
// is still run with the credential, so it must be an absolute path to a regular file owned
// by this user that nobody else can write. Each use writes a value-free stderr line.
function trustedOverride(path) {
  if (!isAbsolute(path)) throw new Error("PENCIL_BINARY must be an absolute path");
  let st;
  try {
    st = lstatSync(path);
  } catch (err) {
    throw new Error(`PENCIL_BINARY cannot be used: ${err?.code ?? "unreadable"}`);
  }
  if (st.isSymbolicLink()) throw new Error("PENCIL_BINARY must not be a symlink");
  if (!st.isFile()) throw new Error("PENCIL_BINARY must be a regular file");
  if (typeof process.getuid === "function" && st.uid !== process.getuid()) {
    throw new Error("PENCIL_BINARY must be owned by the current user");
  }
  if ((st.mode & 0o022) !== 0) throw new Error("PENCIL_BINARY must not be group- or world-writable");
  process.stderr.write("[pencil-adapter] PENCIL_BINARY override in use (the default pen binary was not resolved)\n");
  return realpathSync(path);
}

function resolveBinary() {
  const override = process.env.PENCIL_BINARY;
  return override ? trustedOverride(override) : findPenBinary();
}

// --- Child process environment ---

// The child gets an allowlisted environment plus the credential under ONE name. Empty and
// relative PATH entries are dropped (they would resolve against the project the user
// opened); the adapter's own Node directory goes first so the engine's shebang resolves to
// the Node (22.19+) that runs the adapter.
function buildPencilEnv() {
  const allowed = ["HOME", "NODE_ENV", "LANG", "TERM", "USER", "SHELL", "TMPDIR"];
  const env = {};
  for (const key of allowed) {
    if (process.env[key] !== undefined) {
      env[key] = process.env[key];
    }
  }
  const dirs = [dirname(process.execPath), ...(process.env.PATH ?? "").split(":").filter((p) => p && isAbsolute(p))];
  env.PATH = [...new Set(dirs)].join(":");
  env.PEN_CLI_KEY = API_KEY;
  return env;
}

// The engine opens things relative to its cwd (and its ancestors): hand it a private,
// empty directory instead of the project the user opened. It only ever receives absolute
// paths. Removed at exit.
let CHILD_CWD = null;
function childCwd() {
  if (!CHILD_CWD) CHILD_CWD = mkdtempSync(join(tmpdir(), "pen-adapter-cwd-"));
  return CHILD_CWD;
}

// --- The save baseline (#11168) ---
//
// What this session last loaded or last saved, as a tagged state (see pencil-save-gate.mjs).
// The state lives in a #-private field so the only ways to change it are the four methods
// below, each with ONE call site: capture + commit in spawn(), adopt in guardedSave(),
// clear in clearTarget().
class SaveBaseline {
  #state = { tag: "none" };

  // Read the file into a state. Never throws: a failed read is an `unknown` state with the
  // errno, and says so on stderr.
  capture(file) {
    try {
      return fingerprintState(readBytesOrNull(file));
    } catch (err) {
      const detail = String(err?.code ?? err?.message ?? err);
      process.stderr.write(`[pencil-adapter] baseline capture failed (${oneLine(detail)}); baseline=unknown\n`);
      return { tag: "unknown", cause: "capture-failed", detail };
    }
  }

  commit(state) {
    this.#state = state;
  }

  adopt(state) {
    this.#state = state;
  }

  clear() {
    this.#state = { tag: "none" };
  }

  get() {
    return this.#state;
  }
}

const baseline = new SaveBaseline();

// Set by a stale/missing refusal and cleared ONLY by a successful open_document: until then
// every save is refused, and a crash respawn does not recapture the baseline (a respawn
// must not turn a refusal into a silent re-baseline). `null` until first set.
let refusalPending = null;
let restartedWhileArmed = false;

function armRefusal(file) {
  if (refusalPending === true) return;
  refusalPending = true;
  restartedWhileArmed = false;
  process.stderr.write(`[pencil-adapter] refusalPending=true ${oneLine(redactKey(file))}\n`);
}

function clearRefusal(file) {
  const was = refusalPending === true;
  refusalPending = false;
  restartedWhileArmed = false;
  if (was) process.stderr.write(`[pencil-adapter] refusalPending=false ${oneLine(redactKey(file))} (open_document ok)\n`);
}

// --- PencilProcess class ---

const FS_PROBE = {
  exists: (p) => existsSync(p),
  size: (p) => {
    try {
      return statSync(p).size;
    } catch {
      return 0;
    }
  },
};

// The prompt must be at the END of the buffer and stay there this long before a reply
// counts as complete; stderr must have been quiet this long as well. Bytes that arrive
// after that, with no command in flight, are a desync.
const PROMPT_QUIET_MS = 50;

// Set when open_document could not load the file it was given. Every tool errors until the
// next successful open_document, so nothing runs (or saves) against a document that is not
// the one the caller asked for. Cleared ONLY on success.
let openFailure = null;
const OPEN_FAILED_NEXT =
  "Next step: open_document a different .pen path (the failed file was not modified), or restore it from version control. Do not delete it to bypass this.";

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

class PencilProcess {
  constructor() {
    this.child = null;
    this.ready = false;
    this.buffer = "";
    this.stderrBuffer = "";
    this.lastStderrAt = 0;
    // True when the last reply carried an error on STDERR (the engine's only error channel).
    this.lastStderrError = false;
    // The document the session is bound to. Set when a spawn reaches its prompt, cleared
    // only by clearTarget() (a failed open_document). A FAILED respawn leaves it alone, so
    // the next call retries the same file instead of falling through to a scratch document.
    this.outputFile = null;
    // The file the last successful spawn passed as --in (null = started empty).
    this.lastInFile = null;
    this.scratchFile = null;
    this._waiter = null;
    this._onExit = null;
    this._redactor = null;
  }

  clearTarget() {
    this.outputFile = null;
    this.lastInFile = null;
    baseline.clear();
  }

  // Called only from inside the command queue, so spawns are serialized.
  async ensureAlive() {
    if (openFailure) throw new Error(`open failed: ${openFailure}\n${OPEN_FAILED_NEXT}`);
    if (this.child && this.ready) return;
    if (this.child) await this.kill(); // a half-started (or desynchronised) child is never reused
    if (this.outputFile) {
      // Respawn: no explicit input, so planSpawn reloads the saved file and a template can
      // never overwrite saved edits. Before the first save it falls back to the template
      // the target was opened from.
      let recapture = true;
      if (refusalPending === true) {
        recapture = false;
        restartedWhileArmed = true;
        process.stderr.write("[pencil-adapter] respawn: refusalPending still armed, baseline not recaptured\n");
      } else if (baseline.get().tag === "unknown") {
        recapture = false;
        process.stderr.write("[pencil-adapter] respawn: baseline unknown, not recaptured (open_document to re-baseline)\n");
      }
      await this.spawn(this.outputFile, null, this.lastInFile, { recapture });
      return;
    }
    // No document opened yet: a private scratch document, so tools that need none
    // (get_editor_state, read_skill) work before open_document.
    if (!this.scratchFile) {
      this.scratchFile = join(realpathSync(mkdtempSync(join(tmpdir(), "pencil-adapter-"))), "scratch.pen");
    }
    await this.spawn(this.scratchFile);
  }

  // `explicitInFile` is the caller's template (open_document `inputPath`).
  async spawn(outFile, explicitInFile = null, resumeInFile = null, { recapture = true } = {}) {
    const binary = resolveBinary();
    const { inFile } = planSpawn({
      outFile,
      initialInFile: explicitInFile,
      resumeInFile,
      probe: FS_PROBE,
    });
    const args = ["interactive", "--out", outFile];
    if (inFile) {
      args.push("--in", inFile);
    }

    // What this session starts from, read from --out BEFORE the engine exists. A change
    // between here and the first save (including while the engine loads) is a change the
    // session did not see, so the first save refuses. Committed only once the prompt arrives.
    const captured = recapture ? baseline.capture(outFile) : null;

    this.buffer = "";
    this.stderrBuffer = "";
    this.lastStderrAt = 0;
    this.ready = false;

    // Spawn the engine using the adapter's own Node binary (process.execPath) and the
    // REALPATH resolved above, so the child runs the same Node (22.19+) that runs the
    // adapter and a link swapped since resolution is not followed.
    const child = nodeSpawn(process.execPath, [binary, ...args], {
      stdio: ["pipe", "pipe", "pipe"],
      env: buildPencilEnv(),
      cwd: childCwd(),
    });
    this.child = child;
    const redactor = createRollingRedactor(REDACT_FORMS);
    this._redactor = redactor;

    // Everything below is bound to THIS child: the events of a killed child can arrive
    // after its replacement was spawned and must not touch the new one.
    child.stdout.on("data", (chunk) => this._onStdout(child, chunk.toString()));
    child.stderr.on("data", (chunk) => {
      const text = chunk.toString();
      const safe = redactor.push(text);
      if (safe) process.stderr.write(safe);
      if (this.child === child) {
        this.stderrBuffer += text;
        if (this.stderrBuffer.length > 1 << 20) this.stderrBuffer = this.stderrBuffer.slice(-(1 << 19));
        this.lastStderrAt = Date.now();
      }
    });
    // An EPIPE between the child's death and its close event must not crash the adapter;
    // the close handler reports the death.
    child.stdin.on("error", () => {});

    const gone = (code, signal, err) => {
      const rest = redactor.flush();
      if (rest) process.stderr.write(rest);
      process.stderr.write(
        `[pencil-adapter] pen process exited: code=${code} signal=${signal}${err ? ` error=${oneLine(err.message)}` : ""}\n`
      );
      if (this.child !== child) return;
      this.ready = false;
      this.child = null;
      if (this._onExit) this._onExit(code, signal, err);
    };
    // `close`, not `exit`: it fires after the stdio streams drained, so the stderr tail in
    // the failure message is complete.
    child.on("close", (code, signal) => gone(code, signal));
    child.on("error", (err) => gone(null, null, err));

    try {
      await this.waitForPrompt(30000); // banner + initial prompt
    } catch (err) {
      if (this.child === child) await this.kill(); // never leave a half-started child behind
      throw err;
    }
    if (captured) baseline.commit(captured);
    this.outputFile = outFile;
    this.lastInFile = inFile;
    this.ready = true;
  }

  async kill() {
    const child = this.child;
    this.child = null;
    this.ready = false;
    if (!child || child.exitCode !== null || child.signalCode !== null) return;
    await new Promise((resolveKill) => {
      const escalate = setTimeout(() => child.kill("SIGKILL"), 2000);
      const giveUp = setTimeout(done, 4000);
      function done() {
        clearTimeout(escalate);
        clearTimeout(giveUp);
        resolveKill();
      }
      child.once("close", done);
      child.once("error", done);
      child.kill("SIGTERM");
    });
  }

  async restart(outFile, explicitInFile = null) {
    await this.kill(); // waits for the old child to be gone
    await this.spawn(outFile, explicitInFile);
  }

  // Stdout bytes with no reply being awaited are a desync (a forged or late tail): the
  // child is not trusted to be at its prompt any more, so it is replaced from the saved
  // file on the next call.
  _onStdout(child, text) {
    if (this.child !== child) return;
    if (this._waiter) {
      this._waiter.feed(text);
      return;
    }
    if (this.ready) {
      this.ready = false;
      process.stderr.write(
        "[pencil-adapter] desync: bytes arrived after the prompt with no command in flight; restarting pen from the saved file on the next call\n"
      );
    }
  }

  async sendCommand(cmd) {
    if (!this.child || !this.ready) {
      throw new Error("pen process is not running");
    }
    this.buffer = "";
    this.stderrBuffer = "";
    this.lastStderrAt = 0;
    this.child.stdin.write(cmd + "\n");
    let raw;
    try {
      raw = await this.waitForPrompt(30000);
      // Errors travel on STDERR and may land a moment after the prompt: wait for it to go quiet.
      const t0 = Date.now();
      while (this.lastStderrAt && Date.now() - this.lastStderrAt < PROMPT_QUIET_MS && Date.now() - t0 < 500) {
        await sleep(PROMPT_QUIET_MS - (Date.now() - this.lastStderrAt) + 1);
      }
    } catch (err) {
      // A timed-out reply would otherwise be attributed to the NEXT command.
      if (this.child) {
        await this.kill();
        throw new Error(
          `${err.message}; pen was stopped and restarts from ${this.outputFile ?? "a scratch document"} on the next call (anything not yet saved is lost)`
        );
      }
      throw err;
    }
    const rest = this._redactor?.flush();
    if (rest) process.stderr.write(rest);
    // Every reply leaves here, so one redaction covers every sink that follows.
    const errText = stripAnsi(redactKey(this.stderrBuffer)).trim();
    const out = redactKey(raw);
    // stderr holds the engine's failures (`Error:`, `[ERROR]`, `Save failed:`, `Unknown tool:`).
    // When it carries one it goes first, so the whole text is scanned; stderr that holds only
    // warnings is already in the adapter's own stderr log and stays out of the reply.
    this.lastStderrError = errText !== "" && classifyResponse(errText).isError;
    if (this.lastStderrError) return out ? `${errText}\n${out}` : errText;
    return out;
  }

  waitForPrompt(timeoutMs = 30000) {
    return new Promise((resolvePrompt, reject) => {
      const child = this.child;
      if (!child) {
        reject(new Error("[pencil-adapter] No child process to listen to"));
        return;
      }
      const duringCommand = this.ready;
      let quiet = null;
      const cleanup = () => {
        clearTimeout(timeout);
        if (quiet) clearTimeout(quiet);
        this._waiter = null;
        this._onExit = null;
      };
      const timeout = setTimeout(() => {
        cleanup();
        reject(new Error(`[pencil-adapter] Timed out waiting for prompt after ${timeoutMs}ms`));
      }, timeoutMs);

      // A child that exits before its prompt (bad --in file, auth failure) or mid-command
      // fails the wait immediately with its stderr tail, not after 30 s.
      this._onExit = (code, signal, err) => {
        cleanup();
        const tail = stripAnsi(redactKey(this.stderrBuffer))
          .trim()
          .split("\n")
          .slice(-10)
          .map(oneLine)
          .filter(Boolean)
          .join(" | ");
        reject(
          new Error(
            `[pencil-adapter] pen exited ${duringCommand ? "during a command (its effect is unknown)" : "before it was ready"} (code=${code} signal=${signal}${err ? ` error=${oneLine(err.message)}` : ""})` +
              (tail ? `: ${tail}` : "")
          )
        );
      };

      // The reply is complete only when the prompt is the LAST thing in the buffer and
      // nothing more arrives for PROMPT_QUIET_MS: a node name or a read_skill page that
      // contains the prompt text at a line start does not end the reply early.
      this._waiter = {
        feed: (text) => {
          this.buffer += text;
          if (quiet) {
            clearTimeout(quiet);
            quiet = null;
          }
          const stripped = stripAnsi(this.buffer);
          if (stripped !== REPL_PROMPT && !stripped.endsWith("\n" + REPL_PROMPT)) return;
          quiet = setTimeout(() => {
            cleanup();
            resolvePrompt(stripped.slice(0, stripped.length - REPL_PROMPT.length).trim());
          }, PROMPT_QUIET_MS);
        },
      };
    });
  }
}

// --- Command Queue ---

class CommandQueue {
  constructor(pencilProcess) {
    this.process = pencilProcess;
    this.queue = [];
    this.running = false;
  }

  async enqueue(command) {
    return this.runExclusive((send) => send(command));
  }

  // Run `fn` as ONE queue job: no other queued command, and no restart, can land while it
  // runs. `fn` receives `send(cmd)`, which talks to the process directly (enqueueing from
  // inside a job would wait on itself). The process is (re)started here, inside the
  // serialized section, so two callers can never both spawn. Used for the save sentinel
  // (probe + save), for an edit together with its auto-save, and for open_document's
  // kill-and-respawn.
  async runExclusive(fn, { ensure = true } = {}) {
    return new Promise((resolveJob, reject) => {
      this.queue.push({ job: fn, ensure, resolve: resolveJob, reject });
      if (!this.running) this._drain();
    });
  }

  async _drain() {
    this.running = true;
    while (this.queue.length > 0) {
      const item = this.queue.shift();
      try {
        if (item.ensure) await this.process.ensureAlive();
        item.resolve(await item.job((cmd) => this.process.sendCommand(cmd)));
      } catch (err) {
        item.reject(err);
      }
    }
    this.running = false;
  }
}

const pencilProcess = new PencilProcess();
const commandQueue = new CommandQueue(pencilProcess);

process.on("exit", () => {
  for (const dir of [pencilProcess.scratchFile ? dirname(pencilProcess.scratchFile) : null, CHILD_CWD]) {
    if (!dir) continue;
    try {
      rmSync(dir, { recursive: true, force: true });
    } catch {
      // best effort
    }
  }
});

// --- Guarded save (the ONLY place the REPL `save` command is emitted) ---
//
// Must run inside an exclusive queue job (`send` is that job's channel): read the file on
// disk, probe the in-memory document, decide, re-read the file, decide again, then save,
// with nothing able to interleave. An empty document is never written over a file that
// holds nodes, nothing is written over a file that is not a recognizable .pen (#11143), and
// nothing is written over a file that changed behind the session (#11168); see
// pencil-save-gate.mjs. Callers: an edit's auto-save and the explicit `save` tool.

// A confirmed save is exactly `Saved <this file>`: anything else (empty, another path, a
// failure line) is not a confirmation.
function isSavedFor(raw, file) {
  const path = savedReplyPath(raw);
  if (!path) return false;
  try {
    return canonicalFile(path) === canonicalFile(file);
  } catch {
    return false;
  }
}

async function guardedSave(send, source) {
  const file = pencilProcess.outputFile;
  const saved = await runGuardedSave({
    file,
    source,
    readDisk: async () => readBytesOrNull(file),
    probeMemory: async () => {
      const nonce = newCountNonce();
      const raw = await send(buildCountCommand(nonce));
      const verdict = classifyResponse(raw);
      if (verdict.isError) throw new Error(oneLine(verdict.text).slice(0, 200));
      return { text: rawText(raw), nonce };
    },
    readFresh: async () => readBytesOrNull(file),
    getBaseline: () => baseline.get(),
    isRefusalPending: () => refusalPending === true,
    send: async () => send(formatReplCommand("save", {})),
    isConfirmed: (raw) => isSavedFor(raw, file),
    readAfterSave: async () => readBytesOrNull(file),
    adoptBaseline: (state) => baseline.adopt(state),
    wasRestarted: () => restartedWhileArmed,
  });
  if (saved.refused && saved.arm) armRefusal(file);
  if (saved.unconfirmed) {
    process.stderr.write(
      "[pencil-adapter] save unconfirmed: reply did not match the expected Saved line; baseline=unknown\n"
    );
  }
  if (saved.warning) {
    process.stderr.write(`[pencil-adapter] WARN post-save read failed (${oneLine(saved.detail)}); baseline=unknown\n`);
  }
  return saved;
}

// Every refusal state leaves ONE stderr line, from here, whichever save path hit it
// (hashes only as 8-hex-char prefixes).
function logRefusal(saved, via) {
  const file = pencilProcess.outputFile ?? "";
  const hashes =
    saved.code === "stale" || saved.code === "missing" || saved.code === "refusal-pending"
      ? ` baseline=${hash8(saved.baselineHash)} disk=${hash8(saved.diskHash)}`
      : "";
  const cause = saved.code === "unknown-baseline" ? ` cause=${saved.cause ?? "unknown"}${saved.detail ? ` errno=${saved.detail}` : ""}` : "";
  process.stderr.write(
    oneLine(redactKey(`[pencil-adapter] REFUSED save: [reason=${saved.code}] ${file}${hashes}${cause} via=${via}`)) + "\n"
  );
}

// The refused operations are appended to a refusal so the replay does not depend on the
// agent's context (64 KiB cap, redacted).
const MAX_ECHO_BYTES = 64 * 1024;
function refusalText(saved, operations) {
  if (operations === undefined) return saved.message;
  let ops = redactKey(String(operations));
  if (Buffer.byteLength(ops) > MAX_ECHO_BYTES) ops = `${ops.slice(0, MAX_ECHO_BYTES)}\n[... truncated at 64 KiB]`;
  return `${saved.message}\n\nRefused operations (replay them in order after open_document):\n\`\`\`\n${ops}\n\`\`\``;
}

function errorResult(text) {
  return { content: [{ type: "text", text }], isError: true };
}

// --- MCP Server setup ---

const server = new McpServer({
  name: "pencil-mcp-adapter",
  version: "0.0.1",
});

// Every tool goes through here: an open-failed adapter refuses everything but
// open_document, and any thrown error (a REPL contract violation, a dead process, a
// timeout) becomes an isError result with the replacement hints.
function registerTool(name, schema, handler, { allowWhenOpenFailed = false, description } = {}) {
  const callback = async (params) => {
    if (openFailure && !allowWhenOpenFailed) {
      return errorResult(
        `open failed: ${openFailure}\nNo tool runs until open_document succeeds on a valid .pen file. ${OPEN_FAILED_NEXT}`
      );
    }
    try {
      return await handler(params ?? {});
    } catch (err) {
      return errorResult(enrichErrorMessage(redactKey(String(err?.message ?? err))));
    }
  };
  if (description) server.tool(name, description, schema, callback);
  else server.tool(name, schema, callback);
}

// --- Read-only tool handler factory ---
//
// `build(params)` returns the one REPL line (validated by the surface module). Replies are
// capped (64 KiB) by the classifier and redacted by the process, never parsed. A reply is
// an error when it arrived with an error on stderr or classifies as one.
function registerReadOnlyTool(name, schema, build, options) {
  registerTool(name, schema, async (params) => {
    const cmd = build(params);
    const { raw, stderrError } = await commandQueue.runExclusive(async (send) => {
      const reply = await send(cmd);
      return { raw: reply, stderrError: pencilProcess.lastStderrError };
    });
    const { text, isError: classified } = classifyResponse(raw);
    const isError = name === "read_skill" ? stderrError : classified;
    return {
      content: [{ type: "text", text: isError ? enrichErrorMessage(text) : text }],
      isError,
    };
  }, options);
}

// Tools @pencil.dev/cli 0.2.9 / the Desktop server had and @pen.dev/cli does not. They stay
// registered so a stale session or Desktop-style caller gets a replacement hint instead of
// a bare "tool not found"; nothing reaches the engine and nothing is saved. The schema is
// empty on purpose: any arguments the caller sends must reach the hint, not an SDK
// validation error. REMOVED_TOOL_NAMES is the ONE table (pencil-error-enrichment.mjs).
function registerRemovedTool(name) {
  registerTool(
    name,
    {},
    async () => {
      formatReplCommand(name, {}); // throws `Unknown tool:` for anything outside the REPL surface
      throw new Error(`Unknown tool: ${name}`);
    },
    { description: `Not available in the headless adapter. ${removedToolHint(name)}` }
  );
}

// --- Read-only tools ---

registerReadOnlyTool(
  "get_editor_state",
  {
    include_schema: z.boolean().optional(),
  },
  () => buildEditorStateCommand(),
  {
    description:
      "State of the open document: its top-level nodes and the selection. `include_schema` is accepted and ignored; " +
      'the operation grammar is read_skill({ path: "execute.md" }) and the file schema is read_skill({ path: "pen-schema.md" }).',
  }
);

registerReadOnlyTool("get_variables", {}, () => buildVariablesCommand());

registerReadOnlyTool(
  "read_skill",
  { path: z.string().optional() },
  ({ path }) => buildReadSkillCommand(path),
  {
    description:
      "Read the engine's own design guidance: read_skill() lists the pages; read_skill({ path }) reads one (execute.md is the operation grammar, pen-schema.md the file schema, guide/<name>.md the design guides). Read-only.",
  }
);

// get_screenshot — the reply carries a JSON array [{nodeId,image(base64),mimeType}]; parse it
// from the UNtruncated text (the classifier's 64 KiB cap would break it) and persist a copy
// next to the document.
const MAX_SHOT_REPLY = 8 * 1024 * 1024;
const UNSAVED_WARNING = "WARNING: rendered from unsaved memory, not the file on disk";

function parseScreenshots(text) {
  if (text.length > MAX_SHOT_REPLY) throw new Error("screenshot reply is larger than 8 MiB");
  const m = /\n(\[\s*\{[\s\S]*\])\s*$/.exec(text);
  if (!m) return null;
  let shots;
  try {
    shots = JSON.parse(m[1]);
  } catch {
    throw new Error("the screenshot reply carried malformed JSON");
  }
  if (!Array.isArray(shots)) throw new Error("the screenshot reply carried malformed JSON");
  for (const s of shots) {
    if (
      !s ||
      typeof s.image !== "string" ||
      !/^[A-Za-z0-9+/=]+$/.test(s.image) ||
      !Object.hasOwn(SHOT_EXT, s.mimeType)
    ) {
      throw new Error("the screenshot reply carried a malformed image entry");
    }
  }
  return shots;
}

registerTool("get_screenshot", { nodeId: z.string() }, async ({ nodeId }) => {
  const raw = await commandQueue.enqueue(buildScreenshotCommand(nodeId));
  const { text: capped, isError } = classifyResponse(raw);
  if (isError) {
    return errorResult(enrichErrorMessage(capped));
  }
  const shots = parseScreenshots(rawText(raw));
  const content = [];
  if (refusalPending === true) content.push({ type: "text", text: UNSAVED_WARNING });
  if (!shots || shots.length === 0) {
    content.push({ type: "text", text: capped });
    return { content };
  }
  for (const shot of shots) content.push({ type: "image", data: shot.image, mimeType: shot.mimeType });
  // Persist the first image; a disk failure must not discard the image
  try {
    const savedPath = saveScreenshot(shots[0].image, shots[0].mimeType, nodeId);
    if (savedPath) content.push({ type: "text", text: `Screenshot saved: ${savedPath}` });
  } catch (err) {
    const note = `Screenshot not saved to disk: ${oneLine(redactKey(err?.message ?? err))}`;
    process.stderr.write(`[pencil-adapter] ${note}\n`);
    content.push({ type: "text", text: note });
  }
  return { content };
});

// export_nodes — the output directory is agent-chosen, so it is a write primitive: absolute,
// contained (containedDir), validated before anything is created. The adapter does not
// rename exported files (the agent does, per ux-design-lead.md step 3.4) and returns only
// the engine-printed paths that resolve inside the directory.
registerTool(
  "export_nodes",
  {
    nodeIds: z.array(z.string()),
    outputDir: z.string(),
    format: z.enum(["png", "jpeg", "webp", "pdf"]).optional(),
    scale: z.number().optional(),
    quality: z.number().optional(),
  },
  async ({ nodeIds, outputDir, format, scale, quality }) => {
    const ids = validateNodeIds(nodeIds);
    const fmt = validateExportFormat(format);
    validateScale(scale);
    validateQuality(quality);
    validateOutputDir(outputDir);
    const dir = containedDir(outputDir);
    const overwritten = ids.map((id) => `${id}.${fmt}`).filter((name) => existsSync(join(dir, name)));
    const raw = await commandQueue.enqueue(
      buildExportCommand({ nodeIds: ids, outputDir: dir, format: fmt, scale, quality })
    );
    const { text, isError } = classifyResponse(raw);
    if (isError) {
      return errorResult(enrichErrorMessage(text));
    }
    const exported = rawText(raw)
      .split("\n")
      .map((l) => l.trim())
      .filter((l) => l.startsWith("Exported "))
      .map((l) => l.slice("Exported ".length))
      .filter((p) => {
        if (!isAbsolute(p)) return false;
        try {
          return isInside(dir, existsSync(p) ? realpathSync(p) : resolve(p));
        } catch {
          return false;
        }
      });
    const lines = [];
    if (refusalPending === true) lines.push(UNSAVED_WARNING);
    lines.push(`Exported to: ${dir}`);
    if (overwritten.length > 0) {
      lines.push(`These files already existed there and were overwritten: ${overwritten.join(", ")}`);
    }
    for (const p of exported) lines.push(`Exported ${p}`);
    return { content: [{ type: "text", text: lines.join("\n") }] };
  }
);

for (const name of REMOVED_TOOL_NAMES) registerRemovedTool(name);

// --- Mutating tool (auto-save after) ---

// A successful edit's reply: the engine text (an `## issues detected:` block passes through),
// then the document it hit, then any save warning.
function editResult(saved, text) {
  const lines = [text, `Document: ${pencilProcess.outputFile}`];
  if (saved.warning) lines.push(`WARNING: ${saved.warning}`);
  return { content: [{ type: "text", text: lines.join("\n") }] };
}

registerTool(
  "batch_design",
  { operations: z.string() },
  async ({ operations }) => {
    const cmd = buildBatchDesignCommand(operations);
    // ONE exclusive job: the edit and its save cannot be separated by a crash respawn, a
    // queued open_document or another command, so a success reply means the edit was
    // applied AND persisted (or the reply says otherwise).
    return commandQueue.runExclusive(async (send) => {
      const { text, isError } = classifyResponse(await send(cmd));
      if (isError) {
        // Surface the error AND skip the save: a failed edit must not trigger a write that
        // replaces valid .pen content with empty or stale state.
        process.stderr.write(`[pencil-adapter] SKIPPED save (batch_design errored): ${oneLine(text).slice(0, 200)}\n`);
        return errorResult(enrichErrorMessage(text));
      }
      let saved;
      try {
        saved = await guardedSave(send, "auto-save");
      } catch (err) {
        const reason = oneLine(redactKey(err?.message ?? err));
        process.stderr.write(`[pencil-adapter] save did not complete after batch_design: ${reason}\n`);
        return errorResult(
          `The edit was applied in memory but the save did not complete (${reason}); it is not persisted.`
        );
      }
      if (saved.refused) {
        logRefusal(saved, "auto-save");
        return errorResult(
          `${refusalText(saved, operations)}\n\nEngine response to the edit:\n${text}`
        );
      }
      if (saved.unconfirmed) {
        const after = classifyResponse(saved.raw);
        return errorResult(
          after.isError
            ? `Edit applied but the save failed: ${enrichErrorMessage(after.text)}\nThe save was not confirmed; call open_document on the file before saving again.`
            : "Edit applied but the save was not confirmed (the engine's reply was not `Saved <file>`); call open_document on the file before saving again."
        );
      }
      return editResult(saved, text);
    });
  },
  {
    description:
      "Run a Pencil operation script (Insert, Update, Copy, Replace, Move, Delete, Generate, with short aliases I, U, C, R, M, D, G). " +
      'The field is `operations`. Full grammar: read_skill({ path: "execute.md" }). ' +
      "The document is saved after every successful call (a read through Get/Print saves too); a refused save is reported as an error that lists the refused operations. " +
      "Layout problems arrive as an `## issues detected:` block in the reply. The reply ends with `Document: <path>`.",
  }
);

// --- Meta tools ---

registerTool(
  "open_document",
  {
    filePath: z.string(),
    inputPath: z.string().optional(),
  },
  async ({ filePath, inputPath }) => {
    // Absolute .pen paths, never a symlink: the child process and the save sentinel must
    // agree on which file is meant, and the engine writes through links. A refusal here
    // changes no session state.
    const outFile = penPath(filePath, "filePath");
    const inFile = inputPath ? penPath(inputPath, "inputPath") : null;

    // The kill-and-respawn runs inside the same exclusive section as the saves, so no
    // queued command or save can land between the old document going away and the new one
    // loading. There is no pre-switch save: every successful edit is saved in the same job,
    // so it could only persist state the sentinel would refuse.
    return commandQueue.runExclusive(
      async (send) => {
        if (inFile && inFile !== outFile && diskTopLevelCount(readBytesOrNull(outFile)) !== null) {
          return errorResult(
            `Refusing to open: ${outFile} already holds a document and inputPath ${inFile} would replace it on the first save. ` +
              `Open ${outFile} without inputPath, or open a new .pen path.`
          );
        }
        try {
          // spawn() reads the file's baseline BEFORE the engine starts and commits it at the prompt
          await pencilProcess.restart(outFile, inFile);
          const loadedFrom = pencilProcess.lastInFile;
          const nonce = newCountNonce();
          const memoryCount = memoryTopLevelCount(rawText(await send(buildCountCommand(nonce))), nonce);
          let note = "";
          if (loadedFrom) {
            const diskCount = diskTopLevelCount(readBytesOrNull(loadedFrom));
            if (diskCount === DISK_UNRECOGNIZED) {
              throw new Error(
                `${loadedFrom} exists but is not a recognizable .pen document (the engine loads such a file as empty); it was not modified`
              );
            }
            if (typeof diskCount === "number" && diskCount > 0 && !(memoryCount > 0)) {
              throw new Error(
                `${loadedFrom} holds ${diskCount} top-level node(s) on disk but loaded ${memoryCount === null ? "unreadable" : "empty"}; it was not modified`
              );
            }
            if (diskCount === 0) {
              note = ` (${loadedFrom} is an empty document; if you expected content, check version control)`;
            }
          }
          openFailure = null;
          clearRefusal(outFile);
          return {
            content: [
              {
                type: "text",
                text: `Opened ${outFile} (${memoryCount === null ? "unknown" : memoryCount} top-level node(s) loaded)${note}`,
              },
            ],
          };
        } catch (err) {
          openFailure = oneLine(redactKey(err?.message ?? err));
          pencilProcess.clearTarget();
          await pencilProcess.kill();
          process.stderr.write(`[pencil-adapter] open failed: ${openFailure}\n`);
          return errorResult(
            `open failed: ${openFailure}\nNo other tool runs until open_document succeeds. ${OPEN_FAILED_NEXT}`
          );
        }
      },
      { ensure: false }
    );
  },
  {
    allowWhenOpenFailed: true,
    description:
      "Open (or create) a .pen document. Reports how many top-level nodes loaded. A failure leaves the file untouched and refuses every other tool until open_document succeeds; recover by opening a different path. After a refused (stale) save, open_document on the file reloads what is on disk and re-enables saving.",
  }
);

registerTool("save", {}, async () => {
  // Explicit saves are subject to the same sentinel and stale check as the auto-save,
  // inside one exclusive job.
  const saved = await commandQueue.runExclusive((send) => guardedSave(send, "save"));
  if (saved.refused) {
    logRefusal(saved, "save");
    return errorResult(refusalText(saved));
  }
  const { text, isError } = classifyResponse(saved.raw);
  if (saved.unconfirmed) {
    return errorResult(
      isError
        ? `${enrichErrorMessage(text)}\nThe save was not confirmed; call open_document on the file before saving again.`
        : "The save was not confirmed (the engine's reply was not `Saved <file>`); call open_document on the file before saving again."
    );
  }
  return {
    content: [{ type: "text", text: saved.warning ? `${text}\nWARNING: ${saved.warning}` : text }],
  };
});

// --- Start server ---
// The credential hard-fail and Node-version gate both run at the top of this module, before
// the dynamic imports. See the comment block above the imports for rationale.

const transport = new StdioServerTransport();
await server.connect(transport);
process.stderr.write("[pencil-adapter] MCP server started on stdio\n");
