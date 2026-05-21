// TR9 PR-3 (#4211) — synthetic OAuth probe migrated to Inngest cron.
//
// Migrated from the GHA scheduled-oauth-probe workflow (deleted in the
// same commit per TR9 I-13 hygiene). Carry-forward of PR-1 / PR-2
// substrate; ADR-030 + ADR-033 invariants apply.
//
// Unlike PR-1/PR-2 (claude-eval cron-*.ts), this function does NOT spawn
// the `claude` binary — the probe is pure network IO (curl-equivalents
// via fetch + a single DNS lookup) plus three side-effect emissions
// (GitHub issue, Resend email, Sentry heartbeat). ADR-033 invariants
// degrade accordingly:
//   I1 — All outbound IO is inside step.run for Inngest replay memoization.
//   I2 — Trivially satisfied: no claude / no BYOK lease. Sweep test
//        `cron-no-byok-lease-sweep.test.ts` glob auto-extends here.
//   I3 — No long-running subprocess; per-fetch AbortSignal.timeout(10_000)
//        bounds the probe wallclock to ~2.5 min worst case (~13 probes).
//   I5 — Deterministic step.run return shapes; no captured stdout.
//   I6 — N/A; this function emits no Inngest events.
//
// NAME NOTE: Sentry monitor slug stays "scheduled-oauth-probe" for
// historical check-in continuity (the GHA workflow used that slug; the
// existing `sentry_cron_monitor.scheduled_oauth_probe` Terraform resource
// is updated in-place rather than recreated). Inngest function id is
// "cron-oauth-probe" (TR9 cron-* convention).
//
// FAILURE MODE TAXONOMY: preserved verbatim from the GHA workflow's
// `record_failure` call sites so the existing runbook and tracking issues
// keep working without remapping. See switch in `probeOauth()` below.

import { promises as dnsPromises } from "node:dns";
import { Octokit } from "@octokit/core";
import { inngest } from "@/server/inngest/client";
import { reportSilentFallback } from "@/server/observability";
import { createProbeOctokit } from "@/server/github/probe-octokit";
import {
  GITHUB_REDIRECT_URI_ERROR_SENTINEL,
  GITHUB_APP_SUSPENDED_SENTINEL,
  GITHUB_AUTHORIZE_PAGE_ANCHORS,
} from "@/server/inngest/functions/oauth-probe-sentinels";

const SENTRY_MONITOR_SLUG = "scheduled-oauth-probe";

// Per-fetch timeout matching the GHA `curl --max-time 10`.
const FETCH_TIMEOUT_MS = 10_000;
// Sentry heartbeat is a single end-of-job POST; uses the same timeout as
// the heartbeat in cron-daily-triage.ts:357.
const SENTRY_HEARTBEAT_TIMEOUT_MS = 10_000;

// Default host fallbacks match the GHA workflow envs verbatim. Doppler
// `prd` MAY override via APP_HOST / API_HOST.
const DEFAULT_APP_HOST = "app.soleur.ai";
const DEFAULT_API_HOST = "api.soleur.ai";

// Validators for env-var-sourced Sentry URL components — identical to
// cron-daily-triage.ts. A typo in Doppler (e.g., SENTRY_INGEST_DOMAIN
// containing a query string) would otherwise partially attacker-control
// the heartbeat URL.
const SENTRY_DOMAIN_RE = /^[a-z0-9.-]+\.sentry\.io$/i;
const SENTRY_PROJECT_RE = /^\d+$/;
const SENTRY_PUBLIC_KEY_RE = /^[a-f0-9]{32}$/;

const ISSUE_TITLE = "[ci/auth-broken] Synthetic OAuth probe failed";

interface ProbeResult {
  failureMode: string;
  failureDetail: string;
}

// strip_log_injection — defense against log-annotation forgery via values
// echoed into Inngest dashboards, Sentry breadcrumbs, or issue bodies.
// TS-equivalent of the bash strip_log_injection helper from the GHA
// workflow lines 91-94. Strips CR/LF + Unicode line/paragraph/zwsp/bom
// separators. JS regex Unicode-escape syntax (\u{...} requires the `u`
// flag) handles the multi-byte sequences cleanly — bash needed tr+sed.
function stripLogInjection(s: string): string {
  return s
    .replace(/[\r\n\f\v\x7f\x85]/g, "")
    .replace(/[\u2028\u2029\u200B\uFEFF]/g, "");
}

