// PR-H (#3244) Phase 4 — single Inngest function handling all 4 GitHub
// event classes via strategy table. Mirrors ADR-030 invariants:
//   I1: runWithByokLease INSIDE each SDK-calling step.run
//   I2: getFreshTenantClient INSIDE each tenant-touching step
//   I3: verify-state OUTSIDE step.run (single-pass re-verify on retry)
//   I5: "drafts everywhere, sends nowhere" — status='draft' only
//
// RV (plan-review consensus): one function, not four. Concurrency CEL
// key `event.data.founderId + ':' + event.name` keeps parallel
// processing of different event classes for the same founder.

import { inngest } from "@/server/inngest/client";
import { getFreshTenantClient } from "@/lib/supabase/tenant";
// BYOK Delegations PR-A (#4232): see note at agent-runner.ts.
import { resolveKeyOwnerThenLease } from "@/server/byok-resolver";
import { reportSilentFallback } from "@/server/observability";
import { redactGithubSourcedText } from "@/lib/safety/redaction-allowlist";
import {
  MESSAGE_STATUS_DRAFT,
  MESSAGE_SOURCE_GITHUB,
  MESSAGE_TIER_EXTERNAL_LOW_STAKES,
} from "@/lib/messages/tiers";
import {
  ACTION_CLASS_DEFAULTS,
  type ActionClassTier,
} from "@/server/scope-grants/action-class-map";
import { PG_UNIQUE_VIOLATION } from "@/lib/postgres-errors";
import {
  GITHUB_EVENT_STRATEGIES,
  resolveOwningDomain,
  isKnownGitHubActionClass,
  type GitHubActionClass,
} from "./github-event-strategies";

const SUPPORTED_V = "1";

interface HandlerArgs {
  event: {
    name: string;
    v?: string;
    data: {
      founderId: string;
      installationId: number;
      deliveryId: string;
      githubEvent: string;
      action?: string | null;
      tier?: ActionClassTier;
      rawBody: string;
    };
  };
  step: {
    run<T>(name: string, cb: () => Promise<T>): Promise<T>;
  };
  logger: {
    warn: (...args: unknown[]) => void;
    info: (...args: unknown[]) => void;
    error: (...args: unknown[]) => void;
  };
}

/**
 * Derive the dedup-safe source_ref for a given event payload.
 *
 * Each event class anchors source_ref against its naturally-stable id:
 *   pr-<repo>-<number>   for pull_request
 *   ci-<workflow_run_id> for workflow_run
 *   issue-<repo>-<number> for issues
 *   cve-<advisory_id> or secret-scan-<alert_id> for security
 */
function deriveSourceRef(
  actionClass: GitHubActionClass,
  body: Record<string, unknown>,
): string | null {
  const prefix = GITHUB_EVENT_STRATEGIES[actionClass].sourceRefPrefix;
  // Keep org/repo separator as ':' (invalid in GitHub repo names per
  // https://docs.github.com/en/repositories) so 'org/repo-1' and
  // 'org/repo' with number 1 cannot collide. Mirror separator between
  // repo and number so the structure is parseable.
  const repoFullName =
    (body.repository as { full_name?: string } | undefined)?.full_name?.replace("/", ":") ?? null;

  switch (actionClass) {
    case "engineering.pr_review_pending": {
      const pr = body.pull_request as { number?: number } | undefined;
      if (!repoFullName || typeof pr?.number !== "number") return null;
      return `${prefix}${repoFullName}:${pr.number}`;
    }
    case "engineering.ci_failed": {
      const run = body.workflow_run as { id?: number } | undefined;
      if (typeof run?.id !== "number") return null;
      return `${prefix}${run.id}`;
    }
    case "triage.p0p1_issue": {
      const issue = body.issue as { number?: number } | undefined;
      if (!repoFullName || typeof issue?.number !== "number") return null;
      return `${prefix}${repoFullName}:${issue.number}`;
    }
    case "security.cve_alert": {
      const adv = body.repository_advisory as { ghsa_id?: string } | undefined;
      const alert = body.alert as { number?: number } | undefined;
      if (adv?.ghsa_id) return `${prefix}${adv.ghsa_id}`;
      // Include repo prefix so secret-scan alert numbers are dedup-safe
      // across multiple installations (alert.number is per-repo, not global).
      if (typeof alert?.number === "number" && repoFullName) {
        return `secret-scan-${repoFullName}:${alert.number}`;
      }
      return null;
    }
  }
}

