// #3413 — kb-template health probe (Inngest cron).
//
// Every user-account "Create Project" routes through jikig-ai/kb-template's
// /generate endpoint (server/github-app.ts header @ KB_TEMPLATE_OWNER/NAME).
// If an operator deletes/renames/privatizes the template or drops its
// `is_template` flag, every create returns 404/422 — previously detected only
// post-hoc via Sentry. This hourly cron proactively probes the template's
// documented success shape and files a P1 ops issue on drift.
//
// ARCHITECTURE: Inngest cron, NOT a GitHub Actions workflow. The codebase runs
// ~45 cron-*.ts Inngest functions vs 4 legacy scheduled-*.yml workflows; the
// direct structural sibling is cron-github-app-drift-guard.ts. Governing
// ADR-030 (Inngest as durable trigger layer for server-side agents).
//
// AUTH: createProbeOctokit() mints an installation-scoped Octokit via
// @octokit/auth-app internally — NO PAT, NO JWT-mint here
// (hr-github-app-auth-not-pat satisfied by construction).
//
// LEAK TRIPWIRE: assertNoLeak is EXPORTED by cron-github-app-drift-guard.ts and
// imported here (single source of truth for the PEM/JWT/base64-PEM regexes).
// Run every captured GitHub body through it before any issue-body write.
//
// FAILURE-LABEL FAMILIES (distinct from the drift-guard's taxonomy):
//   ops/kb-template-broken  — drift detected, user-impacting: the template was
//                             deleted/renamed (404), un-marked as a template
//                             (is_template !== true), or made private
//                             (private !== false). Onboarding "Create Project"
//                             breaks for every user.
//   ci/guard-broken         — the probe itself malfunctioned: a non-object body,
//                             a missing is_template/private field, or a non-404
//                             HTTP/network error. NOT a template-drift signal.
//
// DUPLICATION NOTE (for a future dedup issue, not filed here): the
// issue-handling shape below (dedup-search → comment-or-open → auto-close on
// PATCH state:closed) mirrors cron-github-app-drift-guard.ts's file-private
// handleFailureIssue. Those helpers are not exported by the sibling, so a
// minimal mirror is co-located here with a kb-template-specific title-phrase.
// A future PR may extract server/github/probe-issue-handler.ts shared by both.

import type { Octokit } from "@octokit/core";
import { inngest } from "@/server/inngest/client";
import { reportSilentFallback } from "@/server/observability";
import { createProbeOctokit, PROBE_ISSUE_OWNER, PROBE_ISSUE_REPO } from "@/server/github/probe-octokit";
import { KB_TEMPLATE_NAME, KB_TEMPLATE_OWNER } from "@/server/github-app";
import { assertNoLeak, redactedError } from "./cron-github-app-drift-guard";
import { postSentryHeartbeat, type HandlerArgs } from "./_cron-shared";

const SENTRY_MONITOR_SLUG = "cron-kb-template-health";
const CRON_NAME = "cron-kb-template-health";

// Dedup title-phrase — distinct from the drift-guard's "GitHub App drift-guard".
const ISSUE_TITLE_PHRASE = "kb-template health";
const ISSUE_TITLE_DRIFT = "[ops/kb-template-broken] kb-template health probe fired";
const ISSUE_TITLE_GUARD_BROKEN =
  "[ci/guard-broken] kb-template health probe malfunctioned";

const RUNBOOK_URL =
  "https://github.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/operations/runbooks/kb-template-health.md";
const RUN_URL =
  "https://de.sentry.io/organizations/jikigai-eu/crons/cron-kb-template-health/";

// =============================================================================
// Documented-success-shape predicate (pure — exported for the dry-run test)
// =============================================================================

// `ops/kb-template-broken` = real template drift (user-impacting); the create
// flow is broken. `ci/guard-broken` = the probe itself could not assert (the
// body was not the documented object shape) — a guard malfunction, NOT drift.
export type KbTemplateFailureLabel = "ops/kb-template-broken" | "ci/guard-broken";

export interface KbTemplateVerdict {
  ok: boolean;
  failureMode: string;
  failureDetail: string;
  failureLabel: KbTemplateFailureLabel;
}

