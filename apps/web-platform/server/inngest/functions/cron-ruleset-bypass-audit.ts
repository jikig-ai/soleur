// TR9 Phase-2 — Daily audit of the GitHub "CI Required" ruleset against
// canonical JSON snapshots. Detects three drift classes and files a single
// compliance/critical issue when any fires:
//   1. bypass_actors widened   (someone can now merge around required checks)
//   2. required_status_checks   (a required gate was un-required, or the live
//      set diverged from the canonical snapshot)
//   3. enforcement != "active"  (the whole ruleset is suspended — every gate
//      is off while it stays non-active)
// Auto-closes the open drift issue on the next green run.
//
// Migrated from .github/workflows/scheduled-ruleset-bypass-audit.yml
// (deleted in #4483, TR9 Phase 2). The required_status_checks + enforcement
// detection and the auto-close-on-green behavior were dropped in that port and
// restored here (#4397). Pure TS — no agent spawn, no ephemeral workspace. All
// IO via Octokit (installation-scoped token).
//
// Source of truth for the live ruleset is Terraform (infra/github/
// ruleset-ci-required.tf). The canonical JSON snapshots this audit reads are
// kept in lockstep with that .tf by the canonical↔terraform sync gate in
// tests/scripts/test-audit-ruleset-bypass.sh — that gate is what prevents the
// stale-snapshot drift that produced #4397.
//
// ADR-033 invariants:
//   I1 — All outbound IO is inside step.run for Inngest replay memoization.
//   I2 — Trivially satisfied: no claude / no BYOK lease.
//   I3 — No long-running subprocess; Octokit timeout bounds wallclock.
//   I5 — Deterministic step.run return shapes.
//   I6 — N/A; this function emits no Inngest events.

import type { Octokit } from "@octokit/core";
import { inngest } from "@/server/inngest/client";
import { reportSilentFallback } from "@/server/observability";
import {
  REPO_OWNER,
  REPO_NAME,
  mintInstallationToken,
  postSentryHeartbeat,
  type HandlerArgs,
} from "./_cron-shared";

// =============================================================================
// Constants
// =============================================================================

const SENTRY_MONITOR_SLUG = "scheduled-ruleset-bypass-audit";

// Installation-token lifetime floor: 15-min headroom for a handful of API calls.
const TOKEN_MIN_LIFETIME_MS = 15 * 60 * 1000;

const CANONICAL_BYPASS_ACTORS_PATH =
  "scripts/ci-required-ruleset-canonical-bypass-actors.json";

const CANONICAL_REQUIRED_STATUS_CHECKS_PATH =
  "scripts/ci-required-ruleset-canonical-required-status-checks.json";

const RULESET_NAME = "CI Required";

const DRIFT_ISSUE_TITLE = "[Ruleset Audit] CI Required ruleset drift";

const DRIFT_LABELS = ["ci/auth-broken", "compliance/critical"] as const;

// =============================================================================
// Types
// =============================================================================

export interface BypassActor {
  actor_id: number | null;
  actor_type: string;
  bypass_mode: string;
}

export interface RequiredStatusCheck {
  context: string;
  integration_id: number | null;
}

interface RulesetDetail {
  enforcement: string;
  bypassActors: BypassActor[];
  requiredStatusChecks: RequiredStatusCheck[];
}

// A single audit finding. `critical` distinguishes the security-weakening
// directions (widened bypass, dropped required check, suspended enforcement)
// from divergence-only signals (live has MORE required checks than canonical —
// safe, but the canonical snapshot is stale and must be reconciled).
export interface AuditFinding {
  kind: "bypass_actors" | "required_status_checks" | "enforcement";
  critical: boolean;
  summary: string;
  detail: string;
}

// =============================================================================
// Helpers — comparison logic
// =============================================================================

/**
 * Compare canonical vs actual bypass actors.
 *
 * Returns:
 *   - `drift: true` if actual has actors NOT in canonical (widened).
 *   - `removed` list if canonical has actors NOT in actual (narrowed, warn only).
 *   - `match: true` if sets are identical.
 */
export function compareBypassActors(
  canonical: BypassActor[],
  actual: BypassActor[],
): {
  drift: boolean;
  added: BypassActor[];
  removed: BypassActor[];
  match: boolean;
} {
  const key = (a: BypassActor) =>
    `${a.actor_id ?? "null"}|${a.actor_type}|${a.bypass_mode}`;

  const canonicalKeys = new Set(canonical.map(key));
  const actualKeys = new Set(actual.map(key));

  const added = actual.filter((a) => !canonicalKeys.has(key(a)));
  const removed = canonical.filter((a) => !actualKeys.has(key(a)));

  return {
    drift: added.length > 0,
    added,
    removed,
    match: added.length === 0 && removed.length === 0,
  };
}

