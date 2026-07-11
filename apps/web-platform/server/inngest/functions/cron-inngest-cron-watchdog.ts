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
// POLLING + BACKSTOP MODEL (#4652): inngest-bootstrap.sh ExecStart now sets
// --poll-interval 60 --sdk-url http://127.0.0.1:3000/api/inngest, so the
// server continuously re-syncs AND re-plans functions from the app's serve
// manifest within <=60s — WITHOUT a restart. This watchdog is therefore a
// BACKSTOP + ALERTING layer, not the primary repair:
//   - It ALWAYS pages (ok=false Sentry heartbeat) on any MISSING/UNPLANNED.
//   - H9b (de-planned): it fires a manual-trigger as a LATENCY OPTIMIZATION
//     (restores the missed check-in immediately rather than waiting up to one
//     poll interval); polling re-plans the cron within <=60s regardless.
//   - It restarts inngest-server ONLY as a guarded backstop, after a function
//     stays defective (MISSING ∪ UNPLANNED) for POLL_RECOVERY_GRACE_TICKS
//     consecutive ticks — i.e. polling has demonstrably FAILED to recover it
//     (app /api/inngest down, poll loop wedged) — and the cooldown permits it.
//
// ADR-033 invariants:
//   I1 — All outbound IO (loopback fetch, inngest.send, webhook POST,
//        Octokit) is inside step.run for Inngest replay memoization.
//   I2 — Trivially satisfied: no claude spawn, no BYOK lease.
//   I5 — Deterministic step.run return shapes (plain JSON).
//
// The watchdog rides the substrate it monitors (Sharp Edge): a full-substrate
// H9a can drop the watchdog itself — defended by (a) --poll-interval re-syncs
// ALL functions including this one within <=60s (the backstop restart also
// re-syncs everything), (b) its own Sentry monitor
// (scheduled-inngest-cron-watchdog) flips to missed if it stops firing.

import { inngest } from "@/server/inngest/client";
import {
  EXPECTED_CRON_FUNCTIONS,
  manualTriggerEventFor,
} from "@/server/inngest/cron-manifest";
import {
  postSentryHeartbeat,
  type HandlerArgs,
} from "./_cron-shared";

// Re-exported from the client-free leaf (#4734) so existing importers of this
// path (function-registry-count, cron-inngest-cron-watchdog, oneshot-4650-
// monitor-close tests) keep resolving these symbols here. The route + allowlist
// import them from cron-manifest.ts directly to avoid loading the Inngest
// client. Imported above (not just re-exported) so the watchdog's own
// internal references below stay in local scope.
export { EXPECTED_CRON_FUNCTIONS, manualTriggerEventFor };

// =============================================================================
// Constants
// =============================================================================

const SENTRY_MONITOR_SLUG = "scheduled-inngest-cron-watchdog";

// Fallback when INNGEST_BASE_URL is unset. Matches the container's
// runtime env: the web-platform `docker run` in ci-deploy.sh sets
// `-e INNGEST_BASE_URL=http://10.0.1.40:8288` (both the canary and
// production run blocks) — the dedicated soleur-inngest host (epic #6178).
// Parity-tested in cron-inngest-cron-watchdog.test.ts.
const INNGEST_HOST_FALLBACK = "http://10.0.1.40:8288";

// Restart cooldown (defense-in-depth on the backstop): must exceed the
// watchdog cron interval (4h) so two consecutive escalated ticks do not
// restart-loop (AC6). 6h → at most ~1 restart per 6h for a persistent defect;
// the ok=false Sentry heartbeat keeps paging in between.
export const RESTART_COOLDOWN_MS = 6 * 60 * 60 * 1000;

// Backstop grace window (#4652). With --poll-interval 60 the server re-syncs
// AND re-plans a dropped/de-planned function within <=60s automatically, so the
// watchdog no longer restarts on the first defective tick. It restarts only
// after a function stays defective (MISSING ∪ UNPLANNED) for this many
// CONSECUTIVE watchdog ticks — evidence that polling has FAILED to recover it
// (e.g. the app /api/inngest route is down or the poll loop is wedged). At the
// 4h cadence, 2 ticks → ~8h of persistent defect despite 60s polling before a
// backstop restart is initiated; the ok=false heartbeat pages the whole time.
export const POLL_RECOVERY_GRACE_TICKS = 2;

const FETCH_TIMEOUT_MS = 10_000;

