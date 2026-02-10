/**
 * Soleur Telegram Bridge
 *
 * Bridges a Telegram bot to a local Claude Code CLI process over WebSocket.
 * The CLI connects via --sdk-url and exchanges NDJSON messages.
 *
 * Architecture:
 *   Telegram <-> grammY bot <-> Bridge logic <-> WebSocket <-> Claude CLI
 */

import { Bot, type Context, InlineKeyboard } from "grammy";
import { hydrateReply, type ParseModeFlavor } from "@grammyjs/parse-mode";

// ---------------------------------------------------------------------------
// 1. Configuration
// ---------------------------------------------------------------------------

const TELEGRAM_BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN;
const TELEGRAM_ALLOWED_USER_ID = process.env.TELEGRAM_ALLOWED_USER_ID;
const WS_PORT = Number(process.env.WS_PORT ?? 8765);
const HEALTH_PORT = 8080;
const PERMISSION_TIMEOUT_MS = 5 * 60 * 1000; // 5 minutes
const CLI_RESTART_DELAY_MS = 5_000;

if (!TELEGRAM_BOT_TOKEN) {
  console.error("FATAL: TELEGRAM_BOT_TOKEN is not set");
  process.exit(1);
}
if (!TELEGRAM_ALLOWED_USER_ID) {
  console.error("FATAL: TELEGRAM_ALLOWED_USER_ID is not set");
  process.exit(1);
}

const allowedUserId = Number(TELEGRAM_ALLOWED_USER_ID);

// ---------------------------------------------------------------------------
// 2. Types
// ---------------------------------------------------------------------------

type CliState = "connecting" | "ready" | "error";

type BotContext = ParseModeFlavor<Context>;

interface PendingPermission {
  requestId: string;
  toolName: string;
  input: Record<string, unknown>;
  toolUseId: string;
  timer: Timer;
  telegramMessageId?: number;
}

interface QueuedMessage {
  chatId: number;
  text: string;
}

// ---------------------------------------------------------------------------
// 3. Global state
// ---------------------------------------------------------------------------

let cliState: CliState = "connecting";
let cliWs: { send(data: string | ArrayBufferLike): void } | null = null;
let cliProcess: ReturnType<typeof Bun.spawn> | null = null;
let messagesProcessed = 0;
let startTime = Date.now();
let processing = false;
const messageQueue: QueuedMessage[] = [];
const pendingPermissions = new Map<string, PendingPermission>();

