// TR9 Phase-2 — GitHub Pages cert state poll migrated to Inngest.
//
// #7640: the daily cron trigger is DISARMED (see the Registration block at the
// bottom for why). This is now a MANUAL-TRIGGER-ONLY routine. Two consequences
// live OUTSIDE this file and are owned elsewhere:
//   - the Sentry cron monitor `scheduled-gh-pages-cert-state`
//     (infra/sentry/cron-monitors.tf) will now miss its check-in window, since
//     the heartbeat below only fires on a manual run;
//   - ROUTINE_METADATA's `scheduleLabel` for this fn was updated in the same
//     change and reads "Disarmed pending ADR-194 cutover (event-only)"
//     (server/inngest/routine-metadata.ts). It is NOT stale; this note used to
//     claim it was, and that claim was corrected in #7749.
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

// ‼️ ESCALATION THRESHOLD — the gap that produced the 2026-08-16 apex outage.
//
// The WARN path (>= this many days) is correctly quiet: it files/updates a
// `[cert-poll]` issue and leaves a daily comment. That is a LOG, not an ALERT.
// On 2026-08-16 the apex cert expired and soleur.ai served CF 526 for hours,
// having been detected 28 days earlier: issue #6691 was filed 2026-07-19 and
// commented EVERY day, counting down "expires in 2 days" → "1 days" → "0 days"
// → "-1 days". Detection worked perfectly; nothing ever escalated, and the
// remediation is manual-trigger-only (ADR-125 v1, human-gated), so a countdown
// that nobody read ran all the way to a public outage.
//
// Inside this window a STUCK-AND-REMEDIABLE cert additionally emits a
// feature-tagged `reportSilentFallback`, which mirrors to Sentry and pages —
// the channel a daily GitHub comment is not. Deliberately NOT gated on
// `tripped` alone: a cert 20 days out is a ticket, one 6 days out that ACME
// cannot self-heal is an incident-in-waiting.
export const CERT_CRITICAL_DAYS = 7;

const HEALTHY_STATES = ["approved", "issued"] as const;

// Mirror of REISSUE_ALLOWED_STATES in cron-gh-pages-cert-reissue.ts. A cert in
// one of these states is WEDGED: ACME will not self-heal it, so waiting cannot
// fix it and only the reissue routine can. Any other unhealthy state (e.g.
// `authorization_pending`, `new`, `dns_changed`) is an order still in flight —
// noisy to page on, and the reissue routine deliberately declines to touch it.
export const REISSUE_ELIGIBLE_STATES = [
  "bad_authz",
  "errored",
  "authorization_revoked",
  "failed",
] as const;

const ISSUE_TITLE_PREFIX = "[cert-poll]";

/**
 * Decide whether a cert reading warrants PAGING (Sentry) rather than only the
 * `[cert-poll]` issue comment.
 *
 * Pure + exported so the escalation predicate is testable without driving the
 * whole Inngest handler — the #6698 lesson that a routine's failure surface must
 * be exercised by tests, not just its happy path.
 *
 * `daysUntilExpiry === null` (unparseable/absent `expires_at`) escalates when
 * the state is wedged: an unknown clock on a cert ACME cannot heal is the case
 * where silence is most expensive, so it fails LOUD rather than assuming time.
 */
export function certEscalation(result: {
  certState: string;
  daysUntilExpiry: number | null;
}): { escalate: boolean; reason: string } {
  const wedged = (REISSUE_ELIGIBLE_STATES as readonly string[]).includes(
    result.certState,
  );
  if (!wedged) return { escalate: false, reason: "" };

  const { daysUntilExpiry: days } = result;
  if (days === null) {
    return {
      escalate: true,
      reason: `cert wedged in "${result.certState}" and expiry is UNKNOWN (absent/unparseable expires_at) — cannot bound time-to-outage`,
    };
  }
  if (days < CERT_CRITICAL_DAYS) {
    const when =
      days < 0
        ? `EXPIRED ${Math.abs(days)} day(s) ago`
        : `expires in ${days} day(s)`;
    return {
      escalate: true,
      reason: `cert wedged in "${result.certState}" and ${when} (< ${CERT_CRITICAL_DAYS}) — ACME cannot self-heal this state; fire cron/gh-pages-cert-reissue.manual-trigger`,
    };
  }
  return { escalate: false, reason: "" };
}

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

  // Step 3b: ESCALATE a wedged cert near expiry to the paging channel.
  //
  // Step 3 above files/comments a GitHub issue. That is durable and auditable
  // but it is not an alert — #6691 accumulated 28 daily countdown comments and
  // the apex still went down on schedule. `reportSilentFallback` mirrors to
  // Sentry, so a cert ACME cannot self-heal reaches on-call while there is
  // still time to run the remediation.
  //
  // Its OWN step so a Sentry/transport failure cannot roll back the issue
  // comment, and so a replay re-emits deterministically. Never throws: a broken
  // escalation must not take down the heartbeat that proves this cron ran (that
  // heartbeat's absence is the backstop detector).
  await step.run("escalate-if-critical", async () => {
    const { escalate, reason } = certEscalation(certResult);
    if (!escalate) return { escalated: false };

    reportSilentFallback(
      new Error(`GitHub Pages cert requires operator action: ${reason}`),
      {
        feature: "cron-gh-pages-cert-state",
        op: "cert-critical",
        message: "GitHub Pages cert wedged near/past expiry — remediation required",
        extra: {
          fn: "cron-gh-pages-cert-state",
          certState: certResult.certState,
          expiresAt: certResult.expiresAt,
          daysUntilExpiry: certResult.daysUntilExpiry,
          remediation: "cron/gh-pages-cert-reissue.manual-trigger",
        },
      },
    );
    logger.warn(
      {
        fn: "cron-gh-pages-cert-state",
        certState: certResult.certState,
        daysUntilExpiry: certResult.daysUntilExpiry,
      },
      `SOLEUR_CERT_CRITICAL escalated: ${reason}`,
    );
    return { escalated: true };
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
  // ‼️ #7640 — THE DAILY SCHEDULE IS DISARMED. It was a daily 03:00 UTC cron
  // trigger; the literal is deliberately not repeated here, because AC26 greps
  // this file for its absence.
  //
  // After the Cloudflare Pages cutover the GitHub Pages certificate is
  // DNS-detached by design, so it can never recover: this poll is permanently
  // tripped. On a daily schedule that is a self-escalating loop — it files (then
  // comments on) a `[cert-poll]` issue EVERY DAY FOREVER whose body reads "fire
  // `cron/gh-pages-cert-reissue.manual-trigger`", handing an autonomous agent a
  // daily, authoritative instruction to run a routine that, against the
  // post-cutover topology, de-proxies live www ONE-WAY (see the topology
  // precondition in cron-gh-pages-cert-reissue.ts). That is not a low-likelihood
  // hazard; it is the retained system's designed steady-state output.
  //
  // The function is NOT deleted — deleting the cert subsystem is deferred to a
  // later PR — and the manual-trigger arm is retained so an operator (or the
  // rollback path) can still read the Pages cert state on demand. Membership in
  // EXPECTED_CRON_FUNCTIONS does not require a schedule: `cron-gh-pages-cert-reissue`
  // is already event-only, and that manifest's own note says so.
  [{ event: "cron/gh-pages-cert-state.manual-trigger" }],
  cronGhPagesCertStateHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
