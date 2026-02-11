/**
 * Soleur Telegram Bridge
 *
 * Bridges a Telegram bot to a local Claude Code CLI process over stdio.
 * The CLI runs with --print --input-format stream-json --output-format stream-json
 * and exchanges NDJSON messages via stdin/stdout.
 *
 * Architecture:
 *   Telegram <-> grammY bot <-> Bridge logic <-> stdin/stdout <-> Claude CLI
 */

import { Bot, type Context } from "grammy";
import { hydrateReply, type ParseModeFlavor } from "@grammyjs/parse-mode";

// ---------------------------------------------------------------------------
// 1. Configuration
// ---------------------------------------------------------------------------

const TELEGRAM_BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN;
const TELEGRAM_ALLOWED_USER_ID = process.env.TELEGRAM_ALLOWED_USER_ID;
const HEALTH_PORT = 8080;
const CLI_RESTART_DELAY_MS = 5_000;
const PLUGIN_DIR = process.env.SOLEUR_PLUGIN_DIR ?? "";

if (!TELEGRAM_BOT_TOKEN) {
  console.error("FATAL: TELEGRAM_BOT_TOKEN is not set");
  process.exit(1);
}
if (!TELEGRAM_ALLOWED_USER_ID) {
  console.error("FATAL: TELEGRAM_ALLOWED_USER_ID is not set");
  process.exit(1);
}

const allowedUserId = Number(TELEGRAM_ALLOWED_USER_ID);
if (Number.isNaN(allowedUserId)) {
  console.error("FATAL: TELEGRAM_ALLOWED_USER_ID is not a valid number");
  process.exit(1);
}

// ---------------------------------------------------------------------------
// 2. Types
// ---------------------------------------------------------------------------

type CliState = "connecting" | "ready" | "error";

type BotContext = ParseModeFlavor<Context>;

interface QueuedMessage {
  chatId: number;
  text: string;
}

// ---------------------------------------------------------------------------
// 3. Global state
// ---------------------------------------------------------------------------

let cliState: CliState = "connecting";
let cliStdin: { write(data: string | Uint8Array): number | Promise<number> } | null = null;
let cliProcess: ReturnType<typeof Bun.spawn> | null = null;
let messagesProcessed = 0;
let startTime = Date.now();
let processing = false;
let initialResultReceived = false;
const messageQueue: QueuedMessage[] = [];

// The chat ID for relaying messages; set when user first interacts
let activeChatId: number | null = null;

// Status message tracking for the current turn
let statusMessageId: number | null = null;
let turnStartTime = 0;
let toolCallsSeen: string[] = [];
let lastStatusUpdate = 0;
let typingInterval: ReturnType<typeof setInterval> | null = null;

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

function stripHtmlTags(html: string): string {
  return html.replace(/<[^>]+>/g, "");
}

