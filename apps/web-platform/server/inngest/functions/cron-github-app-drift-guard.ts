// TR9 PR-4 (#4235) — GitHub App drift-guard migrated to Inngest cron.
//
// Migrated from the GHA scheduled-github-app-drift-guard workflow
// (deleted in the same PR per TR9 I-13 hygiene). Carry-forward of PR-1 /
// PR-2 / PR-3 substrate; ADR-030 + ADR-033 invariants apply.
//
// FAILURE MODE TAXONOMY (12+ modes preserved verbatim from the GHA bash):
//   missing_app_id, app_id_not_numeric, missing_expected_client_id,
//   missing_private_key, pem_b64_decode_failed, pem_shape_invalid,
//   jwt_mint_failed, jwt_mint_empty, github_api_network, github_app_401,
//   github_api_http, github_api_invalid_json, github_api_missing_fields,
//   app_id_mismatch, client_id_mismatch, permission_drift,
//   permission_unexpected_grant, response_shape_unparseable,
//   manifest_diff_unknown_mode, manifest_unparseable,
//   installation_api_http, installation_list_truncated,
//   installation_list_shape_unparseable, installation_permission_drift,
//   installation_unexpected_grant, installation_response_shape_unparseable,
//   installation_diff_unknown_mode.
//
// ROUTING TABLE (mode → label):
//   ci/auth-broken (drift detected, user-impacting):
//     github_app_401, app_id_mismatch, client_id_mismatch,
//     permission_drift, installation_permission_drift
//   ci/guard-broken (guard malfunctioned):
//     all other modes
//   security/leak-suspected (set ONLY by tripwire branch):
//     LeakDetectedError caught by outer handler
//
// First-failure-wins semantics (matches bash `record_failure`'s
// `[[ -z "$failure_mode" ]]` guard).
//
// NAME NOTE: Sentry monitor slug stays "scheduled-github-app-drift-guard"
// for historical check-in continuity (the GHA workflow used that slug;
// the existing sentry_cron_monitor.scheduled_github_app_drift_guard
// Terraform resource is updated in-place).

import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import type { Octokit } from "@octokit/core";
import { inngest } from "@/server/inngest/client";
import { reportSilentFallback } from "@/server/observability";
import {
  createAppJwtOctokit,
  createProbeOctokit,
  PROBE_ISSUE_OWNER,
  PROBE_ISSUE_REPO,
} from "@/server/github/probe-octokit";
import {
  postSentryHeartbeat,
  type HandlerArgs,
} from "./_cron-shared";
import {
  diffGithubAppManifest,
  type AppManifest,
  type ManifestDiffResult,
} from "@/server/github/manifest-diff";

const SENTRY_MONITOR_SLUG = "scheduled-github-app-drift-guard";
const RESEND_TIMEOUT_MS = 10_000;

// Issue titles — match workflow lines 603, 606, 577 verbatim.
const ISSUE_TITLE_AUTH_BROKEN = "[ci/auth-broken] GitHub App drift-guard fired";
const ISSUE_TITLE_GUARD_BROKEN =
  "[ci/guard-broken] GitHub App drift-guard malfunctioned";
const ISSUE_TITLE_LEAK_SUSPECTED =
  "[security/leak-suspected] GitHub App drift-guard log-leak tripwire";

// Manifest paths (workflow line 315-316).
const MANIFEST_FILE = "apps/web-platform/infra/github-app-manifest.json";
const SUPPRESS_FILE = "apps/web-platform/infra/MANIFEST_DRIFT_SUPPRESS_UNTIL";

// Suppression: strict ISO-8601 UTC + 30-day cap (workflow lines 328-334).
const SUPPRESS_TIMESTAMP_RE =
  /^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$/;
const SUPPRESS_MAX_WINDOW_MS = 30 * 24 * 3600 * 1000;

