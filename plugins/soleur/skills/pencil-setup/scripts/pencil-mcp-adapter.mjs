#!/usr/bin/env node

// pencil-mcp-adapter.mjs — MCP server bridging Claude Code to pencil interactive REPL
// Architecture: Claude Code ←(MCP stdio)→ this adapter ←(stdin/stdout REPL)→ pencil interactive
//
// The Node-version gate, argv defense, and PENCIL_CLI_KEY hard-fail run BEFORE
// any module imports so a broken registration exits with a clear adapter-authored
// error instead of ERR_MODULE_NOT_FOUND from the MCP SDK. All imports are dynamic
// (`await import`) for the same reason — static imports resolve during module
// parsing, before any top-level statement runs. Rule:
// cq-pencil-mcp-silent-drop-diagnosis-checklist.

// --- Node version gate ---

const [major, minor] = process.version.slice(1).split(".").map(Number);
if (major < 22 || (major === 22 && minor < 9)) {
  process.stderr.write(
    `[pencil-adapter] Node >= 22.9.0 required, got ${process.version}\n`
  );
  process.exit(1);
}

// --- Defense-in-depth: parse -e KEY=VALUE from argv ---
// If `claude mcp add` passes -e flags as args instead of env vars
// (e.g., -e placed after -- separator), inject them into process.env.

for (let i = 2; i < process.argv.length; i++) {
  if (process.argv[i] === "-e" && i + 1 < process.argv.length) {
    const eqIdx = process.argv[i + 1].indexOf("=");
    if (eqIdx > 0) {
      const key = process.argv[i + 1].slice(0, eqIdx);
      const val = process.argv[i + 1].slice(eqIdx + 1);
      if (!process.env[key]) {
        process.env[key] = val;
      }
    }
    i++; // skip the value arg
  }
}

// --- PENCIL_CLI_KEY hard-fail ---
// Runs BEFORE MCP SDK import so the exit message is adapter-authored, not a
// raw ERR_MODULE_NOT_FOUND. Previously this was a stderr WARNING that let the
// adapter boot and every REPL mutation return an auth error the auto-save ran
// over — producing 0-byte .pen files the caller mistook for successful stubs
// (#2630).

if (!process.env.PENCIL_CLI_KEY) {
  process.stderr.write(
    "[pencil-adapter] ERROR: PENCIL_CLI_KEY not set. Refusing to start.\n" +
    "[pencil-adapter] If you used `claude mcp add`, ensure -e appears BEFORE --\n" +
    "[pencil-adapter] Run `/soleur:pencil-setup` to re-register with a valid key.\n"
  );
  process.exit(1);
}

// --- Dynamic imports (deferred so the gates above run first) ---
//
// Wrapped in try/catch so a missing `node_modules/@modelcontextprotocol/sdk`
// (e.g., after a drifted install that copied the adapter but not its deps)
// surfaces as an adapter-authored error rather than an unhandledRejection
// trace. Matches the hard-fail UX of the PENCIL_CLI_KEY gate above.

let McpServer, StdioServerTransport, z, nodeSpawn;
let existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync, statSync, writeFileSync;
let dirname, isAbsolute, join, resolve, homedir, tmpdir;
let enrichErrorMessage, sanitizeFilename, classifyResponse, stripAnsi;
let runGuardedSave, diskTopLevelCount, memoryTopLevelCount, DISK_UNRECOGNIZED;
let formatReplCommand, planSpawn;

