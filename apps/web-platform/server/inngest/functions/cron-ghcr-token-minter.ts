// #6031 — Control-plane GHCR installation-token minter (ADR-088).
//
// Retires the interim machine-account `read:packages` PAT (ADR-087 D1, shipped by
// #6011) with a zero-touch, platform-owned mint: every ~20 min this function mints
// a 1h `packages:read` GitHub App INSTALLATION token from the Doppler-stored App
// key and writes it to Doppler `prd_ghcr` as GHCR_READ_TOKEN (+ GHCR_READ_USER=
// x-access-token). Consumers are UNCHANGED — the running host (ci-deploy.sh) and
// every cold-boot host (soleur-host-bootstrap.sh) keep reading those two keys from
// `--config prd` (cross-config-referenced from prd_ghcr) and `docker login ghcr.io`.
// Only WHO writes the value changes. See ADR-088 + phase0-evidence.md.
//
// TTL / refresh model: 1h hard TTL, minted every 20 min (<= TTL/3) so Doppler
// always holds a live <40-min token and the model survives one missed tick
// (<=40 < 60 min TTL); plus an event-driven mint on `ghcr/token-minter.mint-now`
// for freshness the moment a host is provisioned or a deploy fires.
//
// SECURITY invariants (deepen-plan security + architecture triad):
//   - The token NEVER crosses a step.run boundary. Inngest persists every step
//     return to its state store (readable in the run-output view) and the Sentry
//     scrubber is key-name-based, not value-based — so mint + Doppler-write happen
//     inside ONE step.run that returns only non-secret metadata (AC-Sec1).
//   - FRESH mint only: minRemainingMs = 40 min forces generateInstallationToken to
//     re-mint over a <40-min cached token, preserving the <=40<60 staleness floor
//     (AC-Sec3 / architecture HIGH Q4).
//   - Failure captures read the NUMERIC HTTP status ONLY — never the token, the
//     request body, or the response body (which echoes the token) (AC-Sec2).
//   - Partial named-secrets upsert (not a full-config replace) so the co-resident
//     write credential GHCR_MINTER_DOPPLER_TOKEN survives every write (R3).

import { inngest } from "@/server/inngest/client";
import { reportSilentFallback } from "@/server/observability";
import {
  generateInstallationToken,
  findInstallationByAccountLogin,
} from "@/server/github-app";
import { postSentryHeartbeat, type HandlerArgs } from "./_cron-shared";

const SENTRY_MONITOR_SLUG = "scheduled-ghcr-token-minter";
const CRON_NAME = "cron-ghcr-token-minter";

// The org that owns the private soleur-* GHCR packages (ADR-088 mint target).
const GHCR_PACKAGE_ORG = "jikig-ai";
// packages:read — the App manifest grant is the hard ceiling; this narrows within
// it. GHCR_READ_USER is the installation-token `docker login` convention.
const GHCR_READ_USER_VALUE = "x-access-token";
// Written token must have >= 40 min remaining so it survives one missed 20-min
// tick (<=40 < 60-min TTL). Passed as minRemainingMs to force a fresh mint.
const FRESHNESS_FLOOR_MS = 40 * 60 * 1000;

// Doppler partial-upsert endpoint (merges named secrets; never a full replace).
const DOPPLER_SECRETS_URL = "https://api.doppler.com/v3/configs/config/secrets";
const DOPPLER_PROJECT = "soleur";
const DOPPLER_GHCR_CONFIG = "prd_ghcr";

interface MintResult {
  ok: boolean;
  // Non-secret metadata only. NEVER the token (AC-Sec1).
  dopplerStatus?: number;
  errorSummary?: string;
}