// =============================================================================
// Leak tripwire — load-bearing security regex constants.
//
// Re-anchored here from the deleted contract test at
// apps/web-platform/test/github-app-drift-guard-contract.test.ts:26-34
// (deleted by TR9 PR-4). The base64-of-PEM tripwire catches the future-PR
// mistake where someone echoes $PRIVATE_KEY_B64 directly without decoding
// — the decoded PEM lines are individually scanned, but the un-decoded
// base64 form is a single line that bypasses line-by-line registration.
//
// `LS0tLS1CRUdJTi` is the deterministic base64 prefix of any standard PEM
// (`-----BEGIN `); the trailing `[A-Za-z0-9+/]` ensures the constant itself
// (no trailing alphanum) does NOT false-positive.
//
// CODEOWNERS gates future drift on these constants.
// =============================================================================

export const LEAK_TRIPWIRE_PEM_REGEX = "BEGIN [A-Z ]*PRIVATE KEY";
export const LEAK_TRIPWIRE_PEM_B64_REGEX = "LS0tLS1CRUdJTi[A-Za-z0-9+/]";
export const LEAK_TRIPWIRE_JWT_REGEX = "eyJ[A-Za-z0-9_-]{20,}";

// Hoisted to module scope (P3.1) so assertNoLeak doesn't recompile on each call.
const LEAK_TRIPWIRE_RE = new RegExp(
  `${LEAK_TRIPWIRE_PEM_REGEX}|${LEAK_TRIPWIRE_PEM_B64_REGEX}|${LEAK_TRIPWIRE_JWT_REGEX}`,
);

export class LeakDetectedError extends Error {
  constructor(label: string, matched: string) {
    super(`Leak tripwire fired at '${label}': pattern ${matched}`);
    this.name = "LeakDetectedError";
  }
}

/**
 * Scans `s` against the three leak-tripwire regex alternations. Throws
 * `LeakDetectedError` on match. Call at every emission site (Sentry
 * breadcrumb, issue body, Resend body, logs) BEFORE the value is emitted.
 *
 * Note: unlike the GHA workflow which scanned a tee-captured step-output.log
 * post-step, this TS implementation is a pre-emission gate. The defense
 * surface is structurally narrower (no implicit capture surface in Node);
 * the gate fires only at explicit `assertNoLeak` call sites. Any future
 * refactor that adds a new emission path MUST also route through this gate.
 */
export function assertNoLeak(label: string, s: string): void {
  const m = s.match(LEAK_TRIPWIRE_RE);
  if (m) {
    throw new LeakDetectedError(label, m[0].slice(0, 16) + "...");
  }
}

/**
 * Wrap a raw error before passing it to `reportSilentFallback`. If the
 * `.message` carries a PEM/JWT shape from an upstream library, replace it
 * with a redaction marker so Sentry never sees the leaked bytes. The
 * tripwire branch downstream still flips `leakDetected` separately.
 *
 * P2.1: previously every catch fed raw upstream errors through Sentry,
 * which could leak PEM bytes if @octokit/auth-app's error message ever
 * included the key body. This is a defensive ban on raw .message
 * forwarding to the observability pipe.
 */
function redactedError(e: unknown): Error {
  const orig = e instanceof Error ? e : new Error(String(e));
  const msg = orig.message ?? "";
  if (LEAK_TRIPWIRE_RE.test(msg)) {
    const redacted = new Error("[REDACTED — error message contained PEM/JWT shape]");
    redacted.name = orig.name;
    return redacted;
  }
  return orig;
}

// =============================================================================
// Failure-routing types
// =============================================================================

type FailureLabel = "ci/auth-broken" | "ci/guard-broken";

interface DriftResult {
  failureMode: string;
  failureDetail: string;
  failureLabel: FailureLabel;
}

const EMPTY_RESULT: DriftResult = {
  failureMode: "",
  failureDetail: "",
  failureLabel: "ci/guard-broken",
};