// fetch wrapper with manual-redirect (don't follow 30x) plus a tight
// per-call timeout. Returns { status, location, body? }. Network errors
// surface as `kind: "network_error"` so callers can route to the
// matching failure mode.
type FetchOutcome =
  | {
      kind: "ok";
      status: number;
      location: string;
      body: string;
    }
  | { kind: "network_error"; error: string };

async function probeFetch(
  url: string,
  opts: { followRedirects: boolean; readBody: boolean } = {
    followRedirects: false,
    readBody: false,
  },
): Promise<FetchOutcome> {
  try {
    const res = await fetch(url, {
      method: "GET",
      // "manual" => fetch surfaces 30x as a response with status + Location
      // header instead of following. "follow" => fetch follows up to ~20
      // redirects, surfacing only the final response (and final URL via
      // res.url). Both shapes are needed: probe_github_redirect_uri uses
      // -L (follow); check_redirect uses --max-redirs 0 (no follow).
      redirect: opts.followRedirects ? "follow" : "manual",
      signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
      headers: {
        "User-Agent": "soleur-oauth-probe/1.0",
      },
    });
    return {
      kind: "ok",
      status: res.status,
      // Location only meaningful for manual-redirect 30x responses.
      location: res.headers.get("location") ?? res.url,
      body: opts.readBody ? await res.text() : "",
    };
  } catch (err) {
    return {
      kind: "network_error",
      error: (err as Error).name + ": " + (err as Error).message,
    };
  }
}

// Translates one probe_github_redirect_uri / probe_github_supabase_shape_e2e
// body inspection into a failureMode string. Returns "" on healthy body.
// `labelPrefix` lets the caller scope the label (e.g., `github_resolve` or
// `supabase_shape_e2e`).
function classifyGithubAuthorizeBody(
  body: string,
  labelPrefix: string,
  redirectSafe: string,
  followRedirectUrlSafe?: string,
): ProbeResult | null {
  if (body.includes(GITHUB_REDIRECT_URI_ERROR_SENTINEL)) {
    if (labelPrefix === "supabase_shape_e2e") {
      return {
        failureMode: "github_oauth_supabase_shape_e2e_unregistered",
        failureDetail: `GitHub rejected user-shape redirect_uri (Supabase Flow A) for redirect_to=${redirectSafe}; rejected at ${followRedirectUrlSafe ?? ""} — operator must audit GitHub App callback list (see runbook)`,
      };
    }
    return {
      failureMode: `github_oauth_${labelPrefix}_unregistered`,
      failureDetail: `GitHub rejected redirect_uri=${redirectSafe} — operator must add this URL verbatim to the GitHub App callback list (see runbook)`,
    };
  }
  if (body.includes(GITHUB_APP_SUSPENDED_SENTINEL)) {
    return {
      failureMode: "github_app_suspended",
      failureDetail: `GitHub App for the probe's client_id is suspended — every GitHub auth flow breaks until reinstated (see runbook)`,
    };
  }
  const hasAnchor = GITHUB_AUTHORIZE_PAGE_ANCHORS.some((a) => body.includes(a));
  if (!hasAnchor) {
    const tail = followRedirectUrlSafe ? ` (followed to ${followRedirectUrlSafe})` : "";
    return {
      failureMode:
        labelPrefix === "supabase_shape_e2e"
          ? "github_oauth_supabase_shape_e2e_html_drift"
          : `github_oauth_${labelPrefix}_html_drift`,
      failureDetail: `Authorize response for ${redirectSafe}${tail} lacked GitHub-specific anchors (authenticity_token / Sign in to GitHub / Authorize <App>) — GitHub may have reworded the page; refresh sentinels in oauth-probe-sentinels.ts (see runbook)`,
    };
  }
  return null;
}

