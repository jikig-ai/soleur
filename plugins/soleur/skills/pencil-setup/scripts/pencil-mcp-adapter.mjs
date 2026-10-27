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
// statement runs. Rule: ex-cq-pencil-mcp-silent-drop-diagnosis-checklist.
//
// Binary trust (the child holds the credential): the pen CLI is resolved only under the
// installing user's own prefix, and an override travels in this process's ARGV
// (`--pencil-binary=<abs>`, set by the user-approved MCP registration), never in an
// environment variable a project settings file could set. See findPenBinary / trustedOverride.

// --- Node version gate (numeric: a string compare orders 22.9.0 after 22.19.0) ---
// NODE_FLOOR is an inline copy of pencil-repl-surface.mjs's (this gate runs before any
// import can); pencil-repl-surface.test.ts pins it, that module and check_deps.sh together.

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
        "[pencil-adapter] Run `/soleur:pencil-setup` (it runs `check_deps.sh --auto`; in a Soleur checkout: `bash plugins/soleur/skills/pencil-setup/scripts/check_deps.sh --auto`) to find or install a supported Node, then re-register.\n"
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
// `--pencil-binary=<absolute path>`: the only way to point the adapter at another engine
// binary (stub tests, the live probe). Validated at spawn time by trustedOverride().
let PENCIL_BINARY_ARG = null;
for (let i = 2; i < process.argv.length; i++) {
  if (process.argv[i].startsWith("--pencil-binary=")) {
    PENCIL_BINARY_ARG = process.argv[i].slice("--pencil-binary=".length) || null;
    continue;
  }
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
if (PENCIL_BINARY_ARG === null && (process.env.PENCIL_BINARY ?? "") !== "") {
  process.stderr.write(
    "[pencil-adapter] WARN: the PENCIL_BINARY environment variable is ignored (a project settings file can set it). " +
      "To run another engine binary, register the adapter with --pencil-binary=<absolute path> in its arguments.\n"
  );
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
let homedir, tmpdir, userInfo;
let enrichErrorMessage, removedToolHint, REMOVED_TOOL_NAMES, RAW_CALL_STEERING, sanitizeFilename, classifyResponse, stripAnsi, createAnsiStripper;
let runGuardedSave, diskTopLevelCount, memoryTopLevelCount, fingerprintState, savedReplyPath, hash8;
let loadFidelityFailure, notPersistedMessage, recreatedNote, isDefiniteSaveFailure, saveFailureLine;
let formatReplCommand, planSpawn, REPL_PROMPT;
let buildBatchDesignCommand, buildScreenshotCommand, buildExportCommand, buildVariablesCommand;
let buildEditorStateCommand, buildReadSkillCommand, newCountNonce, buildCountCommand;
let validateNodeIds, validateExportFormat, validateScale, validateQuality, validateOutputDir, EXPORT_FORMATS;
let redactionForms, redactText, createRollingRedactor, heldPrefixLength;

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
  ({ homedir, tmpdir, userInfo } = await import("node:os"));
  ({ enrichErrorMessage, removedToolHint, REMOVED_TOOL_NAMES, RAW_CALL_STEERING } = await import("./pencil-error-enrichment.mjs"));
  ({ sanitizeFilename } = await import("./sanitize-filename.mjs"));
  ({ classifyResponse, stripAnsi, createAnsiStripper } = await import("./pencil-response-classify.mjs"));
  ({
    runGuardedSave,
    diskTopLevelCount,
    memoryTopLevelCount,
    fingerprintState,
    savedReplyPath,
    hash8,
    loadFidelityFailure,
    notPersistedMessage,
    recreatedNote,
    isDefiniteSaveFailure,
    saveFailureLine,
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
    EXPORT_FORMATS,
    redactionForms,
    redactText,
    createRollingRedactor,
    heldPrefixLength,
  } = await import("./pencil-repl-surface.mjs"));
} catch (err) {
  process.stderr.write(
    `[pencil-adapter] ERROR: dependency import failed: ${err?.message ?? err}\n` +
    "[pencil-adapter] The installed adapter at ~/.local/share/pencil-adapter may be\n" +
    "[pencil-adapter] missing node_modules or out of sync. Run /soleur:pencil-setup to refresh the install\n" +
    "[pencil-adapter] (in a Soleur checkout: bash plugins/soleur/skills/pencil-setup/scripts/copy_adapter.sh).\n"
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

// Every wait and escalation in one place (milliseconds).
const TIMEOUTS = {
  spawnPromptMs: 30000, // banner + first prompt of a new engine
  replyMs: 30000, // one command's reply
  promptQuietMs: 50, // the prompt must end the buffer, and stderr must stay quiet, this long
  stderrSettleMs: 500, // at most this long waiting for late stderr after the prompt
  killTermMs: 2000, // SIGTERM -> SIGKILL
  killGiveUpMs: 4000, // stop waiting for a child that will not die
};

const MAX_PEN_BYTES = 64 * 1024 * 1024; // larger files are refused (read whole for the baseline hash)
const STDERR_BUFFER_CAP = 1 << 20;

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

// The engine is ASSUMED to write through symlinks (never observed either way on
// @pen.dev/cli), and the sentinel's reads would follow them too, so a link from a project's
// design.pen to an unrelated file could turn one edit into an overwrite of that file. Only
// plain .pen files; the returned path is canonical.
function penPath(value, label) {
  const abs = resolve(value);
  if (!abs.toLowerCase().endsWith(".pen")) {
    throw new Error(`${label} must be a .pen file (got ${abs})`);
  }
  try {
    if (lstatSync(abs).isSymbolicLink()) {
      throw new Error(`${label} ${abs} is a symlink; refusing (a link could redirect the write to another file)`);
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
// spawned. Resolved only inside <home>/.local/share/pen-cli (the lockfile-pinned prefix
// check_deps.sh installs): the package's name must be @pen.dev/cli, its declared bin.pen
// target must be a regular file inside the package directory, and the realpath of
// .bin/pen must EQUAL that target. No PATH walk, never the `pencil` name. The caller spawns
// the returned REALPATH with `node`, so a link swapped before a respawn is not followed. A
// version other than the pin only warns.
//
// Where the prefix lives is a trust decision too (a settings env block can redirect $HOME):
// candidates are the passwd home first, then $HOME when it differs (a container whose HOME
// is not the passwd home keeps working). A candidate is used only when its package
// directory is outside the working directory and CLAUDE_PROJECT_DIR (a project cannot
// supply the binary), owned by this user and not group- or world-writable.
const PEN_CLI_PIN = "0.3.13";
// What the customer is told to run. The repo-relative path is a dev note: a customer's
// project has no plugins/ directory, but /soleur:pencil-setup runs the same script.
const CHECK_DEPS_CMD = "bash plugins/soleur/skills/pencil-setup/scripts/check_deps.sh --auto";
const REPAIR_HINT = `run /soleur:pencil-setup (it runs \`check_deps.sh --auto\`; in a Soleur checkout: \`${CHECK_DEPS_CMD}\`)`;

// realpath of the working directory and of CLAUDE_PROJECT_DIR. `exemptHome` (the realpath of
// the PASSWD home, which no environment variable can redirect) drops any root that contains
// it: a root at or above the user's own home would exclude every default install and is the
// user's tree, not a project that could plant a binary. Pass null for the $HOME candidate:
// a project's settings env block can set HOME inside the project, so no root is ever
// skipped for it.
function projectRoots(exemptHome) {
  const roots = [];
  for (const p of [process.cwd(), process.env.CLAUDE_PROJECT_DIR]) {
    if (!p) continue;
    let real;
    try {
      real = realpathSync(p);
    } catch {
      continue;
    }
    if (real === sep || (exemptHome && isInside(real, exemptHome)) || roots.includes(real)) continue;
    roots.push(real);
  }
  return roots;
}

function findPenBinary() {
  const candidates = [];
  try {
    const home = userInfo().homedir;
    if (home) candidates.push({ label: "passwd", home });
  } catch {
    // no passwd entry: $HOME is the only candidate
  }
  const envHome = process.env.HOME;
  if (envHome && !candidates.some((c) => c.home === envHome)) candidates.push({ label: "HOME", home: envHome });

  // One candidate: the verdict is { declared, pkg } or { why, installed } (installed: the
  // package directory exists but is not trusted or not a valid install).
  const inspect = (home, exempt) => {
    const prefix = join(home, ".local", "share", "pen-cli");
    let pkgDir;
    try {
      pkgDir = realpathSync(join(prefix, "node_modules", "@pen.dev", "cli"));
    } catch {
      return { installed: false, why: "@pen.dev/cli is not installed under ~/.local/share/pen-cli" };
    }
    let exemptHome = null;
    if (exempt) {
      try {
        exemptHome = realpathSync(home);
      } catch {
        // keep null: nothing extra to exempt
      }
    }
    if (projectRoots(exemptHome).some((root) => isInside(root, pkgDir))) {
      return { installed: true, why: "the package directory is inside the working directory or the project directory" };
    }
    let st;
    try {
      st = statSync(pkgDir);
    } catch {
      return { installed: true, why: "the package directory cannot be inspected" };
    }
    if (typeof process.getuid === "function" && st.uid !== process.getuid()) {
      return { installed: true, why: "the package directory is not owned by the current user" };
    }
    if ((st.mode & 0o022) !== 0) {
      return {
        installed: true,
        // the LITERAL path: $HOME can come from a project's env block, and this text is read by the agent
        why: "the package directory is group- or world-writable; run `chmod -R go-w ~/.local/share/pen-cli/node_modules` (an npm ci under umask 002 leaves it so)",
      };
    }
    let pkg;
    try {
      pkg = JSON.parse(readFileSync(join(pkgDir, "package.json"), "utf8"));
    } catch {
      return { installed: true, why: "its package.json is unreadable" };
    }
    if (pkg?.name !== "@pen.dev/cli") return { installed: true, why: "the package name is not @pen.dev/cli" };
    const declaredRel = pkg?.bin && typeof pkg.bin === "object" ? pkg.bin.pen : undefined;
    if (typeof declaredRel !== "string" || declaredRel === "") return { installed: true, why: "the package declares no pen bin" };
    let declared;
    try {
      declared = realpathSync(resolve(pkgDir, declaredRel));
    } catch {
      return { installed: true, why: "the declared pen bin is missing" };
    }
    if (!isInside(pkgDir, declared)) return { installed: true, why: "the declared pen bin resolves outside the package directory" };
    try {
      if (!statSync(declared).isFile()) return { installed: true, why: "the declared pen bin is not a regular file" };
    } catch {
      return { installed: true, why: "the declared pen bin cannot be inspected" };
    }
    let linked;
    try {
      linked = realpathSync(join(prefix, "node_modules", ".bin", "pen"));
    } catch {
      return { installed: true, why: ".bin/pen is missing" };
    }
    if (linked !== declared) return { installed: true, why: ".bin/pen does not point at the package's declared pen bin" };
    return { declared, pkg };
  };

  const whys = [];
  for (const candidate of candidates) {
    const verdict = inspect(candidate.home, candidate.label === "passwd");
    if (!verdict.declared) {
      whys.push(verdict);
      continue;
    }
    if (candidate.label === "HOME") {
      process.stderr.write("[pencil-adapter] using the pen CLI under $HOME (it differs from the passwd home directory)\n");
    }
    if (verdict.pkg.version !== PEN_CLI_PIN) {
      process.stderr.write(
        `[pencil-adapter] WARN: @pen.dev/cli version ${oneLine(verdict.pkg.version)} differs from the pin ${PEN_CLI_PIN}; ${REPAIR_HINT} to re-install the pinned version\n`
      );
    }
    return { binary: verdict.declared, home: candidate.home };
  }
  const why = (whys.find((v) => v.installed) ?? whys[0])?.why ?? "no home directory could be determined";
  throw new Error(
    `pen CLI not found or not trusted (${why}); ${REPAIR_HINT} to install @pen.dev/cli@${PEN_CLI_PIN}`
  );
}

// `--pencil-binary=<abs>` (argv, set by the user-approved registration): still run with the
// credential, so it must be an absolute path to a regular file owned by this user that
// nobody else can write and that is not inside the working directory or the project
// directory. Each use writes a value-free stderr line.
function trustedOverride(path) {
  if (!isAbsolute(path)) throw new Error("--pencil-binary must be an absolute path");
  let st;
  try {
    st = lstatSync(path);
  } catch (err) {
    throw new Error(`--pencil-binary cannot be used: ${err?.code ?? "unreadable"}`);
  }
  if (st.isSymbolicLink()) throw new Error("--pencil-binary must not be a symlink");
  if (!st.isFile()) throw new Error("--pencil-binary must be a regular file");
  if (typeof process.getuid === "function" && st.uid !== process.getuid()) {
    throw new Error("--pencil-binary must be owned by the current user");
  }
  if ((st.mode & 0o022) !== 0) throw new Error("--pencil-binary must not be group- or world-writable");
  const real = realpathSync(path);
  let passwdHome = null;
  try {
    passwdHome = realpathSync(userInfo().homedir);
  } catch {
    // keep null
  }
  if (projectRoots(passwdHome).some((root) => isInside(root, real))) {
    throw new Error("--pencil-binary must not be inside the working directory or the project directory");
  }
  process.stderr.write("[pencil-adapter] --pencil-binary override in use (the default pen binary was not resolved)\n");
  return real;
}

// { binary, home }: the binary to run and the home directory the child engine gets as HOME
// (the home findPenBinary resolved it under; an override: see overrideChildHome).
function resolveBinary() {
  if (PENCIL_BINARY_ARG) return { binary: trustedOverride(PENCIL_BINARY_ARG), home: overrideChildHome() };
  return findPenBinary();
}

// The home an override-launched engine gets: the passwd home (no environment variable can
// redirect it), unless $HOME is outside the working directory and CLAUDE_PROJECT_DIR (a
// container whose HOME is not the passwd home). A $HOME inside the project, which a project's
// settings env block can set, is never handed to the engine; with no passwd entry the child
// gets no HOME at all.
function overrideChildHome() {
  let passwd = null;
  try {
    passwd = userInfo().homedir || null;
  } catch {
    // no passwd entry
  }
  const envHome = process.env.HOME;
  if (envHome) {
    try {
      const real = realpathSync(envHome);
      if (!projectRoots(null).some((root) => isInside(root, real))) return envHome;
    } catch {
      // an unresolvable HOME is not trusted
    }
  }
  return passwd;
}

// --- Child process environment ---

// The child gets an allowlisted environment, HOME from the binary resolution, plus the
// credential under ONE name. Empty and
// relative PATH entries are dropped (they would resolve against the project the user
// opened); the adapter's own Node directory goes first so the engine's shebang resolves to
// the Node (22.19+) that runs the adapter.
function buildPencilEnv(home) {
  const allowed = ["NODE_ENV", "LANG", "TERM", "USER", "SHELL", "TMPDIR"];
  const env = {};
  for (const key of allowed) {
    if (process.env[key] !== undefined) {
      env[key] = process.env[key];
    }
  }
  // HOME is the one findPenBinary trusted, not whatever $HOME says now: the engine keeps its
  // login state and caches there.
  if (home) env.HOME = home;
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

  // Read the file into { state, bytes }: bytes is a Buffer, null (the file does not
  // exist) or undefined (unreadable). Never throws: a failed read is an `unknown` state
  // with the errno, and says so on stderr.
  capture(file) {
    try {
      const bytes = readBytesOrNull(file);
      return { state: fingerprintState(bytes), bytes };
    } catch (err) {
      const detail = String(err?.code ?? err?.message ?? err);
      process.stderr.write(
        `[pencil-adapter] baseline capture failed for ${oneLine(redactKey(file))} (${oneLine(redactKey(detail))}); baseline=unknown\n`
      );
      return { state: { tag: "unknown", cause: "capture-failed", detail }, bytes: undefined };
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

// Set by a stale refusal (or a respawn that found the file changed or gone) and cleared
// ONLY by a successful open_document: until then every save is refused, and a crash
// respawn does not recapture the baseline (a respawn must not turn a refusal into a silent
// re-baseline).
let refusalPending = false;
// Why the refusal is armed, beyond "the file is behind the session" (false): "failed-write"
// (a failed save changed the file), "restart" (it was already armed, or edits were unpersisted
// at a respawn), or the cause that armed it at a respawn ("external-change" | "file-missing").
// The FIRST cause is kept: a later restart never overwrites it.
let restartedWhileArmed = false;
// True from the moment an edit's outcome is a refusal or a NOT PERSISTED result until a
// confirmed save or a successful open_document: exports and screenshots made meanwhile are
// rendered from memory, not from the file.
let unpersistedEdits = false;

// `cause` says why it is armed beyond "the file is behind the session" (false): "failed-write"
// (a save failed and the file changed during the write: the memory copy is the only complete
// one) or, from a respawn, "external-change" | "file-missing" | "restart". The FIRST cause is
// kept while armed.
function armRefusal(file, cause = false) {
  // an armed refusal means edits are (or may be) unpersisted, so renders from memory are marked
  unpersistedEdits = true;
  if (refusalPending === true) return;
  refusalPending = true;
  restartedWhileArmed = cause;
  process.stderr.write(`[pencil-adapter] refusalPending=true ${oneLine(redactKey(file))}${cause ? ` cause=${cause}` : ""}\n`);
}

function clearRefusal(file) {
  const was = refusalPending === true;
  refusalPending = false;
  restartedWhileArmed = false;
  unpersistedEdits = false;
  if (was) process.stderr.write(`[pencil-adapter] refusalPending=false ${oneLine(redactKey(file))} (open_document ok)\n`);
}

// --- PencilProcess class ---

const FS_PROBE = {
  exists: (p) => existsSync(p),
  size: (p) => {
    try {
      return statSync(p).size;
    } catch (err) {
      // 0 sends planSpawn to its no-input branch; the errno is the only trace of why
      process.stderr.write(`[pencil-adapter] could not stat ${oneLine(redactKey(p))} (${err?.code ?? "error"}); treating it as empty for --in\n`);
      return 0;
    }
  },
};

// Set when open_document could not load the file it was given. Every tool errors until the
// next successful open_document, so nothing runs (or saves) against a document that is not
// the one the caller asked for. Cleared ONLY on success.
let openFailure = null;
const OPEN_FAILED_NEXT =
  "Next step: open_document a different .pen path (the failed file was not modified), or restore it from version control. Do not delete it to bypass this. The original file is untouched; it can still be edited in Pencil Desktop.";

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
    // diskTopLevelCount of the bytes of --in as read BEFORE the last spawn (null: no --in)
    this.lastLoadDiskCount = null;
    this.scratchFile = null;
    this._waiter = null;
    this._onExit = null;
    this._redactor = null;
  }

  clearTarget() {
    this.outputFile = null;
    this.lastInFile = null;
    this.lastLoadDiskCount = null;
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
        if (restartedWhileArmed === false) restartedWhileArmed = "restart";
        process.stderr.write("[pencil-adapter] respawn: refusalPending still armed, baseline not recaptured\n");
      } else if (baseline.get().tag === "unknown") {
        recapture = false;
        process.stderr.write("[pencil-adapter] respawn: baseline unknown, not recaptured (open_document to re-baseline)\n");
      }
      await this.spawn(this.outputFile, null, this.lastInFile, { recapture, respawn: true });
      return;
    }
    // No document opened yet: a private scratch document, so tools that need none
    // (get_editor_state, read_skill) work before open_document.
    if (!this.scratchFile) {
      this.scratchFile = join(realpathSync(mkdtempSync(join(tmpdir(), "pencil-adapter-"))), "scratch.pen");
    }
    await this.spawn(this.scratchFile);
  }

  // `explicitInFile` is the caller's template (open_document `inputPath`). `respawn` marks
  // the crash/timeout reload of the bound document: it compares what is on disk now with
  // the session's baseline (ruling: arm the refusal when the file changed or vanished) and
  // checks load fidelity here, because no open_document runs after it.
  async spawn(outFile, explicitInFile = null, resumeInFile = null, { recapture = true, respawn = false } = {}) {
    const { binary, home: engineHome } = resolveBinary();
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
    const captured = baseline.capture(outFile);
    // The bytes of the document the engine is about to load, read before it starts: the
    // top-level count the load must reproduce (the file itself when it is --in).
    let loadedDiskCount = null;
    if (inFile) {
      let inBytes = captured.bytes;
      let unreadable = captured.state.tag === "unknown" ? captured.state.detail : null;
      if (inFile !== outFile) {
        try {
          inBytes = readBytesOrNull(inFile);
        } catch (err) {
          inBytes = undefined;
          unreadable = String(err?.code ?? err?.message ?? err);
        }
      }
      if (inBytes === undefined) {
        throw new Error(`${inFile} could not be read before loading it (${oneLine(unreadable ?? "unreadable")}); it was not modified`);
      }
      loadedDiskCount = diskTopLevelCount(inBytes);
    }
    // A respawn onto a changed or vanished file is decided now, applied at the prompt.
    let armCause = null;
    const previous = baseline.get();
    if (respawn && recapture && previous.tag === "hash") {
      if (captured.state.tag === "missing") armCause = "file-missing";
      else if (captured.state.tag === "hash" && captured.state.hash !== previous.hash) armCause = "external-change";
    }
    // Edits that were never persisted (a refused, failed, unconfirmed or incomplete save) died
    // with the old engine: the file looks unchanged, and adopting it would let the next
    // save pass as if nothing was lost. The baseline stays the old one.
    if (respawn && recapture && armCause === null && unpersistedEdits) armCause = "restart";

    this.buffer = "";
    this.stderrBuffer = "";
    this.stderrHeld = "";
    this.lastStderrAt = 0;
    this.ready = false;

    // Spawn the engine using the adapter's own Node binary (process.execPath) and the
    // REALPATH resolved above, so the child runs the same Node (22.19+) that runs the
    // adapter and a link swapped since resolution is not followed.
    const child = nodeSpawn(process.execPath, [binary, ...args], {
      stdio: ["pipe", "pipe", "pipe"],
      env: buildPencilEnv(engineHome),
      cwd: childCwd(),
    });
    this.child = child;
    const redactor = createRollingRedactor(REDACT_FORMS);
    const ansi = createAnsiStripper();
    this._redactor = redactor;

    // Everything below is bound to THIS child: the events of a killed child can arrive
    // after its replacement was spawned and must not touch the new one.
    child.stdout.on("data", (chunk) => this._onStdout(child, chunk.toString()));
    child.stderr.on("data", (chunk) => {
      const text = chunk.toString();
      // Escape sequences go BEFORE the redactor: a credential interleaved with them would
      // otherwise reach the log with the sequences between its characters.
      const safe = redactor.push(ansi.push(text));
      if (safe) process.stderr.write(safe);
      if (this.child === child) {
        // Stripped, THEN redacted, BEFORE it is stored or trimmed: a spelling interleaved with
        // escape sequences, or straddling the trim point (or a chunk boundary: the whole
        // buffer is re-scanned), is already replaced, so the kept tail never starts with half
        // a credential. A spelling still being assembled at the very end stays whole in the
        // buffer until its second half arrives (heldTailOf keeps it out of every result).
        this.stderrBuffer = redactKey(stripAnsi(this.stderrBuffer + text));
        if (this.stderrBuffer.length > STDERR_BUFFER_CAP) {
          // trim at a line start where there is one
          const tail = this.stderrBuffer.slice(-(STDERR_BUFFER_CAP >> 1));
          const nl = tail.indexOf("\n");
          this.stderrBuffer = nl === -1 ? tail : tail.slice(nl + 1);
        }
        this.lastStderrAt = Date.now();
      }
    });
    // An EPIPE between the child's death and its close event must not crash the adapter;
    // the close handler reports the death.
    child.stdin.on("error", () => {});

    const gone = (code, signal, err) => {
      // the rolling redactor is flushed here, when the stream has ended, and nowhere else
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
      await this.waitForPrompt(TIMEOUTS.spawnPromptMs); // banner + initial prompt
    } catch (err) {
      if (this.child === child) await this.kill(); // never leave a half-started child behind
      throw err;
    }
    if (armCause) {
      // the baseline stays the OLD one: the engine loaded content (or nothing) this session never saw
      armRefusal(outFile, armCause);
      const what =
        armCause === "file-missing"
          ? "file is gone behind a restarted session"
          : armCause === "external-change"
            ? "file changed on disk behind a restarted session"
            : "edits were not persisted when the engine restarted";
      process.stderr.write(
        `[pencil-adapter] respawn: ${what} (cause=${armCause}) baseline=${hash8(previous.hash)} disk=${hash8(captured.state.hash)}; refusalPending armed\n`
      );
    } else if (recapture) {
      baseline.commit(captured.state);
    }
    this.outputFile = outFile;
    this.lastInFile = inFile;
    this.lastLoadDiskCount = loadedDiskCount;
    this.ready = true;
    if (respawn) {
      // no open_document runs after a respawn, so the load is verified here
      const nonce = newCountNonce();
      const memoryCount = memoryTopLevelCount(rawText(await this.sendCommand(buildCountCommand(nonce))), nonce);
      const failure = loadFidelityFailure({ file: inFile ?? outFile, diskCount: loadedDiskCount, memoryCount });
      if (failure) {
        openFailure = oneLine(redactKey(failure));
        process.stderr.write(`[pencil-adapter] respawn load check failed: ${openFailure}\n`);
        await this.kill();
        throw new Error(`open failed: ${openFailure}\n${OPEN_FAILED_NEXT}`);
      }
    }
  }

  async kill() {
    const child = this.child;
    this.child = null;
    this.ready = false;
    if (!child || child.exitCode !== null || child.signalCode !== null) return;
    await new Promise((resolveKill) => {
      const escalate = setTimeout(() => child.kill("SIGKILL"), TIMEOUTS.killTermMs);
      const giveUp = setTimeout(done, TIMEOUTS.killGiveUpMs);
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
      raw = await this.waitForPrompt(TIMEOUTS.replyMs);
      // Errors travel on STDERR and may land a moment after the prompt: wait for it to go quiet.
      const t0 = Date.now();
      while (this.lastStderrAt && Date.now() - this.lastStderrAt < TIMEOUTS.promptQuietMs && Date.now() - t0 < TIMEOUTS.stderrSettleMs) {
        await sleep(TIMEOUTS.promptQuietMs - (Date.now() - this.lastStderrAt) + 1);
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
    // (the rolling redactor behind the adapter's own stderr log is NOT flushed here: a
    // spelling split across the end of one reply and the start of the next must still be
    // caught THERE, so it is flushed when the child's streams close. That protection is for
    // the log sink only: a tool result carries one reply's stderr, which is buffered per
    // command.) The buffer is already redacted; redacting the reply text too covers every
    // sink that follows.
    const errText = this.takeReleasableStderr().trim();
    const out = redactKey(raw);
    // stderr holds the engine's failures (`Error:`, `[ERROR]`, `Save failed:`, `Unknown tool:`).
    // When it carries one it goes first, so the whole text is scanned; stderr that holds only
    // warnings is already in the adapter's own stderr log and stays out of the reply.
    this.lastStderrError = errText !== "" && classifyResponse(errText).isError;
    if (this.lastStderrError) return out ? `${errText}\n${out}` : errText;
    return out;
  }

  // This reply's redacted stderr, minus the unfinished credential prefix at its very end
  // (kept in `stderrHeld` and joined to the NEXT reply's stderr: if that completes the
  // credential, the whole spelling is replaced; if not, the held part is dropped, never shown).
  takeReleasableStderr() {
    let text = stripAnsi(this.stderrBuffer);
    if (this.stderrHeld) {
      const joined = this.stderrHeld + text;
      const redacted = redactKey(joined);
      if (redacted !== joined) text = redacted;
    }
    const held = heldPrefixLength(text, REDACT_FORMS);
    this.stderrHeld = held > 0 ? text.slice(text.length - held) : "";
    return held > 0 ? text.slice(0, text.length - held) : text;
  }

  waitForPrompt(timeoutMs = TIMEOUTS.replyMs) {
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
        const tail = this.takeReleasableStderr()
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
      // nothing more arrives for TIMEOUTS.promptQuietMs: a node name or a read_skill page that
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
          }, TIMEOUTS.promptQuietMs);
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

// A recreate (the file was removed behind a live session) is allowed only while the path is
// still the canonical one the session opened: no directory on the way has been swapped for a
// link or moved, so the write cannot land somewhere else.
function canRecreatePath(file) {
  try {
    if (canonicalFile(file) !== file) return false;
    return !lstatSync(dirname(file)).isSymbolicLink();
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
    isDefiniteFailure: (raw) => isDefiniteSaveFailure(raw),
    readAfterSave: async () => readBytesOrNull(file),
    adoptBaseline: (state) => baseline.adopt(state),
    wasRestarted: () => restartedWhileArmed,
    canRecreate: async () => canRecreatePath(file),
  });
  // a refusal that says the session is behind the file, or a failed write that left the
  // file different from the baseline, arms the refusal until open_document succeeds
  if (saved.refused && saved.arm) armRefusal(file);
  else if (saved.failed && saved.arm) armRefusal(file, "failed-write");
  if (saved.refused || saved.failed || saved.unconfirmed) unpersistedEdits = true;
  else if (saved.saved) unpersistedEdits = false;
  if (saved.recreated) {
    process.stderr.write(
      oneLine(redactKey(`[pencil-adapter] [reason=recreated] ${file} baseline=${hash8(saved.baselineHash)}`)) + "\n"
    );
  }
  if (saved.failed) {
    process.stderr.write(
      `[pencil-adapter] save failed (definite): baseline kept${saved.changedDuringFailedWrite ? ", but the file changed during the failed write (refusalPending armed)" : ""}; ${failureDetail(saved.raw)}\n`
    );
  }
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

// The engine's own reason for a failed save, one line, redacted, capped.
function failureDetail(raw) {
  return oneLine(redactKey(saveFailureLine(raw))).slice(0, 300);
}

// Every refusal state leaves ONE stderr line, from here, whichever save path hit it
// (hashes only as 8-hex-char prefixes).
function logRefusal(saved, via) {
  const file = pencilProcess.outputFile ?? "";
  const hashes =
    saved.code === "stale" || saved.code === "refusal-pending"
      ? ` baseline=${hash8(saved.baselineHash)} disk=${hash8(saved.diskHash)}`
      : "";
  const cause =
    saved.code === "unknown-baseline"
      ? ` cause=${saved.cause ?? "unknown"}${saved.detail ? ` errno=${saved.detail}` : ""}`
      : saved.code === "refusal-pending" && restartedWhileArmed
        ? ` cause=${restartedWhileArmed}`
        : "";
  process.stderr.write(
    oneLine(redactKey(`[pencil-adapter] REFUSED save: [reason=${saved.code}] ${file}${hashes}${cause} via=${via}`)) + "\n"
  );
}

// The refused operations are appended to a refusal so the replay does not depend on the
// agent's context (64 KiB cap, redacted). Variables bound by an EARLIER batch_design call
// are not part of the echo and are lost when the document is reopened.
const MAX_ECHO_BYTES = 64 * 1024;
function refusalText(saved, operations) {
  if (operations === undefined) return saved.message;
  let ops = redactKey(String(operations));
  if (Buffer.byteLength(ops) > MAX_ECHO_BYTES) ops = `${ops.slice(0, MAX_ECHO_BYTES)}\n[... truncated at 64 KiB]`;
  return `${saved.message}\n\nRefused operations (replay them in order after open_document; re-bind any variable that an earlier batch_design call defined, those bindings are lost on reopen):\n\`\`\`\n${ops}\n\`\`\``;
}

function errorResult(text) {
  return { content: [{ type: "text", text }], isError: true };
}

// The NOT PERSISTED result for a save outcome that is neither a refusal nor a confirmation
// (`failed` / `unconfirmed`), with the engine's own text in `detail` (redacted, capped).
function notPersistedResult(saved) {
  const file = pencilProcess.outputFile;
  if (saved.failed) {
    return notPersistedMessage({ code: "save-failed", file, detail: failureDetail(saved.raw), changed: saved.changedDuringFailedWrite === true });
  }
  const after = classifyResponse(saved.raw);
  const detail = after.isError ? oneLine(enrichErrorMessage(after.text)).slice(0, 300) : "";
  return notPersistedMessage({ code: "unconfirmed", file, detail });
}

// A save that threw (timeout, dead engine, a desynchronised engine) after the edit was
// applied. Runs inside the exclusive job. The text says the engine was stopped, so it is: a
// child that is still alive (a desync, an unexpected throw) is killed here, and the next
// call respawns from the file with the refusal armed.
async function saveIncompleteResult(err) {
  unpersistedEdits = true;
  const reason = oneLine(redactKey(err?.message ?? err)).slice(0, 300);
  await pencilProcess.kill();
  process.stderr.write(`[pencil-adapter] save did not complete: ${reason}\n`);
  return errorResult(notPersistedMessage({ code: "save-incomplete", file: pencilProcess.outputFile, detail: reason }));
}

// --- MCP Server setup ---

// A failure while the server is being built or started (a tool that cannot be registered, a
// transport that cannot connect) leaves one adapter-authored, redacted, bounded line in the
// MCP log and exits 1; without it Claude Code only reports `failed to connect`.
function startFailed(err) {
  process.stderr.write(`[pencil-adapter] ERROR: server start failed: ${oneLine(redactKey(err?.message ?? err)).slice(0, 300)}\n`);
  process.exit(1);
}

let server;
try {
  server = new McpServer({
    name: "pencil-mcp-adapter",
    version: "0.0.1",
  });
} catch (err) {
  startFailed(err);
}

// Every tool goes through here: an open-failed adapter refuses everything but
// open_document, and any thrown error (a REPL contract violation, a bad path, a dead
// process, a timeout) becomes an isError result with the replacement hints AND one stderr
// line `tool=<name> error: ...` (redacted, one line, at most 300 characters), so the
// adapter's own log shows what the caller was told.
function registerTool(name, schema, handler, { allowWhenOpenFailed = false, description } = {}) {
  const callback = async (params) => {
    if (openFailure && !allowWhenOpenFailed) {
      process.stderr.write(`[pencil-adapter] tool=${name} refused: open failed\n`);
      return errorResult(
        `open failed: ${openFailure}\nNo tool runs until open_document succeeds on a valid .pen file. ${OPEN_FAILED_NEXT}`
      );
    }
    try {
      return await handler(params ?? {});
    } catch (err) {
      const message = redactKey(String(err?.message ?? err));
      process.stderr.write(`[pencil-adapter] tool=${name} error: ${oneLine(message).slice(0, 300)}\n`);
      return errorResult(enrichErrorMessage(message));
    }
  };
  try {
    if (description) server.tool(name, description, schema, callback);
    else server.tool(name, schema, callback);
  } catch (err) {
    startFailed(err);
  }
}

// --- Read-only tool handler factory ---
//
// `build(params)` returns the one REPL line (validated by the surface module). Replies are
// capped (64 KiB) by the classifier and redacted by the process, never parsed. A reply is
// an error when it classifies as one; with `errorFrom: "stderr"` only an error on the
// engine's stderr counts (read_skill returns markdown that can contain error-looking lines).
function registerReadOnlyTool(name, schema, build, { errorFrom, ...options } = {}) {
  registerTool(name, schema, async (params) => {
    const cmd = build(params);
    const { raw, stderrError } = await commandQueue.runExclusive(async (send) => {
      const reply = await send(cmd);
      return { raw: reply, stderrError: pencilProcess.lastStderrError };
    });
    const { text, isError: classified } = classifyResponse(raw);
    const isError = errorFrom === "stderr" ? stderrError : classified;
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
    errorFrom: "stderr",
    description:
      "Read the engine's own design guidance: read_skill() lists the pages; read_skill({ path }) reads one (execute.md is the operation grammar, pen-schema.md the file schema, guide/<name>.md the design guides). Read-only. " +
      "Archetype names are listed in the engine index but this adapter does not expose get_style; use brand tokens or a guide/*.md page.",
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
  if (unpersistedEdits) content.push({ type: "text", text: UNSAVED_WARNING });
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
    format: z.enum(EXPORT_FORMATS).optional(),
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
    // png/jpeg/webp write `<nodeId>.<format>`; a pdf export combines the nodes into one export.pdf
    const expected = fmt === "pdf" ? ["export.pdf"] : ids.map((id) => `${id}.${fmt}`);
    const overwritten = expected.filter((name) => existsSync(join(dir, name)));
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
    if (unpersistedEdits) lines.push(UNSAVED_WARNING);
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
// then the document it hit, then any save warning. A save that recreated a file removed
// behind the session is announced FIRST.
function editResult(saved, text) {
  const lines = [];
  if (saved.recreated) lines.push(recreatedNote(pencilProcess.outputFile));
  lines.push(text, `Document: ${pencilProcess.outputFile}`);
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
    // applied AND persisted (or the reply says otherwise, in a result whose first line is
    // `REFUSED save: [reason=...]` or `NOT PERSISTED: [reason=...]`).
    return commandQueue.runExclusive(async (send) => {
      const { text, isError } = classifyResponse(await send(cmd));
      if (isError) {
        // Surface the error AND skip the save: a failed edit must not trigger a write that
        // replaces valid .pen content with empty or stale state. unpersistedEdits stays as it
        // was. MEASURED: an operation that fails (a bad Insert/Update/Delete argument) makes
        // the engine roll the whole block back ("All operations in this block have been rolled
        // back"), so the in-memory document is unchanged. NOT measured: a raw Export or
        // TakeScreenshot that errors mid-block, after earlier operations of the same block
        // ran. Whether those are rolled back is unknown, and an errored block is not marked
        // unpersisted for it: an accepted residual (the steering sentence tells the agent not
        // to call them inside batch_design).
        process.stderr.write(`[pencil-adapter] SKIPPED save (batch_design errored): ${oneLine(text).slice(0, 200)}\n`);
        return errorResult(enrichErrorMessage(text));
      }
      let saved;
      try {
        saved = await guardedSave(send, "auto-save");
      } catch (err) {
        return await saveIncompleteResult(err);
      }
      if (saved.refused) {
        logRefusal(saved, "auto-save");
        return errorResult(
          `${refusalText(saved, operations)}\n\nEngine response to the edit:\n${text}`
        );
      }
      if (saved.failed || saved.unconfirmed) {
        return errorResult(`${notPersistedResult(saved)}\n\nEngine response to the edit:\n${text}`);
      }
      return editResult(saved, text);
    });
  },
  {
    description:
      "Run a Pencil operation script (Insert, Update, Copy, Replace, Move, Delete, Generate, with short aliases I, U, C, R, M, D, G). " +
      'The field is `operations`. Full grammar: read_skill({ path: "execute.md" }). ' +
      "The document is saved after every successful call (a read through Get/Print saves too); a save that did not persist is reported as an error whose first line is `REFUSED save: [reason=...]` (refused, with the refused operations echoed) or `NOT PERSISTED: [reason=...]`. " +
      "Layout problems arrive as an `## issues detected:` block in the reply. The reply ends with `Document: <path>`. " +
      RAW_CALL_STEERING,
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
        // Opening ANOTHER path while edits are unpersisted discards them with the old engine:
        // the result says so (re-opening the same path is the documented recovery).
        const discardsEdits = unpersistedEdits && pencilProcess.outputFile !== null && pencilProcess.outputFile !== outFile;
        try {
          // spawn() reads the file's baseline (and the count the load must reproduce)
          // BEFORE the engine starts and commits the baseline at the prompt
          await pencilProcess.restart(outFile, inFile);
          const loadedFrom = pencilProcess.lastInFile;
          const nonce = newCountNonce();
          const memoryCount = memoryTopLevelCount(rawText(await send(buildCountCommand(nonce))), nonce);
          let note = "";
          if (loadedFrom) {
            const diskCount = pencilProcess.lastLoadDiskCount;
            const failure = loadFidelityFailure({ file: loadedFrom, diskCount, memoryCount });
            if (failure) throw new Error(failure);
            if (diskCount === 0) {
              note = ` (${loadedFrom} is an empty document; if you expected content, check version control)`;
            }
          }
          const captured = baseline.get();
          if (captured.tag === "unknown") {
            note += `\nWARNING: could not record a baseline for ${outFile} (${oneLine(redactKey(captured.detail ?? captured.cause))}); every save is refused until the file is a readable regular file and open_document succeeds on it.`;
          }
          if (discardsEdits) note += "\nNOTE: unsaved edits to the previous document were discarded.";
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
  const saved = await commandQueue.runExclusive(async (send) => {
    try {
      return await guardedSave(send, "save");
    } catch (err) {
      return { incompleteResult: await saveIncompleteResult(err) };
    }
  });
  if (saved.incompleteResult) return saved.incompleteResult;
  if (saved.refused) {
    logRefusal(saved, "save");
    return errorResult(refusalText(saved));
  }
  if (saved.failed || saved.unconfirmed) return errorResult(notPersistedResult(saved));
  const { text } = classifyResponse(saved.raw);
  const lines = [];
  if (saved.recreated) lines.push(recreatedNote(pencilProcess.outputFile));
  lines.push(text);
  if (saved.warning) lines.push(`WARNING: ${saved.warning}`);
  return { content: [{ type: "text", text: lines.join("\n") }] };
});

// --- Start server ---
// The credential hard-fail and Node-version gate both run at the top of this module, before
// the dynamic imports. See the comment block above the imports for rationale.

try {
  await server.connect(new StdioServerTransport());
} catch (err) {
  startFailed(err);
}
process.stderr.write("[pencil-adapter] MCP server started on stdio\n");
