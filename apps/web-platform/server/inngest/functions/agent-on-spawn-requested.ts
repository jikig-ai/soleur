// PR-B (#4379) — Inngest function `agent-on-spawn-requested`.
//
// Consumes `agent.spawn.requested` events emitted by the dashboard /send
// route AFTER `writeActionSend` and BEFORE the `messages.status` archive
// flip.
//
// PR-A (#4124, merged #4378 commit 7d5620a5) shipped a deterministic
// acknowledgment stub. PR-B replaces the body of `post-acknowledgment`
// with a per-turn Anthropic-SDK leader-prompt loop driven by
// `anthropic.messages.create` with tool-use rounds (per ADR-042).
//
// LOAD-BEARING INVARIANTS (PR-A I1/I2/I3/I5 inherited; I4 deliberately
// REVERSED — this is the first raw `@anthropic-ai/sdk` site in
// apps/web-platform/server/):
//   I1 — `installationId` is server-resolved INSIDE step 1 via
//        `resolveInstallationIdForWorkspace` (service-role read of the
//        workspaces installation credential) keyed by the SERVER-DERIVED
//        `founderId` (the user's solo workspace id; ADR-038 N2 / ADR-044).
//        The event payload type OMITS `installationId`; any consumer
//        reading `event.data.installationId` fails `tsc`.
//   I2 — Every Octokit call routes through `createGitHubAppClient(
//        installationId, founderId)` (PA-16 factory hook).
//   I3 — Idempotency key = `event.data.actionSendId`. Inngest's
//        `step.run` memoization makes the loop replay-safe: re-runs
//        return cached step results without re-invoking the SDK or
//        the cost-writer.
//   I5 — UPDATE on `action_sends` uses the service-role client.
//        Mig 067's columns (current_turn, reversal_handles,
//        cancellation_requested_at, prompt_version, undone_at,
//        current_turn_started_at) are admitted by the WORM trigger
//        because the trigger's BEFORE UPDATE OF list excludes them
//        (default-admit on non-listed columns).

import { createHash } from "node:crypto";

import Anthropic from "@anthropic-ai/sdk";

import { inngest } from "@/server/inngest/client";
import { getServiceClient } from "@/lib/supabase/service";
import { createGitHubAppClient } from "@/server/github/app-client";
import { resolveInstallationIdForWorkspace } from "@/server/resolve-installation-id-for-workspace";
import { reportSilentFallback } from "@/server/observability";
import { runWithByokLease } from "@/server/byok-lease";
import { recordByokUseAndCheckCap } from "@/server/byok-cap-rpc";
import { persistTurnCostAwaitable } from "@/server/cost-writer";
import { notifyOfflineUser, isCostBreakerReason } from "@/server/notifications";
import type { ActionClass } from "@/server/scope-grants/action-class-map";
import {
  LEADER_MAX_TURNS,
  LEADER_MAX_TOKENS,
  PER_SPAWN_COST_CEILING_CENTS,
  SONNET_MODEL,
  HAIKU_MODEL,
  type LeaderActionClass,
  type LeaderPromptModule,
} from "@/server/inngest/leader-prompts";
import { LEADER_PROMPTS } from "@/server/inngest/leader-prompts";

// UUIDv5 namespace for the per-spawn conversationId (AC6). LOAD-BEARING —
// regenerating this constant silently shifts every in-flight loop's
// conversationId and breaks cumulative-cost queries that filter by
// derived `conversation_id`. Pinned verbatim by
// `conversation-namespace-stability.test.ts`.
const CONVERSATION_NAMESPACE = "9b6dc8f1-3a7e-4c2b-8d4f-5a2e9c1b7d3e";

/**
 * UUIDv5 (sha1-namespace) per RFC 4122 §4.3. Inlined to avoid pulling
 * `uuid` + `@types/uuid` as a webplat dep — the algorithm is small and
 * the namespace is pinned at module-load (no test-only branches).
 */