/**
 * Compare canonical vs actual required_status_checks.
 *
 * Direction matters for required checks (opposite of bypass_actors):
 *   - `removed` (canonical has it, live does NOT) is the dangerous direction —
 *     a required gate was un-required and PRs can now merge without it.
 *   - `added` (live has it, canonical does NOT) means the live ruleset has MORE
 *     gates than the snapshot. Safe for merge-security, but the canonical
 *     snapshot is stale and must be reconciled to the Terraform source of truth
 *     (this exact staleness produced the false-positive #4397).
 *
 * Comparison is on the (context, integration_id) pair: the integration_id is
 * load-bearing (CodeQL is pinned to the GitHub Advanced Security app id; a
 * same-name check from github-actions[bot] would NOT satisfy the gate).
 */
export function compareRequiredStatusChecks(
  canonical: RequiredStatusCheck[],
  actual: RequiredStatusCheck[],
): {
  added: RequiredStatusCheck[];
  removed: RequiredStatusCheck[];
  match: boolean;
} {
  const key = (c: RequiredStatusCheck) =>
    `${c.context}|${c.integration_id ?? "null"}`;

  const canonicalKeys = new Set(canonical.map(key));
  const actualKeys = new Set(actual.map(key));

  const added = actual.filter((c) => !canonicalKeys.has(key(c)));
  const removed = canonical.filter((c) => !actualKeys.has(key(c)));

  return {
    added,
    removed,
    match: added.length === 0 && removed.length === 0,
  };
}

// =============================================================================
// Helpers — Octokit operations
// =============================================================================

async function fetchCanonicalJson<T>(
  octokit: Octokit,
  path: string,
): Promise<T> {
  const resp = (await octokit.request(
    "GET /repos/{owner}/{repo}/contents/{path}",
    {
      owner: REPO_OWNER,
      repo: REPO_NAME,
      path,
    },
  )) as { data: { content?: string; encoding?: string } };

  if (!resp.data.content || resp.data.encoding !== "base64") {
    throw new Error(
      `Unexpected content encoding for ${path}: ${resp.data.encoding}`,
    );
  }

  const decoded = Buffer.from(resp.data.content, "base64").toString("utf-8");
  return JSON.parse(decoded) as T;
}

/**
 * Fetch the live "CI Required" ruleset detail: enforcement, bypass_actors, and
 * required_status_checks. The list endpoint omits bypass_actors/rules, so the
 * individual-ruleset GET is required.
 */
async function fetchRulesetDetail(octokit: Octokit): Promise<RulesetDetail> {
  const list = (await octokit.request("GET /repos/{owner}/{repo}/rulesets", {
    owner: REPO_OWNER,
    repo: REPO_NAME,
    per_page: 100,
  })) as { data: Array<{ id: number; name: string }> };

  const ruleset = list.data.find((r) => r.name === RULESET_NAME);
  if (!ruleset) {
    throw new Error(
      `Ruleset "${RULESET_NAME}" not found in ${REPO_OWNER}/${REPO_NAME}`,
    );
  }

  const detail = (await octokit.request(
    "GET /repos/{owner}/{repo}/rulesets/{ruleset_id}",
    {
      owner: REPO_OWNER,
      repo: REPO_NAME,
      ruleset_id: ruleset.id,
    },
  )) as {
    data: {
      enforcement?: string;
      bypass_actors?: BypassActor[];
      rules?: Array<{
        type: string;
        parameters?: {
          required_status_checks?: RequiredStatusCheck[];
        };
      }>;
    };
  };

  if (!detail.data.bypass_actors) {
    throw new Error(
      `Ruleset "${RULESET_NAME}" response missing bypass_actors — ` +
        "installation token may lack administration:read scope",
    );
  }

  const rscRule = detail.data.rules?.find(
    (r) => r.type === "required_status_checks",
  );
  if (!rscRule?.parameters?.required_status_checks) {
    throw new Error(
      `Ruleset "${RULESET_NAME}" has no required_status_checks rule — ` +
        "the required-check gate is missing entirely",
    );
  }

  return {
    enforcement: detail.data.enforcement ?? "unknown",
    bypassActors: detail.data.bypass_actors,
    requiredStatusChecks: rscRule.parameters.required_status_checks.map((c) => ({
      context: c.context,
      integration_id: c.integration_id,
    })),
  };
}

async function findOpenDriftIssue(
  octokit: Octokit,
): Promise<number | null> {
  const resp = (await octokit.request("GET /repos/{owner}/{repo}/issues", {
    owner: REPO_OWNER,
    repo: REPO_NAME,
    state: "open",
    labels: DRIFT_LABELS.join(","),
    per_page: 100,
  })) as { data: Array<{ number: number; title: string }> };

  const existing = resp.data.find((i) => i.title === DRIFT_ISSUE_TITLE);
  return existing?.number ?? null;
}

