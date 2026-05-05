/**
 * Server-side guard for inbound `chat` content containing the
 * `claude-agent-sdk` CLI's `[Image #N]` text-editor placeholders.
 *
 * Wired into `apps/web-platform/server/ws-handler.ts` `chat` case so
 * the placeholders never reach the LLM, never reach the durable
 * `messages.content` record, and the user gets a structured error event
 * (errorCode `image_paste_lost`) so the UI can render a non-blocking
 * banner asking them to re-attach the image directly.
 *
 * Pure function: caller injects `send` (per-user WS dispatcher) and
 * `reportFallback` (Sentry mirror) so the helper is testable without
 * spinning the WS server up.
 */
import type { WSMessage } from "@/lib/types";
import { detectImagePlaceholders } from "@/lib/image-placeholder-detect";
import { reportSilentFallback } from "./observability";

export interface ImagePasteStripCtx {
  userId: string;
  conversationId: string | null;
  send: (msg: WSMessage) => void;
  reportFallback?: typeof reportSilentFallback;
}

const USER_FACING_MESSAGE =
  "Looks like an image got flattened to text. Re-attach the image so the agent can see it.";

export function stripAndReportImagePlaceholders(
  content: string,
  ctx: ImagePasteStripCtx,
): string {
  const { count, cleaned } = detectImagePlaceholders(content);
  if (count === 0) return content;

  ctx.send({
    type: "error",
    message: USER_FACING_MESSAGE,
    errorCode: "image_paste_lost",
  });

  (ctx.reportFallback ?? reportSilentFallback)(null, {
    feature: "command-center",
    op: "image-placeholder-strip",
    extra: { count, conversationId: ctx.conversationId },
  });

  return cleaned;
}