export async function cronGhcrTokenMinterHandler({
  step,
  logger,
}: HandlerArgs): Promise<MintResult> {
  const dopplerToken = process.env.GHCR_MINTER_DOPPLER_TOKEN;
  if (!dopplerToken) {
    // Env misconfiguration — page so the operator fixes it (a minter that cannot
    // run is a credential-provisioning-down signal on the deploy critical path).
    reportSilentFallback(new Error("GHCR_MINTER_DOPPLER_TOKEN not set"), {
      feature: CRON_NAME,
      op: "ghcr-minter-doppler-token-missing",
      message: "GHCR token minter cannot run — GHCR_MINTER_DOPPLER_TOKEN unset",
      extra: { fn: CRON_NAME },
    });
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({ ok: false, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: CRON_NAME, logger });
    });
    return { ok: false, errorSummary: "GHCR_MINTER_DOPPLER_TOKEN not set" };
  }

  // SINGLE step.run — mint + write together, returns ONLY non-secret metadata.
  // Classified failures RETURN {ok:false} (not throw) so the terminal heartbeat
  // below flips the monitor `error` (AC4 output-aware). The 20-min cron floor is
  // the retry cadence; a genuinely unexpected throw is still caught by `retries`.
  const result = await step.run("mint-and-write", async (): Promise<MintResult> => {
    let token: string;
    try {
      const installationId = await findInstallationByAccountLogin(GHCR_PACKAGE_ORG);
      if (installationId == null) {
        throw new Error(
          `No GitHub App installation found for org "${GHCR_PACKAGE_ORG}"`,
        );
      }
      token = await generateInstallationToken(installationId, {
        permissions: { packages: "read" },
        minRemainingMs: FRESHNESS_FLOOR_MS,
      });
    } catch (err) {
      // Mint failure (generateInstallationToken throws on non-ok; its message is
      // `... failed: <status>` and NEVER contains the token). Numeric-safe capture.
      reportSilentFallback(err instanceof Error ? err : new Error("ghcr mint failed"), {
        feature: CRON_NAME,
        op: "ghcr-token-mint-failed",
        extra: { fn: CRON_NAME },
      });
      return { ok: false, errorSummary: "mint failed" };
    }

    // Partial named-secrets upsert — merges GHCR_READ_TOKEN + GHCR_READ_USER,
    // leaving the co-resident GHCR_MINTER_DOPPLER_TOKEN intact. Token delivered in
    // the request body over TLS; the auth token is env-injected, never argv.
    const res = await fetch(DOPPLER_SECRETS_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${dopplerToken}`,
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify({
        project: DOPPLER_PROJECT,
        config: DOPPLER_GHCR_CONFIG,
        secrets: {
          GHCR_READ_TOKEN: token,
          GHCR_READ_USER: GHCR_READ_USER_VALUE,
        },
      }),
    });
    const dopplerStatus = res.status;
    // Drain the socket but NEVER read the body — the 2xx response echoes the token
    // and the scrubber is key-name-based (AC-Sec2).
    await res.text().catch(() => undefined);

    if (!res.ok) {
      // Fail loud — numeric status ONLY, never the token/request/response body.
      reportSilentFallback(
        new Error(`Doppler GHCR_READ_TOKEN write failed: ${dopplerStatus}`),
        { feature: CRON_NAME, op: "ghcr-token-doppler-write-failed", extra: { fn: CRON_NAME, dopplerStatus } },
      );
      return { ok: false, dopplerStatus, errorSummary: `Doppler write failed: ${dopplerStatus}` };
    }

    // Non-secret metadata only.
    return { ok: true, dopplerStatus };
  });

  // Terminal output-aware heartbeat — `ok` ONLY on a 2xx write, `error` otherwise.
  await step.run("sentry-heartbeat", async () => {
    await postSentryHeartbeat({ ok: result.ok, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: CRON_NAME, logger });
  });
  return result;
}

// =============================================================================
// Registration
// =============================================================================
//
// Triggers: 20-min scheduled floor (<= TTL/3) + event-driven mint on
// `ghcr/token-minter.mint-now` (emitted at the provision/deploy trigger point).
// account-scope "cron-platform" concurrency caps to 1 simultaneous cron-* run.

export const cronGhcrTokenMinter = inngest.createFunction(
  {
    id: "cron-ghcr-token-minter",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "*/20 * * * *" },
    { event: "ghcr/token-minter.mint-now" },
  ],
  cronGhcrTokenMinterHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