function renderIssueBody(findings: AuditFinding[]): string {
  const sections = findings
    .map(
      (f) =>
        `### ${f.critical ? "🔴" : "⚠️"} ${f.summary}\n\n${f.detail}`,
    )
    .join("\n\n");

  return (
    `## CI Required ruleset drift detected\n\n` +
    `The live \`CI Required\` ruleset has diverged from the canonical ` +
    `snapshots (source of truth: \`infra/github/ruleset-ci-required.tf\`).\n\n` +
    `${sections}\n\n` +
    `### What to do\n\n` +
    `Triage by drift class per the ` +
    `[ruleset-bypass-drift.md runbook](https://github.com/${REPO_OWNER}/${REPO_NAME}/blob/main/knowledge-base/engineering/operations/runbooks/ruleset-bypass-drift.md). ` +
    `If the change is authorized, reconcile \`infra/github/ruleset-ci-required.tf\` ` +
    `and the canonical JSON snapshots together (the sync gate requires both). ` +
    `If unauthorized, treat as an auth-broken incident.\n\n` +
    `_Auto-created by the [scheduled-ruleset-bypass-audit Inngest function](https://github.com/${REPO_OWNER}/${REPO_NAME}/blob/main/apps/web-platform/server/inngest/functions/cron-ruleset-bypass-audit.ts). It auto-closes on the next green run._`
  );
}

async function fileDriftIssue(
  octokit: Octokit,
  findings: AuditFinding[],
): Promise<number> {
  const resp = (await octokit.request("POST /repos/{owner}/{repo}/issues", {
    owner: REPO_OWNER,
    repo: REPO_NAME,
    title: DRIFT_ISSUE_TITLE,
    body: renderIssueBody(findings),
    labels: [...DRIFT_LABELS, "priority/p1-high", "domain/legal"],
  })) as { data: { number: number } };

  return resp.data.number;
}

async function closeDriftIssue(
  octokit: Octokit,
  issueNumber: number,
): Promise<void> {
  await octokit.request(
    "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
    {
      owner: REPO_OWNER,
      repo: REPO_NAME,
      issue_number: issueNumber,
      body:
        "✅ Ruleset audit green — live `CI Required` ruleset matches the " +
        "canonical snapshots (bypass_actors, required_status_checks) and " +
        "`enforcement` is `active`. Auto-closing.",
    },
  );
  await octokit.request(
    "PATCH /repos/{owner}/{repo}/issues/{issue_number}",
    {
      owner: REPO_OWNER,
      repo: REPO_NAME,
      issue_number: issueNumber,
      state: "closed",
      state_reason: "completed",
    },
  );
}

// =============================================================================
// Audit — pure assembly of findings from a ruleset detail + canonicals
// =============================================================================

export function buildFindings(
  detail: RulesetDetail,
  canonicalBypassActors: BypassActor[],
  canonicalRequiredChecks: RequiredStatusCheck[],
): AuditFinding[] {
  const findings: AuditFinding[] = [];

  // 1. enforcement must be active — a suspended ruleset turns off every gate.
  if (detail.enforcement !== "active") {
    findings.push({
      kind: "enforcement",
      critical: true,
      summary: `Ruleset enforcement is "${detail.enforcement}", not "active"`,
      detail:
        "Every required check and bypass guarantee is suspended while " +
        "enforcement is non-active. PRs can merge with no gate running.",
    });
  }

  // 2. bypass_actors — widening (added) is the dangerous direction.
  const ba = compareBypassActors(canonicalBypassActors, detail.bypassActors);
  if (ba.drift) {
    findings.push({
      kind: "bypass_actors",
      critical: true,
      summary: "bypass_actors widened beyond canonical",
      detail:
        "Actors present live but NOT in canonical (can merge around required " +
        "checks):\n\n```json\n" +
        JSON.stringify(ba.added, null, 2) +
        "\n```",
    });
  }

  // 3. required_status_checks — removal (un-requiring a gate) is critical;
  //    an extra live check is divergence-only (canonical snapshot is stale).
  const rsc = compareRequiredStatusChecks(
    canonicalRequiredChecks,
    detail.requiredStatusChecks,
  );
  if (rsc.removed.length > 0) {
    findings.push({
      kind: "required_status_checks",
      critical: true,
      summary: "required_status_checks dropped a gate",
      detail:
        "Checks required by canonical but NOT enforced live (a gate was " +
        "un-required):\n\n```json\n" +
        JSON.stringify(rsc.removed, null, 2) +
        "\n```",
    });
  }
  if (rsc.added.length > 0) {
    findings.push({
      kind: "required_status_checks",
      critical: false,
      summary: "required_status_checks diverged (live has extra gates)",
      detail:
        "Checks enforced live but NOT in the canonical snapshot. Merge-" +
        "security is intact, but the snapshot is stale — reconcile it to the " +
        "Terraform source of truth:\n\n```json\n" +
        JSON.stringify(rsc.added, null, 2) +
        "\n```",
    });
  }

  return findings;
}