try {
  ({ McpServer } = await import("@modelcontextprotocol/sdk/server/mcp.js"));
  ({ StdioServerTransport } = await import("@modelcontextprotocol/sdk/server/stdio.js"));
  ({ z } = await import("zod"));
  ({ spawn: nodeSpawn } = await import("node:child_process"));
  ({
    existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync, statSync, writeFileSync,
  } = await import("node:fs"));
  ({ dirname, isAbsolute, join, resolve } = await import("node:path"));
  ({ homedir, tmpdir } = await import("node:os"));
  ({ enrichErrorMessage } = await import("./pencil-error-enrichment.mjs"));
  ({ sanitizeFilename } = await import("./sanitize-filename.mjs"));
  ({ classifyResponse, stripAnsi } = await import("./pencil-response-classify.mjs"));
  ({
    runGuardedSave,
    diskTopLevelCount,
    memoryTopLevelCount,
    DISK_UNRECOGNIZED,
  } = await import("./pencil-save-gate.mjs"));
  ({ formatReplCommand, planSpawn } = await import("./pencil-repl-surface.mjs"));
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

// --- Env allowlist ---

function buildPencilEnv() {
  const allowed = [
    "HOME",
    "PATH",
    "NODE_ENV",
    "LANG",
    "TERM",
    "USER",
    "SHELL",
    "TMPDIR",
    "PENCIL_CLI_KEY",
  ];
  const env = {};
  for (const key of allowed) {
    if (process.env[key] !== undefined) {
      env[key] = process.env[key];
    }
  }
  // Prepend the adapter's own Node directory to PATH so that pencil's
  // `#!/usr/bin/env node` shebang resolves to the same Node version (22+)
  // that runs the adapter, not an incompatible system Node.
  const nodeDir = dirname(process.execPath);
  if (env.PATH) {
    env.PATH = `${nodeDir}:${env.PATH}`;
  } else {
    env.PATH = nodeDir;
  }
  return env;
}

// `stripAnsi` and `classifyResponse` are imported from
// `pencil-response-classify.mjs` (see the dynamic-import block above).
// The classifier lives in a sibling pure module so it can be unit-tested
// without loading the MCP SDK. Auth-failure patterns (`pencil login`,
// `Invalid API key`, `Unauthorized`, `HTTP 401`) classify as errors so
// the edit tools skip the auto-save when the engine reports an error
// rather than overwrite .pen files with 0-byte output (#2630).

// --- Small helpers ---

// Every stderr line and tool-result fragment built from engine or model text
// goes through these: a node name or a CLI error must not forge a log line
// (control characters, U+0085/U+2028/U+2029) or carry the credential.
function oneLine(value) {
  return String(value ?? "").replace(/[\u0000-\u001f\u007f\u0085\u2028\u2029]+/g, " ").trim();
}

function redactKey(value) {
  const key = process.env.PENCIL_CLI_KEY;
  return key && key.length >= 8 ? String(value).split(key).join("<redacted>") : String(value);
}

// Untruncated reply text. classifyResponse() caps its text at 64 KiB for the
// error-pattern scan; a capped batch_get() is not valid JSON, so anything that
// PARSES a reply (the node counts behind the save sentinel) must read this.
function rawText(raw) {
  return stripAnsi(String(raw ?? "")).trim();
}

// null when the file does not exist; any other read error propagates, because
// "could not read it" is not "nothing there to protect".
function readTextOrNull(file) {
  try {
    return readFileSync(file, "utf8");
  } catch (err) {
    if (err?.code === "ENOENT") return null;
    throw err;
  }
}

// The engine writes through symlinks (measured on 0.2.9) and the sentinel reads
// through them too, so a link from a project's design.pen to an unrelated file
// would turn one edit into an overwrite of that file. Only plain .pen files.
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
  return abs;
}

// --- Screenshot persistence ---

function saveScreenshot(base64Data, nodeId) {
  const penFile = pencilProcess.outputFile;
  if (!penFile) return null;
  const screenshotDir = join(dirname(penFile), "screenshots");
  mkdirSync(screenshotDir, { recursive: true });
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
  const safeId = String(nodeId).replace(/[^A-Za-z0-9_-]/g, "_");
  const filePath = join(screenshotDir, `${safeId}-${timestamp}.png`);
  writeFileSync(filePath, Buffer.from(base64Data, "base64"));
  return filePath;
}

// --- Binary resolution ---