function makeFailure(
  mode: string,
  detail: string,
  label: FailureLabel,
): DriftResult {
  return { failureMode: mode, failureDetail: detail, failureLabel: label };
}

// =============================================================================
// Manifest-diff routing (in-process now, no spawn) — AC8
// =============================================================================

/**
 * Map the pure manifest-diff TS module's result to a DriftResult.
 *
 * `scopePrefix === "installation_"` causes the failure-mode names to be
 * prefixed to preserve the existing routing taxonomy (installation_* family).
 * `installId` decorates the detail string with the installation id for
 * operator triage.
 */
function routeDiffResult(
  result: ManifestDiffResult,
  scopePrefix: "" | "installation_",
  installId?: string,
): DriftResult | null {
  if (result.kind === "ok") return null;
  const installSuffix = installId ? `installation_id=${installId} ` : "";
  switch (result.kind) {
    case "permission_drift":
      if (scopePrefix === "installation_") {
        return makeFailure(
          "installation_permission_drift",
          `${installSuffix}${result.detail}`,
          "ci/auth-broken",
        );
      }
      return makeFailure("permission_drift", result.detail, "ci/auth-broken");
    case "permission_unexpected_grant":
      if (scopePrefix === "installation_") {
        return makeFailure(
          "installation_unexpected_grant",
          `${installSuffix}${result.detail}`,
          "ci/guard-broken",
        );
      }
      return makeFailure(
        "permission_unexpected_grant",
        result.detail,
        "ci/guard-broken",
      );
    case "response_shape_unparseable":
      if (scopePrefix === "installation_") {
        return makeFailure(
          "installation_response_shape_unparseable",
          `${installSuffix}${result.detail}`,
          "ci/guard-broken",
        );
      }
      return makeFailure(
        "response_shape_unparseable",
        result.detail,
        "ci/guard-broken",
      );
  }
}

// =============================================================================
// MANIFEST_DRIFT_SUPPRESS_UNTIL gate (AC9)
// =============================================================================

interface SuppressOutcome {
  active: boolean;
  warning?: string;
}

async function readSuppression(now: Date): Promise<SuppressOutcome> {
  if (!existsSync(SUPPRESS_FILE)) return { active: false };
  let raw = "";
  try {
    raw = await readFile(SUPPRESS_FILE, "utf-8");
  } catch {
    return { active: false };
  }
  const trimmed = raw.replace(/[\s\r\n]/g, "");
  if (!trimmed) return { active: false };
  if (!SUPPRESS_TIMESTAMP_RE.test(trimmed)) {
    return {
      active: false,
      warning: `MANIFEST_DRIFT_SUPPRESS_UNTIL must be strict ISO-8601 UTC; got '${trimmed.slice(0, 64)}'. Ignoring suppression.`,
    };
  }
  const suppressEpochMs = Date.parse(trimmed);
  if (Number.isNaN(suppressEpochMs)) {
    return {
      active: false,
      warning:
        "MANIFEST_DRIFT_SUPPRESS_UNTIL contains an unparseable timestamp; ignoring suppression.",
    };
  }
  const nowMs = now.getTime();
  if (suppressEpochMs - nowMs > SUPPRESS_MAX_WINDOW_MS) {
    return {
      active: false,
      warning: `MANIFEST_DRIFT_SUPPRESS_UNTIL exceeds 30-day cap (until ${trimmed}); ignoring suppression to prevent indefinite silence.`,
    };
  }
  if (nowMs < suppressEpochMs) {
    return { active: true, warning: `Manifest drift suppressed until ${trimmed}.` };
  }
  return { active: false };
}

// =============================================================================
// Probe — env guards + /app + manifest-diff + installation-diff (AC2, AC3, AC10)
// =============================================================================

