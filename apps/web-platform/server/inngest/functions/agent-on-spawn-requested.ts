// PR-A (#4124) — Inngest function `agent-on-spawn-requested`.
//
// Consumes `agent.spawn.requested` events emitted by the dashboard /send
// route AFTER `writeActionSend` and BEFORE the `messages.status` archive
// flip. Produces exactly one deterministic GitHub artifact per event:
//   - `pr-*` source refs → PR comment via createComment
//   - everything else (ci-, issue-, cve-, secret-scan-, link-, anchor-) →
//     issue label `soleur/acknowledged` via addLabels (idempotent at the
//     GitHub API layer — re-adding an existing label is a no-op).
//
// PR-B (filed before PR-A merges; ADR-039) replaces the deterministic stub
// body with the Anthropic SDK leader-prompt loop + per-action-class
// specialization.
//
// LOAD-BEARING INVARIANTS:
//   I1 — `installationId` is server-resolved INSIDE step 1 from
//        `users.github_installation_id` keyed by the SERVER-DERIVED
//        `founderId` (the event was signed by INNGEST_SIGNING_KEY and the
//        founderId comes from the cookie-scoped Supabase auth at the
//        webhook predicate / dashboard send route). The event payload
//        type OMITS `installationId`; any consumer reading
//        `event.data.installationId` fails `tsc`. The runtime sentinel
//        test (`installation-id-source-of-truth.test.ts`) enforces the
//        negative grep as belt-and-suspenders.
//   I2 — Every Octokit call routes through `createGitHubAppClient(
//        installationId, founderId)` (PA-16 / PR-H+1 #4098 factory hook).
//        NEVER `probeOctokit` (audit-skipping) or raw `new Octokit(...)`.
//        The per-call audit row in `audit_github_token_use` is the only
//        durable record of the API call surface.
//   I3 — Idempotency key = `event.data.actionSendId`. Duplicate event
//        fires produce exactly one updated `action_sends` row and exactly
//        one artifact (GitHub-side natural idempotency for labels + Inngest
//        step memoization for the createComment cache).
//   I4 — No Anthropic SDK call in PR-A. `byok-audit-writer-sweep` lint
//        asserts no new `runWithByokLease(` site is added under this path.
//   I5 — UPDATE on `action_sends` uses the service-role client because
//        the table's RLS has owner-INSERT + owner-SELECT policies only;
//        UPDATE has no permissive policy (default-deny). The WORM trigger
//        reshape in mig 064 admits UPDATEs that touch ONLY
//        acknowledged_at / artifact_url / failure_reason; any drift
//        toward writing a pre-064 column will fail at the trigger.

import { inngest } from "@/server/inngest/client";
import { getServiceClient } from "@/lib/supabase/service";
import { createGitHubAppClient } from "@/server/github/app-client";
import { reportSilentFallback } from "@/server/observability";
import type { ActionClass } from "@/server/scope-grants/action-class-map";
import {
  ACK_LABEL,
  ACK_PR_COMMENT_TEMPLATE,
  parseSourceRef,
} from "@/server/inngest/agent-acknowledgment-templates";

// The event payload type EXPLICITLY OMITS `installationId`. A future
// event-author who tries to thread `installationId` from the event
// envelope fails `tsc` at consumption time. This is the TypeScript-level
// counterpart to AC2's runtime grep sentinel.
interface AgentSpawnRequestedEvent {
  name: "agent.spawn.requested";
  data: {
    founderId: string;
    messageId: string;
    actionClass: ActionClass;
    sourceRef: string;
    actionSendId: string;
    // NO installationId — server-resolved inside step 1 from
    // users.github_installation_id keyed by founderId.
  };
}

interface HandlerArgs {
  event: AgentSpawnRequestedEvent;
  step: {
    run<T>(name: string, cb: () => Promise<T>): Promise<T>;
  };
  logger: {
    warn: (...args: unknown[]) => void;
    info: (...args: unknown[]) => void;
    error: (...args: unknown[]) => void;
  };
}

export async function agentOnSpawnRequestedHandler({
  event,
  step,
  logger,
}: HandlerArgs): Promise<
  | { acknowledged: true; artifactUrl: string }
  | { acknowledged: false; failureReason: string }
