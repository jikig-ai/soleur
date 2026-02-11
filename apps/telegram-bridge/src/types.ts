export type CliState = "connecting" | "ready" | "error";

export interface QueuedMessage {
  chatId: number;
  text: string;
}

export interface TurnStatus {
  chatId: number;
  messageId: number; // 0 until sendMessage resolves
  startTime: number;
  tools: string[]; // Tool names seen this turn
  lastEditTime: number; // Last time we edited the status message
  typingTimer: Timer; // Periodic sendChatAction("typing")
}

// Minimal interface for the subset of bot.api we actually use
export interface BotApi {
  sendMessage(
    chatId: number,
    text: string,
    other?: Record<string, unknown>,
  ): Promise<{ message_id: number }>;
  editMessageText(
    chatId: number,
    messageId: number,
    text: string,
  ): Promise<unknown>;
  deleteMessage(chatId: number, messageId: number): Promise<true>;
  sendChatAction(chatId: number, action: string): Promise<true>;
}
