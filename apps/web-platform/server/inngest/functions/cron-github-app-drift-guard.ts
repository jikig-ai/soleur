// TR9 PR-4 (#4235) — GitHub App drift-guard migrated to Inngest cron.
//
// Migrated from .github/workflows/scheduled-github-app-drift-guard.yml
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
//   manifest_diff_unknown_mode, installation_api_http,
//   installation_list_truncated, installation_list_shape_unparseable,
//   installation_permission_drift, installation_unexpected_grant,
//   installation_response_shape_unparseable, installation_diff_unknown_mode.
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

import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdtemp, writeFile, rm, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import type { Octokit } from "@octokit/core";
import { inngest } from "@/server/inngest/client";
import { reportSilentFallback } from "@/server/observability";
import {
  createAppJwtOctokit,
  PROBE_ISSUE_OWNER,
  PROBE_ISSUE_REPO,
} from "@/server/github/probe-octokit";

const SENTRY_MONITOR_SLUG = "scheduled-github-app-drift-guard";
const SENTRY_HEARTBEAT_TIMEOUT_MS = 10_000;
const RESEND_TIMEOUT_MS = 10_000;

// Validators (identical to cron-oauth-probe).
const SENTRY_DOMAIN_RE = /^[a-z0-9.-]+\.sentry\.io$/i;
const SENTRY_PROJECT_RE = /^\d+$/;
const SENTRY_PUBLIC_KEY_RE = /^[a-f0-9]{32}$/;

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
  const re = new RegExp(
    `${LEAK_TRIPWIRE_PEM_REGEX}|${LEAK_TRIPWIRE_PEM_B64_REGEX}|${LEAK_TRIPWIRE_JWT_REGEX}`,
  );
  const m = s.match(re);
  if (m) {
    throw new LeakDetectedError(label, m[0].slice(0, 16) + "...");
  }
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
// Manifest-diff spawn helper (AC8)
// =============================================================================

interface DiffOutcome {
  exitCode: number;
  stdout: string;
  stderr: string;
}

async function runManifestDiff(
  manifestFile: string,
  responseFile: string,
): Promise<DiffOutcome> {
  return new Promise((resolve, reject) => {
    const child = spawn("bash", ["bin/diff-github-app-manifest.sh"], {
      env: {
        ...process.env,
        MANIFEST_FILE: manifestFile,
        RESPONSE_FILE: responseFile,
      },
    });
    let stdout = "";
    let stderr = "";
    child.stdout?.on?.("data", (chunk: Buffer | string) => {
      stdout += chunk.toString();
    });
    child.stderr?.on?.("data", (chunk: Buffer | string) => {
      stderr += chunk.toString();
    });
    child.on("error", (err: Error) => reject(err));
    child.on("close", (code: number | null) => {
      resolve({ exitCode: code ?? -1, stdout, stderr });
    });
  });
}

