import type { AttachmentRef } from "@/lib/types";
import { reportSilentFallback } from "@/lib/client-observability";

// Client module: report through the client shim, never `@/server/*` (pino would
// enter the browser bundle and trip the client/server boundary gate).

const FEATURE = "kb-chat";
const DEFAULT_DEADLINE_MS = 45_000;

export interface FirstRunLive {
  conversationId: string | null;
  connected: boolean;
  sessionConfirmed: boolean;
}

export interface FirstRunSendDeps {
  msgParam: string | null;
  files: File[];
  /** The id the files are uploaded under (the pending/real conversation id). */
  conversationId: string | null;
  /** Read AFTER the upload: the socket may have dropped or re-minted its id. */
  getLive: () => FirstRunLive;
  upload: (files: File[], conversationId: string) => Promise<AttachmentRef[]>;
  send: (content: string, attachments?: AttachmentRef[]) => void;
  /** Upload deadline; neither the presign fetch nor the storage PUT has a timeout. */
  deadlineMs?: number;
}

const TIMED_OUT = Symbol("first-run-upload-timeout");

/** Re-wrap with a sanitized message: upload errors can embed signed-URL tokens. */
function sanitized(stage: string, err: unknown): Error {
  const original = err instanceof Error ? err.message : String(err);
  return new Error(`[kb-chat] ${stage} (original message length ${original.length})`);
}

/**
 * First-run (Command Center) send: upload staged files FIRST, then send ONE
 * message carrying the text and the attachment refs. Never rejects. Returns
 * `retry: true` when the session went away during the upload so the caller can
 * re-arm once under the new session.
 */
export async function runFirstRunSend(
  d: FirstRunSendDeps,
): Promise<{ sent: boolean; retry: boolean }> {
  const { msgParam, files } = d;
  try {
    if (files.length === 0) {
      if (msgParam) {
        d.send(msgParam);
        return { sent: true, retry: false };
      }
      return { sent: false, retry: false };
    }

    const attempted = files.length;
    let uploaded: AttachmentRef[] = [];

    if (!d.conversationId) {
      // Caller waits for an id before passing files; defensive only.
      reportSilentFallback(new Error("[kb-chat] first-run send dropped (no conversation id)"), {
        feature: FEATURE,
        op: "first-run-send-dropped",
        extra: { attempted },
      });
      return { sent: false, retry: true };
    }

    const deadlineMs = d.deadlineMs ?? DEFAULT_DEADLINE_MS;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const convId = d.conversationId;
    // async wrapper: a synchronous throw from `upload` becomes a rejection and
    // takes the all-failed path (text still sent) instead of the batch catch.
    const uploadPromise = (async () => d.upload(files, convId))();
    // A late rejection after the deadline must not surface as unhandled.
    uploadPromise.catch(() => {});
    const deadline = new Promise<typeof TIMED_OUT>((resolve) => {
      timer = setTimeout(() => resolve(TIMED_OUT), deadlineMs);
    });

    try {
      const raced = await Promise.race([uploadPromise, deadline]);
      if (raced === TIMED_OUT) {
        reportSilentFallback(new Error("[kb-chat] first-run upload timed out"), {
          feature: FEATURE,
          op: "first-run-upload-timeout",
          extra: { attempted, deadlineMs },
        });
      } else {
        uploaded = raced;
        if (uploaded.length < attempted) {
          reportSilentFallback(new Error("[kb-chat] first-run upload partially failed"), {
            feature: FEATURE,
            op: "first-run-upload-failed",
            extra: { attempted, uploaded: uploaded.length },
          });
        }
      }
    } catch (err) {
      reportSilentFallback(sanitized("first-run upload failed", err), {
        feature: FEATURE,
        op: "first-run-upload-failed",
        extra: { attempted, uploaded: 0 },
      });
    } finally {
      if (timer) clearTimeout(timer);
    }

    // Nothing to deliver: failure already captured, do not re-arm.
    if (uploaded.length === 0 && !msgParam) return { sent: false, retry: false };

    // Re-read live state AFTER the upload. `connected` + unchanged id alone is
    // not enough: a reconnect resets `sessionConfirmed` but leaves the old id
    // until the next session_started, and the refs carry the old id prefix.
    const live = d.getLive();
    const ready =
      live.connected && live.sessionConfirmed && live.conversationId === d.conversationId;
    if (!ready) {
      reportSilentFallback(new Error("[kb-chat] first-run send dropped (session changed)"), {
        feature: FEATURE,
        op: "first-run-send-dropped",
        extra: {
          attempted,
          uploaded: uploaded.length,
          connected: live.connected,
          sessionConfirmed: live.sessionConfirmed,
          idChanged: live.conversationId !== d.conversationId,
        },
      });
      return { sent: false, retry: true };
    }

    if (uploaded.length > 0) {
      d.send(msgParam ?? "", uploaded);
    } else if (msgParam) {
      d.send(msgParam);
    }
    return { sent: true, retry: false };
  } catch (err) {
    reportSilentFallback(sanitized("first-run batch failed", err), {
      feature: FEATURE,
      op: "first-run-upload-failed",
      extra: { attempted: files.length, stage: "batch" },
    });
    return { sent: false, retry: false };
  }
}
