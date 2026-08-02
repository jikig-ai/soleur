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
      throw err;
    }
  }
}