// ---------------------------------------------------------------------------
// 4. HTML formatting helpers
// ---------------------------------------------------------------------------

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function markdownToHtml(text: string): string {
  // First, extract code blocks so they are not processed by inline rules.
  const codeBlocks: string[] = [];
  let processed = text.replace(/```(?:\w*)\n?([\s\S]*?)```/g, (_match, code) => {
    const idx = codeBlocks.length;
    codeBlocks.push(`<pre>${escapeHtml(code.trimEnd())}</pre>`);
    return `\x00CODEBLOCK_${idx}\x00`;
  });

  // Inline code (must come before bold to avoid conflicts inside backticks)
  const inlineCodes: string[] = [];
  processed = processed.replace(/`([^`]+)`/g, (_match, code) => {
    const idx = inlineCodes.length;
    inlineCodes.push(`<code>${escapeHtml(code)}</code>`);
    return `\x00INLINE_${idx}\x00`;
  });

  // Escape remaining HTML entities in the plain-text portions
  processed = escapeHtml(processed);

  // Bold: **text** or __text__
  processed = processed.replace(/\*\*(.+?)\*\*/g, "<b>$1</b>");
  processed = processed.replace(/__(.+?)__/g, "<b>$1</b>");

  // Restore inline codes
  processed = processed.replace(/\x00INLINE_(\d+)\x00/g, (_m, idx) => inlineCodes[Number(idx)]);

  // Restore code blocks
  processed = processed.replace(/\x00CODEBLOCK_(\d+)\x00/g, (_m, idx) => codeBlocks[Number(idx)]);

  // Strip remaining markdown that Telegram HTML mode cannot render
  // Headings: ### Heading -> <b>Heading</b>
  processed = processed.replace(/^#{1,6}\s+(.+)$/gm, "<b>$1</b>");

  // Italic: *text* (single asterisk, not bold)
  processed = processed.replace(/(?<!\*)\*([^*]+)\*(?!\*)/g, "<i>$1</i>");

  // Strip image/link markdown: [text](url) -> text
  processed = processed.replace(/\[([^\]]+)\]\([^)]+\)/g, "$1");

  return processed;
}

// ---------------------------------------------------------------------------
// 5. Message chunking
// ---------------------------------------------------------------------------

const MAX_CHUNK_SIZE = 4000;

function chunkMessage(text: string): string[] {
  if (text.length <= MAX_CHUNK_SIZE) return [text];

  const chunks: string[] = [];
  let remaining = text;

  while (remaining.length > 0) {
    if (remaining.length <= MAX_CHUNK_SIZE) {
      chunks.push(remaining);
      break;
    }

    // Try to split on double-newline within the limit
    const window = remaining.slice(0, MAX_CHUNK_SIZE);
    const splitIdx = window.lastIndexOf("\n\n");

    if (splitIdx > 0) {
      chunks.push(remaining.slice(0, splitIdx));
      remaining = remaining.slice(splitIdx + 2);
    } else {
      // Hard-split at MAX_CHUNK_SIZE
      chunks.push(remaining.slice(0, MAX_CHUNK_SIZE));
      remaining = remaining.slice(MAX_CHUNK_SIZE);
    }
  }

  return chunks;
}

async function sendChunked(chatId: number, html: string): Promise<void> {
  const chunks = chunkMessage(html);
  for (const chunk of chunks) {
    try {
      await bot.api.sendMessage(chatId, chunk, { parse_mode: "HTML" });
    } catch (err) {
      // If HTML parsing fails, try sending as plain text
      console.error("Failed to send HTML message, retrying as plain text:", err);
      try {
        await bot.api.sendMessage(chatId, chunk);
      } catch (err2) {
        console.error("Failed to send plain text message:", err2);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// 6. WebSocket server (Bun.serve)
// ---------------------------------------------------------------------------

function handleCliMessage(raw: string, chatId: number): void {
  let msg: Record<string, unknown>;
  try {
    msg = JSON.parse(raw);
  } catch {
    console.error("Failed to parse CLI message:", raw.slice(0, 200));
    return;
  }

  const type = msg.type as string;

  switch (type) {
    case "system": {
      if (msg.subtype === "init") {
        cliState = "ready";
        console.log("CLI connected and initialized");
        // Drain the message queue now that CLI is ready
        drainQueue();
      }
      break;
    }

    case "assistant": {
      const message = msg.message as { content?: Array<{ type: string; text?: string }> } | undefined;
      if (message?.content) {
        const textParts = message.content
          .filter((c) => c.type === "text" && c.text)
          .map((c) => c.text as string);
        if (textParts.length > 0) {
          const html = markdownToHtml(textParts.join("\n"));
          sendChunked(chatId, html);
        }
      }
      break;
    }

    case "result": {
      messagesProcessed++;
      processing = false;
      console.log(`Turn complete (total processed: ${messagesProcessed})`);
      // Process next queued message if any
      drainQueue();
      break;
    }

    case "control_request": {
      const request = msg.request as {
        subtype?: string;
        tool_name?: string;
        input?: Record<string, unknown>;
        tool_use_id?: string;
      } | undefined;
      const requestId = msg.request_id as string;

      if (request?.subtype === "can_use_tool" && requestId) {
        handlePermissionRequest(chatId, requestId, request);
      }
      break;
    }

    default:
      // Ignore unknown message types (e.g. progress)
      break;
  }
}

function handlePermissionRequest(
  chatId: number,
  requestId: string,
  request: { tool_name?: string; input?: Record<string, unknown>; tool_use_id?: string }
): void {
  const toolName = request.tool_name ?? "unknown";
  const input = request.input ?? {};
  const toolUseId = request.tool_use_id ?? "";

  // Format a readable summary of the tool request
  let summary = `<b>Permission requested: ${escapeHtml(toolName)}</b>\n`;
  const inputStr = JSON.stringify(input, null, 2);
  if (inputStr.length > 500) {
    summary += `<pre>${escapeHtml(inputStr.slice(0, 500))}...</pre>`;
  } else {
    summary += `<pre>${escapeHtml(inputStr)}</pre>`;
  }

  const keyboard = new InlineKeyboard()
    .text("Approve", `perm_approve:${requestId}`)
    .text("Deny", `perm_deny:${requestId}`);

  // Set up auto-deny timeout
  const timer = setTimeout(() => {
    const pending = pendingPermissions.get(requestId);
    if (pending) {
      pendingPermissions.delete(requestId);
      sendPermissionResponse(requestId, "deny");
      bot.api
        .sendMessage(chatId, "Permission request timed out (5 min). Auto-denied.")
        .catch(console.error);
    }
  }, PERMISSION_TIMEOUT_MS);

  const pending: PendingPermission = {
    requestId,
    toolName,
    input,
    toolUseId,
    timer,
  };
  pendingPermissions.set(requestId, pending);

  bot.api
    .sendMessage(chatId, summary, { parse_mode: "HTML", reply_markup: keyboard })
    .then((sentMsg) => {
      const p = pendingPermissions.get(requestId);
      if (p) p.telegramMessageId = sentMsg.message_id;
    })
    .catch(console.error);
}

function sendPermissionResponse(requestId: string, behavior: "allow" | "deny"): void {
  if (!cliWs) return;

  const pending = pendingPermissions.get(requestId);
  const response: Record<string, unknown> = {
    type: "control_response",
    response: {
      subtype: "success",
      request_id: requestId,
      response:
        behavior === "allow"
          ? { behavior: "allow", updatedInput: pending?.input ?? {} }
          : { behavior: "deny" },
    },
  };

  cliWs.send(JSON.stringify(response) + "\n");
}

// The chat ID for relaying messages; set when user first interacts
let activeChatId: number | null = null;

const wsServer = Bun.serve({
  port: WS_PORT,
  hostname: "127.0.0.1",
  fetch(req, server) {
    // Upgrade WebSocket connections
    if (server.upgrade(req)) {
      return undefined;
    }
    return new Response("WebSocket upgrade required", { status: 426 });
  },
  websocket: {
    open(ws) {
      console.log("CLI WebSocket connected");
      cliWs = ws;
    },
    message(ws, data) {
      const raw = typeof data === "string" ? data : new TextDecoder().decode(data as unknown as ArrayBuffer);
      // NDJSON: may contain multiple lines
      const lines = raw.split("\n").filter((l) => l.trim());
      for (const line of lines) {
        handleCliMessage(line, activeChatId ?? 0);
      }
    },
    close() {
      console.log("CLI WebSocket disconnected");
      cliWs = null;
      cliState = "connecting";
    },
  },
});

console.log(`WebSocket server listening on ws://127.0.0.1:${WS_PORT}`);

