// TR9 Phase 2 T10 — Cloudflare Access service token expiry check.
//
// Migrated from .github/workflows/scheduled-cf-token-expiry-check.yml
// (deleted in the same PR per TR9 I-13 hygiene). Pure TS port — no bash
// script, no gh CLI. All GitHub ops via Octokit; CF API via fetch.
//
// Event-triggered only (no cron schedule). No Sentry cron monitor — errors
// reported via reportSilentFallback only.
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
  type HandlerArgs,
} from "./_cron-shared";

// =============================================================================
// Constants — exported for tests
// =============================================================================

export const WARN_DAYS = 30;
const TOKEN_NAME = "github-actions-deploy";
const TOKEN_MIN_LIFETIME_MS = 15 * 60 * 1000;

// ISO 8601 date-time regex for validation
const ISO_DATETIME_RE =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/;

// =============================================================================
// Handler
// =============================================================================

export async function eventCfTokenExpiryCheckHandler({
  step,
  logger,
}: HandlerArgs): Promise<{
  ok: boolean;
  skipped?: boolean;
  daysRemaining?: number;
  reason?: string;
}> {
  // Step 1: mint installation token
  const installationToken = await step.run(
    "mint-installation-token",
    async () => {
      return mintInstallationToken({ tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS });
    },
  );

  // Step 2: check CF token expiry
  const result = await step.run(
    "check-cf-token",
    async (): Promise<{
      ok: boolean;
      skipped?: boolean;
      daysRemaining?: number;
      reason?: string;
    }> => {
      // Read env vars inside handler — NOT at module load
      const cfApiToken = process.env.CF_API_TOKEN;
      const cfAccountId = process.env.CF_ACCOUNT_ID;

      if (!cfApiToken) {
        logger.warn(
          { fn: "event-cf-token-expiry-check" },
          "CF_API_TOKEN is not set. Skipping check.",
        );
        return { ok: true, skipped: true, reason: "CF_API_TOKEN not set" };
      }

      if (!cfAccountId) {
        logger.warn(
          { fn: "event-cf-token-expiry-check" },
          "CF_ACCOUNT_ID is not set. Skipping check.",
        );
        return { ok: true, skipped: true, reason: "CF_ACCOUNT_ID not set" };
      }

      // Fetch service tokens from CF API
      let response: Response;
      try {
        response = await fetch(
          `https://api.cloudflare.com/client/v4/accounts/${cfAccountId}/access/service_tokens`,
          {
            headers: { Authorization: `Bearer ${cfApiToken}` },
            signal: AbortSignal.timeout(10_000),
          },
        );
      } catch (err) {
        reportSilentFallback(err, {
          feature: "event-cf-token-expiry-check",
          op: "fetch-service-tokens",
          message: "Network error fetching CF service tokens",
          extra: { fn: "event-cf-token-expiry-check" },
        });
        return { ok: false, reason: "network_error" };
      }

      if (response.status < 200 || response.status >= 300) {
        logger.warn(
          { fn: "event-cf-token-expiry-check", status: response.status },
          `Cloudflare API returned HTTP ${response.status}. Token status unknown.`,
        );
        return { ok: true, skipped: true, reason: `http_${response.status}` };
      }

      // JSON validation guard
      let json: { result?: Array<{ name?: string; expires_at?: string }> };
      try {
        json = (await response.json()) as typeof json;
      } catch {
        logger.warn(
          { fn: "event-cf-token-expiry-check" },
          "Cloudflare API returned non-JSON body. Skipping check.",
        );
        return { ok: true, skipped: true, reason: "invalid_json" };
      }

      if (typeof json !== "object" || json === null || !Array.isArray(json.result)) {
        logger.warn(
          { fn: "event-cf-token-expiry-check" },
          "Cloudflare API response missing result array. Skipping check.",
        );
        return { ok: true, skipped: true, reason: "missing_result_array" };
      }

      // Find token by name
      const token = json.result.find((t) => t.name === TOKEN_NAME);
      if (!token || !token.expires_at) {
        logger.warn(
          { fn: "event-cf-token-expiry-check" },
          `Service token '${TOKEN_NAME}' not found in API response.`,
        );
        return { ok: true, skipped: true, reason: "token_not_found" };
      }

      // Validate ISO 8601 date format
      if (!ISO_DATETIME_RE.test(token.expires_at)) {
        reportSilentFallback(
          new Error(`Unexpected date format from API: '${token.expires_at}'`),
          {
            feature: "event-cf-token-expiry-check",
            op: "parse-expiry",
            message: "Invalid date format from CF API",
            extra: { fn: "event-cf-token-expiry-check", expiresAt: token.expires_at },
          },
        );
        return { ok: false, reason: "invalid_date_format" };
      }

      // Calculate days remaining
      const expiresEpochMs = new Date(token.expires_at).getTime();
      const nowMs = Date.now();
      const daysRemaining = Math.floor((expiresEpochMs - nowMs) / 86_400_000);

      logger.info(
        { fn: "event-cf-token-expiry-check", daysRemaining, expiresAt: token.expires_at },
        `Token '${TOKEN_NAME}' expires at ${token.expires_at} (${daysRemaining} days remaining).`,
      );

      const { Octokit: OctokitCtor } = await import("@octokit/core");
      const octokit = new OctokitCtor({
        auth: installationToken,
      }) as unknown as Octokit;

      const issueTitle = `[Action Required] Cloudflare Access token expiring (${TOKEN_NAME})`;

      if (daysRemaining <= WARN_DAYS) {
        // Token expiring soon — file or comment on issue
        const body = [
          "## Cloudflare Deploy Service Token Expiring",
          "",
          `The \`${TOKEN_NAME}\` service token expires on **${token.expires_at}** (${daysRemaining} days remaining).`,
          "",
          "When expired, all deploys via `web-platform-release.yml` will fail with HTTP 403.",
          "",
          "### What to do",
          "",
          `Follow the [rotation runbook](https://github.com/${REPO_OWNER}/${REPO_NAME}/blob/main/knowledge-base/engineering/operations/runbooks/cloudflare-service-token-rotation.md) for renewal steps.`,
          "",
          "**References:** #974",
        ].join("\n");

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
              body: `Token check ran ${new Date().toISOString().slice(0, 16).replace("T", " ")} UTC — ${daysRemaining} days remaining.`,
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

        return { ok: true, daysRemaining };
      }

      // Token is healthy — close stale issues
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
            body: `Token check ran ${new Date().toISOString().slice(0, 16).replace("T", " ")} UTC — ${daysRemaining} days remaining. Auto-closing.`,
          },
        );
        await octokit.request("PATCH /repos/{owner}/{repo}/issues/{issue_number}", {
          owner: REPO_OWNER,
          repo: REPO_NAME,
          issue_number: stale.number,
          state: "closed",
        });
      }

      return { ok: true, daysRemaining };
    },
  );

  return result;
}

// =============================================================================
// Registration
// =============================================================================

export const eventCfTokenExpiryCheck = inngest.createFunction(
  {
    id: "event-cf-token-expiry-check",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  { event: "cf-token-expiry-check.manual-trigger" },
  eventCfTokenExpiryCheckHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
