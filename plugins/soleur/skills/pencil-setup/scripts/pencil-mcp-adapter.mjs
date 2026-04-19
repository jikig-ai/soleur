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

const { McpServer } = await import("@modelcontextprotocol/sdk/server/mcp.js");
const { StdioServerTransport } = await import("@modelcontextprotocol/sdk/server/stdio.js");
const { z } = await import("zod");
const { spawn: nodeSpawn } = await import("node:child_process");
const { existsSync, mkdirSync, renameSync, writeFileSync } = await import("node:fs");
const { dirname, join } = await import("node:path");
const { homedir, tmpdir } = await import("node:os");
const { enrichErrorMessage } = await import("./pencil-error-enrichment.mjs");
const { sanitizeFilename } = await import("./sanitize-filename.mjs");
const { classifyResponse } = await import("./pencil-response-classify.mjs");
const { shouldSkipSave } = await import("./pencil-save-gate.mjs");

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

// --- ANSI stripping ---

function stripAnsi(str) {
  return str.replace(/\x1b\[[0-9;]*[a-zA-Z]/g, "");
}

// --- Response parsing ---
//
// Delegates to the pure `classifyResponse` module so the classifier can be
// unit-tested without importing this adapter (which pulls in the MCP SDK and
// cannot load under `bun test`). Auth-failure patterns (`pencil login`,
// `Invalid API key`, `Unauthorized`, `HTTP 401`) classify as errors so the
// post-mutation save gate (see `shouldSkipSave`) can skip auto-save and
// avoid overwriting .pen files with 0-byte output (#2630).

function parseResponse(raw) {
  return classifyResponse(raw);
}

// --- Node ID extraction ---

function extractNodeIds(response) {
  const entries = [];
  const pattern = /Inserted node `([A-Za-z0-9_-]+)`/g;
  let match;
  while ((match = pattern.exec(response)) !== null) {
    entries.push(match[1]);
  }
  return entries;
}

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

class PencilProcess {
  constructor() {
    this.child = null;
    this.ready = false;
    this.buffer = "";
    this.stderrBuffer = "";
    this.outputFile = null;
    this.inputFile = null;
    this.nodeIdMap = new Map();
    this._dataHandler = null;
  }

  async spawn(outFile, inFile = null) {
    const binary = process.env.PENCIL_BINARY || findPencilBinary();
    const args = ["interactive", "--out", outFile];
    if (inFile) {
      args.push("--in", inFile);
    }

    this.outputFile = outFile;
    this.inputFile = inFile;
    this.buffer = "";
    this.nodeIdMap.clear();

    // Spawn pencil using the adapter's own Node binary (process.execPath)
    // instead of relying on the pencil script's #!/usr/bin/env node shebang,
    // which resolves to the system Node (potentially <22) and fails with
    // ERR_REQUIRE_ESM. This guarantees the child process uses the same
    // Node version (22+) that runs the adapter.
    this.child = nodeSpawn(process.execPath, [binary, ...args], {
      stdio: ["pipe", "pipe", "pipe"],
      env: buildPencilEnv(),
    });

    // Capture child stderr for error reporting AND pipe to adapter stderr
    this.child.stderr.on("data", (chunk) => {
      this.stderrBuffer += chunk.toString();
      process.stderr.write(chunk);
    });

    // Crash detection
    this.child.on("exit", (code, signal) => {
      this.ready = false;
      this.child = null;
      process.stderr.write(
        `[pencil-adapter] pencil process exited: code=${code} signal=${signal}\n`
      );
    });

    this.child.on("error", (err) => {
      this.ready = false;
      this.child = null;
      process.stderr.write(
        `[pencil-adapter] pencil process error: ${err.message}\n`
      );
    });

    // Consume welcome banner + initial prompt
    await this.waitForPrompt(30000);
    this.ready = true;
  }

  async kill() {
    if (this.child) {
      this.child.kill("SIGTERM");
      this.child = null;
      this.ready = false;
    }
  }

  async restart(outFile, inFile = null) {
    await this.kill();
    // Brief delay to let the old process clean up
    await new Promise((r) => setTimeout(r, 200));
    await this.spawn(outFile, inFile);
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
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        if (this._dataHandler && this.child) {
          this.child.stdout.removeListener("data", this._dataHandler);
        }
        this._dataHandler = null;
        reject(
          new Error(
            `[pencil-adapter] Timed out waiting for prompt after ${timeoutMs}ms`
          )
        );
      }, timeoutMs);

      this._dataHandler = (chunk) => {
        this.buffer += chunk.toString();
        const stripped = stripAnsi(this.buffer);
        // Detect prompt: "pencil > " at start or after newline
        const promptIdx = stripped.indexOf("\npencil > ");
        const startsWithPrompt = stripped.startsWith("pencil > ");

        if (promptIdx !== -1 || startsWithPrompt) {
          clearTimeout(timeout);
          if (this.child) {
            this.child.stdout.removeListener("data", this._dataHandler);
          }
          this._dataHandler = null;

          let response;
          if (promptIdx !== -1) {
            response = stripped.substring(0, promptIdx);
          } else {
            // Buffer starts with prompt — empty response (initial prompt)
            response = "";
          }
          resolve(response.trim());
        }
      };

      if (this.child) {
        this.child.stdout.on("data", this._dataHandler);
      } else {
        clearTimeout(timeout);
        reject(new Error("[pencil-adapter] No child process to listen to"));
      }
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
    return new Promise((resolve, reject) => {
      this.queue.push({ command, resolve, reject });
      if (!this.running) this._drain();
    });
  }

  async _drain() {
    this.running = true;
    while (this.queue.length > 0) {
      const { command, resolve: res, reject: rej } = this.queue.shift();
      try {
        // Auto-restart if process died
        if (!this.process.ready && !this.process.child) {
          if (this.process.outputFile) {
            await this.process.spawn(
              this.process.outputFile,
              this.process.inputFile
            );
          } else {
            throw new Error(
              "Pencil process not running and no file to restart with"
            );
          }
        }
        const result = await this.process.sendCommand(command);
        res(result);
      } catch (err) {
        rej(err);
      }
    }
    this.running = false;
  }
}