async function sendChunked(chatId: number, html: string): Promise<void> {
  const chunks = chunkMessage(html);
  for (const chunk of chunks) {
    try {
      await bot.api.sendMessage(chatId, chunk, { parse_mode: "HTML" });
    } catch {
      // HTML parsing failed (likely unclosed tags from chunking) -- send as plain text
      try {
        await bot.api.sendMessage(chatId, stripHtmlTags(chunk));
      } catch (err2) {
        console.error("Failed to send message:", err2);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// 6. CLI message handler
// ---------------------------------------------------------------------------

function handleCliMessage(raw: string): void {
  let msg: Record<string, unknown>;
  try {
    msg = JSON.parse(raw);
  } catch {
    // Not JSON -- could be plain text output from CLI startup
    if (raw.trim()) console.log("[CLI]", raw.trimEnd());
    return;
  }

  const type = msg.type as string;

  switch (type) {
    case "system": {
      if (msg.subtype === "init" && cliState === "connecting") {
        cliState = "ready";
        console.log("CLI initialized (system/init received)");
        drainQueue();
      }
      break;
    }

    case "assistant": {
      if (!activeChatId) break; // No user to send to yet

      const message = msg.message as {
        content?: Array<{ type: string; text?: string; name?: string; input?: Record<string, unknown> }>;
      } | undefined;
      if (!message?.content) break;

      // Track tool-use and update the single status message (throttled)
      const toolUses = message.content.filter((c) => c.type === "tool_use");
      for (const tool of toolUses) {
        toolCallsSeen.push(tool.name ?? "unknown");
      }
      if (toolUses.length > 0) {
        updateStatusMessage().catch((err) => console.error("Status update failed:", err));
      }

      // Send text content
      const textParts = message.content
        .filter((c) => c.type === "text" && c.text)
        .map((c) => c.text as string);
      if (textParts.length > 0) {
        const html = markdownToHtml(textParts.join("\n"));
        sendChunked(activeChatId, html).catch((err) => console.error("sendChunked failed:", err));
      }
      break;
    }

    case "result": {
      if (!initialResultReceived) {
        // Initial empty-prompt result -- CLI is now truly ready
        initialResultReceived = true;
        cliState = "ready";
        console.log("CLI ready (initial result received)");
        if (activeChatId) {
          bot.api
            .sendMessage(activeChatId, "Ready.")
            .catch(console.error);
        }
        drainQueue();
        break;
      }
      // Turn complete -- clean up status message and reset state
      deleteStatusMessage().catch(() => {});
      resetTurnState();
      messagesProcessed++;
      processing = false;
      console.log(`Turn complete (total processed: ${messagesProcessed})`);
      drainQueue();
      break;
    }

    default:
      // Log unknown types for debugging
      if (type) console.log(`[CLI msg] type=${type}`, JSON.stringify(msg).slice(0, 200));
      break;
  }
}

// ---------------------------------------------------------------------------
// 7. CLI process management (stdio transport)
// ---------------------------------------------------------------------------

let cliGeneration = 0;

function spawnCli(): void {
  cliState = "connecting";
  console.log("Spawning Claude CLI (stdio mode)...");

  const cliArgs = [
    "claude",
    "--print",
    "--verbose",
    "--output-format", "stream-json",
    "--input-format", "stream-json",
    // Auto-approve all tool operations. In headless mode, control_request messages
    // for Bash commands cause the bridge to hang since the approval UI is unreliable.
    "--dangerously-skip-permissions",
    "--model", "claude-opus-4-6",
    "-p", "",
  ];

  // Load Soleur plugin if path provided
  if (PLUGIN_DIR) {
    cliArgs.splice(1, 0, "--plugin-dir", PLUGIN_DIR);
  }

  const proc = Bun.spawn(
    cliArgs,
    {
      stdin: "pipe",
      stdout: "pipe",
      stderr: "pipe",
      env: (() => {
        const { TELEGRAM_BOT_TOKEN: _, TELEGRAM_ALLOWED_USER_ID: __, ...safeEnv } = process.env;
        return safeEnv;
      })(),
    }
  );

  cliProcess = proc;
  cliStdin = proc.stdin;
  const thisGeneration = ++cliGeneration;

  // Read stdout for NDJSON messages (scoped buffer per generation)
  (async () => {
    if (!proc.stdout) return;
    const reader = proc.stdout.getReader();
    const decoder = new TextDecoder();
    let buffer = "";
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done || thisGeneration !== cliGeneration) break;
        const chunk = decoder.decode(value, { stream: true });
        buffer += chunk;

        // Process complete lines
        let newlineIdx: number;
        while ((newlineIdx = buffer.indexOf("\n")) !== -1) {
          const line = buffer.slice(0, newlineIdx).trim();
          buffer = buffer.slice(newlineIdx + 1);
          if (line && thisGeneration === cliGeneration) handleCliMessage(line);
        }
      }
    } catch (err) {
      if (thisGeneration === cliGeneration) console.error("CLI stdout reader error:", err);
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
    cliStdin = null;
    processing = false;
    initialResultReceived = false;
    resetTurnState();

    // Notify user if chat is active
    if (activeChatId) {
      bot.api
        .sendMessage(activeChatId, `CLI process exited (code ${code}). Restarting in ${CLI_RESTART_DELAY_MS / 1000}s...`)
        .catch(console.error);
    }

    console.log(`Restarting CLI in ${CLI_RESTART_DELAY_MS / 1000}s...`);
    setTimeout(spawnCli, CLI_RESTART_DELAY_MS);
  });

  // Fallback: if no system/init or result arrives within 5s, mark ready anyway.
  // The CLI in --print mode with an empty prompt may not send system/init.
  setTimeout(() => {
    if (cliState === "connecting" && cliProcess && !cliProcess.killed) {
      cliState = "ready";
      initialResultReceived = true;
      console.log("CLI marked ready (timeout fallback)");
      drainQueue();
    }
  }, 5000);
}

// ---------------------------------------------------------------------------
// 8. Status message helpers
// ---------------------------------------------------------------------------

const STATUS_UPDATE_INTERVAL_MS = 3_000;
const TYPING_ACTION_INTERVAL_MS = 4_000;

function buildStatusText(): string {
  const elapsed = Math.floor((Date.now() - turnStartTime) / 1000);
  if (toolCallsSeen.length === 0) {
    return `Thinking... (${elapsed}s)`;
  }
  // Deduplicate tool names, keeping order of first appearance
  const unique = [...new Set(toolCallsSeen)];
  return `Working... (${elapsed}s · ${unique.join(", ")})`;
}

function resetTurnState(): void {
  if (typingInterval) {
    clearInterval(typingInterval);
    typingInterval = null;
  }
  statusMessageId = null;
  turnStartTime = 0;
  toolCallsSeen = [];
  lastStatusUpdate = 0;
}

async function deleteStatusMessage(): Promise<void> {
  if (!activeChatId || !statusMessageId) return;
  try {
    await bot.api.deleteMessage(activeChatId, statusMessageId);
  } catch {
    // Message may already be deleted or too old
  }
  statusMessageId = null;
}

async function updateStatusMessage(): Promise<void> {
  if (!activeChatId || !statusMessageId) return;
  const now = Date.now();
  if (now - lastStatusUpdate < STATUS_UPDATE_INTERVAL_MS) return;

  lastStatusUpdate = now;
  const text = buildStatusText();
  try {
    await bot.api.editMessageText(activeChatId, statusMessageId, text);
  } catch {
    // Edit may fail if message was deleted or content unchanged
  }
}

// ---------------------------------------------------------------------------
// 9. Message relay helpers
// ---------------------------------------------------------------------------

function sendUserMessage(text: string): void {
  if (!cliStdin) {
    console.error("Cannot send user message: CLI stdin not available");
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

  const line = JSON.stringify(msg) + "\n";
  console.log(`[Bridge -> CLI] Sending user message (${text.length} chars)`);
  processing = true;
  turnStartTime = Date.now();
  toolCallsSeen = [];
  lastStatusUpdate = 0;

  // Send initial status message and start typing indicator
  if (activeChatId) {
    const chatId = activeChatId;
    bot.api.sendChatAction(chatId, "typing").catch(() => {});
    bot.api
      .sendMessage(chatId, "Thinking...")
      .then((sent) => {
        statusMessageId = sent.message_id;
        lastStatusUpdate = Date.now();
      })
      .catch((err) => console.error("Failed to send status message:", err));

    typingInterval = setInterval(() => {
      bot.api.sendChatAction(chatId, "typing").catch(() => {});
    }, TYPING_ACTION_INTERVAL_MS);
  }

  try {
    const result = cliStdin.write(line);
    if (result instanceof Promise) {
      result.catch((err) => {
        console.error("Failed to write user message to CLI stdin:", err);
        processing = false;
        resetTurnState();
        drainQueue();
      });
    }
  } catch (err) {
    console.error("Failed to write user message to CLI stdin:", err);
    processing = false;
    resetTurnState();
    drainQueue();
  }
}

function drainQueue(): void {
  if (processing || messageQueue.length === 0) return;
  if (cliState !== "ready" || !cliStdin) return;

  const next = messageQueue.shift()!;
  activeChatId = next.chatId;
  sendUserMessage(next.text);
}

// ---------------------------------------------------------------------------
// 10. Telegram bot setup
// ---------------------------------------------------------------------------

const bot = new Bot<BotContext>(TELEGRAM_BOT_TOKEN);

// Install parse-mode hydration
bot.use(hydrateReply);

// Auth middleware: reject non-owner users and non-private chats
bot.use(async (ctx, next) => {
  if (ctx.chat && ctx.chat.type !== "private") {
    await ctx.reply("This bot only works in private chats.");
    return;
  }
  if (ctx.from && ctx.from.id !== allowedUserId) {
    await ctx.reply("Unauthorized. This bot is private.");
    return;
  }
  await next();
});

// ---------------------------------------------------------------------------
// 11. Bridge-native commands
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
      `Stdin: <code>${cliStdin ? "connected" : "disconnected"}</code>\n` +
      `Processing: <code>${processing ? "yes" : "no"}</code>\n` +
      `Queued messages: <code>${messageQueue.length}</code>\n` +
      `Messages processed: <code>${messagesProcessed}</code>\n` +
      `Uptime: <code>${uptimeStr}</code>`,
    { parse_mode: "HTML" }
  );
});