> {
  const { founderId, messageId, actionClass, sourceRef, actionSendId } =
    event.data;

  // Step 1: resolve installation_id from users (SERVER-DERIVED, never
  // from the event payload). I1.
  let installationId: number;
  try {
    installationId = await step.run("resolve-installation", async () => {
      const sb = getServiceClient();
      const { data, error } = await sb
        .from("users")
        .select("github_installation_id")
        .eq("id", founderId)
        .maybeSingle();
      if (error) {
        throw new Error(
          `agent-on-spawn: users select error for founder ${founderId}: ${error.message}`,
        );
      }
      const row = data as { github_installation_id?: number | null } | null;
      if (!row?.github_installation_id) {
        throw new Error(
          `agent-on-spawn: no github_installation_id for founder ${founderId}`,
        );
      }
      return row.github_installation_id;
    });
  } catch (err) {
    return await persistFailure(step, {
      actionSendId,
      reason: "github_installation_unauthorized",
      err,
      founderId,
      messageId,
      actionClass,
      sourceRef,
      logger,
    });
  }

  // Step 2: route through createGitHubAppClient (audit hook attaches per
  // PR-H+1 #4098 factory; one audit_github_token_use row per Octokit
  // response). I2.
  // Step 3: deterministic acknowledgment — 2 paths only (PR comment vs
  // issue label). I3 (step memoization keeps re-fires from creating
  // duplicate comments; GitHub-side label add is naturally idempotent).
  let artifactUrl: string;
  try {
    artifactUrl = await step.run("post-acknowledgment", async () => {
      const parsed = parseSourceRef(sourceRef);
      const octokit = await createGitHubAppClient(installationId, founderId);
      if (parsed.isPr) {
        const { data } = await octokit.request(
          "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
          {
            owner: parsed.owner,
            repo: parsed.repo,
            issue_number: parsed.number,
            body: ACK_PR_COMMENT_TEMPLATE,
          },
        );
        return (data as { html_url: string }).html_url;
      }
      await octokit.request(
        "POST /repos/{owner}/{repo}/issues/{issue_number}/labels",
        {
          owner: parsed.owner,
          repo: parsed.repo,
          issue_number: parsed.number,
          labels: [ACK_LABEL],
        },
      );
      return `https://github.com/${parsed.owner}/${parsed.repo}/issues/${parsed.number}`;
    });
  } catch (err) {
    return await persistFailure(step, {
      actionSendId,
      reason: classifyGithubError(err),
      err,
      founderId,
      messageId,
      actionClass,
      sourceRef,
      logger,
    });
  }

  // Step 4: UPDATE action_sends with acknowledgment columns. I5.
  // WORM trigger (mig 064) admits this UPDATE because the SET list
  // touches ONLY acknowledged_at + artifact_url; any drift toward a
  // pre-064 column trips the trigger.
  await step.run("mark-acknowledged", async () => {
    const sb = getServiceClient();
    const { error } = await sb
      .from("action_sends")
      .update({
        acknowledged_at: new Date().toISOString(),
        artifact_url: artifactUrl,
      })
      .eq("id", actionSendId);
    if (error) {
      // The artifact landed on GitHub but the row UPDATE failed.
      // Surface to Sentry; the operator's "Acknowledged" pill rendered
      // optimistically on the 200 response and the canonical artifact
      // is on GitHub, so this is degraded-not-broken.
      reportSilentFallback(error, {
        feature: "spawn-agent",
        op: "mark-acknowledged",
        message:
          "action_sends UPDATE failed after artifact emitted on GitHub",
        extra: { founderId, messageId, actionClass, actionSendId },
      });
      throw error;
    }
  });

  return { acknowledged: true, artifactUrl };
}

async function persistFailure(
  step: HandlerArgs["step"],
  args: {
    actionSendId: string;
    reason: string;
    err: unknown;
    founderId: string;
    messageId: string;
    actionClass: ActionClass;
    sourceRef: string;
    logger: HandlerArgs["logger"];
  },
): Promise<{ acknowledged: false; failureReason: string }> {
  const { actionSendId, reason, err } = args;
  reportSilentFallback(err instanceof Error ? err : new Error(String(err)), {
    feature: "spawn-agent",
    op: "agent-on-spawn-requested",
    message: `agent-on-spawn deadlettered: ${reason}`,
    extra: {
      founderId: args.founderId,
      messageId: args.messageId,
      actionClass: args.actionClass,
      sourceRef: args.sourceRef,
      actionSendId,
    },
  });
  await step.run("persist-failure", async () => {
    const sb = getServiceClient();
    await sb
      .from("action_sends")
      .update({ failure_reason: reason })
      .eq("id", actionSendId);
  });
  return { acknowledged: false, failureReason: reason };
}

function classifyGithubError(err: unknown): string {
  if (err instanceof Error && /^agent-on-spawn: malformed/i.test(err.message)) {
    return "malformed_source_ref";
  }
  const status = (err as { status?: number } | null)?.status;
  if (status === 401 || status === 403) return "github_installation_unauthorized";
  if (status === 404) return "github_target_not_found";
  return "github_api_error";
}

export const agentOnSpawnRequested = inngest.createFunction(
  {
    id: "agent-on-spawn-requested",
    idempotency: "event.data.actionSendId",
    retries: 3,
  },
  { event: "agent.spawn.requested" },
  agentOnSpawnRequestedHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