// --- REPL command formatting ---

function formatReplCommand(toolName, params) {
  if (!params || Object.keys(params).length === 0) {
    return `${toolName}()`;
  }
  if (toolName === "batch_design") {
    return `batch_design({ operations: ${JSON.stringify(params.operations)} })`;
  }
  return `${toolName}(${JSON.stringify(params)})`;
}

// --- Lazy spawn helper ---

const pencilProcess = new PencilProcess();
const commandQueue = new CommandQueue(pencilProcess);

// Tracks the classification of the most recent REPL mutation so open_document's
// pre-restart save() can skip when the prior mutation errored. See
// `shouldSkipSave` and the #2630 regression.
let lastMutationClassification = null;

async function ensureProcess() {
  if (!pencilProcess.ready && !pencilProcess.child) {
    if (pencilProcess.outputFile) {
      await pencilProcess.spawn(
        pencilProcess.outputFile,
        pencilProcess.inputFile
      );
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

// --- MCP Server setup ---

const server = new McpServer({
  name: "pencil-mcp-adapter",
  version: "0.0.1",
});

// --- Read-only tool handler factory ---

function registerReadOnlyTool(name, schema, handler) {
  server.tool(name, schema, async (params) => {
    await ensureProcess();
    const cmd = formatReplCommand(name, params);
    const raw = await commandQueue.enqueue(cmd);
    const { text, isError } = parseResponse(raw);
    if (handler) {
      return handler(text, isError);
    }
    return { content: [{ type: "text", text }], isError };
  });
}

// --- Mutating tool handler factory ---

function registerMutatingTool(name, schema, postHandler) {
  server.tool(name, schema, async (params) => {
    await ensureProcess();
    const cmd = formatReplCommand(name, params);
    const raw = await commandQueue.enqueue(cmd);
    const classification = parseResponse(raw);
    lastMutationClassification = classification;
    const { text, isError } = classification;
    if (isError) {
      // Surface the error AND skip the auto-save that used to clobber
      // .pen files with 0-byte output. See `shouldSkipSave`.
      process.stderr.write(
        `[pencil-adapter] SKIPPED save (${name} errored): ${text.slice(0, 200)}\n`
      );
      return { content: [{ type: "text", text: enrichErrorMessage(text) }], isError: true };
    }
    if (postHandler) {
      postHandler(text);
    }
    // Auto-save after mutating operations — gated by `shouldSkipSave` so a
    // failed mutation does not trigger a save that overwrites valid .pen
    // content with empty or stale state.
    if (!shouldSkipSave(classification)) {
      await commandQueue.enqueue("save()");
    }
    return { content: [{ type: "text", text }] };
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
  topic: z.enum([
    "code",
    "table",
    "tailwind",
    "landing-page",
    "design-system",
    "slides",
    "mobile-app",
    "web-app",
  ]),
});

// get_screenshot — special handling for base64 image data + auto-save to disk
server.tool("get_screenshot", { nodeId: z.string() }, async ({ nodeId }) => {
  await ensureProcess();
  const cmd = formatReplCommand("get_screenshot", { nodeId });
  const raw = await commandQueue.enqueue(cmd);
  const { text, isError } = parseResponse(raw);
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

registerReadOnlyTool("get_style_guide", {
  name: z.string().optional(),
  tags: z.array(z.string()).optional(),
});

registerReadOnlyTool("get_style_guide_tags", {});

registerReadOnlyTool("get_variables", {});

registerReadOnlyTool("find_empty_space_on_canvas", {
  direction: z.enum(["top", "right", "bottom", "left"]),
  height: z.number(),
  width: z.number(),
  padding: z.number(),
  nodeId: z.string().optional(),
});

registerReadOnlyTool("search_all_unique_properties", {
  parents: z.array(z.string()),
  properties: z.array(z.string()),
});

registerReadOnlyTool("snapshot_layout", {
  parentId: z.string().optional(),
  maxDepth: z.number().optional(),
  problemsOnly: z.boolean().optional(),
});

// export_nodes — custom handler to rename exported files using node names
server.tool(
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
      const { text: batchText } = parseResponse(batchRaw);
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
    const { text, isError } = parseResponse(raw);
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

registerMutatingTool(
  "batch_design",
  { operations: z.string() },
  (text) => {
    // Extract and track node IDs
    const nodeIds = extractNodeIds(text);
    for (const id of nodeIds) {
      pencilProcess.nodeIdMap.set(id, id);
    }
  }
);

registerMutatingTool("replace_all_matching_properties", {
  parents: z.array(z.string()),
  properties: z.record(z.string(), z.unknown()),
});

// set_variables — auto-coerce bare values into {type, value} objects
server.tool(
  "set_variables",
  {
    variables: z.record(z.string(), z.unknown()),
    replace: z.boolean().optional(),
  },
  async ({ variables, replace }) => {
    await ensureProcess();
    // Coerce bare values: "#hex" → {type:"color"}, number → {type:"number"}, string → {type:"string"}
    const coerced = {};
    for (const [key, val] of Object.entries(variables)) {
      if (val && typeof val === "object" && val.type && val.value !== undefined) {
        coerced[key] = val; // already typed
      } else if (typeof val === "string" && /^#[0-9a-fA-F]{3,8}$/.test(val)) {
        coerced[key] = { type: "color", value: val };
      } else if (typeof val === "number") {
        coerced[key] = { type: "number", value: val };
      } else if (typeof val === "string") {
        coerced[key] = { type: "string", value: val };
      } else {
        coerced[key] = val; // pass through unknown shapes
      }
    }
    const params = { variables: coerced };
    if (replace !== undefined) params.replace = replace;
    const cmd = formatReplCommand("set_variables", params);
    const raw = await commandQueue.enqueue(cmd);
    const classification = parseResponse(raw);
    lastMutationClassification = classification;
    const { text, isError } = classification;
    if (isError) {
      let enriched = text;
      if (/does not have a valid definition/i.test(text)) {
        enriched += '\nExpected: { "type": "color" | "string" | "number", "value": <value> }';
      } else if (/invalid type property/i.test(text)) {
        enriched += "\nValid types: color, string, number";
      }
      process.stderr.write(
        `[pencil-adapter] SKIPPED save (set_variables errored): ${text.slice(0, 200)}\n`
      );
      return { content: [{ type: "text", text: enriched }], isError: true };
    }
    if (!shouldSkipSave(classification)) {
      await commandQueue.enqueue("save()");
    }
    return { content: [{ type: "text", text }] };
  }
);

// --- Meta tools ---

server.tool(
  "open_document",
  {
    filePath: z.string(),
    inputPath: z.string().optional(),
  },
  async ({ filePath, inputPath }) => {
    // Save current document first if process is running — but skip when the
    // preceding mutation errored (would overwrite good content with 0 bytes).
    if (pencilProcess.ready && !shouldSkipSave(lastMutationClassification)) {
      try {
        await commandQueue.enqueue("save()");
      } catch {
        // Process may have died — proceed with restart
      }
    } else if (pencilProcess.ready && shouldSkipSave(lastMutationClassification)) {
      process.stderr.write(
        "[pencil-adapter] SKIPPED pre-restart save (prior mutation errored)\n"
      );
    }
    await pencilProcess.restart(filePath, inputPath);
    // Reset classification — new document means prior error is no longer relevant.
    lastMutationClassification = null;
    return {
      content: [{ type: "text", text: `Opened ${filePath}` }],
    };
  }
);

server.tool("save", {}, async () => {
  await ensureProcess();
  const raw = await commandQueue.enqueue("save()");
  const { text, isError } = parseResponse(raw);
  return { content: [{ type: "text", text }], isError };
});

// --- Start server ---
// The PENCIL_CLI_KEY hard-fail and Node-version gate both run at the top of
// this module, before the dynamic imports. See the comment block above the
// imports for rationale.

const transport = new StdioServerTransport();
await server.connect(transport);
process.stderr.write("[pencil-adapter] MCP server started on stdio\n");