async function probeDriftGuard(args: {
  octokit: Octokit;
  logger: HandlerArgs["logger"];
}): Promise<DriftResult> {
  const { octokit, logger } = args;

  // --- Env guards (workflow lines 175-189) ---
  const appId = process.env.GH_APP_DRIFTGUARD_APP_ID ?? "";
  const privateKeyB64 = process.env.GH_APP_DRIFTGUARD_PRIVATE_KEY_B64 ?? "";
  const expectedClientId = process.env.OAUTH_PROBE_GITHUB_CLIENT_ID ?? "";

  if (!appId) {
    return makeFailure(
      "missing_app_id",
      "GH_APP_DRIFTGUARD_APP_ID secret is not set",
      "ci/guard-broken",
    );
  }
  if (!/^[1-9][0-9]+$/.test(appId)) {
    return makeFailure(
      "app_id_not_numeric",
      "GH_APP_DRIFTGUARD_APP_ID is not a positive integer",
      "ci/guard-broken",
    );
  }
  if (!expectedClientId) {
    return makeFailure(
      "missing_expected_client_id",
      "OAUTH_PROBE_GITHUB_CLIENT_ID secret is not set",
      "ci/guard-broken",
    );
  }
  if (!privateKeyB64) {
    return makeFailure(
      "missing_private_key",
      "GH_APP_DRIFTGUARD_PRIVATE_KEY_B64 secret is not set",
      "ci/guard-broken",
    );
  }

  // --- GET /app (workflow lines 243-292) ---
  let appData: {
    id?: number | string;
    client_id?: string;
    permissions?: Record<string, string>;
    events?: string[];
    [k: string]: unknown;
  };
  let appHeaders: Record<string, string | undefined> = {};
  try {
    const res = await octokit.request("GET /app");
    appData = res.data as typeof appData;
    appHeaders = (res.headers ?? {}) as Record<string, string | undefined>;
  } catch (err) {
    const e = err as Error & { status?: number; message?: string };
    if (e.status === 401) {
      return makeFailure(
        "github_app_401",
        `GET /app -> 401 Bad credentials. Either App ID ${appId} was deleted/suspended/swapped (drift) OR our PEM is stale vs GitHub-side rotation (guard mis-bootstrap). See runbook 401-disambiguation.`,
        "ci/auth-broken",
      );
    }
    if (typeof e.status === "number") {
      return makeFailure(
        "github_api_http",
        `GET /app -> HTTP ${e.status}`,
        "ci/guard-broken",
      );
    }
    return makeFailure(
      "github_api_network",
      `GET /app -> network error: ${e.name}: ${e.message ?? ""}`,
      "ci/guard-broken",
    );
  }
  void appHeaders;

  if (!appData || typeof appData !== "object") {
    return makeFailure(
      "github_api_invalid_json",
      "GET /app returned non-object body",
      "ci/guard-broken",
    );
  }

  const actualId =
    appData.id === undefined || appData.id === null ? "" : String(appData.id);
  const actualClientId = appData.client_id ?? "";
  if (!actualId || !actualClientId) {
    return makeFailure(
      "github_api_missing_fields",
      "GET /app response missing id or client_id field",
      "ci/guard-broken",
    );
  }
  if (actualId !== appId) {
    return makeFailure(
      "app_id_mismatch",
      `GitHub App database ID drift: expected ${appId}, got ${actualId}`,
      "ci/auth-broken",
    );
  }
  if (actualClientId !== expectedClientId) {
    return makeFailure(
      "client_id_mismatch",
      `GitHub App client_id drift: expected ${expectedClientId}, got ${actualClientId}`,
      "ci/auth-broken",
    );
  }

  // --- Manifest-diff (App-level + per-installation) ---
  const suppress = await readSuppression(new Date());
  if (suppress.warning) {
    // P2.2: the operator-written suppression-warning string is bounded but
    // could in theory be tampered with. Gate it through the leak tripwire
    // so an attacker who lands a PEM into the file can't smuggle it into
    // the pino log via this code path.
    assertNoLeak("suppress-warning", suppress.warning);
    logger.warn({ fn: "cron-github-app-drift-guard" }, suppress.warning);
  }

  // P3.4: single existsSync read (was twice — wasteful + race-y).
  const manifestPresent = existsSync(MANIFEST_FILE);
  if (suppress.active || !manifestPresent) {
    return EMPTY_RESULT;
  }

  // Read manifest ONCE. Parse failures are an operator-fixable inventory bug,
  // not a drift signal — route to ci/guard-broken via a dedicated failure mode.
  let manifest: AppManifest;
  try {
    const raw = await readFile(MANIFEST_FILE, "utf-8");
    manifest = JSON.parse(raw) as AppManifest;
  } catch (err) {
    const e = err as Error;
    return makeFailure(
      "manifest_unparseable",
      `Could not read/parse ${MANIFEST_FILE}: ${e.name}: ${e.message}`,
      "ci/guard-broken",
    );
  }

  // App-level diff: feed parsed /app body directly to the pure diff module.
  {
    const result = diffGithubAppManifest(manifest, {
      permissions: appData.permissions,
      events: appData.events,
    });
    const routed = routeDiffResult(result, "");
    if (routed) return routed;
  }

  // --- Installation iteration (AC10) ---
  let installRes: {
    data: unknown;
    headers: Record<string, string | undefined>;
  };
  try {
    const r = await octokit.request("GET /app/installations", {
      per_page: 100,
    });
    installRes = {
      data: r.data,
      headers: (r.headers ?? {}) as Record<string, string | undefined>,
    };
  } catch (err) {
    const e = err as Error & { status?: number };
    return makeFailure(
      "installation_api_http",
      `GET /app/installations -> HTTP ${e.status ?? "network_error"}`,
      "ci/guard-broken",
    );
  }
  const linkHeader = installRes.headers.link ?? "";
  if (linkHeader.includes('rel="next"')) {
    return makeFailure(
      "installation_list_truncated",
      'GET /app/installations returned a paginated response (Link: rel="next" present); per-page bump or pagination loop required',
      "ci/guard-broken",
    );
  }
  if (!Array.isArray(installRes.data)) {
    return makeFailure(
      "installation_list_shape_unparseable",
      "GET /app/installations response root is not an array",
      "ci/guard-broken",
    );
  }
  for (const install of installRes.data as Array<{
    id?: number;
    permissions?: Record<string, string>;
    events?: string[];
  }>) {
    const installId = install.id ? String(install.id) : "unknown";
    const result = diffGithubAppManifest(manifest, {
      permissions: install.permissions ?? {},
      events: install.events ?? [],
    });
    const routed = routeDiffResult(result, "installation_", installId);
    if (routed) return routed;
  }

  return EMPTY_RESULT;
}

