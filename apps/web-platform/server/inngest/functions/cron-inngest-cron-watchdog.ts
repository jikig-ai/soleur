// Inngest cron-trigger self-healing watchdog (fixes the desync regression
// tracked in issue #4650; durable successor to the CI-guard-only #4533).
//
// WHY THIS EXISTS: the self-hosted Inngest server (ADR-030, loopback
// 127.0.0.1:8288, SQLite at /var/lib/inngest) drops or de-plans cron
// triggers after deploy churn — web-platform-release.yml redeploys the
// container on every apps/web-platform/** merge, and each restart fires an
// SDK function-sync PUT. Runbook H9 (cloud-scheduled-tasks.md) documents
// two runtime failure modes the build-time CI guard (#4531
// function-registry-count.test.ts) CANNOT detect:
//   H9a — function deregistered: slug absent from /v1/functions.
//   H9b — cron trigger not re-planned: slug present but no cron trigger.
// The /health heartbeat (inngest-heartbeat.timer → Better Stack) proves
// only process liveness; H9 is "process alive, cron de-planned". This
// watchdog queries the *running server's* /v1/functions registry and
// self-restores — no operator SSH (never-defer-operator-actions,
// hr-no-ssh-fallback-in-runbooks).
//
// RE-SYNC ASYMMETRY (verified vs inngest-bootstrap.sh:147 — ExecStart sets
// no --poll-interval / --sdk-url): function discovery is bound to container
// restart, not polling. So H9a (dropped) genuinely needs a restart/redeploy
// to re-sync; H9b (de-planned) is recoverable by a manual-trigger event
// alone. The two heal paths below map exactly to this asymmetry.
//
// ADR-033 invariants:
//   I1 — All outbound IO (loopback fetch, inngest.send, webhook POST,
//        Octokit) is inside step.run for Inngest replay memoization.
//   I2 — Trivially satisfied: no claude spawn, no BYOK lease.
//   I5 — Deterministic step.run return shapes (plain JSON).
//
// The watchdog rides the substrate it monitors (Sharp Edge): a full-substrate
// H9a can drop the watchdog itself — defended by (a) restart re-syncs ALL
// functions including this one, (b) its own Sentry monitor
// (scheduled-inngest-cron-watchdog) flips to missed if it stops firing.

import { createHmac } from "node:crypto";

import { inngest } from "@/server/inngest/client";
import { reportSilentFallback } from "@/server/observability";
import { sendInngestWithRetry } from "@/server/inngest/send-with-retry";
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

const SENTRY_MONITOR_SLUG = "scheduled-inngest-cron-watchdog";

// Loopback fallback when INNGEST_BASE_URL is unset. Matches the container's
// runtime env: the web-platform `docker run` in ci-deploy.sh sets
// `-e INNGEST_BASE_URL=http://host.docker.internal:8288` (both the canary and
// production run blocks). Parity-tested in cron-inngest-cron-watchdog.test.ts.
const INNGEST_HOST_FALLBACK = "http://host.docker.internal:8288";

// Restart cooldown: must exceed the watchdog cron interval (4h) so two
// consecutive H9a ticks do not restart-loop (AC6). 6h → at most ~1 restart
// per 6h for a persistent H9a; the ok=false Sentry heartbeat keeps paging
// in between.
export const RESTART_COOLDOWN_MS = 6 * 60 * 60 * 1000;

// Escalate a persistent H9b (cron de-planned) to the H9a restart path after
// this many CONSECUTIVE watchdog ticks still find the function UNPLANNED. A
// manual-trigger re-runs the handler but does NOT re-plan the cron schedule
// (Sharp Edge); only a restart re-plans it. Threshold 2 → ~8h of de-planned
// state before a restart is initiated (the manual-trigger keeps the function
// executing every 4h in the meantime, so the monitor does not go silent).
export const UNPLANNED_RESTART_THRESHOLD = 2;

// State persisted to the container-local filesystem (NOT a host bind-mount —
// only /mnt/data/workspaces and /mnt/data/plugins are mounted into this
// container; this path is a plain writable-layer dir). That is sufficient for
// a read-own-write cooldown: it survives the event it gates — H9a heal restarts
// `inngest-server.service`, a SEPARATE process, leaving this container (and
// this file) untouched. A web-platform REDEPLOY resets it, but a redeploy
// re-syncs every function (no MISSING → no restart attempted), so the reset is
// benign. In-memory state would be cleared on every Inngest function replay, so
// an on-disk file is still required between the 4h ticks.
const COOLDOWN_DIR = "/var/lib/inngest/cron-watchdog";
const COOLDOWN_FILE = `${COOLDOWN_DIR}/restart-cooldown.json`;