// Single GitHub-redirect-uri probe — mirrors the GHA bash function
// `probe_github_redirect_uri(label, redirect_uri)`. Returns null on
// healthy.
async function probeGithubRedirectUri(
  label: string,
  redirectUri: string,
  clientId: string,
): Promise<ProbeResult | null> {
  const redirectSafe = stripLogInjection(redirectUri);
  const url = `https://github.com/login/oauth/authorize?client_id=${encodeURIComponent(clientId)}&redirect_uri=${encodeURIComponent(redirectUri)}`;
  const r = await probeFetch(url, { followRedirects: true, readBody: true });
  if (r.kind === "network_error") {
    return {
      failureMode: `github_oauth_${label}_network`,
      failureDetail: `GET .../authorize for redirect_uri=${redirectSafe} -> ${r.error} (DNS, TLS, or connect; see runbook)`,
    };
  }
  if (r.status !== 200) {
    return {
      failureMode: `github_oauth_${label}_http`,
      failureDetail: `GET .../authorize for ${redirectSafe} -> HTTP ${r.status} (see runbook)`,
    };
  }
  return classifyGithubAuthorizeBody(r.body, label, redirectSafe);
}

// End-to-end Supabase-shape probe — mirrors the GHA bash function
// `probe_github_supabase_shape_e2e(redirect_to)`. Two legs: capture
// Supabase 302, then follow into GitHub authorize and inspect body.
async function probeGithubSupabaseShapeE2E(
  redirectTo: string,
  apiHost: string,
): Promise<ProbeResult | null> {
  const redirectSafe = stripLogInjection(redirectTo);
  const supabaseUrl = `https://${apiHost}/auth/v1/authorize?provider=github&redirect_to=${encodeURIComponent(redirectTo)}`;
  // Leg 1 — Supabase 302.
  const leg1 = await probeFetch(supabaseUrl);
  if (leg1.kind === "network_error") {
    return {
      failureMode: "github_oauth_supabase_shape_e2e_supabase_network",
      failureDetail: `Supabase /auth/v1/authorize for redirect_to=${redirectSafe} -> ${leg1.error} (DNS, TLS, or connect; see runbook)`,
    };
  }
  if (leg1.status !== 302) {
    return {
      failureMode: "github_oauth_supabase_shape_e2e_supabase_http",
      failureDetail: `Supabase /auth/v1/authorize for redirect_to=${redirectSafe} -> HTTP ${leg1.status} (see runbook)`,
    };
  }
  const redirectUrlSafe = stripLogInjection(leg1.location);
  // Leg 2 — follow into GitHub authorize page.
  const leg2 = await probeFetch(leg1.location, {
    followRedirects: true,
    readBody: true,
  });
  if (leg2.kind === "network_error") {
    return {
      failureMode: "github_oauth_supabase_shape_e2e_github_network",
      failureDetail: `Follow Supabase 302 for redirect_to=${redirectSafe} -> ${leg2.error} against ${redirectUrlSafe} (see runbook)`,
    };
  }
  if (leg2.status !== 200) {
    return {
      failureMode: "github_oauth_supabase_shape_e2e_github_http",
      failureDetail: `Follow Supabase 302 for redirect_to=${redirectSafe} -> HTTP ${leg2.status} from ${redirectUrlSafe} (see runbook)`,
    };
  }
  return classifyGithubAuthorizeBody(
    leg2.body,
    "supabase_shape_e2e",
    redirectSafe,
    redirectUrlSafe,
  );
}

// /auth/v1/authorize → expected provider host (GHA `check_redirect`).
async function checkRedirect(
  provider: "google" | "github",
  expectedHost: string,
  appHost: string,
  apiHost: string,
): Promise<ProbeResult | null> {
  const url = `https://${apiHost}/auth/v1/authorize?provider=${provider}&redirect_to=https%3A%2F%2F${appHost}%2Fcallback`;
  const r = await probeFetch(url);
  if (r.kind === "network_error") {
    return {
      failureMode: "network_error",
      failureDetail: `GET ${url} -> ${r.error}`,
    };
  }
  let redirectHost = "";
  try {
    redirectHost = r.location ? new URL(r.location).host : "";
  } catch {
    redirectHost = "";
  }
  if (r.status !== 302 || redirectHost !== expectedHost) {
    return {
      failureMode: `${provider}_authorize`,
      failureDetail: `GET ${url} -> HTTP ${r.status}, redirect_host=${redirectHost}`,
    };
  }
  return null;
}

