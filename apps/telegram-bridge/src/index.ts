/**
 * Soleur Telegram Bridge
 *
 * Bridges a Telegram bot to a local Claude Code CLI process over stdio.
 * The CLI runs with --print --input-format stream-json --output-format stream-json
 * and exchanges NDJSON messages via stdin/stdout.
 *
 * Architecture:
 *   Telegram <-> grammY bot <-> Bridge class <-> stdin/stdout <-> Claude CLI
 */

import { Bot, type Context } from "grammy";
import { hydrateReply, type ParseModeFlavor } from "@grammyjs/parse-mode";
import type { BotApi } from "./types";
import { Bridge } from "./bridge";
import { createHealthServer } from "./health";

// ---------------------------------------------------------------------------
// 1. Configuration
// ---------------------------------------------------------------------------

const TELEGRAM_BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN;
const TELEGRAM_ALLOWED_USER_ID = process.env.TELEGRAM_ALLOWED_USER_ID;
const HEALTH_PORT = 8080;
const CLI_RESTART_DELAY_MS = 5_000;
const PLUGIN_DIR = process.env.SOLEUR_PLUGIN_DIR ?? "";
const STATUS_EDIT_INTERVAL_MS = 3_000; // Throttle status edits (Telegram allows ~20/min)
const TYPING_INTERVAL_MS = 4_000; // Re-send typing action every 4s (lasts 5s)

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

type BotContext = ParseModeFlavor<Context>;

// ---------------------------------------------------------------------------
// 3. Telegram bot + Bridge
// ---------------------------------------------------------------------------

const bot = new Bot<BotContext>(TELEGRAM_BOT_TOKEN);

// Adapt grammY's Api to our minimal BotApi interface
const botApi: BotApi = {
  sendMessage: (chatId, text, other?) => bot.api.sendMessage(chatId, text, other as any),
  editMessageText: (chatId, messageId, text) => bot.api.editMessageText(chatId, messageId, text),
  deleteMessage: (chatId, messageId) => bot.api.deleteMessage(chatId, messageId),
  sendChatAction: (chatId, action) => bot.api.sendChatAction(chatId, action as any),
};

const bridge = new Bridge(botApi, {
  statusEditIntervalMs: STATUS_EDIT_INTERVAL_MS,
  typingIntervalMs: TYPING_INTERVAL_MS,
});

// Process-level state (not part of Bridge)
let cliProcess: ReturnType<typeof Bun.spawn> | null = null;
const startTime = Date.now();

// ---------------------------------------------------------------------------
// 4. CLI process management (stdio transport)
// ---------------------------------------------------------------------------

let cliGeneration = 0;

function spawnCli(): void {
  bridge.cliState = "connecting";
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
  bridge.cliStdin = proc.stdin;
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
          if (line && thisGeneration === cliGeneration) bridge.handleCliMessage(line);
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
    bridge.cliState = "error";
    cliProcess = null;
    bridge.cliStdin = null;
    bridge.processing = false;
    bridge.initialResultReceived = false;

    // Clean up any active status message
    bridge.cleanupTurnStatus().catch(() => {});

    // Notify user if chat is active
    if (bridge.activeChatId) {
      bot.api
        .sendMessage(bridge.activeChatId, `CLI process exited (code ${code}). Restarting in ${CLI_RESTART_DELAY_MS / 1000}s...`)
        .catch(console.error);
    }

    console.log(`Restarting CLI in ${CLI_RESTART_DELAY_MS / 1000}s...`);
    setTimeout(spawnCli, CLI_RESTART_DELAY_MS);
  });

  // Fallback: if no system/init or result arrives within 5s, mark ready anyway.
  // The CLI in --print mode with an empty prompt may not send system/init.
  setTimeout(() => {
    if (bridge.cliState === "connecting" && cliProcess && !cliProcess.killed) {
      bridge.cliState = "ready";
      bridge.initialResultReceived = true;
      console.log("CLI marked ready (timeout fallback)");
      bridge.drainQueue();
    }
  }, 5000);
}

// ---------------------------------------------------------------------------
// 5. Telegram bot setup
// ---------------------------------------------------------------------------

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
// 6. Bridge-native commands
// ---------------------------------------------------------------------------

bot.command("start", async (ctx) => {
  bridge.activeChatId = ctx.chat.id;
  const stateEmoji = bridge.cliState === "ready" ? "OK" : bridge.cliState === "connecting" ? "..." : "ERR";
  await ctx.reply(
    `<b>Soleur Telegram Bridge</b>\n\n` +
      `CLI status: <code>${bridge.cliState}</code> [${stateEmoji}]\n` +
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
      `CLI state: <code>${bridge.cliState}</code>\n` +
      `Stdin: <code>${bridge.cliStdin ? "connected" : "disconnected"}</code>\n` +
      `Processing: <code>${bridge.processing ? "yes" : "no"}</code>\n` +
      `Queued messages: <code>${bridge.messageQueue.length}</code>\n` +
      `Messages processed: <code>${bridge.messagesProcessed}</code>\n` +
      `Uptime: <code>${uptimeStr}</code>`,
    { parse_mode: "HTML" }
  );
});

bot.command("new", async (ctx) => {
  bridge.activeChatId = ctx.chat.id;

  // Clear message queue and status
  bridge.messageQueue.length = 0;
  bridge.processing = false;
  bridge.initialResultReceived = false;
  await bridge.cleanupTurnStatus();

  // Kill the current CLI process -- the exit handler will auto-restart it
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
// 7. Text message relay
// ---------------------------------------------------------------------------

bot.on("message:text", async (ctx) => {
  bridge.activeChatId = ctx.chat.id;
  const text = ctx.message.text;

  // If CLI is not ready, queue with feedback
  if (bridge.cliState !== "ready" || !bridge.cliStdin) {
    bridge.messageQueue.push({ chatId: ctx.chat.id, text });
    await ctx.reply("Connecting to Claude... Your message is queued.");
    return;
  }

  // If currently processing another message, queue it
  if (bridge.processing) {
    bridge.messageQueue.push({ chatId: ctx.chat.id, text });
    await ctx.reply("Still processing previous request. Your message is queued.");
    return;
  }

  // Send directly
  bridge.sendUserMessage(text);
});

// ---------------------------------------------------------------------------
// 8. Health endpoint
// ---------------------------------------------------------------------------

const healthServer = createHealthServer(HEALTH_PORT, {
  get cliProcess() { return cliProcess; },
  get cliState() { return bridge.cliState; },
  messageQueue: bridge.messageQueue,
  startTime,
  get messagesProcessed() { return bridge.messagesProcessed; },
});

console.log(`Health endpoint listening on http://127.0.0.1:${HEALTH_PORT}/health`);

// ---------------------------------------------------------------------------
// 9. Graceful shutdown
// ---------------------------------------------------------------------------

async function shutdown(signal: string): Promise<void> {
  console.log(`Received ${signal}, shutting down...`);

  // Stop Telegram bot polling
  try {
    await bot.stop();
  } catch {
    // Already stopped
  }

  // Clean up status message
  await bridge.cleanupTurnStatus();

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
// 10. Startup
// ---------------------------------------------------------------------------

// Spawn CLI, then start Telegram bot.
spawnCli();

bot.start({
  onStart: () => {
    console.log("Telegram bot started (long polling)");
    console.log(`Allowed user ID: ${allowedUserId}`);
  },
});