function routeManifestDiff(
  outcome: DiffOutcome,
  scopePrefix: "" | "installation_",
  installId?: string,
): DriftResult | null {
  if (outcome.exitCode === 0) return null;
  if (outcome.exitCode === 2) {
    return makeFailure(
      "manifest_diff_unknown_mode",
      `diff-github-app-manifest exited 2 stderr: ${outcome.stderr.slice(0, 200)}`,
      "ci/guard-broken",
    );
  }
  // exit-1: `<mode>:<details>` on stdout. Use indexOf to split at first ":".
  const out = outcome.stdout.trim();
  const sep = out.indexOf(":");
  const mode = sep === -1 ? out : out.slice(0, sep);
  const detail = sep === -1 ? "" : out.slice(sep + 1);
  const installSuffix = installId ? `installation_id=${installId} ` : "";
  switch (mode) {
    case "permission_drift":
      if (scopePrefix === "installation_") {
        return makeFailure(
          "installation_permission_drift",
          `${installSuffix}${detail}`,
          "ci/auth-broken",
        );
      }
      return makeFailure("permission_drift", detail, "ci/auth-broken");
    case "permission_unexpected_grant":
      if (scopePrefix === "installation_") {
        return makeFailure(
          "installation_unexpected_grant",
          `${installSuffix}${detail}`,
          "ci/guard-broken",
        );
      }
      return makeFailure(
        "permission_unexpected_grant",
        detail,
        "ci/guard-broken",
      );
    case "response_shape_unparseable":
      if (scopePrefix === "installation_") {
        return makeFailure(
          "installation_response_shape_unparseable",
          `${installSuffix}${detail}`,
          "ci/guard-broken",
        );
      }
      return makeFailure(
        "response_shape_unparseable",
        detail,
        "ci/guard-broken",
      );
    default:
      return makeFailure(
        `${scopePrefix}manifest_diff_unknown_mode`,
        `${installSuffix}diff_rc=${outcome.exitCode} out=${out}`,
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

  // --- Manifest-diff (App-level) ---
  const suppress = await readSuppression(new Date());
  if (suppress.warning) logger.warn({ fn: "cron-github-app-drift-guard" }, suppress.warning);

  let tempDir: string | null = null;
  try {
    tempDir = await mkdtemp(path.join(tmpdir(), "drift-guard-"));
    const responseFile = path.join(tempDir, "app-response.json");
    await writeFile(responseFile, JSON.stringify(appData));

    if (!suppress.active && existsSync(MANIFEST_FILE)) {
      const diff = await runManifestDiff(MANIFEST_FILE, responseFile);
      const routed = routeManifestDiff(diff, "");
      if (routed) return routed;
    }

    // --- Installation iteration (AC10) ---
    if (!suppress.active && existsSync(MANIFEST_FILE)) {
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
        const synth = {
          permissions: install.permissions ?? {},
          events: install.events ?? [],
        };
        const installFile = path.join(tempDir, `install-${installId}.json`);
        await writeFile(installFile, JSON.stringify(synth));
        const diff = await runManifestDiff(MANIFEST_FILE, installFile);
        const routed = routeManifestDiff(diff, "installation_", installId);
        if (routed) return routed;
      }
    }
  } finally {
    if (tempDir) {
      try {
        await rm(tempDir, { recursive: true, force: true });
      } catch {
        /* best-effort */
      }
    }
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

interface HandlerArgs {
  step: { run<T>(name: string, cb: () => Promise<T>): Promise<T> };
  logger: {
    info: (...a: unknown[]) => void;
    warn: (...a: unknown[]) => void;
    error: (...a: unknown[]) => void;
  };
}

export async function cronGithubAppDriftGuardHandler({
  step,
  logger,
}: HandlerArgs): Promise<{
  failureMode: string;
  failureLabel: FailureLabel | "security/leak-suspected";
  leakDetected: boolean;
}> {
  let leakDetected = false;
  let leakReason = "";

  // Step 1: drift-check (env guards + /app + manifest-diff + install-diff).
  let result: DriftResult = EMPTY_RESULT;
  try {
    result = await step.run("drift-check", async (): Promise<DriftResult> => {
      const { octokit, appJwt } = await createAppJwtOctokit();
      // Drop the JWT into a guarded path: never emit it. Stored in a const
      // referenced only inside the probe; assertNoLeak guards downstream
      // emission sites.
      void appJwt;
      return await probeDriftGuard({
        octokit: octokit as unknown as Octokit,
        logger,
      });
    });
  } catch (err) {
    if (err instanceof LeakDetectedError) {
      leakDetected = true;
      leakReason = err.message;
    } else {
      const e = err as Error;
      reportSilentFallback(e, {
        feature: "cron-github-app-drift-guard",
        op: "probeDriftGuard",
        message: "Drift probe threw — converting to github_api_network",
        extra: { fn: "cron-github-app-drift-guard" },
      });
      result = makeFailure(
        "github_api_network",
        `probeDriftGuard threw: ${e.name}: ${e.message}`,
        "ci/guard-broken",
      );
    }
  }

  const detectedAtIso = new Date().toISOString();
  const runUrl = "https://github.com/jikig-ai/soleur/actions";
  const runbookUrl =
    "https://github.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/ops/runbooks/github-app-drift.md";

  // Step 2: issue-handling — failure / leak / recovery paths.
  await step.run("issue-handling", async () => {
    try {
      const { octokit } = await createAppJwtOctokit();
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
            leakReason = innerErr.message;
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
      const e = err as Error;
      reportSilentFallback(e, {
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
          leakReason = err.message;
        } else {
          const e = err as Error;
          reportSilentFallback(e, {
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
  void leakReason;

  // Step 4: sentry-heartbeat — single end-of-job POST.
  await step.run("sentry-heartbeat", async () => {
    const domain = process.env.SENTRY_INGEST_DOMAIN;
    const projectId = process.env.SENTRY_PROJECT_ID;
    const publicKey = process.env.SENTRY_PUBLIC_KEY;
    if (!domain || !projectId || !publicKey) {
      logger.info(
        { fn: "cron-github-app-drift-guard" },
        "Sentry env unset — skipping heartbeat",
      );
      return;
    }
    if (
      !SENTRY_DOMAIN_RE.test(domain) ||
      !SENTRY_PROJECT_RE.test(projectId) ||
      !SENTRY_PUBLIC_KEY_RE.test(publicKey)
    ) {
      logger.warn(
        { fn: "cron-github-app-drift-guard" },
        "Sentry env malformed — skipping heartbeat",
      );
      return;
    }
    // Status routing: ok only when no failure AND no leak.
    const status =
      result.failureMode === "" && !leakDetected ? "ok" : "error";
    const url = `https://${domain}/api/${projectId}/cron/${SENTRY_MONITOR_SLUG}/${publicKey}/?status=${status}`;
    try {
      await fetch(url, {
        method: "POST",
        signal: AbortSignal.timeout(SENTRY_HEARTBEAT_TIMEOUT_MS),
      });
    } catch (err) {
      const e = err as Error;
      reportSilentFallback(e, {
        feature: "cron-sentry-heartbeat",
        op: "fetch",
        message: "Sentry Crons heartbeat POST failed",
        extra: {
          fn: "cron-github-app-drift-guard",
          status,
          aborted: e.name === "TimeoutError",
        },
      });
    }
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

// Test surface — exported only for vitest.
export const __TESTING__ = {
  assertNoLeak,
  probeDriftGuard,
  readSuppression,
  runManifestDiff,
  routeManifestDiff,
  handleFailureIssue,
  handleLeakIssue,
  notifyOpsEmail,
  buildFailureIssueBody,
  buildLeakIssueBody,
  SENTRY_MONITOR_SLUG,
  ISSUE_TITLE_AUTH_BROKEN,
  ISSUE_TITLE_GUARD_BROKEN,
  ISSUE_TITLE_LEAK_SUSPECTED,
};