/**
 * Extract human-readable draft preview text from the event body.
 * Per-event-class extraction; redaction runs at INSERT time
 * (`redactGithubSourcedText` in persist-draft step).
 */
function extractRawPreview(actionClass: GitHubActionClass, body: Record<string, unknown>): string {
  switch (actionClass) {
    case "engineering.pr_review_pending": {
      const pr = body.pull_request as { title?: string; html_url?: string } | undefined;
      return `${pr?.title ?? "<no title>"} (${pr?.html_url ?? ""})`;
    }
    case "engineering.ci_failed": {
      const run = body.workflow_run as { name?: string; html_url?: string } | undefined;
      return `CI failed: ${run?.name ?? "<unknown workflow>"} (${run?.html_url ?? ""})`;
    }
    case "triage.p0p1_issue": {
      const issue = body.issue as { title?: string; body?: string } | undefined;
      return `${issue?.title ?? "<no title>"}\n\n${issue?.body ?? ""}`;
    }
    case "security.cve_alert": {
      const adv = body.repository_advisory as
        | { ghsa_id?: string; severity?: string; summary?: string }
        | undefined;
      const alert = body.alert as { secret_type?: string; number?: number } | undefined;
      if (adv) {
        return `${adv.ghsa_id ?? "<no id>"} (${adv.severity ?? "<no sev>"}): ${
          adv.summary ?? ""
        }`;
      }
      if (alert) {
        return `Secret scan alert #${alert.number ?? "?"}: ${alert.secret_type ?? "<unknown>"}`;
      }
      return "<unknown advisory>";
    }
  }
}

export async function githubOnEventHandler({
  event,
  step,
  logger,
}: HandlerArgs): Promise<
  | { deadlettered: true; reason: string }
  | { drafted: false; reason: string }
  | { drafted: true }
