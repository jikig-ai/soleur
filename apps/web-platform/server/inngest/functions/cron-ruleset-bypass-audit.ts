// TR9 Phase-2 — Daily audit of the GitHub "CI Required" AND "CLA Required"
// rulesets against canonical JSON snapshots. Detects drift and files a single
// compliance/critical issue PER RULESET when any of these fire:
//   1. bypass_actors widened   (someone can now merge around the gate)
//   2. required_status_checks   (a required gate was un-required, the live set
//      diverged, or the whole required_status_checks rule is gone)
//   3. enforcement != "active"  (the whole ruleset is suspended — every gate off)
// Auto-closes each ruleset's open drift issue on its next green run.
//
// Both rulesets are audited through the SAME `auditOneRuleset` helper, each in
// its own `step.run` step (replay isolation: a throw/guard-fault on one cannot
// abort the other, and each memoizes independently on the retries:1 replay).
//
// Migrated from .github/workflows/scheduled-ruleset-bypass-audit.yml
// (deleted in #4483, TR9 Phase 2). Pure TS — no agent spawn, no ephemeral
// workspace. All IO via Octokit (installation-scoped token).
//
// Source of truth for the CI ruleset is Terraform (infra/github/
// ruleset-ci-required.tf); for the CLA ruleset it is the imperative
// scripts/create-cla-required-ruleset.sh (Terraform-ifying CLA is deferred —
// #6061 Phase 6.1). The canonical JSON snapshots this audit reads are kept in
// lockstep with those sources by sync gates in
// tests/scripts/test-audit-ruleset-bypass.sh.
//
// Guard-fault vs. drift routing (#6061): a corrupt/empty canonical, a redacted
// bypass_actors (token scope), or a network/API error is an ops/infra fault —
// it degrades the Sentry heartbeat via reportSilentFallback and does NOT file a
// compliance/critical drift issue (that fault is the CTO's, not a legal drift).
// Only real drift files the titled compliance issue.
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

// The label set the drift-issue LIST query filters on. Both rulesets' drift
// issues carry these; the per-ruleset title disambiguates which one is open.
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
  // `null` signals the required_status_checks RULE is missing entirely (a
  // catastrophic drift — every gate un-required). Kept as data, not a throw, so
  // auditOneRuleset maps it to a critical finding that FILES the issue (#6061).
  requiredStatusChecks: RequiredStatusCheck[] | null;
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

// Per-ruleset audit configuration — bundles the scalars so they thread through
// one object, not four independent params (#6061 simplicity review).
interface RulesetAuditConfig {
  rulesetName: string;
  canonicalBypassPath: string;
  canonicalRscPath: string;
  driftTitle: string;
  // Human-facing source-of-truth hint in the drift issue body (the file the
  // operator reconciles the canonical against).
  sourceHint: string;
}

const CI_AUDIT_CONFIG: RulesetAuditConfig = {
  rulesetName: "CI Required",
  canonicalBypassPath: "scripts/ci-required-ruleset-canonical-bypass-actors.json",
  canonicalRscPath:
    "scripts/ci-required-ruleset-canonical-required-status-checks.json",
  driftTitle: "[Ruleset Audit] CI Required ruleset drift",
  sourceHint: "infra/github/ruleset-ci-required.tf",
};

const CLA_AUDIT_CONFIG: RulesetAuditConfig = {
  rulesetName: "CLA Required",
  canonicalBypassPath:
    "scripts/ci-cla-required-ruleset-canonical-bypass-actors.json",
  canonicalRscPath:
    "scripts/ci-cla-required-ruleset-canonical-required-status-checks.json",
  driftTitle: "[Ruleset Audit] CLA Required ruleset drift",
  sourceHint: "scripts/create-cla-required-ruleset.sh",
};

