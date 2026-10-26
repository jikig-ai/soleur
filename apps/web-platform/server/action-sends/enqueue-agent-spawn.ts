// #10543 — the single place the dashboard Send route dispatches `agent.spawn.requested`.
//
// The event id is derived from the action_sends row (the WORM approval), so the same Inngest event
// dedups across every retry attempt AND every founder re-click replay of the same approval. The
// consumer already keys its idempotency on `actionSendId`; this makes the producer agree.
//
// installationId is OMITTED from `data` by design — the consumer server-resolves it from
// users.github_installation_id keyed by founderId (invariant I1: a producer must never choose which
// tenant installation an agent acts on). `actionClass` is typed `ActionClass`, so no `as string`
// widening sits next to the send (the action-class-typed-literals sentinel stays green).

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

export function agentSpawnEventId(actionSendId: string): string {
  return `agent-spawn-${actionSendId}`;
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
    { feature: "spawn-agent", eventId: id },
  );
}