const PASS_VERDICT: KbTemplateVerdict = {
  ok: true,
  failureMode: "",
  failureDetail: "",
  failureLabel: "ops/kb-template-broken",
};

/**
 * Assert the DOCUMENTED success shape of a `GET /repos/{owner}/{repo}` body for
 * the kb-template: an object carrying `is_template === true` AND
 * `private === false`.
 *
 * Pure + total — never throws, never does I/O. Exported so the dry-run test can
 * exercise it directly against the canonical synthesized repo-metadata fixture,
 * proving the probe asserts the documented shape (not merely HTTP 200).
 *
 * Routing:
 *   - non-object body / missing is_template|private field → `ci/guard-broken`
 *     (the probe could not even read the documented shape).
 *   - is_template !== true OR private !== false → `ops/kb-template-broken`
 *     (the shape was readable and the template drifted — user-impacting).
 */
export function assertKbTemplateHealthy(data: unknown): KbTemplateVerdict {
  if (!data || typeof data !== "object") {
    return {
      ok: false,
      failureMode: "response_not_object",
      failureDetail: "GET /repos returned a non-object body",
      failureLabel: "ci/guard-broken",
    };
  }
  const body = data as Record<string, unknown>;
  if (typeof body.is_template !== "boolean" || typeof body.private !== "boolean") {
    return {
      ok: false,
      failureMode: "response_missing_fields",
      failureDetail:
        "GET /repos response missing boolean is_template or private field",
      failureLabel: "ci/guard-broken",
    };
  }
  if (body.is_template !== true) {
    return {
      ok: false,
      failureMode: "is_template_dropped",
      failureDetail: `${KB_TEMPLATE_OWNER}/${KB_TEMPLATE_NAME} is no longer marked as a template (is_template=false); cross-account /generate returns 404 for every user`,
      failureLabel: "ops/kb-template-broken",
    };
  }
  if (body.private !== false) {
    return {
      ok: false,
      failureMode: "template_private",
      failureDetail: `${KB_TEMPLATE_OWNER}/${KB_TEMPLATE_NAME} was made private; cross-account /generate from user-installation tokens returns 404 for every user`,
      failureLabel: "ops/kb-template-broken",
    };
  }
  return PASS_VERDICT;
}

// =============================================================================
// Probe — GET /repos/{owner}/{repo} + documented-shape assertion
// =============================================================================

async function probeKbTemplate(args: {
  octokit: Octokit;
}): Promise<KbTemplateVerdict> {
  const { octokit } = args;
  let data: unknown;
  try {
    const res = await octokit.request("GET /repos/{owner}/{repo}", {
      owner: KB_TEMPLATE_OWNER,
      repo: KB_TEMPLATE_NAME,
    });
    data = res.data;
  } catch (err) {
    const e = err as Error & { status?: number };
    if (e.status === 404) {
      return {
        ok: false,
        failureMode: "repo_not_found",
        failureDetail: `GET /repos/${KB_TEMPLATE_OWNER}/${KB_TEMPLATE_NAME} -> 404. Template deleted, renamed, or made private — every user "Create Project" returns 404/422.`,
        failureLabel: "ops/kb-template-broken",
      };
    }
    if (typeof e.status === "number") {
      return {
        ok: false,
        failureMode: "github_api_http",
        failureDetail: `GET /repos/${KB_TEMPLATE_OWNER}/${KB_TEMPLATE_NAME} -> HTTP ${e.status}`,
        failureLabel: "ci/guard-broken",
      };
    }
    return {
      ok: false,
      failureMode: "github_api_network",
      failureDetail: `GET /repos/${KB_TEMPLATE_OWNER}/${KB_TEMPLATE_NAME} -> network error: ${e.name}: ${e.message ?? ""}`,
      failureLabel: "ci/guard-broken",
    };
  }
  return assertKbTemplateHealthy(data);
}

// A TRANSIENT probe failure is a non-404 HTTP error (5xx, 429 rate-limit) or a
// network blip — NOT a real deletion (404 → repo_not_found) and NOT a drift
// verdict (is_template/private). The sibling retries-once on a transient
// github_app_401 so a single GitHub blip auto-resolves before paging P1.
function isTransientProbeFailure(verdict: KbTemplateVerdict): boolean {
  return (
    !verdict.ok &&
    (verdict.failureMode === "github_api_http" ||
      verdict.failureMode === "github_api_network")
  );
}