// ---------------------------------------------------------------------------
// 7. CLI process management
// ---------------------------------------------------------------------------

function spawnCli(): void {
  cliState = "connecting";
  console.log("Spawning Claude CLI...");

  const proc = Bun.spawn(
    [
      "claude",
      "--sdk-url",
      `ws://127.0.0.1:${WS_PORT}`,
      "--print",
      "--output-format",
      "stream-json",
      "--input-format",
      "stream-json",
      "-p",
      "",
    ],
    {
      stdout: "pipe",
      stderr: "pipe",
      env: { ...process.env },
    }
  );

  cliProcess = proc;

  // Read stdout for diagnostics
  (async () => {
    if (!proc.stdout) return;
    const reader = proc.stdout.getReader();
    const decoder = new TextDecoder();
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        const text = decoder.decode(value, { stream: true });
        if (text.trim()) console.log("[CLI stdout]", text.trimEnd());
      }
    } catch {
      // Stream closed
    }
  })();

  // Read stderr for diagnostics
  (async () => {
    if (!proc.stderr) return;
    const reader = proc.stderr.getReader();
    const decoder = new TextDecoder();
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        const text = decoder.decode(value, { stream: true });
        if (text.trim()) console.error("[CLI stderr]", text.trimEnd());
      }
    } catch {
      // Stream closed
    }
  })();

  // Watch for exit and auto-restart
  proc.exited.then((code) => {
    console.error(`CLI process exited with code ${code}`);
    cliState = "error";
    cliProcess = null;
    cliWs = null;
    processing = false;

    console.log(`Restarting CLI in ${CLI_RESTART_DELAY_MS / 1000}s...`);
    setTimeout(spawnCli, CLI_RESTART_DELAY_MS);
  });
}

