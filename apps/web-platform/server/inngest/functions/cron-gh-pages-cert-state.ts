// TR9 Phase-2 — Daily GitHub Pages cert state poll migrated to Inngest cron.
//
// Migrated from .github/workflows/scheduled-gh-pages-cert-state.yml (deleted
// in the same PR per TR9 I-13 hygiene). Pure TS port — no agent spawn,
// no ephemeral workspace. All IO via Octokit (installation-scoped token).
//
// ADR-033 invariants:
//   I1 — All outbound IO is inside step.run for Inngest replay memoization.
//   I2 — Trivially satisfied: no claude / no BYOK lease.
//   I3 — No long-running subprocess; Octokit timeout bounds wallclock.
//   I5 — Deterministic step.run return shapes.
//   I6 — N/A; this function emits no Inngest events.
//
// NAME NOTE: Sentry monitor slug "scheduled-gh-pages-cert-state" preserves
// historical check-in continuity from the GHA workflow. Plan says tighten
// checkin_margin_minutes from 240 to 30 (done in sentry cron-monitors.tf).

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

const SENTRY_MONITOR_SLUG = "scheduled-gh-pages-cert-state";

// Installation-token lifetime floor: 15-min headroom for a handful of API calls.
const TOKEN_MIN_LIFETIME_MS = 15 * 60 * 1000;

export const CERT_WARN_DAYS = 21;

const HEALTHY_STATES = ["approved", "issued"] as const;

const ISSUE_TITLE_PREFIX = "[cert-poll]";

// =============================================================================
// Helpers
// =============================================================================

interface CertCheckResult {
  tripped: boolean;
  detail: string;
  certState: string;
  expiresAt: string;
  daysUntilExpiry: number | null;
}

function checkCert(pages: {
  https_certificate?: {
    state?: string;
    expires_at?: string;
  };
}): CertCheckResult {
  const cert = pages.https_certificate;
  if (!cert) {
    return {
      tripped: true,
      detail: "No https_certificate field in Pages response",
      certState: "missing",
      expiresAt: "",
      daysUntilExpiry: null,
    };
  }

  const state = cert.state ?? "unknown";
  const expiresAt = cert.expires_at ?? "";

  // Check state
  const stateOk = (HEALTHY_STATES as readonly string[]).includes(state);

  // Check expiry
  let daysUntilExpiry: number | null = null;
  let expiryTripped = false;
  if (expiresAt) {
    const expiryMs = Date.parse(expiresAt);
    if (!Number.isNaN(expiryMs)) {
      daysUntilExpiry = Math.floor(
        (expiryMs - Date.now()) / (86400 * 1000),
      );
      if (daysUntilExpiry < CERT_WARN_DAYS) {
        expiryTripped = true;
      }
    }
  }

  const tripped = !stateOk || expiryTripped;
  let detail = "";
  if (!stateOk) {
    detail = `cert state="${state}" not in [${HEALTHY_STATES.join(", ")}]`;
  }
  if (expiryTripped) {
    const expiryDetail = `expires in ${daysUntilExpiry} days (< ${CERT_WARN_DAYS})`;
    detail = detail ? `${detail}; ${expiryDetail}` : expiryDetail;
  }
  if (!tripped) {
    detail = `state=${state}, expires_at=${expiresAt}, days_until_expiry=${daysUntilExpiry}`;
  }

  return { tripped, detail, certState: state, expiresAt, daysUntilExpiry };
}

// =============================================================================
// Handler
// =============================================================================

