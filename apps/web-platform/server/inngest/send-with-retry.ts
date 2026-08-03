import * as Sentry from "@sentry/nextjs";

import logger from "@/server/logger";

const MAX_RETRIES = 2;
const BASE_DELAY_MS = 500;

export function isTransientFetchError(err: unknown): boolean {
  if (err instanceof TypeError && err.message === "fetch failed") return true;
  if (err instanceof DOMException && err.name === "TimeoutError") return true;
  if (
    err instanceof Error &&
    "code" in err &&
    typeof (err as { code: unknown }).code === "string"
  ) {
    const code = (err as { code: string }).code;
    return [
      "UND_ERR_CONNECT_TIMEOUT",
      "UND_ERR_SOCKET",
      "ECONNRESET",
      "ECONNREFUSED",
      "ENOTFOUND",
      "ENETDOWN",
    ].includes(code);
  }
  return false;
}

// Retries inngest.send() on transient network failures (the hop to the
// co-located inngest-server via host.docker.internal:8288 can blip during
// deploy restarts).
//
// NOTE: retries only help a TRANSIENT fault. When the dispatch target is
// simply not listening, every attempt is refused and the caller's failure is
// structural, not transient — see #7144, where the target host never bound
// :8288 at all and this retried into a closed port for ~3 days.
export async function sendInngestWithRetry(
  fn: () => Promise<unknown>,
  context: { feature: string; deliveryId?: string | null; eventId?: string },
): Promise<void> {
  for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
    try {
      await fn();
      return;
    } catch (err) {
      if (attempt < MAX_RETRIES && isTransientFetchError(err)) {
        logger.warn(
          { attempt: attempt + 1, maxAttempts: MAX_RETRIES + 1, ...context, err },
          `${context.feature}: inngest.send transient failure — retrying (${attempt + 1}/${MAX_RETRIES + 1})`,
        );
        await new Promise((r) => setTimeout(r, BASE_DELAY_MS * 2 ** attempt));
        continue;
      }

      // TERMINAL. Every path out of this function that is not a success lands here, and
      // until #7144 it emitted NOTHING: the warn above is gated on
      // `attempt < MAX_RETRIES && isTransientFetchError(err)`, so the last attempt — and
      // any non-transient error on the first — rethrew silently.
      //
      // Two failures that produces. A 401 (what a post-reconcile signing-key mismatch
      // looks like) matches none of isTransientFetchError's cases, so it neither retries
      // nor warns: zero rows, and the econnrefused column drops to 0 after a repoint,
      // which reads as FIXED while send_failed keeps climbing. And an EXHAUSTED transient
      // failure — the actual #7144 shape, ECONNREFUSED into a closed port for ~3 days —
      // logged only its first two attempts and went quiet on the one that gave up.
      //
      // Emitting HERE rather than at a call site is deliberate: there are 8 call sites,
      // and the two that do capture (resend-inbound, github) both capture the ORIGINAL
      // instance immediately after `logger.error({ err })` has already mirrored it to
      // Sentry via the pino hook — which marks that instance caught, so the tagged call
      // early-returns and its op tag never lands. That is why `op:inngest-send` measured
      // 0 issues while dispatch was failing continuously.
      const attempts = attempt + 1;
      const transient = isTransientFetchError(err);
      const summary = `${context.feature}: inngest.send failed after ${attempts} attempt(s) — event was NOT dispatched`;

      // `err` stays an object, never String(err): pino's cause-flattening is the only
      // reason the underlying `connect ECONNREFUSED <host>:<port>` reaches the log line.
      logger.error({ ...context, attempts, transient, err }, summary);

      // A distinct wrapper, not `err`. Capturing `err` here would be swallowed by the
      // same already-captured dedup described above the moment anything mirrors it.
      // `cause` keeps the real chain attached — linkedErrorsIntegration walks it.
      Sentry.captureException(new Error(summary, { cause: err }), {
        tags: { feature: context.feature, op: "inngest-send" },
        extra: {
          attempts,
          transient,
          deliveryId: context.deliveryId ?? undefined,
          eventId: context.eventId,
        },
      });

      // Rethrow the ORIGINAL so existing callers' handling is byte-for-byte unchanged.
      throw err;
    }
  }
}
