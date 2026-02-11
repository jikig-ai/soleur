import type { BotApi, CliState, QueuedMessage, TurnStatus } from "./types";
import {
  markdownToHtml,
  chunkMessage,
  stripHtmlTags,
  formatStatusText,
} from "./helpers";

export interface BridgeConfig {
  statusEditIntervalMs: number;
  typingIntervalMs: number;
}

const DEFAULT_CONFIG: BridgeConfig = {
  statusEditIntervalMs: 3_000,
  typingIntervalMs: 4_000,
};

export class Bridge {
  private api: BotApi;
  private config: BridgeConfig;

  // State
  cliState: CliState = "connecting";
  cliStdin: { write(data: string | Uint8Array): number | Promise<number> } | null = null;
  processing = false;
  initialResultReceived = false;
  messagesProcessed = 0;
  activeChatId: number | null = null;
  turnStatus: TurnStatus | null = null;
  messageQueue: QueuedMessage[] = [];

  constructor(api: BotApi, config?: Partial<BridgeConfig>) {
    this.api = api;
    this.config = { ...DEFAULT_CONFIG, ...config };
  }

  async sendChunked(chatId: number, html: string): Promise<void> {
    const chunks = chunkMessage(html);
    for (const chunk of chunks) {
      try {
        await this.api.sendMessage(chatId, chunk, { parse_mode: "HTML" });
      } catch {
        // HTML parsing failed (likely unclosed tags from chunking) -- send as plain text
        try {
          await this.api.sendMessage(chatId, stripHtmlTags(chunk));
        } catch (err2) {
          console.error("Failed to send message:", err2);
        }
      }
    }
  }

  async startTurnStatus(chatId: number): Promise<void> {
    // Clean up any existing status
    await this.cleanupTurnStatus();

    // Start periodic typing indicator immediately (before message send)
    const typingTimer = setInterval(() => {
      this.api.sendChatAction(chatId, "typing").catch(() => {});
    }, this.config.typingIntervalMs);
    this.api.sendChatAction(chatId, "typing").catch(() => {});

    // Create status object with messageId=0 (set once sendMessage resolves)
    this.turnStatus = {
      chatId,
      messageId: 0,
      startTime: Date.now(),
      tools: [],
      lastEditTime: Date.now(),
      typingTimer,
    };

    // Send initial status message, then backfill the messageId
    try {
      const sent = await this.api.sendMessage(chatId, "Thinking...");
      if (this.turnStatus && this.turnStatus.typingTimer === typingTimer) {
        this.turnStatus.messageId = sent.message_id;
      }
    } catch (err) {
      console.error("Failed to send status message:", err);
    }
  }

  recordToolUse(toolName: string): void {
    if (!this.turnStatus || this.turnStatus.messageId === 0) return;

    // Deduplicate consecutive same-tool entries
    if (this.turnStatus.tools[this.turnStatus.tools.length - 1] !== toolName) {
      this.turnStatus.tools.push(toolName);
    }

    // Throttle edits: only update if enough time has passed
    if (Date.now() - this.turnStatus.lastEditTime >= this.config.statusEditIntervalMs) {
      this.flushStatusEdit();
    }
  }

  flushStatusEdit(): void {
    if (!this.turnStatus || this.turnStatus.messageId === 0) return;
    this.turnStatus.lastEditTime = Date.now();

    const text = formatStatusText(this.turnStatus);
    this.api
      .editMessageText(this.turnStatus.chatId, this.turnStatus.messageId, text)
      .catch((err) => console.error("Failed to edit status message:", err));
  }

  async cleanupTurnStatus(): Promise<void> {
    const status = this.turnStatus;
    if (!status) return;

    // Null out first to prevent concurrent calls from double-deleting
    this.turnStatus = null;
    clearInterval(status.typingTimer);

    // Delete the status message (if it was ever sent)
    if (status.messageId !== 0) {
      try {
        await this.api.deleteMessage(status.chatId, status.messageId);
      } catch {
        // Message may already be deleted
      }
    }
  }

  handleCliMessage(raw: string): void {
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
        if (msg.subtype === "init" && this.cliState === "connecting") {
          this.cliState = "ready";
          console.log("CLI initialized (system/init received)");
          this.drainQueue();
        }
        break;
      }

      case "assistant": {
        if (!this.activeChatId) break;

        const message = msg.message as {
          content?: Array<{ type: string; text?: string; name?: string; input?: Record<string, unknown> }>;
        } | undefined;
        if (!message?.content) break;

        // Record tool uses for the status message
        const toolUses = message.content.filter((c) => c.type === "tool_use");
        for (const tool of toolUses) {
          this.recordToolUse(tool.name ?? "unknown");
        }

        // Send text content
        const textParts = message.content
          .filter((c) => c.type === "text" && c.text)
          .map((c) => c.text as string);
        if (textParts.length > 0) {
          const html = markdownToHtml(textParts.join("\n"));
          // Clean up status independently -- never block response delivery
          this.cleanupTurnStatus().catch((err) => console.error("Status cleanup failed:", err));
          this.sendChunked(this.activeChatId!, html).catch((err) => console.error("sendChunked failed:", err));
        }
        break;
      }

      case "result": {
        if (!this.initialResultReceived) {
          this.initialResultReceived = true;
          this.cliState = "ready";
          console.log("CLI ready (initial result received)");
          this.drainQueue();
          break;
        }
        // Turn complete
        this.messagesProcessed++;
        this.processing = false;
        console.log(`Turn complete (total processed: ${this.messagesProcessed})`);

        // Clean up status message if still present (no text response was sent)
        this.cleanupTurnStatus().catch((err) => console.error("Status cleanup failed:", err));

        this.drainQueue();
        break;
      }

      default:
        if (type) console.log(`[CLI msg] type=${type}`, JSON.stringify(msg).slice(0, 200));
        break;
    }
  }

  sendUserMessage(text: string): void {
    if (!this.cliStdin) {
      console.error("Cannot send user message: CLI stdin not available");
      return;
    }

    const msg = {
      type: "user",
      message: { role: "user", content: text },
      parent_tool_use_id: null,
      session_id: "",
    };

    const line = JSON.stringify(msg) + "\n";
    console.log(`[Bridge -> CLI] Sending user message (${text.length} chars)`);
    this.processing = true;

    // Start the status message + typing indicator
    if (this.activeChatId) {
      this.startTurnStatus(this.activeChatId).catch((err) => console.error("Failed to start turn status:", err));
    }

    try {
      const result = this.cliStdin.write(line);
      if (result instanceof Promise) {
        result.catch((err) => {
          console.error("Failed to write user message to CLI stdin:", err);
          this.processing = false;
          this.cleanupTurnStatus().catch(() => {});
          this.drainQueue();
        });
      }
    } catch (err) {
      console.error("Failed to write user message to CLI stdin:", err);
      this.processing = false;
      this.cleanupTurnStatus().catch(() => {});
      this.drainQueue();
    }
  }

  drainQueue(): void {
    if (this.processing || this.messageQueue.length === 0) return;
    if (this.cliState !== "ready" || !this.cliStdin) return;

    const next = this.messageQueue.shift()!;
    this.activeChatId = next.chatId;
    this.sendUserMessage(next.text);
  }
}
