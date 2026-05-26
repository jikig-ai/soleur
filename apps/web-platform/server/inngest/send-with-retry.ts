import logger from "@/server/logger";

const MAX_RETRIES = 2;
const BASE_DELAY_MS = 200;

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
    ].includes(code);
  }
  return false;
}

// Retries inngest.send() on transient network failures (loopback to
// 127.0.0.1:8288 can blip during deploy restarts).
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
          { attempt: attempt + 1, ...context, err },
          `${context.feature}: inngest.send transient failure — retrying`,
        );
        await new Promise((r) => setTimeout(r, BASE_DELAY_MS * 2 ** attempt));
        continue;
      }
      throw err;
    }
  }
}