// resolveCname — mimics `dig +short CNAME <host>` head -1 with the
// trailing `.supabase.co.?` stripped. Used to cross-check the static
// SUPABASE_PROJECT_REF env var against the live custom-domain CNAME.
async function resolveSupabaseRefFromCname(apiHost: string): Promise<string | null> {
  try {
    const cnames = await dnsPromises.resolveCname(apiHost);
    if (!cnames.length) return null;
    const first = cnames[0]!;
    return first.replace(/\.supabase\.co\.?$/, "");
  } catch {
    return null;
  }
}

// Main probe — translates the deleted scheduled-oauth-probe GHA workflow
// (lines 71-422) to TS.
// Returns the first failure encountered (matching the bash workflow's
// `record_failure` first-wins semantics via the `[[ -z "$fail_mode" ]]`
// guards).
async function probeOauth(): Promise<ProbeResult> {
  const appHost = process.env.APP_HOST || DEFAULT_APP_HOST;
  const apiHost = process.env.API_HOST || DEFAULT_API_HOST;
  // The GHA workflow mapped `secrets.NEXT_PUBLIC_SUPABASE_ANON_KEY` → env
  // `SUPABASE_ANON_KEY`. Doppler prd carries it under its canonical name
  // (`NEXT_PUBLIC_SUPABASE_ANON_KEY`); accept either to avoid creating a
  // redundant secret.
  const supabaseAnonKey =
    process.env.SUPABASE_ANON_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  const githubClientId = process.env.OAUTH_PROBE_GITHUB_CLIENT_ID;
  const supabaseProjectRef = process.env.SUPABASE_PROJECT_REF;

  // 1. /login is reachable.
  {
    const r = await probeFetch(`https://${appHost}/login`);
    if (r.kind === "network_error") {
      return {
        failureMode: "network_error",
        failureDetail: `GET https://${appHost}/login -> ${r.error}`,
      };
    }
    if (r.status !== 200) {
      return {
        failureMode: "login_unreachable",
        failureDetail: `GET https://${appHost}/login -> HTTP ${r.status}`,
      };
    }
  }

  // 2/3. Google + GitHub OAuth redirects.
  const google = await checkRedirect("google", "accounts.google.com", appHost, apiHost);
  if (google) return google;
  const github = await checkRedirect("github", "github.com", appHost, apiHost);
  if (github) return github;

  // 3b/3c/3d/3e/3f/3g. Probe each registered GitHub App callback URL +
  // user-shape e2e. Skips with distinct failure modes if the required
  // secrets are absent.
  if (!githubClientId) {
    return {
      failureMode: "github_client_id_probe_unset",
      failureDetail:
        "OAUTH_PROBE_GITHUB_CLIENT_ID secret is not set — cannot probe GitHub App callback URL registration (see runbook)",
    };
  }
  if (!supabaseProjectRef) {
    return {
      failureMode: "supabase_project_ref_unset",
      failureDetail:
        "SUPABASE_PROJECT_REF secret is not set — cannot probe canonical supabase.co callback URL (see runbook)",
    };
  }

  // 3c. SUPABASE_PROJECT_REF integrity (CNAME deref vs. stored secret).
  // CNAME deref failure → fall back to the secret (better than no probe).
  const cnameRef = (await resolveSupabaseRefFromCname(apiHost)) ?? supabaseProjectRef;
  if (cnameRef !== supabaseProjectRef) {
    return {
      failureMode: "supabase_project_ref_drift",
      failureDetail: `dig CNAME ${apiHost} resolved ref=${stripLogInjection(cnameRef)} but env SUPABASE_PROJECT_REF=${supabaseProjectRef} — re-run Doppler set or investigate Supabase re-provision (see runbook)`,
    };
  }

  // 3d/3e/3f. Three registered callback URLs.
  const callbackTargets: Array<{ label: string; url: string }> = [
    {
      label: "github_resolve",
      url: `https://${appHost}/api/auth/github-resolve/callback`,
    },
    { label: "supabase_custom", url: `https://${apiHost}/auth/v1/callback` },
    {
      label: "supabase_canonical",
      url: `https://${supabaseProjectRef}.supabase.co/auth/v1/callback`,
    },
  ];
  for (const t of callbackTargets) {
    const r = await probeGithubRedirectUri(t.label, t.url, githubClientId);
    if (r) return r;
  }

  // 3g. User-shape end-to-end probe.
  const e2e = await probeGithubSupabaseShapeE2E(`https://${appHost}/callback`, apiHost);
  if (e2e) return e2e;

  // 4. /auth/v1/settings exposes google + github enabled.
  if (!supabaseAnonKey) {
    return {
      failureMode: "settings_misconfigured",
      failureDetail: "SUPABASE_ANON_KEY env is not set",
    };
  }
  try {
    const res = await fetch(`https://${apiHost}/auth/v1/settings`, {
      headers: { apikey: supabaseAnonKey },
      signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
    });
    if (res.status !== 200) {
      return {
        failureMode: "settings_http",
        failureDetail: `GET https://${apiHost}/auth/v1/settings -> HTTP ${res.status}`,
      };
    }
    let json: unknown;
    try {
      json = await res.json();
    } catch {
      return {
        failureMode: "settings_invalid_json",
        failureDetail: `GET https://${apiHost}/auth/v1/settings -> non-JSON body (HTTP ${res.status})`,
      };
    }
    const external = (json as { external?: Record<string, boolean | null> })?.external ?? {};
    for (const prov of ["google", "github"] as const) {
      const enabled = external[prov];
      if (enabled !== true) {
        return {
          failureMode: "settings_provider_disabled",
          failureDetail: `external.${prov}=${String(enabled)}`,
        };
      }
    }
  } catch (err) {
    return {
      failureMode: "network_error",
      failureDetail: `GET https://${apiHost}/auth/v1/settings -> ${(err as Error).name}: ${(err as Error).message}`,
    };
  }

  // 5. /callback?error=access_denied 302/307 → /login?error=oauth_cancelled.
  {
    const cbUrl = `https://${appHost}/callback?error=access_denied`;
    const r = await probeFetch(cbUrl);
    if (r.kind === "network_error") {
      return {
        failureMode: "network_error",
        failureDetail: `GET ${cbUrl} -> ${r.error}`,
      };
    }
    const acceptedStatus = r.status === 302 || r.status === 307;
    if (!acceptedStatus || !r.location.includes("/login?error=oauth_cancelled")) {
      return {
        failureMode: "callback_error_passthrough",
        failureDetail: `GET ${cbUrl} -> HTTP ${r.status}, redirect=${r.location}`,
      };
    }
  }

  return { failureMode: "", failureDetail: "" };
}