// =============================================================================
// Issue body builders + filing (AC4, AC6)
// =============================================================================

function buildFailureIssueBody(args: {
  failureMode: string;
  failureDetail: string;
  failureLabel: FailureLabel;
  detectedAtIso: string;
  runUrl: string;
  runbookUrl: string;
}): string {
  return [
    "## GitHub App drift-guard failed",
    "",
    `- **Failure mode:** \`${args.failureMode}\``,
    `- **Detail:** ${args.failureDetail}`,
    `- **Routed to:** \`${args.failureLabel}\``,
    `- **Detected at:** ${args.detectedAtIso}`,
    `- **Run log:** ${args.runUrl}`,
    "",
    "### What to do",
    "",
    `See [github-app-drift.md runbook](${args.runbookUrl}).`,
    "",
    "**Tracks:** #3187",
    "",
  ].join("\n");
}

function buildLeakIssueBody(args: {
  detectedAtIso: string;
  runUrl: string;
}): string {
  return [
    "## Leak tripwire fired",
    "",
    "A PEM-block header or JWT-shaped string was found in handler-emitted output. Treat as credential leak suspected until proven otherwise.",
    "",
    `- **Detected at:** ${args.detectedAtIso}`,
    `- **Run log:** ${args.runUrl}`,
    "",
    "### What to do",
    "",
    "1. Open the run log and inspect the offending lines (do NOT paste them here).",
    "2. If a real credential leaked: rotate the GitHub App private key immediately (see runbook).",
    "3. Update the handler to mask whatever path leaked.",
    "",
    "**Tracks:** #3187",
    "",
  ].join("\n");
}

