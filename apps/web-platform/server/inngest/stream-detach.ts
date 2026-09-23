// #8611 / ADR-243 — keep the Inngest SDK's streamed step response alive when its consumer goes away.
//
// Under `serve({ streaming: "force" })` the SDK (inngest 3.54.2, helpers/stream.js createStream)
// writes a heartbeat byte every 3 s and clears that interval only in finalize(). Its ReadableStream
// has no cancel() handler, so when the Inngest server's connection drops mid-step (spike S3: a
// stream reset at ~20 min) every later tick throws "Invalid state: Controller is already closed"
// from a timer. That is an uncaughtException, and server/crash-handlers.ts exits the process on it:
// one dropped step stream would restart the web server. An unsigned request that resets its socket
// after the 201 reaches the same path.
//
// The fix is to never let the SDK stream see the cancel: re-stream its body through our own stream
// and, when OUR consumer cancels, keep draining the SDK stream to its end (the step's finalize) and
// discard the bytes. inngest@4 fixes createStream upstream; delete this module with that upgrade
// (#8628).

import { warnSilentFallback } from "@/server/observability";

/** Who the streamed response was for — carried on the drop report so a drop is attributable. */
export interface StreamRequestInfo {
  fnId: string | null;
  stepId: string | null;
  /** An `x-inngest-signature` header was present (an unsigned caller's abort is noise, not a drop). */
  signed: boolean;
}

export function streamRequestInfo(req: Request): StreamRequestInfo {
  let fnId: string | null = null;
  let stepId: string | null = null;
  try {
    const url = new URL(req.url);
    fnId = url.searchParams.get("fnId");
    stepId = url.searchParams.get("stepId");
  } catch {
    // A malformed URL leaves the identity unknown; the drop is still reported.
  }
  return { fnId, stepId, signed: req.headers.has("x-inngest-signature") };
}

export function detachFromConsumerCancel(
  res: Response,
  info: StreamRequestInfo = { fnId: null, stepId: null, signed: false },
): Response {
  const source = res.body;
  if (!source) return res;
  const reader = source.getReader();
  const startedAt = Date.now();
  let consumerGone = false;

  const drain = async () => {
    try {
      for (;;) {
        const { done } = await reader.read();
        if (done) return;
      }
    } catch (err) {
      // Nobody is listening any more; record it so a failing SDK stream stays diagnosable.
      warnSilentFallback(err, {
        feature: "inngest-serve",
        op: "inngest-stream-drain-error",
        message: "SDK step stream errored while being drained after its consumer left",
        tags: { signed: String(info.signed) },
        extra: { ...info },
      });
    }
  };

  const body = new ReadableStream<Uint8Array>({
    async pull(controller) {
      try {
        const { done, value } = await reader.read();
        if (consumerGone) return;
        if (done) controller.close();
        else controller.enqueue(value);
      } catch (err) {
        // With the consumer still attached the error propagates to it; after it left, the drain
        // (started in cancel) owns reporting.
        if (!consumerGone) controller.error(err);
      }
    },
    cancel(reason) {
      consumerGone = true;
      // One sample of the production drop rate per report (ADR-243). Unsigned callers aborting
      // after the 201 are tagged `signed:false` so they can be filtered out of that rate.
      warnSilentFallback(reason instanceof Error ? reason : null, {
        feature: "inngest-serve",
        op: "inngest-stream-consumer-cancel",
        message: "Inngest step stream consumer disconnected mid-step; draining the SDK stream instead of cancelling it",
        tags: { signed: String(info.signed), ...(info.fnId ? { fn: info.fnId } : {}) },
        extra: { ...info, msSinceResponse: Date.now() - startedAt },
      });
      void drain();
    },
  });

  return new Response(body, { status: res.status, statusText: res.statusText, headers: res.headers });
}
