// TR9 Phase 2 T8 — LinkedIn OAuth token introspection cron.
//
// Migrated from .github/workflows/scheduled-linkedin-token-check.yml
// (deleted in the same PR per TR9 I-13 hygiene). Pure TS port — no bash
// script, no gh CLI. All GitHub ops via Octokit; LinkedIn API via fetch.
//
// ADR-033 invariants:
//   I1 — Octokit + fetch called INSIDE step.run (Inngest replay
//        memoization). No claude-eval spawn (pure TS port).
//   I2 — Operator-owned data only; never founder BYOK.
//   I5 — Deterministic step.run return shape per step.

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

const SENTRY_MONITOR_SLUG = "scheduled-linkedin-token-check";
const TOKEN_MIN_LIFETIME_MS = 15 * 60 * 1000;

// Per-token probe table — each secret is checked at an endpoint its minting
// app can authorize. There are two LinkedIn developer apps: the Soleur app
// (OIDC scopes only — openid, profile, w_member_social, email) and the Soleur
// Community app (Community Management API scopes — w_organization_social,
// rw_organization_admin, analytics). The Community app does NOT offer openid,
// so an org token can never pass /v2/userinfo; probing it there files
// "expired" forever on a healthy token (issue #9181).
const TOKEN_PROBES: Record<
  string,
  { url: string; app: string; clientId: string; scopes: string }
> = {
  LINKEDIN_ACCESS_TOKEN: {
    url: "https://api.linkedin.com/v2/userinfo",
    app: "Soleur",
    clientId: "78wtm2wu15iikn",
    scopes: "openid, profile, w_member_social, email",
  },
  LINKEDIN_ORG_ACCESS_TOKEN: {
    url: "https://api.linkedin.com/v2/organizationalEntityAcls?q=roleAssignee&role=ADMINISTRATOR&state=APPROVED",
    app: "Soleur Community",
    clientId: "78s808ujpe6lve",
    scopes:
      "all scopes the Community app offers — w_organization_social (org posting) and rw_organization_admin (this probe's own requirement) are mandatory",
  },
};

// =============================================================================
// Token check logic — exported for tests
// =============================================================================

export interface TokenCheckResult {
  status: "skipped" | "valid" | "expired" | "unknown" | "invalid_json";
  tokenName: string;
  holder?: string;
  // httpStatus keeps the 401-vs-403 distinction visible in the per-token
  // logger.info extras — both share the `expired` status by design.
  httpStatus?: number;
}