const FETCH_TIMEOUT_MS = 10_000;
const WEBHOOK_TIMEOUT_MS = 30_000;

const TOKEN_MIN_LIFETIME_MS = 15 * 60 * 1000;

// Sentinel label the D1-B fallback issue carries; inngest-watchdog-restart-
// dispatch.yml listens for it and dispatches restart-inngest-server.yml,
// keeping the H9a restart autonomous even when the direct webhook POST fails.
const RESTART_ESCALATION_LABEL = "inngest-desync-restart";

// Expected-cron manifest — every cron-*.ts function that MUST have a live
// cron trigger. function-registry-count.test.ts (e) asserts this set equals
// the cron-*.ts file list, so it cannot silently drift. Includes the watchdog
// itself (it is a registered cron; when it runs it is planned → classifies OK;
// its own Sentry monitor is the backstop if it stops).
export const EXPECTED_CRON_FUNCTIONS: string[] = [
  "cron-agent-native-audit",
  "cron-bug-fixer",
  "cron-campaign-calendar",
  "cron-cloud-task-heartbeat",
  "cron-community-monitor",
  "cron-competitive-analysis",
  "cron-compound-promote",
  "cron-content-generator",
  "cron-content-publisher",
  "cron-content-vendor-drift",
  "cron-daily-triage",
  "cron-follow-through-monitor",
  "cron-gh-pages-cert-state",
  "cron-github-app-drift-guard",
  "cron-growth-audit",
  "cron-growth-execution",
  "cron-inngest-cron-watchdog",
  "cron-legal-audit",
  "cron-linkedin-token-check",
  "cron-membership-health",
  "cron-nag-4216-readiness",
  "cron-oauth-probe",
  "cron-plausible-goals",
  "cron-roadmap-review",
  "cron-rule-prune",
  "cron-ruleset-bypass-audit",
  "cron-seo-aeo-audit",
  "cron-skill-freshness",
  "cron-stale-deferred-scope-outs",
  "cron-strategy-review",
  "cron-ux-audit",
  "cron-weekly-analytics",
];

// =============================================================================
// Types
// =============================================================================

export type CronFnStatus = "OK" | "MISSING" | "UNPLANNED";

export interface RegistryFunction {
  slug: string;
  triggers?: Array<{ cron?: string; event?: string } & Record<string, unknown>>;
}

export interface ClassifyResult {
  fnId: string;
  status: CronFnStatus;
}

export interface HealPlan {
  manualTriggerEvents: string[];
  missingFnIds: string[];
  unplannedFnIds: string[];
  defectCount: number;
}

// Persisted watchdog state (container-local file). `unplannedStreaks` tracks
// consecutive-tick UNPLANNED counts per fnId so a persistent H9b escalates to
// a restart (UNPLANNED_RESTART_THRESHOLD).
export interface WatchdogState {
  last_restart_at?: string;
  unplanned_streaks?: Record<string, number>;
}

// =============================================================================
// Pure helpers (unit-tested in cron-inngest-cron-watchdog.test.ts)
// =============================================================================

// fnId "cron-community-monitor" → event "cron/community-monitor.manual-trigger".
// Uniform across all cron-*.ts functions (verified at /work).
export function manualTriggerEventFor(fnId: string): string {
  return `cron/${fnId.replace(/^cron-/, "")}.manual-trigger`;
}

export function resolveInngestHost(baseUrl: string | undefined): string {
  if (!baseUrl) return INNGEST_HOST_FALLBACK;
  return baseUrl.replace(/\/+$/, "");
}

// Match a manifest fnId to a /v1/functions entry. The app id is
// "soleur-runtime", so real slugs are "soleur-runtime-<fnId>"; tolerate a
// bare "<fnId>" too (runbook H9 / #4533 query .slug == "cron-..." directly).
function matchesFn(slug: string, fnId: string): boolean {
  return slug === fnId || slug.endsWith(`-${fnId}`);
}

function hasCronTrigger(fn: RegistryFunction): boolean {
  return (fn.triggers ?? []).some(
    (t) => typeof t.cron === "string" && t.cron.length > 0,
  );
}

export function classifyRegistry(
  registry: RegistryFunction[],
  manifest: string[] = EXPECTED_CRON_FUNCTIONS,
): ClassifyResult[] {
  return manifest.map((fnId) => {
    const entry = registry.find((f) => matchesFn(f.slug, fnId));
    if (!entry) return { fnId, status: "MISSING" };
    return { fnId, status: hasCronTrigger(entry) ? "OK" : "UNPLANNED" };
  });
}