function uuidv5(name: string, namespace: string): string {
  const hex = namespace.replace(/-/g, "");
  const nsBytes = Buffer.from(hex, "hex");
  const hash = createHash("sha1")
    .update(nsBytes)
    .update(Buffer.from(name, "utf8"))
    .digest();
  const bytes = Buffer.from(hash.subarray(0, 16));
  bytes[6] = (bytes[6] & 0x0f) | 0x50; // version 5
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant RFC 4122
  const h = bytes.toString("hex");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20, 32)}`;
}

// Per-model unit pricing in USD per token. Cache-read tokens bill at
// ~10% of input; cache-creation tokens at ~125% of input. Pulled from
// Anthropic public pricing pages 2026-05-25; CFO refreshes via cap
// follow-through.
interface ModelPricing {
  inputPerToken: number;
  outputPerToken: number;
  cacheReadPerToken: number;
  cacheCreatePerToken: number;
}
// Keys are computed properties referencing the SSOT model-ID constants
// (leader-prompts/constants.ts) so a key can never drift out of byte-identity
// with `leaderModule.model` — the `?? {all-zeros}` fallback at the lookup
// below would otherwise silently bill at zero. Parity is CI-guarded by
// model-tiers.test.ts (#5106). Opus is intentionally absent: `leaderModule
// .model` is `AnthropicModelId` (sonnet|haiku), the only value flowing
// through `MODEL_PRICING[…]`, so opus never reaches this lookup.
export const MODEL_PRICING: Record<string, ModelPricing> = {
  [SONNET_MODEL]: {
    inputPerToken: 3 / 1_000_000,
    outputPerToken: 15 / 1_000_000,
    cacheReadPerToken: 0.3 / 1_000_000,
    cacheCreatePerToken: 3.75 / 1_000_000,
  },
  [HAIKU_MODEL]: {
    inputPerToken: 0.8 / 1_000_000,
    outputPerToken: 4 / 1_000_000,
    cacheReadPerToken: 0.08 / 1_000_000,
    cacheCreatePerToken: 1 / 1_000_000,
  },
};

