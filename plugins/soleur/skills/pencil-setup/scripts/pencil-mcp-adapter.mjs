#!/usr/bin/env node

// pencil-mcp-adapter.mjs — MCP server bridging Claude Code to pencil interactive REPL
// Architecture: Claude Code ←(MCP stdio)→ this adapter ←(stdin/stdout REPL)→ pencil interactive

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { spawn as nodeSpawn } from "node:child_process";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { homedir, tmpdir } from "node:os";

// --- Node version gate ---

const [major, minor] = process.version.slice(1).split(".").map(Number);
if (major < 22 || (major === 22 && minor < 9)) {
  process.stderr.write(
    `[pencil-adapter] Node >= 22.9.0 required, got ${process.version}\n`
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
  return env;
}

// --- ANSI stripping ---

function stripAnsi(str) {
  return str.replace(/\x1b\[[0-9;]*[a-zA-Z]/g, "");
}

// --- Response parsing ---

function parseResponse(raw) {
  const text = stripAnsi(raw).trim();
  const isError =
    /^Error:/m.test(text) || /^\[ERROR\]/m.test(text);
  return { text, isError };
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

    this.child = nodeSpawn(binary, args, {
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
    const { text, isError } = parseResponse(raw);
    if (isError) {
      return { content: [{ type: "text", text }], isError: true };
    }
    if (postHandler) {
      postHandler(text);
    }
    // Auto-save after mutating operations
    await commandQueue.enqueue("save()");
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

// get_screenshot — special handling for base64 image data
registerReadOnlyTool(
  "get_screenshot",
  { nodeId: z.string() },
  (text, isError) => {
    if (isError) {
      return { content: [{ type: "text", text }], isError: true };
    }
    // Try parsing as JSON — pencil returns {"image":"<base64>","mimeType":"image/png"}
    try {
      const parsed = JSON.parse(text);
      if (parsed.image && parsed.mimeType) {
        return {
          content: [
            {
              type: "image",
              data: parsed.image,
              mimeType: parsed.mimeType,
            },
          ],
        };
      }
    } catch {
      // Not JSON — try data URI pattern
      const base64Match = text.match(
        /data:image\/(png|jpeg);base64,([A-Za-z0-9+/=]+)/
      );
      if (base64Match) {
        return {
          content: [
            {
              type: "image",
              data: base64Match[2],
              mimeType: `image/${base64Match[1]}`,
            },
          ],
        };
      }
    }
    // Fallback to text
    return { content: [{ type: "text", text }] };
  }
);

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

registerReadOnlyTool("export_nodes", {
  nodeIds: z.array(z.string()),
  outputDir: z.string(),
  format: z.enum(["png", "jpeg", "webp", "pdf"]).optional(),
  scale: z.number().optional(),
  quality: z.number().optional(),
});

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

registerMutatingTool("set_variables", {
  variables: z.record(z.string(), z.unknown()),
  replace: z.boolean().optional(),
});

// --- Meta tools ---

server.tool(
  "open_document",
  {
    filePath: z.string(),
    inputPath: z.string().optional(),
  },
  async ({ filePath, inputPath }) => {
    // Save current document first if process is running
    if (pencilProcess.ready) {
      try {
        await commandQueue.enqueue("save()");
      } catch {
        // Process may have died — proceed with restart
      }
    }
    await pencilProcess.restart(filePath, inputPath);
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

const transport = new StdioServerTransport();
await server.connect(transport);
process.stderr.write("[pencil-adapter] MCP server started on stdio\n");