export function planHeal(results: ClassifyResult[]): HealPlan {
  const missingFnIds = results
    .filter((r) => r.status === "MISSING")
    .map((r) => r.fnId);
  const unplannedFnIds = results
    .filter((r) => r.status === "UNPLANNED")
    .map((r) => r.fnId);
  const manualTriggerEvents = unplannedFnIds.map(manualTriggerEventFor);
  return {
    manualTriggerEvents,
    missingFnIds,
    unplannedFnIds,
    defectCount: missingFnIds.length + unplannedFnIds.length,
  };
}

// Advance the per-fnId consecutive-UNPLANNED streaks: increment each currently
// UNPLANNED fnId, and DROP any fnId no longer UNPLANNED (so a recovered cron
// resets to zero rather than lingering). Pure → unit-tested.
export function nextUnplannedStreaks(
  prev: Record<string, number> | undefined,
  unplannedFnIds: string[],
): Record<string, number> {
  const next: Record<string, number> = {};
  for (const fnId of unplannedFnIds) {
    next[fnId] = (prev?.[fnId] ?? 0) + 1;
  }
  return next;
}

// fnIds whose UNPLANNED streak has reached the escalation threshold — these
// get routed to the restart path (a restart re-plans the cron trigger that a
// manual-trigger alone cannot).
export function escalatedUnplannedFnIds(
  streaks: Record<string, number>,
  threshold: number = UNPLANNED_RESTART_THRESHOLD,
): string[] {
  return Object.keys(streaks).filter((fnId) => streaks[fnId] >= threshold);
}

// Cooldown gate: fail open on a missing/unparseable record (a desync is worse
// than an extra restart).
export function restartAllowed(
  lastRestartAtIso: string | null,
  now: number,
): boolean {
  if (!lastRestartAtIso) return true;
  const last = Date.parse(lastRestartAtIso);
  if (Number.isNaN(last)) return true;
  return now - last >= RESTART_COOLDOWN_MS;
}

// A restart is warranted when at least one function needs the restart path
// (H9a MISSING, or an H9b UNPLANNED that has escalated past the streak
// threshold) AND the cooldown permits it.
export function shouldRestart(
  restartFnIds: string[],
  lastRestartAtIso: string | null,
  now: number,
): boolean {
  return restartFnIds.length > 0 && restartAllowed(lastRestartAtIso, now);
}

// =============================================================================
// IO helpers
// =============================================================================

// Exported for reuse by oneshot-4650-monitor-close.ts (#4654) — the canonical
// registry read. Auth via INNGEST_SIGNING_KEY (already in the container env;
// route.ts throws at load if absent). No new credential.
export async function fetchRegistry(host: string): Promise<RegistryFunction[]> {
  const signingKey = process.env.INNGEST_SIGNING_KEY;
  const res = await fetch(`${host}/v1/functions`, {
    headers: signingKey ? { Authorization: `Bearer ${signingKey}` } : {},
    signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
  });
  if (!res.ok) {
    throw new Error(`inngest /v1/functions returned ${res.status}`);
  }
  const body = (await res.json()) as unknown;
  // Self-hosted Inngest returns a bare array; some versions wrap in { data }.
  const arr = Array.isArray(body)
    ? body
    : Array.isArray((body as { data?: unknown }).data)
      ? (body as { data: unknown[] }).data
      : [];
  return (arr as RegistryFunction[]).filter(
    (f) => f && typeof f.slug === "string",
  );
}

async function readState(): Promise<WatchdogState> {
  try {
    const { readFile } = await import("node:fs/promises");
    const raw = await readFile(COOLDOWN_FILE, "utf8");
    return JSON.parse(raw) as WatchdogState;
  } catch {
    return {}; // no prior state recorded
  }
}

async function writeState(state: WatchdogState): Promise<void> {
  const { mkdir, writeFile } = await import("node:fs/promises");
  await mkdir(COOLDOWN_DIR, { recursive: true });
  await writeFile(COOLDOWN_FILE, JSON.stringify(state));
}