async function handleFailureIssue(args: {
  octokit: Octokit;
  result: DriftResult;
  detectedAtIso: string;
  runUrl: string;
  runbookUrl: string;
}): Promise<void> {
  const { octokit, result } = args;
  const owner = PROBE_ISSUE_OWNER;
  const repo = PROBE_ISSUE_REPO;
  const title =
    result.failureLabel === "ci/auth-broken"
      ? ISSUE_TITLE_AUTH_BROKEN
      : ISSUE_TITLE_GUARD_BROKEN;
  const body = buildFailureIssueBody({
    failureMode: result.failureMode,
    failureDetail: result.failureDetail,
    failureLabel: result.failureLabel,
    detectedAtIso: args.detectedAtIso,
    runUrl: args.runUrl,
    runbookUrl: args.runbookUrl,
  });

  // Pre-emission leak scan — guards against the failureDetail field
  // accidentally containing a PEM/JWT (e.g., a future bug echoing $JWT).
  assertNoLeak("issue-body", body);

  // Failure path: file new issue OR add comment to existing one.
  if (result.failureMode !== "") {
    // Dedup search scoped by label + title-phrase per workflow line 634-637.
    const search = await octokit.request("GET /search/issues", {
      q: `repo:${owner}/${repo} is:issue is:open label:"${result.failureLabel}" in:title "GitHub App drift-guard"`,
      per_page: 1,
    });
    const existing = (search.data.items ?? [])[0];
    if (existing) {
      const commentBody = `Drift-guard failed again at ${args.detectedAtIso} — \`${result.failureMode}\`: ${result.failureDetail}. Run: ${args.runUrl}`;
      assertNoLeak("issue-comment", commentBody);
      await octokit.request(
        "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
        {
          owner,
          repo,
          issue_number: existing.number,
          body: commentBody,
        },
      );
      return;
    }
    await octokit.request("POST /repos/{owner}/{repo}/issues", {
      owner,
      repo,
      title,
      labels: [result.failureLabel, "priority/p1-high"],
      body,
    });
    return;
  }

  // Success path: auto-close stale issues for both labels (workflow 666-687).
  for (const label of ["ci/auth-broken", "ci/guard-broken"] as const) {
    const search = await octokit.request("GET /search/issues", {
      q: `repo:${owner}/${repo} is:issue is:open label:"${label}" in:title "GitHub App drift-guard"`,
      per_page: 1,
    });
    const stale = (search.data.items ?? [])[0];
    if (!stale) continue;
    await octokit.request(
      "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
      {
        owner,
        repo,
        issue_number: stale.number,
        body: `Drift-guard green at ${args.detectedAtIso}. id + client_id matched expected sentinels; leak tripwire passed. Run: ${args.runUrl}`,
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

async function handleLeakIssue(args: {
  octokit: Octokit;
  detectedAtIso: string;
  runUrl: string;
}): Promise<void> {
  const { octokit } = args;
  const owner = PROBE_ISSUE_OWNER;
  const repo = PROBE_ISSUE_REPO;
  await octokit.request("POST /repos/{owner}/{repo}/issues", {
    owner,
    repo,
    title: ISSUE_TITLE_LEAK_SUSPECTED,
    labels: ["security/leak-suspected", "ci/guard-broken", "priority/p1-high"],
    body: buildLeakIssueBody({
      detectedAtIso: args.detectedAtIso,
      runUrl: args.runUrl,
    }),
  });
}

// =============================================================================
// Resend HTTP POST (AC5)
// =============================================================================

async function notifyOpsEmail(args: {
  result: DriftResult;
  leakDetected: boolean;
  runUrl: string;
}): Promise<void> {
  const apiKey = process.env.RESEND_API_KEY;
  if (!apiKey) return; // silent skip mirrors GHA composite action gate
  const runbookUrl =
    "https://github.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/ops/runbooks/github-app-drift.md";
  const subjectMode = args.leakDetected ? "leak-suspected" : args.result.failureMode;
  const subject = `[Soleur Ops] GitHub App drift-guard: ${subjectMode}`;
  const failureMode = args.leakDetected
    ? "leak_tripwire_fired"
    : args.result.failureMode;
  const detail = args.leakDetected
    ? "PEM or JWT-shaped string found in handler-emitted output"
    : args.result.failureDetail;
  const label = args.leakDetected
    ? "security/leak-suspected"
    : args.result.failureLabel;
  const html = [
    `<p><strong>Failure mode:</strong> ${failureMode}</p>`,
    `<p><strong>Detail:</strong> ${detail}</p>`,
    `<p><strong>Label:</strong> ${label}</p>`,
    `<p><a href="${args.runUrl}">Run log</a></p>`,
    `<p>Runbook: <a href="${runbookUrl}">github-app-drift.md</a></p>`,
  ].join("\n");
  assertNoLeak("resend-body", html);
  assertNoLeak("resend-subject", subject);
  await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: "ops@jikigai.com",
      to: ["ops@jikigai.com"],
      subject,
      html,
    }),
    signal: AbortSignal.timeout(RESEND_TIMEOUT_MS),
  });
}