> {
  // Schema-gate (non-throwing). RV2: deterministic failure → no retry burn.
  const v = event.v ?? "0";
  const gate = await step.run("schema-gate", async () => {
    if (v !== SUPPORTED_V) {
      return { deadletter: true as const, reason: `schema_v=${v}` };
    }
    if (!isKnownGitHubActionClass(event.name)) {
      return { deadletter: true as const, reason: `unknown_action_class=${event.name}` };
    }
    return { deadletter: false as const, reason: "" };
  });
  if (gate.deadletter) {
    logger.warn({ name: event.name, v, reason: gate.reason }, "github-on-event deadletter");
    return { deadlettered: true, reason: gate.reason };
  }

  const actionClass = event.name as GitHubActionClass;
  const { founderId, installationId, deliveryId } = event.data;

  // I3: verify-state outside step.run. Parse body once; if rawBody is
  // malformed (post-webhook signing tampering is impossible, but
  // pre-Phase-3 fixture replays may carry an empty body), deadletter.
  let body: Record<string, unknown>;
  try {
    body = JSON.parse(event.data.rawBody);
  } catch {
    return { deadlettered: true, reason: "rawBody-not-json" };
  }

  const sourceRef = deriveSourceRef(actionClass, body);
  if (!sourceRef) {
    return { drafted: false, reason: "no-source-ref-derivable" };
  }

  const owningDomain = resolveOwningDomain(actionClass, body);
  const strategy = GITHUB_EVENT_STRATEGIES[actionClass];

  // I1: lease opens INSIDE the SDK-calling step.run. The body-draft step
  // is a stub today (mirrors cfo-on-payment-failed Phase 3 stub) — the
  // Anthropic SDK call wires in alongside cohort onboarding. The lease
  // is held open so the structural test surface stays accurate.
  //
  // byok-audit-writer-sweep: out-of-scope — PR-H Phase 4 stub holds the
  // lease open for the structural test surface (R1 / I1: lease MUST open
  // inside each SDK-calling step). The actual Anthropic SDK call +
  // per-turn recordByokUseAndCheckCap + persistTurnCost wire in PR-H+1
  // alongside the "spawn agent" action wiring. Until then there is no
  // real token cost to record; the stub returns tokenCount=0 /
  // unitCostCents=0 deterministically. Mirrors the marker at
  // cfo-on-payment-failed.ts.
  const _draft = await step.run("draft-github-card", async () => {
    // Sentinel sweep site #5 (#4232 PR-A). callerUserId = founderId
    // from Inngest event payload (server-emitted by github-on-event
    // webhook handler — never request-body-derived from GitHub
    // payload signers, which carry repo-scoped identity not user-
    // scoped).
    return resolveKeyOwnerThenLease(
      founderId,
      founderId,
      async (_lease) => {
      // STUB: leader prompt loop wires later. Return raw preview now
      // so the persist step has the right shape to redact + insert.
      return {
        rawBody: extractRawPreview(actionClass, body),
        tokenCount: 0,
        unitCostCents: 0,
      };
    });
  });

  // I2: getFreshTenantClient + per-step JWT freshness. Redaction is
  // INSERT-time per plan TR6-amendment (belt-and-suspenders; render-time
  // is the load-bearing Art. 14 gate at Phase 6).
  await step.run("persist-draft", async () => {
    const tenant = await getFreshTenantClient(founderId);
    const draftPreview = redactGithubSourcedText(_draft.rawBody, {
      source: strategy.redactSource,
    });

    const { error } = await tenant.from("messages").insert({
      user_id: founderId,
      tier: MESSAGE_TIER_EXTERNAL_LOW_STAKES,
      status: MESSAGE_STATUS_DRAFT,
      source: MESSAGE_SOURCE_GITHUB,
      source_ref: sourceRef,
      owning_domain: owningDomain,
      draft_preview: draftPreview,
      urgency: strategy.urgency,
      trust_tier: event.data.tier ?? ACTION_CLASS_DEFAULTS[actionClass],
    });

    if (error) {
      // ADR-037: the partial-unique index can fire on Inngest retry
      // (same source_ref already drafted). Treat as a non-error, no
      // throw — Inngest retries would burn budget chasing a deterministic
      // conflict.
      if (error.code === PG_UNIQUE_VIOLATION) {
        logger.info(
          { founderId, actionClass, sourceRef, deliveryId, installationId },
          "github-on-event: duplicate draft (partial-unique conflict) — idempotent skip",
        );
        return;
      }
      // Other DB errors surface to Sentry via reportSilentFallback;
      // the step throw causes Inngest to retry the persist step (with
      // the function's retries:1 cap above).
      reportSilentFallback(error, {
        feature: "github-on-event",
        op: "persist-draft",
        message: "github-on-event: persist-draft failed",
        extra: { founderId, actionClass, sourceRef },
      });
      throw error;
    }
  });

  return { drafted: true };
}

export const githubOnEvent = inngest.createFunction(
  {
    id: "github-on-event",
    concurrency: [
      // Per-(founder, event-class) parallelism: CI events do NOT queue
      // behind PR-review events for the same founder. Same founder +
      // same event class still serialize (limit:1).
      {
        scope: "fn",
        key: 'event.data.founderId + ":" + event.name',
        limit: 1,
      },
      { scope: "account", key: '"agent-runtime"', limit: 50 },
    ],
    retries: 1,
  },
  [
    { event: "engineering.pr_review_pending" },
    { event: "engineering.ci_failed" },
    { event: "triage.p0p1_issue" },
    { event: "security.cve_alert" },
  ],
  githubOnEventHandler as unknown as Parameters<typeof inngest.createFunction>[2],
);