// D1-A: POST the deploy webhook to restart inngest-server (same HMAC + CF-Access
// path as restart-inngest-server.yml). The webhook's ci-deploy.sh rejects any
// restart whose component is not `inngest` (the `restart` action branch in
// ci-deploy.sh), so runtime scope is bounded to inngest-server restarts.
async function postRestartWebhook(): Promise<{ ok: boolean; status: number }> {
  const secret = process.env.WEBHOOK_DEPLOY_SECRET;
  const cfId = process.env.CF_ACCESS_CLIENT_ID;
  const cfSecret = process.env.CF_ACCESS_CLIENT_SECRET;
  if (!secret || !cfId || !cfSecret) {
    return { ok: false, status: 0 }; // creds absent → escalate to D1-B
  }
  const payload = JSON.stringify({ command: "restart inngest _ latest" });
  const signature = createHmac("sha256", secret).update(payload).digest("hex");
  const res = await fetch("https://deploy.soleur.ai/hooks/deploy", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Signature-256": `sha256=${signature}`,
      "CF-Access-Client-Id": cfId,
      "CF-Access-Client-Secret": cfSecret,
    },
    body: payload,
    signal: AbortSignal.timeout(WEBHOOK_TIMEOUT_MS),
  });
  return { ok: res.status === 202, status: res.status };
}

// D1-B fallback: file (or comment on) a p0 escalation issue carrying the
// sentinel label that inngest-watchdog-restart-dispatch.yml acts on. Keeps the
// restart autonomous when the direct webhook POST is unreachable.
async function fileRestartEscalationIssue(
  token: string,
  affectedFnIds: string[],
): Promise<void> {
  const { Octokit } = await import("@octokit/core");
  const octokit = new Octokit({ auth: token });
  const title = "[inngest-desync] cron functions need a server restart (H9a/H9b)";
  const search = await octokit.request("GET /search/issues", {
    q: `repo:${REPO_OWNER}/${REPO_NAME} is:issue is:open in:title "${title}"`,
    per_page: 1,
  });
  const existing = (search.data.items ?? [])[0];
  const detail = `Cron-plan defect (dropped or persistently de-planned) at ${new Date().toISOString()}: ${affectedFnIds.join(", ")}`;
  if (existing) {
    await octokit.request(
      "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
      {
        owner: REPO_OWNER,
        repo: REPO_NAME,
        issue_number: existing.number,
        body: `Still desynced — ${detail}`,
      },
    );
    return;
  }
  await octokit.request("POST /repos/{owner}/{repo}/issues", {
    owner: REPO_OWNER,
    repo: REPO_NAME,
    title,
    labels: ["priority/p0-critical", RESTART_ESCALATION_LABEL],
    body: [
      "## Inngest cron functions need a server restart (H9a dropped / H9b persistently de-planned)",
      "",
      detail,
      "",
      "The watchdog could not reach the deploy webhook directly (D1-A). This",
      `issue carries the \`${RESTART_ESCALATION_LABEL}\` label so`,
      "`inngest-watchdog-restart-dispatch.yml` dispatches `restart-inngest-server.yml`.",
      "",
      "Runbook: [cloud-scheduled-tasks.md H9](https://github.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md).",
      "",
      "_Auto-filed by the [cron-inngest-cron-watchdog Inngest function](https://github.com/jikig-ai/soleur/blob/main/apps/web-platform/server/inngest/functions/cron-inngest-cron-watchdog.ts)._",
    ].join("\n"),
  });
}

// =============================================================================
// Handler
// =============================================================================

