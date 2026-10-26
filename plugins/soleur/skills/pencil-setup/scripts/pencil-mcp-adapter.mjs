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
let existsSync, mkdirSync, readFileSync, renameSync, statSync, writeFileSync;
let dirname, join, resolve, homedir, tmpdir;
let enrichErrorMessage, sanitizeFilename, classifyResponse, stripAnsi;
let shouldSkipSave, runGuardedSave, diskTopLevelCount, memoryTopLevelCount;
let formatReplCommand, planSpawn;

try {
  ({ McpServer } = await import("@modelcontextprotocol/sdk/server/mcp.js"));
  ({ StdioServerTransport } = await import("@modelcontextprotocol/sdk/server/stdio.js"));
  ({ z } = await import("zod"));
  ({ spawn: nodeSpawn } = await import("node:child_process"));
  ({ existsSync, mkdirSync, readFileSync, renameSync, statSync, writeFileSync } = await import("node:fs"));
  ({ dirname, join, resolve } = await import("node:path"));
  ({ homedir, tmpdir } = await import("node:os"));
  ({ enrichErrorMessage } = await import("./pencil-error-enrichment.mjs"));
  ({ sanitizeFilename } = await import("./sanitize-filename.mjs"));
  ({ classifyResponse, stripAnsi } = await import("./pencil-response-classify.mjs"));
  ({
    shouldSkipSave,
    runGuardedSave,
    diskTopLevelCount,
    memoryTopLevelCount,
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
// the post-mutation save gate (see `shouldSkipSave`) skips auto-save
// and avoids overwriting .pen files with 0-byte output (#2630).

// --- Screenshot persistence ---

function saveScreenshot(base64Data, nodeId) {
  const penFile = pencilProcess.outputFile;
  if (!penFile) return null;
  const screenshotDir = join(dirname(penFile), "screenshots");
  mkdirSync(screenshotDir, { recursive: true });
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
  const filename = `${nodeId}-${timestamp}.png`;
  const filePath = join(screenshotDir, filename);
  writeFileSync(filePath, Buffer.from(base64Data, "base64"));
  return filePath;
}

// --- Binary resolution ---

function findPencilBinary() {
  const localPath = join(homedir(), ".local", "node_modules", ".bin", "pencil");
  if (existsSync(localPath)) return localPath;
  // Fall back to PATH lookup — spawn will resolve it
  return "pencil";
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

class PencilProcess {
  constructor() {
    this.child = null;
    this.ready = false;
    this.buffer = "";
    this.stderrBuffer = "";
    // Set only after the child reaches its first prompt, so a failed spawn
    // never leaves a path the auto-restart would respawn against.
    this.outputFile = null;
    this._dataHandler = null;
    this._onExit = null;
  }

  // `explicitInFile` is the caller's template (open_document `inputPath`) and
  // applies to this spawn only. A respawn passes none, and `planSpawn` then
  // reloads `outFile`, so saved edits are never overwritten by a template.
  async spawn(outFile, explicitInFile = null) {
    const binary = process.env.PENCIL_BINARY || findPencilBinary();
    const { inFile } = planSpawn({
      outFile,
      initialInFile: explicitInFile,
      probe: FS_PROBE,
    });
    const args = ["interactive", "--out", outFile];
    if (inFile) {
      args.push("--in", inFile);
    }

    this.outputFile = null;
    this.buffer = "";
    this.stderrBuffer = "";

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

    // Capture child stderr for error reporting AND pipe to adapter stderr
    child.stderr.on("data", (chunk) => {
      this.stderrBuffer += chunk.toString();
      process.stderr.write(chunk);
    });

    // Handlers are bound to THIS child: the exit event of a killed child can
    // arrive after its replacement was spawned and must not null the new one.
    child.on("exit", (code, signal) => {
      process.stderr.write(
        `[pencil-adapter] pencil process exited: code=${code} signal=${signal}\n`
      );
      if (this.child === child) {
        this.ready = false;
        this.child = null;
      }
      if (this._onExit) this._onExit(code, signal, this.child === null);
    });

    child.on("error", (err) => {
      process.stderr.write(
        `[pencil-adapter] pencil process error: ${err.message}\n`
      );
      if (this.child === child) {
        this.ready = false;
        this.child = null;
      }
      if (this._onExit) this._onExit(null, null, true, err);
    });

    // Consume welcome banner + initial prompt
    await this.waitForPrompt(30000);
    this.outputFile = outFile;
    this.ready = true;
  }

  async kill() {
    if (this.child) {
      this.child.kill("SIGTERM");
      this.child = null;
      this.ready = false;
    }
  }

  async restart(outFile, explicitInFile = null) {
    await this.kill();
    // Brief delay to let the old process clean up
    await new Promise((r) => setTimeout(r, 200));
    await this.spawn(outFile, explicitInFile);
  }

  async sendCommand(cmd) {
    if (!this.child || !this.ready) {
      throw new Error("Pencil process is not running");
    }
    this.buffer = "";
    this.stderrBuffer = "";
    this.child.stdin.write(cmd + "\n");
    const raw = await this.waitForPrompt(30000);
    // If stdout response is empty but stderr has content, use stderr
    if (!raw && this.stderrBuffer) {
      return this.stderrBuffer;
    }
    return raw;
  }

  waitForPrompt(timeoutMs = 30000) {
    return new Promise((resolvePrompt, reject) => {
      const child = this.child;
      if (!child) {
        reject(new Error("[pencil-adapter] No child process to listen to"));
        return;
      }
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

      // A child that exits before its prompt (bad --in file, auth failure)
      // fails the wait immediately with its stderr tail, not after 30 s.
      this._onExit = (code, signal, _isCurrent, err) => {
        cleanup();
        const tail = this.stderrBuffer.trim().split("\n").slice(-5).join("\n");
        reject(
          new Error(
            `[pencil-adapter] pencil exited before it was ready (code=${code} signal=${signal}${err ? ` error=${err.message}` : ""})` +
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
    return new Promise((resolveJob, reject) => {
      this.queue.push({ command, resolve: resolveJob, reject });
      if (!this.running) this._drain();
    });
  }

  // Run `fn` as ONE queue job: no other queued command, and no restart, can
  // land while it runs. `fn` receives `send(cmd)`, which talks to the process
  // directly (enqueueing from inside a job would wait on itself). This is what
  // makes the save sentinel's probe-then-save atomic.
  async runExclusive(fn, { ensure = true } = {}) {
    return new Promise((resolveJob, reject) => {
      this.queue.push({ job: fn, ensure, resolve: resolveJob, reject });
      if (!this.running) this._drain();
    });
  }

  async _ensureAlive() {
    // Auto-restart if process died. No explicit input: the respawn reloads
    // the output file (see PencilProcess.spawn).
    if (!this.process.ready && !this.process.child) {
      if (this.process.outputFile) {
        await this.process.spawn(this.process.outputFile);
      } else {
        throw new Error(
          "Pencil process not running and no file to restart with"
        );
      }
    }
  }

  async _drain() {
    this.running = true;
    while (this.queue.length > 0) {
      const item = this.queue.shift();
      try {
        if (item.job) {
          if (item.ensure) await this._ensureAlive();
          item.resolve(await item.job((cmd) => this.process.sendCommand(cmd)));
        } else {
          await this._ensureAlive();
          item.resolve(await this.process.sendCommand(item.command));
        }
      } catch (err) {
        item.reject(err);
      }
    }
    this.running = false;
  }
}

// --- Lazy spawn helper ---

const pencilProcess = new PencilProcess();
const commandQueue = new CommandQueue(pencilProcess);

// Tracks the classification of the most recent REPL mutation so a failed
// mutation never triggers an auto-save. See `shouldSkipSave` and #2630.
let lastMutationClassification = null;

// Set when open_document could not load the file it was given. Every tool
// errors until the next successful open_document, so nothing runs (or saves)
// against a document that is not the one the caller asked for.
let openFailure = null;

async function ensureProcess() {
  if (!pencilProcess.ready && !pencilProcess.child) {
    if (pencilProcess.outputFile) {
      await pencilProcess.spawn(pencilProcess.outputFile);
    } else {
      // No document opened yet — use a temp file
      const tempFile = join(
        tmpdir(),
        `pencil-adapter-${process.pid}.pen`
      );
      await pencilProcess.spawn(tempFile);
    }
  }
}

// --- Guarded save (the ONLY place the REPL `save` command is emitted) ---
//
// One exclusive queue job: read the file on disk, probe the in-memory
// document, decide, then save. An empty document is never written over a
// file that still holds nodes (#11143; see pencil-save-gate.mjs). Callers:
// the post-mutation auto-save and the explicit `save` tool.

async function guardedSave(source) {
  return commandQueue.runExclusive(async (send) => {
    const file = pencilProcess.outputFile;
    return runGuardedSave({
      file,
      source,
      readDisk: async () => {
        try {
          return readFileSync(file, "utf8");
        } catch {
          return null;
        }
      },
      probeMemory: async () => {
        try {
          return classifyResponse(await send(formatReplCommand("batch_get", {}))).text;
        } catch {
          return null;
        }
      },
      send: async () => send(formatReplCommand("save", {})),
    });
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
function registerTool(name, schema, handler, { allowWhenOpenFailed = false } = {}) {
  server.tool(name, schema, async (params) => {
    if (openFailure && !allowWhenOpenFailed) {
      return errorResult(
        `open failed: ${openFailure}\nCall open_document with a valid file to continue; no tool runs until then.`
      );
    }
    try {
      return await handler(params ?? {});
    } catch (err) {
      return errorResult(enrichErrorMessage(String(err?.message ?? err)));
    }
  });
}

// --- Read-only tool handler factory ---

function registerReadOnlyTool(name, schema, handler) {
  registerTool(name, schema, async (params) => {
    const cmd = formatReplCommand(name, params);
    await ensureProcess();
    const raw = await commandQueue.enqueue(cmd);
    const { text, isError } = classifyResponse(raw);
    if (handler) {
      return handler(text, isError);
    }
    return {
      content: [{ type: "text", text: isError ? enrichErrorMessage(text) : text }],
      isError,
    };
  });
}

// --- Mutating tool handler factory ---

function registerMutatingTool(name, schema) {
  registerTool(name, schema, async (params) => {
    const cmd = formatReplCommand(name, params);
    await ensureProcess();
    const raw = await commandQueue.enqueue(cmd);
    const classification = classifyResponse(raw);
    lastMutationClassification = classification;
    const { text, isError } = classification;
    if (isError) {
      // Surface the error AND skip the auto-save that used to clobber
      // .pen files with 0-byte output. See `shouldSkipSave`.
      process.stderr.write(
        `[pencil-adapter] SKIPPED save (${name} errored): ${text.slice(0, 200)}\n`
      );
      return errorResult(enrichErrorMessage(text));
    }
    // Auto-save after mutating operations — gated by `shouldSkipSave` so a
    // failed mutation does not trigger a save, and by the empty-overwrite
    // sentinel so an empty document never replaces a file that holds nodes.
    if (!shouldSkipSave(classification)) {
      const saved = await guardedSave("auto-save");
      if (saved.refused) {
        process.stderr.write(`[pencil-adapter] ${saved.message.split("\n")[0]}\n`);
        return errorResult(`${saved.message}\n\nEngine response to the edit:\n${text}`);
      }
      const after = classifyResponse(saved.raw);
      if (after.isError) {
        return errorResult(`Edit applied but the save failed: ${enrichErrorMessage(after.text)}`);
      }
    }
    return { content: [{ type: "text", text }] };
  });
}

// Tools @pencil.dev/cli 0.2.9 removed. They stay registered so Desktop-style
// callers get a replacement hint (pencil-error-enrichment.mjs) instead of a
// bare "tool not found"; formatReplCommand throws `Unknown tool:` for them, so
// nothing reaches the engine and nothing is saved. Retire with #11156.
function registerRemovedTool(name, schema) {
  registerTool(name, schema, async () => {
    formatReplCommand(name, {});
    return errorResult(`Unknown tool: ${name}`);
  });
}

// --- Read-only tools ---

registerReadOnlyTool("batch_get", {
  patterns: z.array(z.record(z.string(), z.unknown())).optional(),
  nodeIds: z.array(z.string()).optional(),
  readDepth: z.number().optional(),
});

registerReadOnlyTool("get_editor_state", {
  include_schema: z.boolean(),
});

registerReadOnlyTool("get_guidelines", {
  category: z.string().optional(),
  name: z.string().optional(),
  params: z.record(z.string(), z.unknown()).optional(),
});

// get_screenshot — special handling for base64 image data + auto-save to disk
registerTool("get_screenshot", { nodeId: z.string() }, async ({ nodeId }) => {
  const cmd = formatReplCommand("get_screenshot", { nodeId });
  await ensureProcess();
  const raw = await commandQueue.enqueue(cmd);
  const { text, isError } = classifyResponse(raw);
  if (isError) {
    return { content: [{ type: "text", text }], isError: true };
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

  // Auto-save screenshot to disk
  const savedPath = saveScreenshot(base64Data, nodeId);
  const content = [{ type: "image", data: base64Data, mimeType }];
  if (savedPath) {
    content.push({ type: "text", text: `Screenshot saved: ${savedPath}` });
  }
  return { content };
});

registerRemovedTool("get_style_guide", {
  name: z.string().optional(),
  tags: z.array(z.string()).optional(),
});

registerRemovedTool("get_style_guide_tags", {});

registerReadOnlyTool("get_variables", {});

registerRemovedTool("find_empty_space_on_canvas", {
  direction: z.enum(["top", "right", "bottom", "left"]),
  height: z.number(),
  width: z.number(),
  padding: z.number(),
  nodeId: z.string().optional(),
});

registerRemovedTool("search_all_unique_properties", {
  parents: z.array(z.string()),
  properties: z.array(z.string()),
});

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
    await ensureProcess();
    const ext = format || "png";

    // Step 1: Try to get node names via batch_get
    let nameMap = new Map();
    try {
      const batchCmd = formatReplCommand("batch_get", { nodeIds });
      const batchRaw = await commandQueue.enqueue(batchCmd);
      const { text: batchText } = classifyResponse(batchRaw);
      const parsed = JSON.parse(batchText);
      if (parsed.nodes && Array.isArray(parsed.nodes)) {
        for (const node of parsed.nodes) {
          if (node.id && node.name) {
            nameMap.set(node.id, node.name);
          }
        }
      }
    } catch (err) {
      process.stderr.write(`[pencil-adapter] batch_get for node names failed: ${err.message}\n`);
    }

    // Step 2: Run the original export_nodes command
    const cmd = formatReplCommand("export_nodes", { nodeIds, outputDir, format, scale, quality });
    const raw = await commandQueue.enqueue(cmd);
    const { text, isError } = classifyResponse(raw);
    if (isError) {
      return { content: [{ type: "text", text }], isError: true };
    }

    // Step 3: Rename exported files from nodeId to sanitized name
    const renamedFiles = [];
    for (const nodeId of nodeIds) {
      const nodeName = nameMap.get(nodeId);
      const sanitized = nodeName ? sanitizeFilename(nodeName) : "";
      if (!sanitized) {
        renamedFiles.push(`${nodeId}.${ext}`);
        continue;
      }
      const oldPath = join(outputDir, `${nodeId}.${ext}`);
      const newPath = join(outputDir, `${sanitized}.${ext}`);
      try {
        renameSync(oldPath, newPath);
        renamedFiles.push(`${sanitized}.${ext}`);
      } catch (err) {
        process.stderr.write(`[pencil-adapter] rename ${oldPath} -> ${newPath} failed: ${err.message}\n`);
        renamedFiles.push(`${nodeId}.${ext}`);
      }
    }

    const summary = `\nExported files: ${renamedFiles.join(", ")}`;
    return { content: [{ type: "text", text: text + summary }] };
  }
);

// --- Mutating tools (auto-save after) ---

registerMutatingTool("batch_design", { operations: z.string() });

registerRemovedTool("replace_all_matching_properties", {
  parents: z.array(z.string()),
  properties: z.record(z.string(), z.unknown()),
});

registerRemovedTool("set_variables", {
  variables: z.record(z.string(), z.unknown()),
  replace: z.boolean().optional(),
});

// --- Meta tools ---

registerTool(
  "open_document",
  {
    filePath: z.string(),
    inputPath: z.string().optional(),
  },
  async ({ filePath, inputPath }) => {
    // Absolute paths: the child process and the save sentinel must agree on
    // which file is meant regardless of either side's working directory.
    const outFile = resolve(filePath);
    const inFile = inputPath ? resolve(inputPath) : null;

    // The kill-and-respawn runs inside the same exclusive section as the
    // saves, so no queued command or save can land between the old document
    // going away and the new one loading. There is no pre-switch save: every
    // mutation already auto-saves, so it could only persist state the
    // sentinel would refuse.
    return commandQueue.runExclusive(
      async (send) => {
        try {
          openFailure = null;
          await pencilProcess.restart(outFile, inFile);
          lastMutationClassification = null;
          const memoryCount = memoryTopLevelCount(
            classifyResponse(await send(formatReplCommand("batch_get", {}))).text
          );
          const diskCount = diskTopLevelCount(
            (() => {
              try {
                return readFileSync(outFile, "utf8");
              } catch {
                return null;
              }
            })()
          );
          if (!inFile && diskCount !== null && diskCount > 0 && !(memoryCount > 0)) {
            throw new Error(
              `${outFile} holds ${diskCount} top-level node(s) on disk but loaded empty; it was not modified`
            );
          }
          const shown = memoryCount === null ? "unknown" : String(memoryCount);
          return {
            content: [
              { type: "text", text: `Opened ${outFile} (${shown} top-level node(s) loaded)` },
            ],
          };
        } catch (err) {
          openFailure = String(err?.message ?? err);
          await pencilProcess.kill();
          process.stderr.write(`[pencil-adapter] open failed: ${openFailure}\n`);
          return errorResult(`open failed: ${openFailure}`);
        }
      },
      { ensure: false }
    );
  },
  { allowWhenOpenFailed: true }
);

registerTool("save", {}, async () => {
  await ensureProcess();
  // Explicit saves are subject to the same empty-overwrite sentinel as the
  // auto-save. When a prior mutation classified as an error, log a stderr note
  // so the sequence (failed mutation → explicit save) is visible in the MCP log.
  if (shouldSkipSave(lastMutationClassification)) {
    process.stderr.write(
      "[pencil-adapter] NOTE: explicit save after preceding errored mutation " +
      "— running at caller's request, but the saved file may not reflect intended state.\n"
    );
  }
  const saved = await guardedSave("save");
  if (saved.refused) {
    process.stderr.write(`[pencil-adapter] ${saved.message.split("\n")[0]}\n`);
    return errorResult(saved.message);
  }
  const { text, isError } = classifyResponse(saved.raw);
  return { content: [{ type: "text", text }], isError };
});

// --- Start server ---
// The PENCIL_CLI_KEY hard-fail and Node-version gate both run at the top of
// this module, before the dynamic imports. See the comment block above the
// imports for rationale.

const transport = new StdioServerTransport();
await server.connect(transport);
process.stderr.write("[pencil-adapter] MCP server started on stdio\n");