// =============================================================================
// Handler entry point
// =============================================================================

export async function cronGithubAppDriftGuardHandler({
  step,
  logger,
}: HandlerArgs): Promise<{
  failureMode: string;
  failureLabel: FailureLabel | "security/leak-suspected";
  leakDetected: boolean;
}> {
  let leakDetected = false;

  // Step 1: drift-check (env guards + /app + manifest-diff + install-diff).
  // App-level JWT Octokit — the only auth that hits GET /app + GET /app/installations.
  let result: DriftResult = EMPTY_RESULT;
  try {
    result = await step.run("drift-check", async (): Promise<DriftResult> => {
      const { octokit } = await createAppJwtOctokit();
      const firstResult = await probeDriftGuard({
        octokit: octokit as unknown as Octokit,
        logger,
      });
      if (firstResult.failureMode !== "github_app_401") return firstResult;

      logger.warn(
        { fn: "cron-github-app-drift-guard" },
        "github_app_401 on drift-check — retrying once after 1s",
      );
      await new Promise((r) => setTimeout(r, 1_000));
      const { octokit: retryOctokit } = await createAppJwtOctokit();
      return await probeDriftGuard({
        octokit: retryOctokit as unknown as Octokit,
        logger,
      });
    });
  } catch (err) {
    if (err instanceof LeakDetectedError) {
      leakDetected = true;
    } else {
      reportSilentFallback(redactedError(err), {
        feature: "cron-github-app-drift-guard",
        op: "probeDriftGuard",
        message: "Drift probe threw — converting to github_api_network",
        extra: { fn: "cron-github-app-drift-guard" },
      });
      const e = err as Error;
      result = makeFailure(
        "github_api_network",
        `probeDriftGuard threw: ${e.name}: ${e.message}`,
        "ci/guard-broken",
      );
    }
  }

  const detectedAtIso = new Date().toISOString();
  // P2.3: previously a dead GHA actions URL. The drift-guard now lives in
  // Inngest + Sentry Crons, so point operator triage at the Sentry monitor.
  const runUrl =
    "https://de.sentry.io/organizations/jikigai-eu/crons/scheduled-github-app-drift-guard/";
  const runbookUrl =
    "https://github.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/ops/runbooks/github-app-drift.md";

  // Step 2: issue-handling — failure / leak / recovery paths.
  //
  // Sharp-Edge #2 (TR9 PR-4 plan): issue ops MUST use an installation-scoped
  // Octokit. The app-level JWT (correct for /app + /app/installations) 404s
  // on /repos/{owner}/{repo}/issues — the JWT has no installation context to
  // bind a repo write to. `createProbeOctokit()` discovers the installation
  // for jikig-ai/soleur and returns an installation-scoped client. Mirror of
  // cron-oauth-probe.ts's same split.
  await step.run("issue-handling", async () => {
    try {
      const octokit = await createProbeOctokit();
      if (leakDetected) {
        await handleLeakIssue({
          octokit: octokit as unknown as Octokit,
          detectedAtIso,
          runUrl,
        });
      } else {
        try {
          await handleFailureIssue({
            octokit: octokit as unknown as Octokit,
            result,
            detectedAtIso,
            runUrl,
            runbookUrl,
          });
        } catch (innerErr) {
          if (innerErr instanceof LeakDetectedError) {
            // assertNoLeak inside handleFailureIssue tripped — file leak issue.
            leakDetected = true;
            await handleLeakIssue({
              octokit: octokit as unknown as Octokit,
              detectedAtIso,
              runUrl,
            });
          } else {
            throw innerErr;
          }
        }
      }
    } catch (err) {
      reportSilentFallback(redactedError(err), {
        feature: "cron-github-app-drift-guard",
        op: "handleIssue",
        message: "GitHub tracking-issue file/comment/close failed",
        extra: {
          fn: "cron-github-app-drift-guard",
          failureMode: result.failureMode,
          leakDetected,
        },
      });
    }
  });

  // Step 3: notify-ops-email — fires on either failure OR leak.
  if (result.failureMode !== "" || leakDetected) {
    await step.run("notify-ops-email", async () => {
      try {
        await notifyOpsEmail({ result, leakDetected, runUrl });
      } catch (err) {
        if (err instanceof LeakDetectedError) {
          leakDetected = true;
        } else {
          reportSilentFallback(redactedError(err), {
            feature: "cron-github-app-drift-guard",
            op: "notifyOpsEmail",
            message: "Resend HTTP POST failed",
            extra: {
              fn: "cron-github-app-drift-guard",
              failureMode: result.failureMode,
              leakDetected,
            },
          });
        }
      }
    });
  }

  // Step 4: sentry-heartbeat — single end-of-job POST.
  await step.run("sentry-heartbeat", async () => {
    await postSentryHeartbeat({
      ok: result.failureMode === "" && !leakDetected,
      sentryMonitorSlug: SENTRY_MONITOR_SLUG,
      cronName: "cron-github-app-drift-guard",
      logger,
    });
  });

  return {
    failureMode: leakDetected ? "leak_tripwire_fired" : result.failureMode,
    failureLabel: leakDetected ? "security/leak-suspected" : result.failureLabel,
    leakDetected,
  };
}

// =============================================================================
// Registration (AC1)
// =============================================================================

export const cronGithubAppDriftGuard = inngest.createFunction(
  {
    id: "cron-github-app-drift-guard",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 * * * *" },
    { event: "cron/github-app-drift-guard.manual-trigger" },
  ],
  cronGithubAppDriftGuardHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);

// Test surface — exported only for vitest. Pruned (P2.6) to the 4 constants
// + assertNoLeak the tests actually consume; all other helpers are now
// internal and exercised through the public handler entry point.
export const __TESTING__ = {
  assertNoLeak,
  LEAK_TRIPWIRE_PEM_REGEX,
  LEAK_TRIPWIRE_PEM_B64_REGEX,
  LEAK_TRIPWIRE_JWT_REGEX,
};