// Build the issue body for a tracking issue file/comment. Mirrors the GHA
// workflow's printf block (lines 446-474) for content parity. `nowIso` is
// the detection timestamp passed in so tests can lock it; in production
// the handler hands in `new Date().toISOString()`.
function buildIssueBody(args: {
  failureMode: string;
  failureDetail: string;
  detectedAtIso: string;
  runUrl: string;
  runbookUrl: string;
}): string {
  const isCallbackDrift =
    /^github_oauth_.*_unregistered$/.test(args.failureMode) ||
    args.failureMode === "github_app_suspended";
  const callbackBlock = isCallbackDrift
    ? [
        "### Required GitHub App callback URLs",
        "",
        "The App `soleur-ai` (client_id `Iv23li9p88M5ZxYv1b7V`) MUST have ALL THREE of these registered:",
        "",
        "```text",
        "https://app.soleur.ai/api/auth/github-resolve/callback",
        "https://api.soleur.ai/auth/v1/callback",
        "https://ifsccnjhymdmidffkzhl.supabase.co/auth/v1/callback",
        "```",
        "",
        "Audit at: https://github.com/organizations/jikig-ai/settings/apps/soleur-ai",
        "",
      ].join("\n")
    : "";
  return [
    "## Synthetic OAuth probe failed",
    "",
    `- **Failure mode:** \`${args.failureMode}\``,
    `- **Detail:** ${args.failureDetail}`,
    `- **Detected at:** ${args.detectedAtIso}`,
    `- **Run log:** ${args.runUrl}`,
    "",
    callbackBlock,
    "### What to do",
    "",
    `See [oauth-probe-failure.md runbook](${args.runbookUrl}).`,
    "",
    "**Tracks:** #2997",
    "",
  ].join("\n");
}

