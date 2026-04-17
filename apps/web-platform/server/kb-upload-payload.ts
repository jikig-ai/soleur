import { linearizePdf } from "@/server/pdf-linearize";
import { warnSilentFallback } from "@/server/observability";

// Sentry message preserved verbatim from the pre-extraction inline call so
// existing dashboards, saved searches, and alert rules filtering on
// `message:"pdf linearization failed"` continue to work after this refactor.
const SENTRY_MESSAGE = "pdf linearization failed";

export interface PrepareUploadContext {
  /** Authenticated user id, recorded in the silent-fallback extras. */
  userId: string;
  /** Target repo path, recorded in the silent-fallback extras. */
  path: string;
}

/**
 * Read an upload File stream into a Buffer, applying PDF linearization when
 * the sanitized extension is `.pdf`. On linearize failure (excluding the
 * intentional `skip_signed` pass-through), returns the original bytes and
 * mirrors a structured warning to pino + Sentry via warnSilentFallback.
 *
 * Stream errors propagate — this helper does not swallow them; the caller's
 * outer try/catch handles them identically to the pre-extraction code.
 */
export async function prepareUploadPayload(
  file: File,
  sanitizedName: string,
  ctx: PrepareUploadContext,
): Promise<Buffer> {
  const chunks: Uint8Array[] = [];
  const reader = file.stream().getReader();
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value);
  }
  const buffer: Buffer = Buffer.concat(chunks);

  const ext = sanitizedName.split(".").pop()?.toLowerCase();
  if (ext !== "pdf") return buffer;

  const t0 = Date.now();
  const result = await linearizePdf(buffer);
  if (result.ok) return result.buffer;

  // skip_signed is an intentional pass-through (signed PDFs would be
  // invalidated by linearization), not a failure — silent in both sinks.
  if (result.reason === "skip_signed") return buffer;

  warnSilentFallback(null, {
    feature: "kb-upload",
    op: "linearize",
    message: SENTRY_MESSAGE,
    extra: {
      reason: result.reason,
      detail: result.detail,
      inputSize: buffer.length,
      durationMs: Date.now() - t0,
      userId: ctx.userId,
      path: ctx.path,
    },
  });
  return buffer;
}