// =============================================================================
// Issue body builder + filing (co-located mirror of the sibling's shape)
// =============================================================================

function buildFailureIssueBody(args: {
  verdict: KbTemplateVerdict;
  detectedAtIso: string;
}): string {
  return [
    "## kb-template health probe failed",
    "",
    `- **Failure mode:** \`${args.verdict.failureMode}\``,
    `- **Detail:** ${args.verdict.failureDetail}`,
    `- **Routed to:** \`${args.verdict.failureLabel}\``,
    `- **Detected at:** ${args.detectedAtIso}`,
    `- **Run log:** ${RUN_URL}`,
    `- **Probed:** \`GET /repos/${KB_TEMPLATE_OWNER}/${KB_TEMPLATE_NAME}\``,
    "",
    "### What to do",
    "",
    `See [kb-template-health.md runbook](${RUNBOOK_URL}).`,
    "",
    "**Tracks:** #3413",
    "",
  ].join("\n");
}

async function handleKbTemplateIssue(args: {
  octokit: Octokit;
  verdict: KbTemplateVerdict;
  detectedAtIso: string;
}): Promise<void> {
  const { octokit, verdict } = args;
  const owner = PROBE_ISSUE_OWNER;
  const repo = PROBE_ISSUE_REPO;

  // Failure path: dedup-search → comment-or-open.
  if (!verdict.ok) {
    const title =
      verdict.failureLabel === "ci/guard-broken"
        ? ISSUE_TITLE_GUARD_BROKEN
        : ISSUE_TITLE_DRIFT;
    const body = buildFailureIssueBody({
      verdict,
      detectedAtIso: args.detectedAtIso,
    });
    // Pre-emission leak scan — guards the failureDetail field from carrying a
    // PEM/JWT shape echoed out of an upstream error into the issue body.
    assertNoLeak("issue-body", body);

    const search = await octokit.request("GET /search/issues", {
      q: `repo:${owner}/${repo} is:issue is:open label:"${verdict.failureLabel}" in:title "${ISSUE_TITLE_PHRASE}"`,
      per_page: 1,
    });
    const existing = (search.data.items ?? [])[0];
    if (existing) {
      const commentBody = `kb-template probe failed again at ${args.detectedAtIso} — \`${verdict.failureMode}\`: ${verdict.failureDetail}.`;
      assertNoLeak("issue-comment", commentBody);
      await octokit.request(
        "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
        { owner, repo, issue_number: existing.number, body: commentBody },
      );
      return;
    }
    await octokit.request("POST /repos/{owner}/{repo}/issues", {
      owner,
      repo,
      title,
      labels: ["priority/p1-high", verdict.failureLabel],
      body,
    });
    return;
  }

  // Success path: auto-close any open issue across both label families
  // (records last-success by closing).
  for (const label of [
    "ops/kb-template-broken",
    "ci/guard-broken",
  ] as const) {
    const search = await octokit.request("GET /search/issues", {
      q: `repo:${owner}/${repo} is:issue is:open label:"${label}" in:title "${ISSUE_TITLE_PHRASE}"`,
      per_page: 1,
    });
    const stale = (search.data.items ?? [])[0];
    if (!stale) continue;
    const successBody = `kb-template probe green at ${args.detectedAtIso}. is_template===true && private===false. Auto-closing.`;
    // Defense-in-depth: this body is provably leak-free today (static template
    // + ISO timestamp), but route it through the tripwire for symmetry so a
    // future edit that interpolates captured data cannot silently bypass it.
    assertNoLeak("issue-comment-success", successBody);
    await octokit.request(
      "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
      {
        owner,
        repo,
        issue_number: stale.number,
        body: successBody,
      },
    );
    await octokit.request("PATCH /repos/{owner}/{repo}/issues/{issue_number}", {
      owner,
      repo,
      issue_number: stale.number,
      state: "closed",
    });
  }
}

// =============================================================================
// Handler entry point
// =============================================================================