export async function checkToken(
  tokenName: string,
  tokenValue: string | undefined,
  octokit: Octokit,
): Promise<TokenCheckResult> {
  if (!tokenValue) {
    return { status: "skipped", tokenName };
  }

  // Fail loud on an unconfigured tokenName — silently defaulting to an
  // endpoint would probe a future token where its app cannot authorize it,
  // which is exactly the defect class this table exists to remove.
  const probe = TOKEN_PROBES[tokenName];
  if (!probe) {
    reportSilentFallback(new Error(`no probe endpoint configured for ${tokenName}`), {
      feature: "cron-linkedin-token-check",
      op: "resolve-probe",
      message: `No probe endpoint configured for ${tokenName}`,
      extra: { fn: "cron-linkedin-token-check", tokenName },
    });
    return { status: "unknown", tokenName };
  }

  let response: Response;
  try {
    response = await fetch(probe.url, {
      headers: { Authorization: `Bearer ${tokenValue}` },
      signal: AbortSignal.timeout(10_000),
    });
  } catch (err) {
    reportSilentFallback(err, {
      feature: "cron-linkedin-token-check",
      op: "token-probe",
      message: `Network error checking ${tokenName}`,
      extra: { fn: "cron-linkedin-token-check", tokenName, probeUrl: probe.url },
    });
    return { status: "unknown", tokenName };
  }

  const issueTitle = `[Action Required] LinkedIn OAuth token has expired (${tokenName})`;

  // HTTP 401 → expired/invalid. HTTP 403 → the token is alive but cannot
  // authorize its own probe (minted under the wrong app, or without the
  // scopes listed below) — also actionable, never silent `unknown`.
  if (response.status === 401 || response.status === 403) {
    const meaning =
      response.status === 403
        ? `The scheduled token check detected that \`${tokenName}\` is **alive but missing required scopes** — its probe returned HTTP 403, meaning the token was minted under a different LinkedIn app or without the scopes below.`
        : `The scheduled token check detected that \`${tokenName}\` is **expired or invalid** (API returned HTTP 401).`;
    const body = [
      `## LinkedIn Token Expired (${tokenName})`,
      "",
      meaning,
      "",
      "Content publisher LinkedIn posting via this token is currently **non-functional**.",
      "",
      "### Renewal steps",
      "",
      `1. Go to https://www.linkedin.com/developers/tools/oauth/token-generator?clientId=${probe.clientId} (the ${probe.app} app — the only app that can mint ${tokenName})`,
      `2. Select scopes: ${probe.scopes}`,
      "3. Accept redirect URL confirmation -> Request access token -> Sign in -> Allow",
      "4. Copy the new token and run (printf, not echo):",
      "   ```bash",
      `   printf '%s' '<new-token>' | gh secret set ${tokenName}`,
      "   ```",
      `5. Also persist to Doppler: \`doppler secrets set ${tokenName}=<new-token> -p soleur -c prd\``,
      "",
      "**Person URN** (`LINKEDIN_PERSON_URN`) does not expire and does not need renewal.",
    ].join("\n");

    // Dedup: search for existing open issue
    const search = await octokit.request("GET /search/issues", {
      q: `repo:${REPO_OWNER}/${REPO_NAME} is:issue is:open in:title "${issueTitle}"`,
      per_page: 1,
    });
    const existing = ((search.data as { items?: Array<{ number: number }> }).items ?? [])[0];

    if (existing) {
      await octokit.request(
        "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
        {
          owner: REPO_OWNER,
          repo: REPO_NAME,
          issue_number: existing.number,
          body: `Token check ran ${new Date().toISOString().slice(0, 16).replace("T", " ")} UTC — ${tokenName} is still expired (HTTP ${response.status}).`,
        },
      );
    } else {
      await octokit.request("POST /repos/{owner}/{repo}/issues", {
        owner: REPO_OWNER,
        repo: REPO_NAME,
        title: issueTitle,
        labels: ["action-required"],
        body,
      });
    }

    return { status: "expired", tokenName, httpStatus: response.status };
  }

  // Other non-2xx (429, 5xx, …) → unknown status, skip — transport/vendor
  // conditions must not file spurious issues.
  if (response.status < 200 || response.status >= 300) {
    return { status: "unknown", tokenName, httpStatus: response.status };
  }

  // HTTP 2xx — validate JSON before trusting response. The ACL probe's shape
  // is {elements: [{organizationalTarget, role, state}], paging} — no `name`.
  let json: { name?: string; elements?: unknown[] };
  try {
    json = (await response.json()) as { name?: string; elements?: unknown[] };
  } catch {
    return { status: "invalid_json", tokenName };
  }

  // Validate it's a proper JSON object
  if (typeof json !== "object" || json === null) {
    return { status: "invalid_json", tokenName };
  }

  const holder =
    typeof json.name === "string"
      ? json.name
      : Array.isArray(json.elements)
        ? `${json.elements.length} administered org(s)`
        : "unknown";

  // Token is valid — close any stale renewal issue
  const search = await octokit.request("GET /search/issues", {
    q: `repo:${REPO_OWNER}/${REPO_NAME} is:issue is:open in:title "${issueTitle}"`,
    per_page: 1,
  });
  const stale = ((search.data as { items?: Array<{ number: number }> }).items ?? [])[0];

  if (stale) {
    await octokit.request(
      "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
      {
        owner: REPO_OWNER,
        repo: REPO_NAME,
        issue_number: stale.number,
        body: `Token check ran ${new Date().toISOString().slice(0, 16).replace("T", " ")} UTC — ${tokenName} is valid. Auto-closing.`,
      },
    );
    await octokit.request("PATCH /repos/{owner}/{repo}/issues/{issue_number}", {
      owner: REPO_OWNER,
      repo: REPO_NAME,
      issue_number: stale.number,
      state: "closed",
    });
  }

  return { status: "valid", tokenName, holder };
}

// =============================================================================
// Handler
// =============================================================================

export async function cronLinkedinTokenCheckHandler({
  step,
  logger,
}: HandlerArgs): Promise<{
  ok: boolean;
  results: TokenCheckResult[];
}> {
  // Step 1: mint installation token
  const installationToken = await step.run(
    "mint-installation-token",
    async () => {
      return mintInstallationToken({ tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS });
    },
  );

  // Step 2: check both tokens
  const results = await step.run(
    "check-tokens",
    async (): Promise<TokenCheckResult[]> => {
      const { Octokit: OctokitCtor } = await import("@octokit/core");
      const octokit = new OctokitCtor({
        auth: installationToken,
      }) as unknown as Octokit;

      // Read tokens inside handler — NOT at module load
      const personalToken = process.env.LINKEDIN_ACCESS_TOKEN;
      const orgToken = process.env.LINKEDIN_ORG_ACCESS_TOKEN;

      const personalResult = await checkToken(
        "LINKEDIN_ACCESS_TOKEN",
        personalToken,
        octokit,
      );
      logger.info(
        { fn: "cron-linkedin-token-check", ...personalResult },
        `LINKEDIN_ACCESS_TOKEN: ${personalResult.status}`,
      );

      const orgResult = await checkToken(
        "LINKEDIN_ORG_ACCESS_TOKEN",
        orgToken,
        octokit,
      );
      logger.info(
        { fn: "cron-linkedin-token-check", ...orgResult },
        `LINKEDIN_ORG_ACCESS_TOKEN: ${orgResult.status}`,
      );

      return [personalResult, orgResult];
    },
  );

  // Step 3: Sentry heartbeat
  const ok = results.every((r) => r.status !== "expired");
  await step.run("sentry-heartbeat", async () => {
    await postSentryHeartbeat({
      ok,
      sentryMonitorSlug: SENTRY_MONITOR_SLUG,
      cronName: "cron-linkedin-token-check",
      logger,
    });
  });

  return { ok, results };
}

// =============================================================================
// Registration
// =============================================================================

export const cronLinkedinTokenCheck = inngest.createFunction(
  {
    id: "cron-linkedin-token-check",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 11 * * 1" },
    { event: "cron/linkedin-token-check.manual-trigger" },
  ],
  cronLinkedinTokenCheckHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