// ---------------------------------------------------------------------------
// 8. Message relay helpers
// ---------------------------------------------------------------------------

function sendUserMessage(text: string): void {
  if (!cliWs) {
    console.error("Cannot send user message: CLI WebSocket not connected");
    return;
  }

  const msg = {
    type: "user",
    message: {
      role: "user",
      content: text,
    },
    parent_tool_use_id: null,
    session_id: "",
  };

  cliWs.send(JSON.stringify(msg) + "\n");
  processing = true;
}

function drainQueue(): void {
  if (processing || messageQueue.length === 0) return;
  if (cliState !== "ready" || !cliWs) return;

  const next = messageQueue.shift()!;
  activeChatId = next.chatId;
  sendUserMessage(next.text);
}

// ---------------------------------------------------------------------------
// 9. Telegram bot setup
// ---------------------------------------------------------------------------

const bot = new Bot<BotContext>(TELEGRAM_BOT_TOKEN);

// Install parse-mode hydration
bot.use(hydrateReply);

// Auth middleware: reject non-owner users
bot.use(async (ctx, next) => {
  if (ctx.from && ctx.from.id !== allowedUserId) {
    await ctx.reply("Unauthorized. This bot is private.");
    return;
  }
  await next();
});

// ---------------------------------------------------------------------------
// 10. Bridge-native commands
// ---------------------------------------------------------------------------

bot.command("start", async (ctx) => {
  activeChatId = ctx.chat.id;
  const stateEmoji = cliState === "ready" ? "OK" : cliState === "connecting" ? "..." : "ERR";
  await ctx.reply(
    `<b>Soleur Telegram Bridge</b>\n\n` +
      `CLI status: <code>${cliState}</code> [${stateEmoji}]\n` +
      `Use /help to see available commands.\n\n` +
      `Send any message to talk to Claude.`,
    { parse_mode: "HTML" }
  );
});

bot.command("status", async (ctx) => {
  const uptimeSeconds = Math.floor((Date.now() - startTime) / 1000);
  const hours = Math.floor(uptimeSeconds / 3600);
  const minutes = Math.floor((uptimeSeconds % 3600) / 60);
  const seconds = uptimeSeconds % 60;
  const uptimeStr = `${hours}h ${minutes}m ${seconds}s`;

  await ctx.reply(
    `<b>Bridge Status</b>\n\n` +
      `CLI state: <code>${cliState}</code>\n` +
      `WebSocket: <code>${cliWs ? "connected" : "disconnected"}</code>\n` +
      `Processing: <code>${processing ? "yes" : "no"}</code>\n` +
      `Queued messages: <code>${messageQueue.length}</code>\n` +
      `Pending permissions: <code>${pendingPermissions.size}</code>\n` +
      `Messages processed: <code>${messagesProcessed}</code>\n` +
      `Uptime: <code>${uptimeStr}</code>`,
    { parse_mode: "HTML" }
  );
});

bot.command("cancel", async (ctx) => {
  await ctx.reply("Cancel is not implemented in v1. The current request will complete normally.");
});

bot.command("help", async (ctx) => {
  await ctx.reply(
    `<b>Available Commands</b>\n\n` +
      `/start - Welcome message with status\n` +
      `/status - CLI state, uptime, stats\n` +
      `/cancel - Cancel current request (v2)\n` +
      `/help - This message\n\n` +
      `Send any text message to talk to Claude. ` +
      `Tool permission requests will appear as inline buttons.`,
    { parse_mode: "HTML" }
  );
});