// EXPECTED_CRON_FUNCTIONS + manualTriggerEventFor moved to the client-free
// cron-manifest.ts leaf (#4734) and re-exported above; see the import block.

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

// Persisted watchdog state (container-local file). `defect_streaks` tracks
// consecutive-tick DEFECT counts per fnId (MISSING ∪ UNPLANNED) so a defect
// that polling fails to recover escalates to the backstop restart after
// POLL_RECOVERY_GRACE_TICKS ticks.
export interface WatchdogState {
  last_restart_at?: string;
  defect_streaks?: Record<string, number>;
}

// =============================================================================
// Pure helpers (unit-tested in cron-inngest-cron-watchdog.test.ts)
// =============================================================================

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

// Advance the per-fnId consecutive-DEFECT streaks (defect = MISSING ∪
// UNPLANNED): increment each currently-defective fnId, and DROP any fnId no
// longer defective (so a poll-recovered cron resets to zero rather than
// lingering). Pure → unit-tested.
export function nextDefectStreaks(
  prev: Record<string, number> | undefined,
  defectFnIds: string[],
): Record<string, number> {
  const next: Record<string, number> = {};
  for (const fnId of defectFnIds) {
    next[fnId] = (prev?.[fnId] ?? 0) + 1;
  }
  return next;
}

// fnIds whose DEFECT streak has reached the backstop grace threshold — these
// get routed to the restart path because polling has had
// POLL_RECOVERY_GRACE_TICKS intervals to re-sync/re-plan them and FAILED. A
// restart re-syncs (H9a) and re-plans (H9b) every function.
export function escalatedDefectFnIds(
  streaks: Record<string, number>,
  threshold: number = POLL_RECOVERY_GRACE_TICKS,
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

// A restart is warranted when at least one function has escalated to the
// backstop — i.e. it stayed defective (MISSING ∪ UNPLANNED) for
// POLL_RECOVERY_GRACE_TICKS consecutive ticks despite polling (#4652) — AND
// the cooldown permits it. `restartFnIds` is the already-escalated set
// (`escalatedDefectFnIds`); MISSING no longer bypasses the streak gate.
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
// registry read. UNAUTHENTICATED: the loopback /v1/functions introspection
// endpoint answers without auth (see the header note below). No credential.
export async function fetchRegistry(host: string): Promise<RegistryFunction[]> {
  // Do NOT send an Authorization header. /v1/functions is an unauthenticated
  // loopback introspection endpoint — ci-deploy.sh's verify_inngest_health
  // curls it with no auth and gets 200. Sending
  // `Authorization: Bearer <signkey-prod-...>` returned 404 from the app
  // container (#4682: WEB-PLATFORM-14 fired 5x — the watchdog ran on schedule
  // but threw here before its heartbeat step, leaving its monitor silent).
  const res = await fetch(`${host}/v1/functions`, {
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
  // RETIRED to a liveness-only beacon (#4682). The original self-heal read the
  // inngest server's /v1/functions registry to classify MISSING/UNPLANNED crons
  // and manual-trigger/restart to repair. That introspection API is
  // loopback-gated on the server: from the app container /health=200 but
  // /v1/functions=404, while the host's 127.0.0.1:8288/v1/functions=200
  // (confirmed via the #4682 /health probe) — so a containerized watchdog
  // CANNOT read it; no auth/network change fixes that.
  //
  // The self-heal is also redundant now:
  //   - `--poll-interval 60` (#4652, live) re-syncs AND re-plans dropped/
  //     de-planned functions within <=60s — the PRIMARY self-heal.
  //   - the per-function Sentry cron monitors (failure_issue_threshold) already
  //     page on missed check-ins (how the #4650 regression was caught).
  //
  // So this function just posts an ok=true liveness heartbeat: its own check-in
  // proves the inngest cron scheduler is alive enough to fire it (if the whole
  // scheduler dies, this monitor goes missed and pages). It no longer reads the
  // registry, fires manual-triggers, or restarts — and no longer false-pages
  // ok=false every 4h on an introspection it cannot perform.
  await step.run("sentry-heartbeat", async () => {
    await postSentryHeartbeat({
      ok: true,
      sentryMonitorSlug: SENTRY_MONITOR_SLUG,
      cronName: "cron-inngest-cron-watchdog",
      logger,
    });
  });

  return { ok: true, results: [], healed: { manualTriggers: [], restartRequested: false } };
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
