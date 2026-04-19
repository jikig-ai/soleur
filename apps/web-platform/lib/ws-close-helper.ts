import type { WebSocket } from "ws";
import { WS_CLOSE_CODES, type ClosePreamble } from "@/lib/types";
import { warnSilentFallback } from "@/server/observability";

/**
 * Close-code labels. Raw `ws.close(40XX, …)` is banned outside this helper —
 * enforced by a pre-push grep (see plan Phase 1).
 */
const CLOSE_CODE_LABELS: Record<number, string> = {
  [WS_CLOSE_CODES.CONCURRENCY_CAP]: "CONCURRENCY_CAP",
  [WS_CLOSE_CODES.TIER_CHANGED]: "TIER_CHANGED",
};

const PREAMBLE_SIZE_WARN_BYTES = 2048;

// ws.WebSocket OPEN = 1; avoid importing the WebSocket constant on the client
// bundle by duck-typing on readyState.
const WS_OPEN = 1;

/**
 * Send a JSON preamble, then close the socket with a labeled code. The
 * preamble carries the authoritative payload (tier, counts) — the close
 * code is secondary because clean-close delivery over TCP reset is best-effort.
 *
 * Callers must use this helper for 4010/4011; a lefthook grep enforces it.
 */
export function closeWithPreamble(
  ws: WebSocket,
  code: number,
  preamble: ClosePreamble,
): void {
  if (ws.readyState !== WS_OPEN) return;

  const body = JSON.stringify(preamble);
  if (body.length > PREAMBLE_SIZE_WARN_BYTES) {
    warnSilentFallback(null, {
      feature: "concurrency",
      op: "closeWithPreamble",
      message: "close preamble exceeds 2 KiB",
      extra: { code, size: body.length, type: preamble.type },
    });
  }

  try {
    ws.send(body);
  } catch {
    // Best-effort — still attempt close so the client unblocks.
  }
  ws.close(code, CLOSE_CODE_LABELS[code] ?? String(code));
}
