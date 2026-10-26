// #10543 — the single place the dashboard Send route dispatches `agent.spawn.requested`.
//
// The event id is derived from the action_sends row (the WORM approval), so the same Inngest event
// dedups across every retry attempt AND every founder re-click replay of the same approval. The
// consumer already keys its idempotency on `actionSendId`; this makes the producer agree.
//
// installationId is OMITTED from `data` by design — the consumer server-resolves it from the
// workspace's github_installation_id keyed by founderId (invariant I1: a producer must never choose
// which tenant installation an agent acts on). `actionClass` is typed `ActionClass`, so no
// `as string` widening sits next to the send (the action-class-typed-literals sentinel stays green).

import { inngest } from "@/server/inngest/client";
import { sendInngestWithRetry } from "@/server/inngest/send-with-retry";
import type { ActionClass } from "@/server/scope-grants/action-class-map";

export interface EnqueueAgentSpawnArgs {
  founderId: string;
  messageId: string;
  actionClass: ActionClass;
  sourceRef: string;
  actionSendId: string;
}

// Per-attempt bound. sendInngestWithRetry has no per-attempt timeout and `inngest.send` takes no
// AbortSignal here, so a hung Inngest host would hold each of the 3 attempts for the HTTP client's
// connect timeout and outlast the browser's 30s send watchdog (the founder would see "Send timed
// out" instead of the 503 retry copy). 3 x 6s plus 1.5s of backoff = 19.5s, under that watchdog.
// A timed-out attempt is classified transient by isTransientFetchError (DOMException TimeoutError)
// and retried; an attempt that actually landed is harmless because the event id dedups.
const ATTEMPT_TIMEOUT_MS = 6_000;

function agentSpawnEventId(actionSendId: string): string {
  return `agent-spawn-${actionSendId}`;
}

async function withAttemptTimeout<T>(attempt: Promise<T>): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(
      () =>
        reject(
          new DOMException(
            `inngest.send exceeded ${ATTEMPT_TIMEOUT_MS}ms`,
            "TimeoutError",
          ),
        ),
      ATTEMPT_TIMEOUT_MS,
    );
  });
  try {
    return await Promise.race([attempt, timeout]);
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Enqueue the spawn event with transient-failure retry. Resolves once Inngest accepted the event;
 * rejects when retries are exhausted or the error is not transient (the caller maps that to 503).
 */
export async function enqueueAgentSpawn(
  args: EnqueueAgentSpawnArgs,
): Promise<void> {
  const id = agentSpawnEventId(args.actionSendId);
  await sendInngestWithRetry(
    () =>
      withAttemptTimeout(
        inngest.send({
          id,
          name: "agent.spawn.requested",
          data: {
            founderId: args.founderId,
            messageId: args.messageId,
            actionClass: args.actionClass,
            sourceRef: args.sourceRef,
            actionSendId: args.actionSendId,
          },
        }),
      ),
    { feature: "spawn-agent", eventId: id },
  );
}