export async function cronGhPagesCertStateHandler({
  step,
  logger,
}: HandlerArgs): Promise<{
  ok: boolean;
  tripped: boolean;
  detail: string;
}> {
  // Step 1: mint installation token
  const installationToken = await step.run(
    "mint-installation-token",
    async () => {
      return mintInstallationToken({ tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS });
    },
  );

  // Step 2: check cert state
  const certResult = await step.run(
    "check-cert-state",
    async (): Promise<CertCheckResult> => {
      const { Octokit } = await import("@octokit/core");
      const octokit = new Octokit({ auth: installationToken });

      const res = await octokit.request("GET /repos/{owner}/{repo}/pages", {
        owner: REPO_OWNER,
        repo: REPO_NAME,
      });

      return checkCert(
        res.data as {
          https_certificate?: { state?: string; expires_at?: string };
        },
      );
    },
  );

  // Step 3: issue handling — file/comment on trip, auto-close on recovery
  await step.run("issue-handling", async () => {
    try {
      const { Octokit } = await import("@octokit/core");
      const octokit = new Octokit({ auth: installationToken });

      // Search for existing open [cert-poll] issue
      const search = await octokit.request("GET /search/issues", {
        q: `repo:${REPO_OWNER}/${REPO_NAME} is:issue is:open in:title "${ISSUE_TITLE_PREFIX}"`,
        per_page: 1,
      });
      const existing = (search.data.items ?? [])[0];

      if (certResult.tripped) {
        // Trip path: comment on existing or file new
        if (existing) {
          await octokit.request(
            "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
            {
              owner: REPO_OWNER,
              repo: REPO_NAME,
              issue_number: existing.number,
              body: `Cert still degraded at ${new Date().toISOString()} — ${certResult.detail}`,
            },
          );
          logger.info(
            { fn: "cron-gh-pages-cert-state", issueNumber: existing.number },
            "Commented on existing cert-poll issue",
          );
        } else {
          await octokit.request("POST /repos/{owner}/{repo}/issues", {
            owner: REPO_OWNER,
            repo: REPO_NAME,
            title: `${ISSUE_TITLE_PREFIX} GitHub Pages cert requires attention`,
            labels: ["action-required", "infra-drift"],
            body: [
              "## GitHub Pages certificate alert",
              "",
              `- **State:** \`${certResult.certState}\``,
              `- **Expires at:** ${certResult.expiresAt || "unknown"}`,
              `- **Days until expiry:** ${certResult.daysUntilExpiry ?? "unknown"}`,
              `- **Detail:** ${certResult.detail}`,
              `- **Detected at:** ${new Date().toISOString()}`,
              "",
              "### What to do",
              "",
              "Fire the scripted reissue remediation (no console step) — trigger the",
              "`cron/gh-pages-cert-reissue.manual-trigger` event via the `trigger-cron`",
              "skill (`POST /api/internal/trigger-cron`). It transiently flips apex+www to",
              "DNS-only, re-orders the cert via the GitHub App, polls for issuance, then",
              "restores the proxied steady state. This routine (`cron-gh-pages-cert-reissue`)",
              "supersedes the manual GitHub-Pages-console step from the original runbook.",
              "",
              "_Auto-created by the [cron-gh-pages-cert-state Inngest function](https://github.com/jikig-ai/soleur/blob/main/apps/web-platform/server/inngest/functions/cron-gh-pages-cert-state.ts)._",
            ].join("\n"),
          });
          logger.info(
            { fn: "cron-gh-pages-cert-state" },
            "Filed new cert-poll issue",
          );
        }
      } else {
        // Recovery path: close any open cert-poll issue
        if (existing) {
          await octokit.request(
            "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
            {
              owner: REPO_OWNER,
              repo: REPO_NAME,
              issue_number: existing.number,
              body: `Cert healthy at ${new Date().toISOString()} — auto-closing. ${certResult.detail}`,
            },
          );
          await octokit.request(
            "PATCH /repos/{owner}/{repo}/issues/{issue_number}",
            {
              owner: REPO_OWNER,
              repo: REPO_NAME,
              issue_number: existing.number,
              state: "closed",
            },
          );
          logger.info(
            { fn: "cron-gh-pages-cert-state", issueNumber: existing.number },
            "Auto-closed cert-poll issue on recovery",
          );
        }
      }
    } catch (err) {
      reportSilentFallback(err, {
        feature: "cron-gh-pages-cert-state",
        op: "issue-handling",
        message: "Failed to handle cert-poll issue",
        extra: { fn: "cron-gh-pages-cert-state", detail: certResult.detail },
      });
    }
  });

  // Step 4: Sentry heartbeat
  const ok = !certResult.tripped;
  await step.run("sentry-heartbeat", async () => {
    await postSentryHeartbeat({
      ok,
      sentryMonitorSlug: SENTRY_MONITOR_SLUG,
      cronName: "cron-gh-pages-cert-state",
      logger,
    });
  });

  return { ok, tripped: certResult.tripped, detail: certResult.detail };
}

// =============================================================================
// Registration
// =============================================================================

export const cronGhPagesCertState = inngest.createFunction(
  {
    id: "cron-gh-pages-cert-state",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 3 * * *" },
    { event: "cron/gh-pages-cert-state.manual-trigger" },
  ],
  cronGhPagesCertStateHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