// ---------------------------------------------------------------------------
// 11. Permission callback handler
// ---------------------------------------------------------------------------

bot.on("callback_query:data", async (ctx) => {
  const data = ctx.callbackQuery.data;

  if (data.startsWith("perm_approve:") || data.startsWith("perm_deny:")) {
    const [action, requestId] = data.split(":", 2) as [string, string];
    const behavior = action === "perm_approve" ? "allow" : "deny";

    const pending = pendingPermissions.get(requestId);
    if (!pending) {
      await ctx.answerCallbackQuery({ text: "Request already handled or expired." });
      return;
    }

    // Clear timeout and remove from map
    clearTimeout(pending.timer);
    pendingPermissions.delete(requestId);

    // Send response to CLI
    sendPermissionResponse(requestId, behavior);

    // Update the Telegram message to reflect the decision
    const statusText = behavior === "allow" ? "APPROVED" : "DENIED";
    try {
      await ctx.editMessageText(
        `${behavior === "allow" ? "Approved" : "Denied"}: <b>${escapeHtml(pending.toolName)}</b> [${statusText}]`,
        { parse_mode: "HTML" }
      );
    } catch {
      // Message may have been deleted or too old
    }

    await ctx.answerCallbackQuery({
      text: `Tool ${behavior === "allow" ? "approved" : "denied"}.`,
    });
  }
});

// ---------------------------------------------------------------------------
// 12. Text message relay
// ---------------------------------------------------------------------------

bot.on("message:text", async (ctx) => {
  activeChatId = ctx.chat.id;
  const text = ctx.message.text;

  // If CLI is not ready, queue with feedback
  if (cliState !== "ready" || !cliWs) {
    messageQueue.push({ chatId: ctx.chat.id, text });
    await ctx.reply("Connecting to Claude... Your message is queued.");
    return;
  }

  // If currently processing another message, queue it
  if (processing) {
    messageQueue.push({ chatId: ctx.chat.id, text });
    await ctx.reply("Still processing previous request. Your message is queued.");
    return;
  }

  // Send directly
  sendUserMessage(text);
});

// ---------------------------------------------------------------------------
// 13. Health endpoint
// ---------------------------------------------------------------------------

const healthServer = Bun.serve({
  port: HEALTH_PORT,
  hostname: "0.0.0.0",
  fetch(req) {
    const url = new URL(req.url);
    if (url.pathname === "/health" && req.method === "GET") {
      return Response.json({
        status: "ok",
        cli: cliState,
        bot: "running",
        uptime: Math.floor((Date.now() - startTime) / 1000),
        messagesProcessed,
      });
    }
    return new Response("Not found", { status: 404 });
  },
});

console.log(`Health endpoint listening on http://0.0.0.0:${HEALTH_PORT}/health`);

// ---------------------------------------------------------------------------
// 14. Graceful shutdown
// ---------------------------------------------------------------------------

async function shutdown(signal: string): Promise<void> {
  console.log(`Received ${signal}, shutting down...`);

  // Stop Telegram bot polling
  try {
    await bot.stop();
  } catch {
    // Already stopped
  }

  // Clear all pending permission timeouts
  for (const [, pending] of pendingPermissions) {
    clearTimeout(pending.timer);
  }
  pendingPermissions.clear();

  // Kill CLI process
  if (cliProcess) {
    try {
      cliProcess.kill();
    } catch {
      // Already dead
    }
  }

  // Close servers
  wsServer.stop(true);
  healthServer.stop(true);

  console.log("Shutdown complete.");
  process.exit(0);
}

process.on("SIGINT", () => shutdown("SIGINT"));
process.on("SIGTERM", () => shutdown("SIGTERM"));

// ---------------------------------------------------------------------------
// 15. Startup
// ---------------------------------------------------------------------------

// Start WebSocket server first (already started above via Bun.serve),
// then spawn CLI, then start Telegram bot.
spawnCli();

bot.start({
  onStart: () => {
    console.log("Telegram bot started (long polling)");
    console.log(`Allowed user ID: ${allowedUserId}`);
  },
});