// Issue-file-or-comment-or-close branch. Caller supplies the constructed
// octokit and the probe result. Mirrors GHA workflow lines 424-526.
async function handleTrackingIssue(args: {
  octokit: Octokit;
  result: ProbeResult;
  detectedAtIso: string;
  runUrl: string;
  runbookUrl: string;
}): Promise<void> {
  const { octokit, result } = args;
  const owner = "jikig-ai";
  const repo = "soleur";

  // Search for an open tracking issue by literal title.
  const search = await octokit.request("GET /search/issues", {
    q: `repo:${owner}/${repo} is:issue is:open in:title "${ISSUE_TITLE}"`,
    per_page: 1,
  });
  const existing = (search.data.items ?? [])[0];

  // Failure path: file new issue OR add comment to existing one.
  if (result.failureMode !== "") {
    if (existing) {
      await octokit.request(
        "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
        {
          owner,
          repo,
          issue_number: existing.number,
          body: `Probe failed again at ${args.detectedAtIso} — \`${result.failureMode}\`: ${result.failureDetail}. Run: ${args.runUrl}`,
        },
      );
      return;
    }
    await octokit.request("POST /repos/{owner}/{repo}/issues", {
      owner,
      repo,
      title: ISSUE_TITLE,
      labels: ["ci/auth-broken", "priority/p1-high"],
      body: buildIssueBody({
        failureMode: result.failureMode,
        failureDetail: result.failureDetail,
        detectedAtIso: args.detectedAtIso,
        runUrl: args.runUrl,
        runbookUrl: args.runbookUrl,
      }),
    });
    return;
  }

  // Success path: auto-close any stale tracking issue.
  if (existing) {
    await octokit.request(
      "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
      {
        owner,
        repo,
        issue_number: existing.number,
        body: `Probe green at ${args.detectedAtIso}. All checks passed (login HTTP 200, google+github authorize 302, settings JSON valid, all 3 GitHub App callback URLs registered, Supabase user-shape e2e green, callback-error pass-through). Run: ${args.runUrl}`,
      },
    );
    await octokit.request(
      "PATCH /repos/{owner}/{repo}/issues/{issue_number}",
      {
        owner,
        repo,
        issue_number: existing.number,
        state: "closed",
      },
    );
  }
}

// Resend HTTP POST matching .github/actions/notify-ops-email/action.yml
// lines 33-44 payload.
async function notifyOpsEmail(result: ProbeResult, runUrl: string): Promise<void> {
  const apiKey = process.env.RESEND_API_KEY;
  if (!apiKey) {
    // Per the GHA composite action's gate: silent skip when key absent
    // (fork PRs, dev). The probe itself already reported failure via
    // Sentry + the tracking issue; the email is a tertiary signal.
    return;
  }
  const runbookUrl =
    "https://github.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md";
  const html = [
    `<p><strong>Failure mode:</strong> ${result.failureMode}</p>`,
    `<p><strong>Detail:</strong> ${result.failureDetail}</p>`,
    `<p><a href="${runUrl}">Run log</a></p>`,
    `<p>Runbook: <a href="${runbookUrl}">oauth-probe-failure.md</a></p>`,
  ].join("\n");
  await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: "ops@jikigai.com",
      to: ["ops@jikigai.com"],
      subject: `[Soleur Ops] OAuth probe failure: ${result.failureMode}`,
      html,
    }),
    signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
  });
}

interface HandlerArgs {
  step: { run<T>(name: string, cb: () => Promise<T>): Promise<T> };
  logger: {
    info: (...a: unknown[]) => void;
    warn: (...a: unknown[]) => void;
    error: (...a: unknown[]) => void;
  };
}