// Per-ruleset audit result. Guard fault (guardBroken) is a Sentry-routed ops
// fault, NOT a filed drift issue; drift/criticalCount carry the compliance
// signal.
interface RulesetAuditResult {
  drift: boolean;
  findings: AuditFinding[];
  criticalCount: number;
  findingCount: number;
  issueNumber: number | null;
  closedIssueNumber: number | null;
  guardBroken: boolean;
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
 *     snapshot is stale and must be reconciled to the source of truth
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
// Helpers — read-time canonical validation
// =============================================================================

// A corrupt/empty canonical on main would make the audit read live gates as
// benign "extra" (empty canonical ⇒ every live actor/check is "added", never
// "removed"). Reject it as a GUARD FAULT (→ Sentry + heartbeat degrade) rather
// than silently pass green (#6061 R3). Applies to BOTH rulesets since both route
// through auditOneRuleset — this also closes a pre-existing latent CI hole.

function assertNonEmptyBypassCanonical(
  data: unknown,
  path: string,
): asserts data is BypassActor[] {
  if (!Array.isArray(data) || data.length === 0) {
    throw new Error(
      `Canonical ${path} is empty or not an array — refusing to audit against ` +
        "a corrupt/empty snapshot (would read live gates as benign)",
    );
  }
  for (const a of data) {
    if (typeof a !== "object" || a === null) {
      throw new Error(`Canonical ${path} has a non-object bypass_actor entry`);
    }
    const o = a as Record<string, unknown>;
    if (typeof o.actor_type !== "string" || typeof o.bypass_mode !== "string") {
      throw new Error(`Canonical ${path} has a malformed bypass_actor entry`);
    }
    if (!(o.actor_id === null || typeof o.actor_id === "number")) {
      throw new Error(`Canonical ${path} bypass_actor.actor_id is not number|null`);
    }
  }
}

function assertNonEmptyRscCanonical(
  data: unknown,
  path: string,
): asserts data is RequiredStatusCheck[] {
  if (!Array.isArray(data) || data.length === 0) {
    throw new Error(
      `Canonical ${path} is empty or not an array — refusing to audit against ` +
        "a corrupt/empty snapshot (would read live gates as benign)",
    );
  }
  for (const c of data) {
    if (typeof c !== "object" || c === null) {
      throw new Error(`Canonical ${path} has a non-object required-check entry`);
    }
    const o = c as Record<string, unknown>;
    if (typeof o.context !== "string") {
      throw new Error(`Canonical ${path} required-check.context is not a string`);
    }
    if (!(o.integration_id === null || typeof o.integration_id === "number")) {
      throw new Error(
        `Canonical ${path} required-check.integration_id is not number|null`,
      );
    }
  }
}

// =============================================================================
// Helpers — Octokit operations
// =============================================================================

async function newOctokit(installationToken: string): Promise<Octokit> {
  const { Octokit: OctokitCtor } = await import("@octokit/core");
  return new OctokitCtor({ auth: installationToken }) as unknown as Octokit;
}

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
 * Fetch a live ruleset detail by name: enforcement, bypass_actors, and
 * required_status_checks. The list endpoint omits bypass_actors/rules, so the
 * individual-ruleset GET is required.
 *
 * Throws (→ guard fault) when the ruleset is absent or bypass_actors is
 * redacted (token scope). Signals a MISSING required_status_checks rule as
 * `requiredStatusChecks: null` (data, not a throw) so the catastrophic
 * "gate missing entirely" drift files the compliance issue (#6061 G1.2).
 */
async function fetchRulesetDetail(
  octokit: Octokit,
  rulesetName: string,
): Promise<RulesetDetail> {
  const list = (await octokit.request("GET /repos/{owner}/{repo}/rulesets", {
    owner: REPO_OWNER,
    repo: REPO_NAME,
    per_page: 100,
  })) as { data: Array<{ id: number; name: string }> };

  const ruleset = list.data.find((r) => r.name === rulesetName);
  if (!ruleset) {
    throw new Error(
      `Ruleset "${rulesetName}" not found in ${REPO_OWNER}/${REPO_NAME}`,
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
      `Ruleset "${rulesetName}" response missing bypass_actors — ` +
        "installation token may lack administration:read scope",
    );
  }

  const rscRule = detail.data.rules?.find(
    (r) => r.type === "required_status_checks",
  );
  const requiredStatusChecks = rscRule?.parameters?.required_status_checks
    ? rscRule.parameters.required_status_checks.map((c) => ({
        context: c.context,
        integration_id: c.integration_id,
      }))
    : null;

  return {
    enforcement: detail.data.enforcement ?? "unknown",
    bypassActors: detail.data.bypass_actors,
    requiredStatusChecks,
  };
}

async function findOpenDriftIssue(
  octokit: Octokit,
  config: RulesetAuditConfig,
): Promise<number | null> {
  const resp = (await octokit.request("GET /repos/{owner}/{repo}/issues", {
    owner: REPO_OWNER,
    repo: REPO_NAME,
    state: "open",
    labels: DRIFT_LABELS.join(","),
    per_page: 100,
  })) as { data: Array<{ number: number; title: string }> };

  const existing = resp.data.find((i) => i.title === config.driftTitle);
  return existing?.number ?? null;
}

function renderIssueBody(
  findings: AuditFinding[],
  config: RulesetAuditConfig,
): string {
  const sections = findings
    .map(
      (f) => `### ${f.critical ? "🔴" : "⚠️"} ${f.summary}\n\n${f.detail}`,
    )
    .join("\n\n");

  return (
    `## ${config.rulesetName} ruleset drift detected\n\n` +
    `The live \`${config.rulesetName}\` ruleset has diverged from the canonical ` +
    `snapshots (source of truth: \`${config.sourceHint}\`).\n\n` +
    `${sections}\n\n` +
    `### What to do\n\n` +
    `Triage by drift class per the ` +
    `[ruleset-bypass-drift.md runbook](https://github.com/${REPO_OWNER}/${REPO_NAME}/blob/main/knowledge-base/engineering/operations/runbooks/ruleset-bypass-drift.md). ` +
    `If the change is authorized, reconcile \`${config.sourceHint}\` ` +
    `and the canonical JSON snapshots together (the sync gate requires both). ` +
    `If unauthorized, treat as an auth-broken incident.\n\n` +
    `_Auto-created by the [scheduled-ruleset-bypass-audit Inngest function](https://github.com/${REPO_OWNER}/${REPO_NAME}/blob/main/apps/web-platform/server/inngest/functions/cron-ruleset-bypass-audit.ts). It auto-closes on the next green run._`
  );
}

async function fileDriftIssue(
  octokit: Octokit,
  findings: AuditFinding[],
  config: RulesetAuditConfig,
): Promise<number> {
  const resp = (await octokit.request("POST /repos/{owner}/{repo}/issues", {
    owner: REPO_OWNER,
    repo: REPO_NAME,
    title: config.driftTitle,
    body: renderIssueBody(findings, config),
    labels: [...DRIFT_LABELS, "priority/p1-high", "domain/legal"],
  })) as { data: { number: number } };

  return resp.data.number;
}

async function closeDriftIssue(
  octokit: Octokit,
  issueNumber: number,
  config: RulesetAuditConfig,
): Promise<void> {
  await octokit.request(
    "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
    {
      owner: REPO_OWNER,
      repo: REPO_NAME,
      issue_number: issueNumber,
      body:
        `✅ Ruleset audit green — live \`${config.rulesetName}\` ruleset matches ` +
        "the canonical snapshots (bypass_actors, required_status_checks) and " +
        "`enforcement` is `active`. Auto-closing.",
    },
  );
  await octokit.request("PATCH /repos/{owner}/{repo}/issues/{issue_number}", {
    owner: REPO_OWNER,
    repo: REPO_NAME,
    issue_number: issueNumber,
    state: "closed",
    state_reason: "completed",
  });
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

  // 3. required_status_checks. A null value means the whole rule is gone —
  //    the most catastrophic drift (every gate un-required). Otherwise removal
  //    (un-requiring a gate) is critical; an extra live check is divergence-only
  //    (canonical snapshot is stale).
  if (detail.requiredStatusChecks === null) {
    findings.push({
      kind: "required_status_checks",
      critical: true,
      summary: "required_status_checks rule missing entirely",
      detail:
        "The ruleset has NO required_status_checks rule — every required gate " +
        "is un-enforced. PRs can merge with no status check required.",
    });
  } else {
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
          "source of truth:\n\n```json\n" +
          JSON.stringify(rsc.added, null, 2) +
          "\n```",
      });
    }
  }

  return findings;
}