bot.command("new", async (ctx) => {
  activeChatId = ctx.chat.id;

  // Clear message queue
  messageQueue.length = 0;
  processing = false;
  initialResultReceived = false;

  // Kill the current CLI process — the exit handler will auto-restart it
  if (cliProcess) {
    await ctx.reply("Clearing session and restarting CLI...");
    try {
      cliProcess.kill();
    } catch (err) {
      console.error("Failed to kill CLI process:", err);
    }
  } else {
    await ctx.reply("No CLI process running. Spawning fresh...");
    spawnCli();
  }
});

bot.command("help", async (ctx) => {
  await ctx.reply(
    `<b>Available Commands</b>\n\n` +
      `/start - Welcome message with status\n` +
      `/status - CLI state, uptime, stats\n` +
      `/new - Clear session and restart CLI\n` +
      `/help - This message\n\n` +
      `Send any text message to talk to Claude.`,
    { parse_mode: "HTML" }
  );
});

// ---------------------------------------------------------------------------
// 12. Text message relay
// ---------------------------------------------------------------------------

bot.on("message:text", async (ctx) => {
  activeChatId = ctx.chat.id;
  const text = ctx.message.text;

  // If CLI is not ready, queue with feedback
  if (cliState !== "ready" || !cliStdin) {
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
  hostname: "127.0.0.1",
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

console.log(`Health endpoint listening on http://127.0.0.1:${HEALTH_PORT}/health`);

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

  // Kill CLI process
  if (cliProcess) {
    try {
      cliProcess.kill();
    } catch {
      // Already dead
    }
  }

  // Close health server
  healthServer.stop(true);

  console.log("Shutdown complete.");
  process.exit(0);
}

process.on("SIGINT", () => shutdown("SIGINT"));
process.on("SIGTERM", () => shutdown("SIGTERM"));

// ---------------------------------------------------------------------------
// 15. Startup
// ---------------------------------------------------------------------------

// Spawn CLI, then start Telegram bot.
spawnCli();

bot.start({
  onStart: () => {
    console.log("Telegram bot started (long polling)");
    console.log(`Allowed user ID: ${allowedUserId}`);
  },
});