export async function cronOauthProbeHandler({
  step,
  logger,
}: HandlerArgs): Promise<{ failureMode: string }> {
  // Step 1: probe — the pure-IO probe logic. Each fetch has its own 10s
  // abort signal so the probe wallclock is bounded to ~2.5 min worst case.
  const result = await step.run("probe", async (): Promise<ProbeResult> => {
    try {
      return await probeOauth();
    } catch (err) {
      // Catch escapes any code path that throws (rather than returning
      // a ProbeResult). Maps to network_error so the rest of the pipeline
      // still files an issue and pings Sentry — silent green would mask
      // the regression class.
      const e = err as Error;
      reportSilentFallback(e, {
        feature: "cron-oauth-probe",
        op: "probeOauth",
        message: "Probe threw — converting to network_error failure mode",
        extra: { fn: "cron-oauth-probe" },
      });
      return {
        failureMode: "network_error",
        failureDetail: `probeOauth threw: ${e.name}: ${e.message}`,
      };
    }
  });

  const detectedAtIso = new Date().toISOString();
  const runUrl =
    "https://github.com/jikig-ai/soleur/actions"; // Inngest run URL is not
  // operator-routable today; the runbook (AC13) documents Better Stack +
  // Inngest dashboard as the substrate lookup. Issue body stays linkable
  // to the operator's known GHA history surface.
  const runbookUrl =
    "https://github.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md";

  // Step 2: issue handling — file/comment on failure, auto-close on
  // recovery. Wrapped in step.run for replay safety AND to isolate the
  // GitHub API failure surface from the heartbeat below.
  await step.run("issue-handling", async () => {
    try {
      const octokit = await createProbeOctokit();
      await handleTrackingIssue({
        octokit: octokit as unknown as Octokit,
        result,
        detectedAtIso,
        runUrl,
        runbookUrl,
      });
    } catch (err) {
      const e = err as Error;
      reportSilentFallback(e, {
        feature: "cron-oauth-probe",
        op: "handleTrackingIssue",
        message: "GitHub tracking-issue file/comment/close failed",
        extra: { fn: "cron-oauth-probe", failureMode: result.failureMode },
      });
    }
  });

  // Step 3: notify-ops-email — only fires on failure.
  if (result.failureMode !== "") {
    await step.run("notify-ops-email", async () => {
      try {
        await notifyOpsEmail(result, runUrl);
      } catch (err) {
        const e = err as Error;
        reportSilentFallback(e, {
          feature: "cron-oauth-probe",
          op: "notifyOpsEmail",
          message: "Resend HTTP POST failed",
          extra: { fn: "cron-oauth-probe", failureMode: result.failureMode },
        });
      }
    });
  }

  // Step 4: sentry-heartbeat — single end-of-job POST. Shape matches
  // cron-daily-triage.ts:329-371 for monitor-resource continuity.
  await step.run("sentry-heartbeat", async () => {
    const domain = process.env.SENTRY_INGEST_DOMAIN;
    const projectId = process.env.SENTRY_PROJECT_ID;
    const publicKey = process.env.SENTRY_PUBLIC_KEY;
    if (!domain || !projectId || !publicKey) {
      logger.info(
        { fn: "cron-oauth-probe" },
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
        { fn: "cron-oauth-probe" },
        "Sentry env malformed — skipping heartbeat",
      );
      return;
    }
    const status = result.failureMode === "" ? "ok" : "error";
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
          fn: "cron-oauth-probe",
          status,
          aborted: e.name === "TimeoutError",
        },
      });
    }
  });

  return { failureMode: result.failureMode };
}

// Registration: BOTH cron (scheduled hourly) AND event (manual-retry)
// triggers. Operator manual retry:
//   `inngest send cron/oauth-probe.manual-trigger`
// account-scope concurrency key "cron-platform" is the global cron-* OOM
// guard shared with cron-daily-triage + cron-follow-through-monitor.
export const cronOauthProbe = inngest.createFunction(
  {
    id: "cron-oauth-probe",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 * * * *" },
    { event: "cron/oauth-probe.manual-trigger" },
  ],
  cronOauthProbeHandler as unknown as Parameters<typeof inngest.createFunction>[2],
);

// Test surface — exported only for vitest. Not part of the runtime API.
export const __TESTING__ = {
  probeOauth,
  probeFetch,
  probeGithubRedirectUri,
  probeGithubSupabaseShapeE2E,
  checkRedirect,
  classifyGithubAuthorizeBody,
  stripLogInjection,
  resolveSupabaseRefFromCname,
  buildIssueBody,
  handleTrackingIssue,
  notifyOpsEmail,
  SENTRY_MONITOR_SLUG,
  ISSUE_TITLE,
};