// Returns an ABSOLUTE path or throws. The binary is run as `node <path>`, and
// `node pencil` resolves ./pencil.js against the working directory, which is the
// project the user opened: a bare name there would execute repo-supplied code
// with PENCIL_CLI_KEY in its environment.
function findPencilBinary() {
  const localPath = join(homedir(), ".local", "node_modules", ".bin", "pencil");
  if (existsSync(localPath)) return localPath;
  for (const dir of (process.env.PATH ?? "").split(":")) {
    if (!dir || !isAbsolute(dir)) continue;
    const candidate = join(dir, "pencil");
    if (existsSync(candidate)) return candidate;
  }
  throw new Error(
    "pencil CLI not found (looked in ~/.local/node_modules/.bin and PATH); run /soleur:pencil-setup"
  );
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

// Set when open_document could not load the file it was given. Every tool errors
// until the next successful open_document, so nothing runs (or saves) against a
// document that is not the one the caller asked for. Cleared ONLY on success.
let openFailure = null;
const OPEN_FAILED_NEXT =
  "Next step: open_document a different .pen path (the failed file was not modified), or restore it from version control. Do not delete it to bypass this.";

class PencilProcess {
  constructor() {
    this.child = null;
    this.ready = false;
    this.buffer = "";
    this.stderrBuffer = "";
    // The document the session is bound to. Set when a spawn reaches its prompt,
    // cleared only by clearTarget() (a failed open_document). A FAILED respawn
    // leaves it alone, so the next call retries the same file instead of
    // falling through to a scratch document.
    this.outputFile = null;
    // The file the last successful spawn passed as --in (null = started empty).
    this.lastInFile = null;
    this.scratchFile = null;
    this._dataHandler = null;
    this._onExit = null;
  }

  clearTarget() {
    this.outputFile = null;
    this.lastInFile = null;
  }

  // Called only from inside the command queue, so spawns are serialized.
  async ensureAlive() {
    if (openFailure) throw new Error(`open failed: ${openFailure}\n${OPEN_FAILED_NEXT}`);
    if (this.child && this.ready) return;
    if (this.child) await this.kill(); // a half-started child is never reused
    if (this.outputFile) {
      // Respawn: no explicit input, so planSpawn reloads the saved file and a
      // template can never overwrite saved edits. Before the first save it
      // falls back to the template the target was opened from.
      await this.spawn(this.outputFile, null, this.lastInFile);
      return;
    }
    // No document opened yet: a private scratch document, so tools that need
    // none (get_editor_state, get_guidelines) work before open_document.
    if (!this.scratchFile) {
      this.scratchFile = join(mkdtempSync(join(tmpdir(), "pencil-adapter-")), "scratch.pen");
    }
    await this.spawn(this.scratchFile);
  }

  // `explicitInFile` is the caller's template (open_document `inputPath`).
  async spawn(outFile, explicitInFile = null, resumeInFile = null) {
    const binary = process.env.PENCIL_BINARY || findPencilBinary();
    if (process.env.PENCIL_BINARY && !isAbsolute(process.env.PENCIL_BINARY)) {
      throw new Error("PENCIL_BINARY must be an absolute path");
    }
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

    this.buffer = "";
    this.stderrBuffer = "";
    this.ready = false;

    // Spawn pencil using the adapter's own Node binary (process.execPath)
    // instead of relying on the pencil script's #!/usr/bin/env node shebang,
    // which resolves to the system Node (potentially <22) and fails with
    // ERR_REQUIRE_ESM. This guarantees the child process uses the same
    // Node version (22+) that runs the adapter.
    const child = nodeSpawn(process.execPath, [binary, ...args], {
      stdio: ["pipe", "pipe", "pipe"],
      env: buildPencilEnv(),
    });
    this.child = child;

    // Everything below is bound to THIS child: the events of a killed child can
    // arrive after its replacement was spawned and must not touch the new one.
    child.stderr.on("data", (chunk) => {
      process.stderr.write(redactKey(chunk.toString()));
      if (this.child === child) this.stderrBuffer += chunk.toString();
    });
    // An EPIPE between the child's death and its close event must not crash the
    // adapter; the close handler reports the death.
    child.stdin.on("error", () => {});

    const gone = (code, signal, err) => {
      process.stderr.write(
        `[pencil-adapter] pencil process exited: code=${code} signal=${signal}${err ? ` error=${oneLine(err.message)}` : ""}\n`
      );
      if (this.child !== child) return;
      this.ready = false;
      this.child = null;
      if (this._onExit) this._onExit(code, signal, err);
    };
    // `close`, not `exit`: it fires after the stdio streams drained, so the
    // stderr tail in the failure message is complete.
    child.on("close", (code, signal) => gone(code, signal));
    child.on("error", (err) => gone(null, null, err));

    try {
      await this.waitForPrompt(30000); // banner + initial prompt
    } catch (err) {
      if (this.child === child) await this.kill(); // never leave a half-started child behind
      throw err;
    }
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

  async sendCommand(cmd) {
    if (!this.child || !this.ready) {
      throw new Error("Pencil process is not running");
    }
    this.buffer = "";
    this.stderrBuffer = "";
    this.child.stdin.write(cmd + "\n");
    let raw;
    try {
      raw = await this.waitForPrompt(30000);
    } catch (err) {
      // A timed-out reply would otherwise be attributed to the NEXT command.
      if (this.child) {
        await this.kill();
        throw new Error(
          `${err.message}; pencil was stopped and restarts from ${this.outputFile ?? "a scratch document"} on the next call (anything not yet saved is lost)`
        );
      }
      throw err;
    }
    // If stdout response is empty but stderr has content, use stderr
    // Every reply leaves here, so one redaction covers every sink that follows.
    if (!raw && this.stderrBuffer) {
      return redactKey(this.stderrBuffer);
    }
    return redactKey(raw);
  }

  waitForPrompt(timeoutMs = 30000) {
    return new Promise((resolvePrompt, reject) => {
      const child = this.child;
      if (!child) {
        reject(new Error("[pencil-adapter] No child process to listen to"));
        return;
      }
      const duringCommand = this.ready;
      const cleanup = () => {
        clearTimeout(timeout);
        child.stdout.removeListener("data", this._dataHandler);
        this._dataHandler = null;
        this._onExit = null;
      };
      const timeout = setTimeout(() => {
        cleanup();
        reject(
          new Error(
            `[pencil-adapter] Timed out waiting for prompt after ${timeoutMs}ms`
          )
        );
      }, timeoutMs);

      // A child that exits before its prompt (bad --in file, auth failure) or
      // mid-command fails the wait immediately with its stderr tail, not after 30 s.
      this._onExit = (code, signal, err) => {
        cleanup();
        const tail = redactKey(this.stderrBuffer)
          .trim()
          .split("\n")
          .slice(-10)
          .map(oneLine)
          .filter(Boolean)
          .join(" | ");
        reject(
          new Error(
            `[pencil-adapter] pencil exited ${duringCommand ? "during a command (its effect is unknown)" : "before it was ready"} (code=${code} signal=${signal}${err ? ` error=${oneLine(err.message)}` : ""})` +
              (tail ? `: ${tail}` : "")
          )
        );
      };

      this._dataHandler = (chunk) => {
        this.buffer += chunk.toString();
        const stripped = stripAnsi(this.buffer);
        // Detect prompt: "pencil > " at start or after newline
        const promptIdx = stripped.indexOf("\npencil > ");
        const startsWithPrompt = stripped.startsWith("pencil > ");

        if (promptIdx !== -1 || startsWithPrompt) {
          cleanup();
          let response;
          if (promptIdx !== -1) {
            response = stripped.substring(0, promptIdx);
          } else {
            // Buffer starts with prompt — empty response (initial prompt)
            response = "";
          }
          resolvePrompt(response.trim());
        }
      };

      child.stdout.on("data", this._dataHandler);
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

  // Run `fn` as ONE queue job: no other queued command, and no restart, can
  // land while it runs. `fn` receives `send(cmd)`, which talks to the process
  // directly (enqueueing from inside a job would wait on itself). The process is
  // (re)started here, inside the serialized section, so two callers can never
  // both spawn. Used for the save sentinel (probe + save), for an edit together
  // with its auto-save, and for open_document's kill-and-respawn.
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
  if (pencilProcess.scratchFile) {
    try {
      rmSync(dirname(pencilProcess.scratchFile), { recursive: true, force: true });
    } catch {
      // best effort
    }
  }
});

// --- Guarded save (the ONLY place the REPL `save` command is emitted) ---
//
// Must run inside an exclusive queue job (`send` is that job's channel): read the
// file on disk, probe the in-memory document, decide, then save, with nothing able
// to interleave. An empty document is never written over a file that holds nodes,
// and nothing is written over a file that is not a recognizable .pen (#11143; see
// pencil-save-gate.mjs). Callers: an edit's auto-save and the explicit `save` tool.

async function guardedSave(send, source) {
  const file = pencilProcess.outputFile;
  return runGuardedSave({
    file,
    source,
    readDisk: async () => readTextOrNull(file),
    probeMemory: async () => {
      const raw = await send(formatReplCommand("batch_get", {}));
      const verdict = classifyResponse(raw);
      if (verdict.isError) throw new Error(oneLine(verdict.text).slice(0, 200));
      return rawText(raw);
    },
    send: async () => send(formatReplCommand("save", {})),
  });
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
// open_document, and any thrown error (a REPL contract violation, a dead
// process, a timeout) becomes an isError result with the replacement hints.
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

function registerReadOnlyTool(name, schema, options) {
  registerTool(name, schema, async (params) => {
    const cmd = formatReplCommand(name, params);
    const raw = await commandQueue.enqueue(cmd);
    const { text, isError } = classifyResponse(raw);
    return {
      content: [{ type: "text", text: isError ? enrichErrorMessage(text) : text }],
      isError,
    };
  }, options);
}

// --- Mutating tool handler factory ---

function registerMutatingTool(name, schema, options) {
  registerTool(name, schema, async (params) => {
    const cmd = formatReplCommand(name, params);
    // ONE exclusive job: the edit and its save cannot be separated by a crash
    // respawn, a queued open_document or another command, so a success reply
    // means the edit was applied AND persisted (or the reply says otherwise).
    return commandQueue.runExclusive(async (send) => {
      const classification = classifyResponse(await send(cmd));
      const { text, isError } = classification;
      if (isError) {
        // Surface the error AND skip the save: a failed edit must not trigger a
        // write that replaces valid .pen content with empty or stale state.
        process.stderr.write(
          `[pencil-adapter] SKIPPED save (${name} errored): ${oneLine(text).slice(0, 200)}\n`
        );
        return errorResult(enrichErrorMessage(text));
      }
      let saved;
      try {
        saved = await guardedSave(send, "auto-save");
      } catch (err) {
        const reason = oneLine(redactKey(err?.message ?? err));
        process.stderr.write(`[pencil-adapter] save did not complete after ${name}: ${reason}\n`);
        return errorResult(
          `The edit was applied in memory but the save did not complete (${reason}); it is not persisted.`
        );
      }
      if (saved.refused) {
        process.stderr.write(`[pencil-adapter] ${oneLine(saved.message.split("\n")[0])} (${saved.reason})\n`);
        return errorResult(`${saved.message}\n\nEngine response to the edit:\n${text}`);
      }
      const after = classifyResponse(saved.raw);
      if (after.isError) {
        process.stderr.write(`[pencil-adapter] save failed after ${name}: ${oneLine(after.text).slice(0, 200)}\n`);
        return errorResult(`Edit applied but the save failed: ${enrichErrorMessage(after.text)}`);
      }
      return { content: [{ type: "text", text }] };
    });
  }, options);
}

// Tools @pencil.dev/cli 0.2.9 removed. They stay registered so Desktop-style
// callers get a replacement hint (pencil-error-enrichment.mjs) instead of a bare
// "tool not found"; formatReplCommand throws `Unknown tool:` for them, so nothing
// reaches the engine and nothing is saved. The schema is empty on purpose: any
// arguments the caller sends must reach the hint, not an SDK validation error.
// Retire with #11156.
function registerRemovedTool(name) {
  registerTool(
    name,
    {},
    async () => {
      formatReplCommand(name, {});
      throw new Error(`Unknown tool: ${name}`);
    },
    { description: `Not available in the headless adapter. ${enrichErrorMessage(`Unknown tool: ${name}`)}` }
  );
}

// --- Read-only tools ---

registerReadOnlyTool("batch_get", {
  patterns: z.array(z.record(z.string(), z.unknown())).optional(),
  nodeIds: z.array(z.string()).optional(),
  readDepth: z.number().optional(),
  parentId: z.string().optional(),
  searchDepth: z.number().optional(),
  resolveInstances: z.boolean().optional(),
  resolveVariables: z.boolean().optional(),
  includePathGeometry: z.boolean().optional(),
});

registerReadOnlyTool(
  "get_editor_state",
  {
    include_schema: z.boolean(),
  },
  {
    description:
      "Editor state of the open document. Pass { include_schema: true } once to get the full batch_design operation grammar.",
  }
);

registerReadOnlyTool("get_guidelines", {
  category: z.string().optional(),
  name: z.string().optional(),
  params: z.record(z.string(), z.unknown()).optional(),
});

// get_screenshot — special handling for base64 image data + auto-save to disk
registerTool("get_screenshot", { nodeId: z.string() }, async ({ nodeId }) => {
  const cmd = formatReplCommand("get_screenshot", { nodeId });
  const raw = await commandQueue.enqueue(cmd);
  const { text, isError } = classifyResponse(raw);
  if (isError) {
    return errorResult(enrichErrorMessage(text));
  }

  // Try parsing as JSON — pencil returns {"image":"<base64>","mimeType":"image/png"}
  let base64Data = null;
  let mimeType = "image/png";
  try {
    const parsed = JSON.parse(text);
    if (parsed.image && parsed.mimeType) {
      base64Data = parsed.image;
      mimeType = parsed.mimeType;
    }
  } catch {
    // Not JSON — try data URI pattern
    const base64Match = text.match(
      /data:image\/(png|jpeg);base64,([A-Za-z0-9+/=]+)/
    );
    if (base64Match) {
      base64Data = base64Match[2];
      mimeType = `image/${base64Match[1]}`;
    }
  }

  if (!base64Data) {
    return { content: [{ type: "text", text }] };
  }

  // Auto-save screenshot to disk; a disk failure must not discard the image
  let savedPath = null;
  let saveNote = null;
  try {
    savedPath = saveScreenshot(base64Data, nodeId);
  } catch (err) {
    saveNote = `Screenshot not saved to disk: ${oneLine(err?.message ?? err)}`;
    process.stderr.write(`[pencil-adapter] ${saveNote}\n`);
  }
  const content = [{ type: "image", data: base64Data, mimeType }];
  if (savedPath) {
    content.push({ type: "text", text: `Screenshot saved: ${savedPath}` });
  } else if (saveNote) {
    content.push({ type: "text", text: saveNote });
  }
  return { content };
});

registerRemovedTool("get_style_guide");
registerRemovedTool("get_style_guide_tags");

registerReadOnlyTool("get_variables", {});

registerRemovedTool("find_empty_space_on_canvas");
registerRemovedTool("search_all_unique_properties");

registerReadOnlyTool("snapshot_layout", {
  parentId: z.string().optional(),
  maxDepth: z.number().optional(),
  problemsOnly: z.boolean().optional(),
});

// export_nodes — custom handler to rename exported files using node names
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
    const ext = format || "png";

    // Step 1: Try to get node names via batch_get
    let nameMap = new Map();
    try {
      const batchCmd = formatReplCommand("batch_get", { nodeIds });
      const batchRaw = await commandQueue.enqueue(batchCmd);
      const parsed = JSON.parse(rawText(batchRaw));
      if (parsed.nodes && Array.isArray(parsed.nodes)) {
        for (const node of parsed.nodes) {
          if (node.id && node.name) {
            nameMap.set(node.id, node.name);
          }
        }
      }
    } catch (err) {
      process.stderr.write(`[pencil-adapter] batch_get for node names failed: ${oneLine(err.message)}\n`);
    }

    // Step 2: Run the original export_nodes command
    const cmd = formatReplCommand("export_nodes", { nodeIds, outputDir, format, scale, quality });
    const raw = await commandQueue.enqueue(cmd);
    const { text, isError } = classifyResponse(raw);
    if (isError) {
      return errorResult(enrichErrorMessage(text));
    }

    // Step 3: Rename exported files from nodeId to sanitized name
    const renamedFiles = [];
    for (const nodeId of nodeIds) {
      const nodeName = nameMap.get(nodeId);
      const sanitized = nodeName ? sanitizeFilename(nodeName) : "";
      if (!sanitized || !/^[A-Za-z0-9_-]+$/.test(nodeId)) {
        renamedFiles.push(`${nodeId}.${ext}`);
        continue;
      }
      const oldPath = join(outputDir, `${nodeId}.${ext}`);
      const newPath = join(outputDir, `${sanitized}.${ext}`);
      if (existsSync(newPath)) {
        // renameSync would silently replace an unrelated file of that name
        process.stderr.write(`[pencil-adapter] rename skipped: ${oneLine(newPath)} already exists\n`);
        renamedFiles.push(`${nodeId}.${ext}`);
        continue;
      }
      try {
        renameSync(oldPath, newPath);
        renamedFiles.push(`${sanitized}.${ext}`);
      } catch (err) {
        process.stderr.write(`[pencil-adapter] rename ${oneLine(oldPath)} -> ${oneLine(newPath)} failed: ${oneLine(err.message)}\n`);
        renamedFiles.push(`${nodeId}.${ext}`);
      }
    }

    const summary = `\nExported files: ${renamedFiles.join(", ")}`;
    return { content: [{ type: "text", text: text + summary }] };
  }
);

// --- Mutating tools (auto-save after) ---

registerMutatingTool("batch_design", { operations: z.string() }, {
  description:
    "Run a Pencil operation script (Insert, Update, Copy, Replace, Move, Delete, Generate, with short aliases I, U, C, R, M, D, G). " +
    "The field is `operations` (the engine's own name for it is `input`). Full grammar: call get_editor_state({ include_schema: true }) once. " +
    "The document is saved after every successful call; a refused save is reported as an error.",
});

registerRemovedTool("replace_all_matching_properties");
registerRemovedTool("set_variables");

// --- Meta tools ---

registerTool(
  "open_document",
  {
    filePath: z.string(),
    inputPath: z.string().optional(),
  },
  async ({ filePath, inputPath }) => {
    // Absolute .pen paths, never a symlink: the child process and the save
    // sentinel must agree on which file is meant, and the engine writes through
    // links. A refusal here changes no session state.
    const outFile = penPath(filePath, "filePath");
    const inFile = inputPath ? penPath(inputPath, "inputPath") : null;

    // The kill-and-respawn runs inside the same exclusive section as the saves,
    // so no queued command or save can land between the old document going away
    // and the new one loading. There is no pre-switch save: every successful edit
    // is saved in the same job (registerMutatingTool), so it could only persist
    // state the sentinel would refuse.
    return commandQueue.runExclusive(
      async (send) => {
        if (inFile && inFile !== outFile && diskTopLevelCount(readTextOrNull(outFile)) !== null) {
          return errorResult(
            `Refusing to open: ${outFile} already holds a document and inputPath ${inFile} would replace it on the first save. ` +
              `Open ${outFile} without inputPath, or open a new .pen path.`
          );
        }
        try {
          await pencilProcess.restart(outFile, inFile);
          const loadedFrom = pencilProcess.lastInFile;
          const memoryCount = memoryTopLevelCount(
            rawText(await send(formatReplCommand("batch_get", {})))
          );
          let note = "";
          if (loadedFrom) {
            const diskCount = diskTopLevelCount(readTextOrNull(loadedFrom));
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
      "Open (or create) a .pen document. Reports how many top-level nodes loaded. A failure leaves the file untouched and refuses every other tool until open_document succeeds; recover by opening a different path.",
  }
);

registerTool("save", {}, async () => {
  // Explicit saves are subject to the same empty-overwrite sentinel as the
  // auto-save, inside one exclusive job.
  const saved = await commandQueue.runExclusive((send) => guardedSave(send, "save"));
  if (saved.refused) {
    process.stderr.write(`[pencil-adapter] ${oneLine(saved.message.split("\n")[0])} (${saved.reason})\n`);
    return errorResult(saved.message);
  }
  const { text, isError } = classifyResponse(saved.raw);
  return isError
    ? errorResult(enrichErrorMessage(text))
    : { content: [{ type: "text", text }] };
});

// --- Start server ---
// The PENCIL_CLI_KEY hard-fail and Node-version gate both run at the top of
// this module, before the dynamic imports. See the comment block above the
// imports for rationale.

const transport = new StdioServerTransport();
await server.connect(transport);
process.stderr.write("[pencil-adapter] MCP server started on stdio\n");