export async function cronInngestCronWatchdogHandler({
  step,
  logger,
}: HandlerArgs): Promise<{
  ok: boolean;
  results: ClassifyResult[];
  healed: { manualTriggers: string[]; restartRequested: boolean };
}> {
  // Step 1: query the running server's function registry (loopback, no SSH).
  const registry = await step.run("fetch-registry", async () => {
    const host = resolveInngestHost(process.env.INNGEST_BASE_URL);
    return fetchRegistry(host);
  });

  // Pure classification (no IO — safe in the handler body).
  const results = classifyRegistry(registry);
  const plan = planHeal(results);

  // Step 2: heal H9b (UNPLANNED) — fire each manual-trigger so the function
  // runs once and re-posts its check-in. NOTE (Sharp Edge): a manual-trigger
  // runs the handler but does NOT re-plan the cron schedule; the de-planned
  // trigger persists until the next container restart re-syncs it. If H9b
  // recurs every interval, the recurring ok=false heartbeat surfaces it.
  const manualTriggers = await step.run("heal-unplanned", async () => {
    const fired: string[] = [];
    for (const eventName of plan.manualTriggerEvents) {
      try {
        await sendInngestWithRetry(
          () => inngest.send({ name: eventName, data: {} }),
          { feature: "cron-inngest-cron-watchdog", eventId: eventName },
        );
        fired.push(eventName);
        logger.info(
          { fn: "cron-inngest-cron-watchdog", event: eventName },
          "H9b heal: fired manual-trigger for de-planned cron",
        );
      } catch (err) {
        reportSilentFallback(err, {
          feature: "cron-inngest-cron-watchdog",
          op: "heal-unplanned",
          message: `Failed to fire manual-trigger ${eventName}`,
          extra: { fn: "cron-inngest-cron-watchdog", event: eventName },
        });
      }
    }
    return fired;
  });

  // Step 3: restart path — H9a (MISSING) AND escalated H9b (UNPLANNED for
  // UNPLANNED_RESTART_THRESHOLD consecutive ticks; a manual-trigger restored
  // the check-in but never re-planned the cron, so only a restart fixes the
  // schedule). Gated by a cooldown so a persistent desync cannot restart-loop
  // (AC6). Streaks persist across ticks in the same state file.
  const restartRequested = await step.run("heal-restart-path", async () => {
    const state = await readState();
    const streaks = nextUnplannedStreaks(
      state.unplanned_streaks,
      plan.unplannedFnIds,
    );
    const escalated = escalatedUnplannedFnIds(streaks);
    const restartFnIds = [...plan.missingFnIds, ...escalated];

    if (restartFnIds.length === 0) {
      // No restart needed this tick — persist streaks (resets recovered fns),
      // preserve the cooldown timestamp.
      await writeState({
        last_restart_at: state.last_restart_at,
        unplanned_streaks: streaks,
      });
      return false;
    }
    if (!shouldRestart(restartFnIds, state.last_restart_at ?? null, Date.now())) {
      logger.warn(
        { fn: "cron-inngest-cron-watchdog", restartFnIds },
        "Restart warranted (H9a/escalated-H9b) but within cooldown — skipping (ok=false heartbeat still pages)",
      );
      await writeState({
        last_restart_at: state.last_restart_at,
        unplanned_streaks: streaks,
      });
      return false;
    }

    // A restart re-syncs + re-plans ALL functions, so clear streaks on success.
    const onRestarted = async () =>
      writeState({ last_restart_at: new Date().toISOString(), unplanned_streaks: {} });

    try {
      const webhook = await postRestartWebhook();
      if (webhook.ok) {
        await onRestarted();
        logger.info(
          { fn: "cron-inngest-cron-watchdog", restartFnIds },
          "Restart webhook accepted (HTTP 202)",
        );
        return true;
      }
      reportSilentFallback(
        new Error(`restart webhook non-202 (status=${webhook.status})`),
        {
          feature: "cron-inngest-cron-watchdog",
          op: "heal-restart-webhook",
          message: "Restart webhook POST failed — escalating to D1-B issue",
          extra: { fn: "cron-inngest-cron-watchdog", status: webhook.status },
        },
      );
    } catch (err) {
      reportSilentFallback(err, {
        feature: "cron-inngest-cron-watchdog",
        op: "heal-restart-webhook",
        message: "Restart webhook POST threw — escalating to D1-B issue",
        extra: { fn: "cron-inngest-cron-watchdog" },
      });
    }
    // D1-B: file the escalation issue (best-effort).
    try {
      const token = await mintInstallationToken({
        tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS,
      });
      await fileRestartEscalationIssue(token, restartFnIds);
      await onRestarted();
      return true;
    } catch (err) {
      reportSilentFallback(err, {
        feature: "cron-inngest-cron-watchdog",
        op: "heal-restart-escalate",
        message: "D1-B escalation-issue filing failed",
        extra: { fn: "cron-inngest-cron-watchdog" },
      });
      // Restart not initiated — keep streaks so the next tick retries.
      await writeState({
        last_restart_at: state.last_restart_at,
        unplanned_streaks: streaks,
      });
      return false;
    }
  });

  // Step 4: Sentry heartbeat — ok=false when any monitored function is
  // MISSING/UNPLANNED, so the watchdog's own monitor flips to error and pages.
  const ok = plan.defectCount === 0;
  await step.run("sentry-heartbeat", async () => {
    await postSentryHeartbeat({
      ok,
      sentryMonitorSlug: SENTRY_MONITOR_SLUG,
      cronName: "cron-inngest-cron-watchdog",
      logger,
    });
  });

  return { ok, results, healed: { manualTriggers, restartRequested } };
}

// =============================================================================
// Registration
// =============================================================================

// Cadence: every 4h. Detection latency (≤4h) is well inside the miss window
// of the tightest monitored daily cron (scheduled-gh-pages-cert-state @
// 0 3 * * *, scheduled-community-monitor @ 0 8 * * *), so a post-deploy
// desync is caught and healed before the next daily fire is missed (AC10).
export const cronInngestCronWatchdog = inngest.createFunction(
  {
    id: "cron-inngest-cron-watchdog",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 */4 * * *" },
    { event: "cron/inngest-cron-watchdog.manual-trigger" },
  ],
  cronInngestCronWatchdogHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