// =============================================================================
// Audit — one ruleset end-to-end (fetch → validate → compare → file/close)
// =============================================================================

/**
 * Audit a single ruleset against its canonical snapshots and reconcile its
 * drift issue. The WHOLE body runs inside one try/catch (#6061 arch MEDIUM):
 * fetchCanonicalJson throws on bad base64/JSON *before* validation runs, so the
 * catch must envelop the fetch too.
 *
 * Guard fault (corrupt/empty canonical, redacted bypass_actors, network/API
 * error) → `guardBroken: true` → Sentry via reportSilentFallback + heartbeat
 * degrade; does NOT file a compliance/legal drift issue and does NOT treat the
 * empty canonical as green. Real drift → critical finding(s) → files the titled
 * issue.
 */
async function auditOneRuleset(
  octokit: Octokit,
  config: RulesetAuditConfig,
  logger: HandlerArgs["logger"],
): Promise<RulesetAuditResult> {
  try {
    const [rawBypass, rawRsc, detail] = await Promise.all([
      fetchCanonicalJson<unknown>(octokit, config.canonicalBypassPath),
      fetchCanonicalJson<unknown>(octokit, config.canonicalRscPath),
      fetchRulesetDetail(octokit, config.rulesetName),
    ]);

    // Read-time canonical validation (before buildFindings) — an empty/corrupt
    // snapshot is a guard fault, not benign green.
    assertNonEmptyBypassCanonical(rawBypass, config.canonicalBypassPath);
    assertNonEmptyRscCanonical(rawRsc, config.canonicalRscPath);

    const findings = buildFindings(detail, rawBypass, rawRsc);
    const criticalCount = findings.filter((f) => f.critical).length;

    const existingIssue = await findOpenDriftIssue(octokit, config);

    // Green: no findings → auto-close any open drift issue.
    if (findings.length === 0) {
      let closedIssueNumber: number | null = null;
      if (existingIssue) {
        await closeDriftIssue(octokit, existingIssue, config);
        closedIssueNumber = existingIssue;
        logger.info(
          {
            fn: "cron-ruleset-bypass-audit",
            ruleset: config.rulesetName,
            issueNumber: existingIssue,
          },
          "Auto-closed stale drift issue on green run",
        );
      } else {
        logger.info(
          { fn: "cron-ruleset-bypass-audit", ruleset: config.rulesetName },
          "Ruleset matches canonical — no drift",
        );
      }
      return {
        drift: false,
        findings,
        criticalCount: 0,
        findingCount: 0,
        issueNumber: null,
        closedIssueNumber,
        guardBroken: false,
      };
    }

    // Drift: file (or de-dupe to) the single open drift issue.
    logger.warn(
      { fn: "cron-ruleset-bypass-audit", ruleset: config.rulesetName, findings },
      `DRIFT: ${config.rulesetName} ruleset diverged from canonical`,
    );

    let issueNumber: number | null = existingIssue;
    if (existingIssue) {
      logger.info(
        {
          fn: "cron-ruleset-bypass-audit",
          ruleset: config.rulesetName,
          issueNumber: existingIssue,
        },
        "Drift issue already open — skipping creation",
      );
    } else {
      issueNumber = await fileDriftIssue(octokit, findings, config);
      logger.info(
        {
          fn: "cron-ruleset-bypass-audit",
          ruleset: config.rulesetName,
          issueNumber,
        },
        "Filed drift issue",
      );
    }

    return {
      drift: true,
      findings,
      criticalCount,
      findingCount: findings.length,
      issueNumber,
      closedIssueNumber: null,
      guardBroken: false,
    };
  } catch (err) {
    // Guard fault: canonical corrupt/empty, bypass_actors redacted (token
    // scope), or a network/API error. Route to Sentry (CTO-visible) + degrade
    // the heartbeat; do NOT file a compliance/legal drift issue.
    reportSilentFallback(err, {
      feature: "cron-ruleset-bypass-audit",
      op: "audit-ruleset",
      message: `Guard fault auditing "${config.rulesetName}" ruleset — cannot compare against canonical`,
      extra: { fn: "cron-ruleset-bypass-audit", ruleset: config.rulesetName },
    });
    return {
      drift: false,
      findings: [],
      criticalCount: 0,
      findingCount: 0,
      issueNumber: null,
      closedIssueNumber: null,
      guardBroken: true,
    };
  }
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
  ci: RulesetAuditResult;
  cla: RulesetAuditResult;
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

  // --- Step 2: audit CI ruleset (own step — replay isolation from CLA) ---
  const ci = await step.run("audit-ci-ruleset", async () => {
    const octokit = await newOctokit(installationToken);
    return auditOneRuleset(octokit, CI_AUDIT_CONFIG, logger);
  });

  // --- Step 3: audit CLA ruleset (own step — a CLA throw cannot abort CI) ---
  const cla = await step.run("audit-cla-ruleset", async () => {
    const octokit = await newOctokit(installationToken);
    return auditOneRuleset(octokit, CLA_AUDIT_CONFIG, logger);
  });

  // Re-derive the aggregate from BOTH rulesets so a leftover single-ruleset
  // count can never keep the heartbeat green on the other's critical (#6061 G1.3).
  const criticalCount = ci.criticalCount + cla.criticalCount;
  const findingCount = ci.findingCount + cla.findingCount;
  const guardBroken = ci.guardBroken || cla.guardBroken;
  const ok = criticalCount === 0 && !guardBroken;

  // --- Step 4: Sentry heartbeat ---
  // A non-critical divergence (live has extra gates) is still "ok" — only a
  // critical finding on EITHER ruleset, or a guard fault, degrades the heartbeat.
  await step.run("sentry-heartbeat", async () => {
    await postSentryHeartbeat({
      ok,
      sentryMonitorSlug: SENTRY_MONITOR_SLUG,
      cronName: "cron-ruleset-bypass-audit",
      logger,
    });
  });

  return {
    ok,
    drift: ci.drift || cla.drift,
    criticalCount,
    findingCount,
    ci,
    cla,
  };
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
