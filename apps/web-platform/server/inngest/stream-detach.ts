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
// discard the bytes. inngest@4 fixes createStream upstream; delete this module with that upgrade.

import { reportSilentFallback } from "@/server/observability";

export function detachFromConsumerCancel(res: Response): Response {
  const source = res.body;
  if (!source) return res;
  const reader = source.getReader();
  let consumerGone = false;

  const drain = async () => {
    try {
      for (;;) {
        const { done } = await reader.read();
        if (done) return;
      }
    } catch {
      // The source errored after our consumer left: nothing is listening, nothing to deliver.
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
        if (!consumerGone) controller.error(err);
      }
    },
    cancel(reason) {
      consumerGone = true;
      // The drop rate on the production edge is unmeasured; every cancel is one sample of it.
      reportSilentFallback(reason instanceof Error ? reason : null, {
        feature: "inngest-serve",
        op: "inngest-stream-consumer-cancel",
        message: "Inngest step stream consumer disconnected mid-step; draining the SDK stream instead of cancelling it",
      });
      void drain();
    },
  });

  return new Response(body, { status: res.status, statusText: res.statusText, headers: res.headers });
}