// =============================================================================
// Handler
// =============================================================================

export async function cronRulesetBypassAuditHandler({
  step,
  logger,
}: HandlerArgs): Promise<{
  ok: boolean;
  drift: boolean;
  criticalCount: number;
  findingCount: number;
  issueNumber: number | null;
  closedIssueNumber: number | null;
}> {
  // --- Step 1: mint installation token ---
  const installationToken = await step.run(
    "mint-installation-token",
    async () => {
      return mintInstallationToken({
        tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS,
      });
    },
  );

  // --- Step 2: audit ruleset (enforcement + bypass_actors + required checks) ---
  const result = await step.run("audit-ruleset", async () => {
    const { Octokit: OctokitCtor } = await import("@octokit/core");
    const octokit = new OctokitCtor({
      auth: installationToken,
    }) as unknown as Octokit;

    const [canonicalBypassActors, canonicalRequiredChecks, detail] =
      await Promise.all([
        fetchCanonicalJson<BypassActor[]>(
          octokit,
          CANONICAL_BYPASS_ACTORS_PATH,
        ),
        fetchCanonicalJson<RequiredStatusCheck[]>(
          octokit,
          CANONICAL_REQUIRED_STATUS_CHECKS_PATH,
        ),
        fetchRulesetDetail(octokit),
      ]);

    const findings = buildFindings(
      detail,
      canonicalBypassActors,
      canonicalRequiredChecks,
    );
    const criticalCount = findings.filter((f) => f.critical).length;

    const existingIssue = await findOpenDriftIssue(octokit);

    // Green: no findings → auto-close any open drift issue.
    if (findings.length === 0) {
      let closedIssueNumber: number | null = null;
      if (existingIssue) {
        try {
          await closeDriftIssue(octokit, existingIssue);
          closedIssueNumber = existingIssue;
          logger.info(
            { fn: "cron-ruleset-bypass-audit", issueNumber: existingIssue },
            "Auto-closed stale drift issue on green run",
          );
        } catch (err) {
          reportSilentFallback(err, {
            feature: "cron-ruleset-bypass-audit",
            op: "close-drift-issue",
            message: "Failed to auto-close drift issue",
            extra: { fn: "cron-ruleset-bypass-audit" },
          });
        }
      } else {
        logger.info(
          { fn: "cron-ruleset-bypass-audit" },
          "Ruleset matches canonical — no drift",
        );
      }
      return {
        drift: false,
        criticalCount: 0,
        findingCount: 0,
        issueNumber: null as number | null,
        closedIssueNumber,
      };
    }

    // Drift: file (or de-dupe to) the single open drift issue.
    logger.warn(
      { fn: "cron-ruleset-bypass-audit", findings },
      "DRIFT: CI Required ruleset diverged from canonical",
    );

    let issueNumber: number | null = existingIssue;
    if (existingIssue) {
      logger.info(
        { fn: "cron-ruleset-bypass-audit", issueNumber: existingIssue },
        "Drift issue already open — skipping creation",
      );
    } else {
      try {
        issueNumber = await fileDriftIssue(octokit, findings);
        logger.info(
          { fn: "cron-ruleset-bypass-audit", issueNumber },
          "Filed drift issue",
        );
      } catch (err) {
        reportSilentFallback(err, {
          feature: "cron-ruleset-bypass-audit",
          op: "file-drift-issue",
          message: "Failed to file drift issue",
          extra: { fn: "cron-ruleset-bypass-audit" },
        });
      }
    }

    return {
      drift: true,
      criticalCount,
      findingCount: findings.length,
      issueNumber,
      closedIssueNumber: null as number | null,
    };
  });

  // --- Step 3: Sentry heartbeat ---
  // A non-critical divergence (live has extra gates) is still "ok" for the
  // heartbeat — merge-security is intact; only critical findings degrade it.
  const ok = result.criticalCount === 0;
  await step.run("sentry-heartbeat", async () => {
    await postSentryHeartbeat({
      ok,
      sentryMonitorSlug: SENTRY_MONITOR_SLUG,
      cronName: "cron-ruleset-bypass-audit",
      logger,
    });
  });

  return { ok, ...result };
}

// =============================================================================
// Registration
// =============================================================================

export const cronRulesetBypassAudit = inngest.createFunction(
  {
    id: "cron-ruleset-bypass-audit",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "13 6 * * *" },
    { event: "cron/ruleset-bypass-audit.manual-trigger" },
  ],
  cronRulesetBypassAuditHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