export async function cronKbTemplateHealthHandler({
  step,
  logger,
}: HandlerArgs): Promise<{
  failureMode: string;
  failureLabel: KbTemplateFailureLabel;
}> {
  // Step 1: probe — installation-scoped Octokit (no PAT) reads the template
  // metadata and asserts the documented success shape.
  let verdict: KbTemplateVerdict = PASS_VERDICT;
  try {
    verdict = await step.run("kb-template-probe", async () => {
      const octokit = await createProbeOctokit();
      const firstVerdict = await probeKbTemplate({
        octokit: octokit as unknown as Octokit,
      });
      // Transient HTTP/network blip (5xx, 429, network — NOT a 404 and NOT a
      // drift verdict): retry ONCE after 1s so a single GitHub blip self-heals
      // before filing a P1-high page. A real 404 deletion and an is_template/
      // private drift verdict still file immediately (no retry — those are real).
      if (!isTransientProbeFailure(firstVerdict)) return firstVerdict;
      logger.warn(
        { fn: CRON_NAME },
        `${firstVerdict.failureMode} on kb-template-probe — retrying once after 1s`,
      );
      await new Promise((r) => setTimeout(r, 1_000));
      const retryOctokit = await createProbeOctokit();
      return probeKbTemplate({ octokit: retryOctokit as unknown as Octokit });
    });
  } catch (err) {
    // Redact upstream error BEFORE it reaches Sentry OR the failureDetail field
    // (which is re-emitted to Sentry below). Mirror of the sibling's defensive
    // ban on raw .message forwarding to the observability pipe.
    const safe = redactedError(err);
    reportSilentFallback(safe, {
      feature: CRON_NAME,
      op: "probeKbTemplate",
      message: "kb-template probe threw — converting to github_api_network",
      extra: { fn: CRON_NAME },
    });
    verdict = {
      ok: false,
      failureMode: "github_api_network",
      failureDetail: `probeKbTemplate threw: ${safe.name}: ${safe.message}`,
      failureLabel: "ci/guard-broken",
    };
  }

  // Probe failures mirror to Sentry (cq-silent-fallback-must-mirror-to-sentry).
  if (!verdict.ok) {
    // failureDetail can carry a raw upstream error message (probe network-error
    // branch interpolates e.message). Redact before it reaches Sentry — the
    // issue-body path is assertNoLeak-gated, but this Sentry path is not.
    reportSilentFallback(
      redactedError(new Error(`${verdict.failureMode}: ${verdict.failureDetail}`)),
      {
        feature: CRON_NAME,
        op: "kb-template-drift",
        message: "kb-template health probe detected a failure",
        extra: {
          fn: CRON_NAME,
          failureMode: verdict.failureMode,
          failureLabel: verdict.failureLabel,
        },
      },
    );
  }

  const detectedAtIso = new Date().toISOString();

  // Step 2: issue-handling — file/comment on failure, auto-close on success.
  await step.run("issue-handling", async () => {
    try {
      const octokit = await createProbeOctokit();
      await handleKbTemplateIssue({
        octokit: octokit as unknown as Octokit,
        verdict,
        detectedAtIso,
      });
    } catch (err) {
      // Read `.status` off the ORIGINAL error BEFORE redactedError(err) —
      // redactedError returns a fresh Error WITHOUT `.status` when the message
      // matches the leak regex, which would silently defeat this discriminator.
      const op =
        (err as { status?: number }).status === 403
          ? "issue_write_403"
          : "handleKbTemplateIssue";
      reportSilentFallback(redactedError(err), {
        feature: CRON_NAME,
        op,
        message: "kb-template tracking-issue file/comment/close failed",
        extra: {
          fn: CRON_NAME,
          failureMode: verdict.failureMode,
        },
      });
    }
  });

  // Step 3: sentry-heartbeat — single end-of-job POST.
  await step.run("sentry-heartbeat", async () => {
    await postSentryHeartbeat({
      ok: verdict.ok,
      sentryMonitorSlug: SENTRY_MONITOR_SLUG,
      cronName: CRON_NAME,
      logger,
    });
  });

  return { failureMode: verdict.failureMode, failureLabel: verdict.failureLabel };
}

// =============================================================================
// Registration
// =============================================================================

export const cronKbTemplateHealth = inngest.createFunction(
  {
    id: "cron-kb-template-health",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 * * * *" },
    { event: "cron/kb-template-health.manual-trigger" },
  ],
  cronKbTemplateHealthHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