interface AgentSpawnRequestedEvent {
  name: "agent.spawn.requested";
  data: {
    founderId: string;
    messageId: string;
    actionClass: ActionClass;
    sourceRef: string;
    actionSendId: string;
    // NO installationId — server-resolved inside step 1.
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

// AC10 — the failure-reason taxonomy admitted on `action_sends.failure_reason`.
// PR-A's set ({github_installation_unauthorized, github_target_not_found,
// github_api_error, malformed_source_ref, acknowledgment_persist_failed})
// is preserved; PR-B extends with the leader-loop reasons.
type FailureReason =
  | "github_installation_unauthorized"
  | "github_target_not_found"
  | "github_api_error"
  | "malformed_source_ref"
  | "acknowledgment_persist_failed"
  | "byok_cap_exceeded"
  | "cost_ceiling_exceeded"
  | "cancelled_by_operator"
  | "byok_lease_unavailable"
  | "anthropic_timeout"
  | "anthropic_rate_limited"
  | "leader_max_turns_exceeded"
  | "leader_response_truncated"
  | "leader_tool_invalid"
  | "leader_class_disabled"
  // feat-l5-runaway-guard PR-A: spawn-entry pause gate + distinct
  // transient-cap-check reason (P2-H — a DB error is not a budget breach).
  | "run_paused"
  | "cap_check_unavailable";

interface ReversalHandle {
  kind:
    | "pr_review_comment"
    | "pr_comment"
    | "issue_label"
    | "issue_comment"
    | "branch"
    | "pr";
  owner: string;
  repo: string;
  // Per-kind identifying fields. Optional union — the dashboard's undo
  // route enforces the per-kind discriminated shape.
  commentId?: number;
  prNumber?: number;
  issueNumber?: number;
  labelName?: string;
  branchRef?: string;
}

interface ToolUseBlock {
  type: "tool_use";
  id: string;
  name: string;
  input: Record<string, unknown>;
}

interface MessageContentText {
  type: "text";
  text: string;
}

type AnthropicContentBlock = ToolUseBlock | MessageContentText | { type: string };

interface AnthropicTurnResult {
  id: string;
  stop_reason: "end_turn" | "tool_use" | "max_tokens" | string;
  content: AnthropicContentBlock[];
  usage: {
    input_tokens: number;
    output_tokens: number;
    cache_read_input_tokens?: number | null;
    cache_creation_input_tokens?: number | null;
  };
}

interface ToolResult {
  type: "tool_result";
  tool_use_id: string;
  content: string;
  is_error?: boolean;
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

  // Step 1: resolve installation_id (I1).
  let installationId: number;
  try {
    installationId = await step.run("resolve-installation", async () => {
      // Service-role read of the user's solo workspace install credential
      // (workspaces.github_installation_id keyed id=founderId). Resolver
      // mirrors db-error → null to Sentry; a null result (not-connected,
      // not-found, or read error) throws → github_installation_unauthorized.
      const install = await resolveInstallationIdForWorkspace(
        founderId,
        getServiceClient(),
      );
      if (install === null) {
        throw new Error(
          `agent-on-spawn: no github_installation_id for founder ${founderId}`,
        );
      }
      return install;
    });
  } catch (err) {
    return persistFailure(step, {
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

  // Resolve the leader prompt module for this class. Unknown class OR
  // operator/CTO-disabled class → fail-closed via `leader_class_disabled`.
  //
  // Runtime kill switch (per-class dogfood escape hatch): `LEADER_CLASSES_DISABLED`
  // is a comma-separated list of `LeaderActionClass` values that the loop
  // refuses to run. Set via Doppler (`prd`) to short-circuit a misbehaving
  // class without redeploy. The operator-facing copy in
  // `failure-reason-copy.ts` ("Autonomous agent for this card class is not
  // enabled yet. CTO has been notified.") is already shipped.
  const disabledClasses = (process.env.LEADER_CLASSES_DISABLED ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
  const leaderModule = LEADER_PROMPTS[actionClass as LeaderActionClass] as
    | LeaderPromptModule
    | undefined;
  if (!leaderModule || disabledClasses.includes(actionClass)) {
    return persistFailure(step, {
      actionSendId,
      reason: "leader_class_disabled",
      err: new Error(
        leaderModule
          ? `class ${actionClass} disabled via LEADER_CLASSES_DISABLED`
          : `no leader module for class ${actionClass}`,
      ),
      founderId,
      messageId,
      actionClass,
      sourceRef,
      logger,
    });
  }

  // Mint conversationId deterministically (AC6) — stable across replays
  // and reproducible from `actionSendId`. Not persisted.
  const conversationId = uuidv5(actionSendId, CONVERSATION_NAMESPACE);
  const leaderId = `agent.spawn.requested:${actionClass}`;

  // Parse the source ref into (owner, repo, number) when applicable. For
  // kb_drift/cve shapes that carry no GitHub target, omit — the leader
  // prompt assembles a synthetic context from sourceRef alone.
  const parsed = tryParseSourceRef(sourceRef);
  const userPrompt = leaderModule.userPromptTemplate({
    actionClass: actionClass as LeaderActionClass,
    sourceRef,
    owner: parsed?.owner,
    repo: parsed?.repo,
    number: parsed?.number,
  });

  // Initial messages array — the assistant turn appends per loop iteration.
  const messages: Array<{
    role: "user" | "assistant";
    content: string | AnthropicContentBlock[] | ToolResult[];
  }> = [{ role: "user", content: userPrompt }];

  // Tool surface allowlist (AC8) — per-class enumerated. Out-of-allowlist
  // tool calls short-circuit with `failure_reason = "leader_tool_invalid"`.
  const allowedTools = new Set(leaderModule.tools.map((t) => t.name));

  // Per-spawn reversal handles ledger (AC9 — multi-artifact array).
  const reversalHandles: ReversalHandle[] = [];

  // Spawn-entry pause gate (feat-l5-runaway-guard PR-A, P0-A). Before the
  // turn loop — and therefore before ANY Anthropic call or audit_byok_use
  // row — refuse to run for a founder whose account is paused. This is the
  // SOLE working-pause guard: the cap RPC does NOT backstop the paused case
  // (#5919 made its kill_tripped exactly-once via `FOUND`, which correctly
  // does not re-trip an already-paused caller). So this gate FAILS CLOSED on
  // a users-read error (CTO ruling on the #5767-vs-#5919 fork) — matching the
  // fail-closed posture of the two adjacent steps (turn-1 cap-check throws on
  // RPC error; precheck-cost-ceiling fail-closes on cumulative-read error).
  let pauseState: { pausedAt: string | null; capCents: number | null };
  try {
    pauseState = await step.run("check-runtime-pause", async () => {
      const sb = getServiceClient();
      const { data, error } = await sb
        .from("users")
        .select("runtime_paused_at, runtime_cost_cap_cents")
        .eq("id", founderId)
        .maybeSingle();
      if (error) {
        // Fail-closed: an unverifiable pause state must not admit a possibly-
        // paused founder into the loop.
        throw new Error(`check-runtime-pause read failed: ${error.message}`);
      }
      const row = data as
        | { runtime_paused_at: string | null; runtime_cost_cap_cents: number | null }
        | null;
      return {
        pausedAt: row?.runtime_paused_at ?? null,
        capCents: row?.runtime_cost_cap_cents ?? null,
      };
    });
  } catch (err) {
    // Read error → halt (fail-closed). run_paused keeps the Resume-button UX;
    // persistFailure's reportSilentFallback mirrors it to Sentry (observable
    // without SSH, cq-silent-fallback-must-mirror-to-sentry).
    return persistFailure(step, {
      actionSendId,
      reason: "run_paused",
      err,
      founderId,
      messageId,
      actionClass,
      sourceRef,
      logger,
    });
  }
  if (pauseState.pausedAt) {
    // No cost-breaker notification here (F3): the founder was already paged by
    // the byok_cap_exceeded breach that SET the pause; the Today card renders
    // this run_paused halt + a Resume button, so re-paging every subsequent
    // blocked spawn would be a notification storm from the guard itself.
    return persistFailure(step, {
      actionSendId,
      reason: "run_paused",
      err: new Error("spawn refused: founder account is paused"),
      founderId,
      messageId,
      actionClass,
      sourceRef,
      logger,
    });
  }

  // The leader prompt loop. Layer-3 backstop (LEADER_MAX_TURNS = 8 turns,
  // per ADR-041); the primary gates are the Layer-1 cap-check + Layer-2
  // cost ceiling.
  for (let n = 1; n <= LEADER_MAX_TURNS; n++) {
    // Step: turn-n-cap-check (Layer 1, AC4).
    let capResult: { cumulativeCents: number; killTripped: boolean };
    try {
      capResult = await step.run(`turn-${n}-cap-check`, async () => {
        return recordByokUseAndCheckCap({
          invocationId: `${actionSendId}-turn-${n}`,
          founderId,
          workspaceId: founderId,
          agentRole: "agent.spawn.requested",
          tokenCount: 0,
          unitCostCents: 0,
        });
      });
    } catch (err) {
      // P2-H: a transient cap-check DB error is NOT a budget breach. Use a
      // distinct reason so the operator alert reads "we couldn't verify your
      // budget", not a false "you exceeded your cap". Fail-closed (no
      // Anthropic call) is preserved — only the reason/copy differs.
      return persistFailure(step, {
        actionSendId,
        reason: "cap_check_unavailable",
        err,
        founderId,
        messageId,
        actionClass,
        sourceRef,
        logger,
        notify: {
          whichWindow: "cap-1h",
          cumulativeCents: null,
          ceilingCents: pauseState.capCents,
        },
      });
    }
    if (capResult.killTripped) {
      return persistFailure(step, {
        actionSendId,
        reason: "byok_cap_exceeded",
        err: new Error("BYOK cap kill-trip"),
        founderId,
        messageId,
        actionClass,
        sourceRef,
        logger,
        notify: {
          whichWindow: "cap-1h",
          cumulativeCents: capResult.cumulativeCents,
          ceilingCents: pauseState.capCents,
        },
      });
    }

    // Step: turn-n-precheck-cost-ceiling (Layer 2, AC15).
    const cumulativeCents = await step.run(
      `turn-${n}-precheck-cost-ceiling`,
      async () => {
        const sb = getServiceClient();
        const result = (await sb
          .from("audit_byok_use")
          .select("unit_cost_cents")
          .eq("founder_id", founderId)
          .eq("agent_role", leaderId)) as {
          data: { unit_cost_cents: number | null }[] | null;
          error: { message: string } | null;
        };
        if (result.error) {
          // Fail-closed on cumulative cost read error.
          throw new Error(
            `agent-on-spawn: audit_byok_use sum failed: ${result.error.message}`,
          );
        }
        return (result.data ?? []).reduce(
          (sum, row) => sum + (row.unit_cost_cents ?? 0),
          0,
        );
      },
    );
    if (cumulativeCents >= PER_SPAWN_COST_CEILING_CENTS) {
      return persistFailure(step, {
        actionSendId,
        reason: "cost_ceiling_exceeded",
        err: new Error(
          `per-spawn cost ceiling reached at turn ${n} (${cumulativeCents}¢)`,
        ),
        founderId,
        messageId,
        actionClass,
        sourceRef,
        logger,
        notify: {
          whichWindow: "spawn",
          cumulativeCents,
          ceilingCents: PER_SPAWN_COST_CEILING_CENTS,
        },
      });
    }

    // Step: turn-n-cancel-check (AC13).
    const cancelled = await step.run(
      `turn-${n}-cancel-check`,
      async () => {
        const sb = getServiceClient();
        const { data } = await sb
          .from("action_sends")
          .select("cancellation_requested_at")
          .eq("id", actionSendId)
          .maybeSingle();
        const row = data as
          | { cancellation_requested_at: string | null }
          | null;
        return Boolean(row?.cancellation_requested_at);
      },
    );
    if (cancelled) {
      return persistFailure(step, {
        actionSendId,
        reason: "cancelled_by_operator",
        err: new Error("operator clicked Stop"),
        founderId,
        messageId,
        actionClass,
        sourceRef,
        logger,
      });
    }

    // Step: turn-n-progress-write (Realtime fanout source).
    await step.run(`turn-${n}-progress-write`, async () => {
      const sb = getServiceClient();
      const patch: Record<string, unknown> = {
        current_turn: n,
        current_turn_started_at: new Date().toISOString(),
      };
      if (n === 1) {
        patch.prompt_version = leaderModule.promptVersion;
      }
      const { error } = await sb
        .from("action_sends")
        .update(patch)
        .eq("id", actionSendId);
      if (error) {
        throw error;
      }
    });

    // Step: turn-n-claude — opens the BYOK lease inside the step so ALS
    // cannot escape and idempotency under replay is preserved (ADR-042).
    let turnResult: AnthropicTurnResult;
    try {
      turnResult = (await step.run(`turn-${n}-claude`, async () => {
        return runWithByokLease(
          {
            workspaceContextUserId: founderId,
            keyOwnerUserId: founderId,
          },
          async (lease) => {
            // Raw-REST consumer (`new Anthropic({apiKey})`) — MUST use the
            // api_key row; an oauth_token cannot authenticate the REST API.
            const apiKey = await lease.getRestApiKey();
            const client = new Anthropic({ apiKey });
            const sdkResult = (await client.messages.create({
              model: leaderModule.model,
              max_tokens: LEADER_MAX_TOKENS,
              system: [
                {
                  type: "text",
                  text: leaderModule.systemPrompt,
                  cache_control: { type: "ephemeral" },
                },
              ],
              tools: leaderModule.tools.map((t) => ({
                ...t,
                cache_control: { type: "ephemeral" },
              })) as never,
              messages: messages as never,
            })) as unknown as AnthropicTurnResult;

            const usage = sdkResult.usage;
            const pricing = MODEL_PRICING[leaderModule.model] ?? {
              inputPerToken: 0,
              outputPerToken: 0,
              cacheReadPerToken: 0,
              cacheCreatePerToken: 0,
            };
            const cacheRead = usage.cache_read_input_tokens ?? 0;
            const cacheCreate = usage.cache_creation_input_tokens ?? 0;
            const totalCostUsd =
              usage.input_tokens * pricing.inputPerToken +
              usage.output_tokens * pricing.outputPerToken +
              cacheRead * pricing.cacheReadPerToken +
              cacheCreate * pricing.cacheCreatePerToken;

            await persistTurnCostAwaitable(
              founderId,
              conversationId,
              leaderId,
              founderId,
              {
                totalCostUsd,
                usage: {
                  input_tokens: usage.input_tokens,
                  output_tokens: usage.output_tokens,
                  cache_read_input_tokens: cacheRead,
                  cache_creation_input_tokens: cacheCreate,
                },
              },
            );
            return sdkResult;
          },
        );
      })) as AnthropicTurnResult;
    } catch (err) {
      const reason = classifyAnthropicOrLeaseError(err);
      return persistFailure(step, {
        actionSendId,
        reason,
        err,
        founderId,
        messageId,
        actionClass,
        sourceRef,
        logger,
      });
    }

    // Handle stop_reason: max_tokens / end_turn / tool_use.
    if (turnResult.stop_reason === "max_tokens") {
      return persistFailure(step, {
        actionSendId,
        reason: "leader_response_truncated",
        err: new Error(`stop_reason=max_tokens on turn ${n}`),
        founderId,
        messageId,
        actionClass,
        sourceRef,
        logger,
      });
    }

    // Collect tool-use blocks and validate against the per-class allowlist.
    const toolUseBlocks: ToolUseBlock[] = [];
    for (const block of turnResult.content) {
      if (block.type === "tool_use") {
        const tu = block as ToolUseBlock;
        if (!allowedTools.has(tu.name)) {
          return persistFailure(step, {
            actionSendId,
            reason: "leader_tool_invalid",
            err: new Error(
              `tool ${tu.name} not in allowlist for ${actionClass}`,
            ),
            founderId,
            messageId,
            actionClass,
            sourceRef,
            logger,
          });
        }
        toolUseBlocks.push(tu);
      }
    }

    // Execute tool calls via createGitHubAppClient (I2).
    const toolResults: ToolResult[] = [];
    for (let i = 0; i < toolUseBlocks.length; i++) {
      const tu = toolUseBlocks[i];
      const result = await step.run(`turn-${n}-tool-${i}`, async () => {
        return executeTool(
          installationId,
          founderId,
          tu,
          actionClass as LeaderActionClass,
        );
      });
      toolResults.push({
        type: "tool_result",
        tool_use_id: tu.id,
        content: result.content,
        is_error: result.isError,
      });
      if (result.handle) {
        reversalHandles.push(result.handle);
      }
    }

    // Loop control: end_turn → write artifact + ack. tool_use → next turn.
    if (turnResult.stop_reason === "end_turn") {
      const artifactUrl =
        reversalHandles.length > 0
          ? deriveArtifactUrl(reversalHandles[0])
          : "";
      try {
        await step.run("mark-acknowledged", async () => {
          const sb = getServiceClient();
          const { error } = await sb
            .from("action_sends")
            .update({
              acknowledged_at: new Date().toISOString(),
              artifact_url: artifactUrl,
              reversal_handles: reversalHandles,
            })
            .eq("id", actionSendId);
          if (error) {
            throw error;
          }
        });
      } catch (err) {
        return persistFailure(step, {
          actionSendId,
          reason: "acknowledgment_persist_failed",
          err,
          founderId,
          messageId,
          actionClass,
          sourceRef,
          logger,
        });
      }
      return { acknowledged: true, artifactUrl };
    }

    // tool_use → append assistant content + tool_result blocks for next turn.
    messages.push({
      role: "assistant",
      content: turnResult.content,
    });
    if (toolResults.length > 0) {
      messages.push({
        role: "user",
        content: toolResults,
      });
    }
  }

  // Loop exhausted without end_turn → max-turns failure.
  return persistFailure(step, {
    actionSendId,
    reason: "leader_max_turns_exceeded",
    err: new Error(`leader loop exhausted ${LEADER_MAX_TURNS} turns`),
    founderId,
    messageId,
    actionClass,
    sourceRef,
    logger,
    notify: {
      // A turn-count halt carries no trustworthy dollar figure.
      whichWindow: "spawn",
      cumulativeCents: null,
      ceilingCents: null,
    },
  });
}

// --- Helpers ----------------------------------------------------------------

interface ToolExecResult {
  content: string;
  isError: boolean;
  handle?: ReversalHandle;
}

async function executeTool(
  installationId: number,
  founderId: string,
  tu: ToolUseBlock,
  actionClass: LeaderActionClass,
): Promise<ToolExecResult> {
  const octokit = await createGitHubAppClient(installationId, founderId);
  const input = tu.input;
  try {
    switch (tu.name) {
      case "createComment": {
        const { owner, repo, issue_number, body } = input as {
          owner: string;
          repo: string;
          issue_number: number;
          body: string;
        };
        const { data } = (await octokit.request(
          "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
          { owner, repo, issue_number, body },
        )) as { data: { id: number; html_url: string } };
        // Per AC9: issue-targeted classes (triage.p0p1_issue,
        // knowledge.kb_drift) emit `issue_comment` handles; PR-targeted
        // classes (engineering.{pr_review_pending,ci_failed},
        // security.cve_alert) emit `pr_comment` handles. The GitHub API
        // endpoint is the same; the kind distinguishes the reversal verb
        // path the dashboard undo route uses.
        const isIssueClass =
          actionClass === "triage.p0p1_issue" ||
          actionClass === "knowledge.kb_drift";
        return {
          content: JSON.stringify({ id: data.id, html_url: data.html_url }),
          isError: false,
          handle: {
            kind: isIssueClass ? "issue_comment" : "pr_comment",
            owner,
            repo,
            commentId: data.id,
            issueNumber: issue_number,
          },
        };
      }
      case "createPullRequestReviewComment": {
        const { owner, repo, pull_number, body, path, line, side, commit_id } =
          input as {
            owner: string;
            repo: string;
            pull_number: number;
            body: string;
            path: string;
            line: number;
            side?: string;
            commit_id?: string;
          };
        const { data } = (await octokit.request(
          "POST /repos/{owner}/{repo}/pulls/{pull_number}/comments",
          {
            owner,
            repo,
            pull_number,
            body,
            path,
            line,
            commit_id: commit_id ?? "",
            side: (side === "LEFT" || side === "RIGHT" ? side : "RIGHT") as
              | "LEFT"
              | "RIGHT",
          },
        )) as { data: { id: number; html_url: string } };
        return {
          content: JSON.stringify({ id: data.id, html_url: data.html_url }),
          isError: false,
          handle: {
            kind: "pr_review_comment",
            owner,
            repo,
            commentId: data.id,
            prNumber: pull_number,
          },
        };
      }
      case "addLabels": {
        const { owner, repo, issue_number, labels } = input as {
          owner: string;
          repo: string;
          issue_number: number;
          labels: string[];
        };
        const { data } = (await octokit.request(
          "POST /repos/{owner}/{repo}/issues/{issue_number}/labels",
          { owner, repo, issue_number, labels },
        )) as { data: { name: string }[] };
        return {
          content: JSON.stringify({ added: data.map((l) => l.name) }),
          isError: false,
          handle: {
            kind: "issue_label",
            owner,
            repo,
            issueNumber: issue_number,
            labelName: labels[0],
          },
        };
      }
      case "createBranch": {
        const { owner, repo, branch_name, sha } = input as {
          owner: string;
          repo: string;
          branch_name: string;
          sha: string;
        };
        const { data } = (await octokit.request(
          "POST /repos/{owner}/{repo}/git/refs",
          { owner, repo, ref: `refs/heads/${branch_name}`, sha },
        )) as { data: { ref: string } };
        return {
          content: JSON.stringify({ ref: data.ref }),
          isError: false,
          handle: { kind: "branch", owner, repo, branchRef: branch_name },
        };
      }
      case "createBlob": {
        const { owner, repo, content, encoding } = input as {
          owner: string;
          repo: string;
          content: string;
          encoding?: string;
        };
        const { data } = (await octokit.request(
          "POST /repos/{owner}/{repo}/git/blobs",
          { owner, repo, content, encoding: encoding ?? "utf-8" },
        )) as { data: { sha: string } };
        return {
          content: JSON.stringify({ sha: data.sha }),
          isError: false,
        };
      }
      case "createCommit": {
        const params = input as {
          owner: string;
          repo: string;
          message: string;
          tree: string;
          parents?: string[];
        };
        const { data } = (await octokit.request(
          "POST /repos/{owner}/{repo}/git/commits",
          params,
        )) as { data: { sha: string } };
        return {
          content: JSON.stringify({ sha: data.sha }),
          isError: false,
        };
      }
      case "createPullRequest": {
        const params = input as {
          owner: string;
          repo: string;
          title?: string;
          head: string;
          base: string;
          body?: string;
          draft?: boolean;
        };
        const { owner, repo } = params;
        const { data } = (await octokit.request(
          "POST /repos/{owner}/{repo}/pulls",
          params,
        )) as {
          data: {
            number: number;
            html_url: string;
            head: { ref: string };
          };
        };
        return {
          content: JSON.stringify({
            number: data.number,
            html_url: data.html_url,
          }),
          isError: false,
          handle: {
            kind: "pr",
            owner,
            repo,
            prNumber: data.number,
            branchRef: data.head.ref,
          },
        };
      }
      default:
        return {
          content: JSON.stringify({ error: `unknown tool ${tu.name}` }),
          isError: true,
        };
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    const status = (err as { status?: number } | null)?.status;
    return {
      content: JSON.stringify({ error: message, status }),
      isError: true,
    };
  }
}

function deriveArtifactUrl(handle: ReversalHandle): string {
  switch (handle.kind) {
    case "pr_review_comment":
    case "pr_comment":
    case "issue_comment":
      return `https://github.com/${handle.owner}/${handle.repo}/issues/${handle.issueNumber ?? handle.prNumber ?? 0}#issuecomment-${handle.commentId ?? 0}`;
    case "issue_label":
      return `https://github.com/${handle.owner}/${handle.repo}/issues/${handle.issueNumber ?? 0}`;
    case "branch":
      return `https://github.com/${handle.owner}/${handle.repo}/tree/${handle.branchRef ?? ""}`;
    case "pr":
      return `https://github.com/${handle.owner}/${handle.repo}/pull/${handle.prNumber ?? 0}`;
  }
}

interface ParsedSourceRef {
  owner: string;
  repo: string;
  number: number;
}

function tryParseSourceRef(sourceRef: string): ParsedSourceRef | null {
  const m = sourceRef.match(/^(?:pr|issue|secret-scan)-([^:]+):([^:]+):(\d+)$/);
  if (!m) return null;
  return { owner: m[1], repo: m[2], number: parseInt(m[3], 10) };
}

function classifyAnthropicOrLeaseError(err: unknown): FailureReason {
  const name = (err as { name?: string } | null)?.name ?? "";
  const cause = (err as { cause?: string } | null)?.cause ?? "";
  const status = (err as { status?: number } | null)?.status;
  if (name === "ByokLeaseError" || cause === "fetch_failed" || cause === "decrypt_failed" || cause === "escape") {
    return "byok_lease_unavailable";
  }
  if (name === "MissingByokKeyError") {
    return "byok_lease_unavailable";
  }
  if (status === 429) return "anthropic_rate_limited";
  if (
    name === "APIConnectionTimeoutError" ||
    name === "APIConnectionError" ||
    /timeout/i.test(String((err as Error | null)?.message ?? ""))
  ) {
    return "anthropic_timeout";
  }
  return "anthropic_timeout";
}

async function persistFailure(
  step: HandlerArgs["step"],
  args: {
    actionSendId: string;
    reason: FailureReason;
    err: unknown;
    founderId: string;
    messageId: string;
    actionClass: ActionClass;
    sourceRef: string;
    logger: HandlerArgs["logger"];
    /**
     * Cost-breaker notification context (feat-l5-runaway-guard PR-A). Present
     * only at the cost/turn-cap/pause call sites; its presence + a reason in
     * COST_BREAKER_NOTIFY_REASONS is what triggers the single notify call.
     */
    notify?: {
      whichWindow: "spawn" | "cap-1h";
      cumulativeCents: number | null;
      ceilingCents: number | null;
    };
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

  // Single notification site (AC3), BEFORE the action_sends UPDATE — mirroring
  // the Sentry-mirror-first ordering above. Wrapped in its OWN memoized
  // step.run so Inngest fires it EXACTLY ONCE across function replays/retries
  // (a raw side-effect here re-executes on every replay → duplicate founder
  // pages) AND awaits completion so the push/email isn't torn down at a later
  // step boundary. `notifyOfflineUser` never throws (it mirrors its own send
  // failures to Sentry via op=notify-cost-breaker), so the step always
  // succeeds and can never mask the terminal state write. `isCostBreakerReason`
  // means cancelled_by_operator / run_paused / infra reasons never page.
  const notify = args.notify;
  if (notify && isCostBreakerReason(reason)) {
    await step.run("notify-cost-breaker", () =>
      notifyOfflineUser(args.founderId, {
        type: "cost_breaker_tripped",
        reason,
        which_window: notify.whichWindow,
        context: {
          cumulativeCents: notify.cumulativeCents,
          ceilingCents: notify.ceilingCents,
        },
      }),
    );
  }

  try {
    await step.run("persist-failure", async () => {
      const sb = getServiceClient();
      const { error } = await sb
        .from("action_sends")
        .update({ failure_reason: reason })
        .eq("id", actionSendId);
      if (error) {
        throw error;
      }
    });
  } catch (persistErr) {
    args.logger.warn(
      {
        founderId: args.founderId,
        actionSendId,
        reason,
        persistErr,
      },
      "agent-on-spawn: persist-failure UPDATE failed; terminal state recorded via Sentry mirror only",
    );
  }
  return { acknowledged: false, failureReason: reason };
}

export const agentOnSpawnRequested = inngest.createFunction(
  {
    id: "agent-on-spawn-requested",
    idempotency: "event.data.actionSendId",
    retries: 3,
    // AC7 — 10-minute timeout. 8 turns × 60s per-turn budget + 2 min
    // for step replay + DB writes.
    timeouts: { finish: "10m" },
  } as unknown as Parameters<typeof inngest.createFunction>[0],
  { event: "agent.spawn.requested" } as unknown as Parameters<
    typeof inngest.createFunction
  >[1],
  agentOnSpawnRequestedHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
