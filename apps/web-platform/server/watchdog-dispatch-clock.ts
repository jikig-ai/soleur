// Watchdog dispatch clock (#8495, ADR-248).
//
// GitHub Actions `schedule:` drops ticks: the external Inngest watchdog
// (*/15) measured one run every 2-7 h, so an Inngest outage went unseen for
// hours. This in-process poll fires `workflow_dispatch` for each row of
// WATCHDOG_DISPATCH_TABLE on a UTC wall-clock slot. A dispatched RUN is created
// within seconds; its JOB still waits in the org runner queue like any other
// job (measured on these workflows 2026-09-24: median ~30 s, p90 ~20 min — the
// Sentry margins in cron-monitors.tf absorb it). The workflows keep their
// `schedule:` crons as a fallback.
//
// It is NOT an Inngest function (a watcher of Inngest cannot be scheduled by
// Inngest — ADR-033 anti-circularity) and must never import server/inngest/
// (pinned by watchdog-dispatch-clock.test.ts). It runs on every deployed web
// host; per-slot jitter plus a slot-scoped "does this slot already have a run?"
// read keep the hosts from double-dispatching in most slots. A collision (both
// hosts inside the read's visibility lag, estimated ~5-10% of slots) and a late
// fallback `schedule:` tick both yield a second, queued run — the workflows use
// cancel-in-progress: false and are written to tolerate a repeat run.
//
// Safety: crash-handlers.ts exits the process on unhandledRejection, so every
// tick sits inside three fences (inner try/catch/finally, an outer .catch that
// emits `tick_escaped`, and fail-open report/emit wrappers). A tick is bounded
// by TICK_DEADLINE_MS. Errors are rebuilt from a token-redacted message; the
// raw Octokit error (whose request/response carry the token) is never forwarded.

import {
  createAppJwtOctokit,
  PROBE_ISSUE_OWNER as REPO_OWNER,
  PROBE_ISSUE_REPO as REPO_NAME,
} from "@/server/github/probe-octokit";
import { generateInstallationToken } from "@/server/github-app";
import {
  reportSilentFallback,
  type SilentFallbackOptions,
} from "@/server/observability";
import {
  emitWatchdogDispatch,
  type WatchdogDispatchMarker,
} from "@/server/cron-liveness-marker";
import {
  WATCHDOG_DISPATCH_TABLE,
  type WatchdogDispatchEntry,
} from "@/server/watchdog-dispatch-table";

const FEATURE = "watchdog-dispatch-clock";

export const POLL_MS = 30_000;
// Jitter spreads the web hosts so the later one's read sees the earlier one's
// run. JITTER_MAX_MS is part of the Sentry margin budget documented on the
// monitors in apps/web-platform/infra/sentry/cron-monitors.tf (poll + jitter +
// tick deadline + runner queue + job runtime must fit inside
// checkin_margin_minutes).
export const JITTER_MIN_MS = 30_000;
export const JITTER_MAX_MS = 120_000;
export const TICK_DEADLINE_MS = 90_000;
// A failed tick (mint/dispatch error or timeout) is retried inside the same
// slot: a GitHub API blip hits both hosts at once, so "the other host covers
// it" does not hold for that failure. Each retry re-reads the runs first, so a
// timed-out POST that actually landed is not dispatched twice.
export const MAX_ATTEMPTS_PER_SLOT = 3;
export const RETRY_BACKOFF_MS = 120_000;
const TOKEN_MIN_LIFETIME_MS = 5 * 60_000;
// Runs read per dedup check. The list is newest-first; we take the newest run
// that could have covered the slot, skipping ineligible ones (other branches,
// other events, runs that never executed).
const RUNS_READ_PAGE = 10;
// Runs that end in these conclusions never executed the workflow's steps, so
// they never post the Sentry check-in and must not suppress the slot.
const NON_EXECUTED_CONCLUSIONS = new Set(["cancelled", "skipped", "startup_failure"]);
// Only the triggers the parity test allows. A branch copy with `pull_request:`
// (including from a fork whose head branch is literally `main`) shares this
// workflow's id and must never suppress a slot.
const COVERING_EVENTS = new Set(["schedule", "workflow_dispatch"]);

type Op = NonNullable<WatchdogDispatchMarker["op"]>;
type Reason = "timeout" | "http" | "throw";

export interface GitHubRequestClient {
  request: (
    route: string,
    params: Record<string, unknown>,
  ) => Promise<{ data?: unknown; status?: number }>;
}

type TimerHandle = { unref?: () => unknown };

export interface WatchdogClockDeps {
  table: ReadonlyArray<WatchdogDispatchEntry>;
  env: { NODE_ENV?: string; SOLEUR_HOST_ID?: string };
  random: () => number;
  mint: () => Promise<string>;
  octokitFor: (token: string) => GitHubRequestClient | Promise<GitHubRequestClient>;
  report: (err: unknown, opts: SilentFallbackOptions) => void;
  emit: (m: WatchdogDispatchMarker) => void;
  setInterval: (fn: () => void, ms: number) => TimerHandle;
  clearInterval: (h: TimerHandle) => void;
}

/** UTC wall-clock multiple of `intervalMinutes` at or before `nowMs`. */
export function slotStartAt(nowMs: number, intervalMinutes: number): number {
  const len = intervalMinutes * 60_000;
  return Math.floor(nowMs / len) * len;
}

/** True iff a run created at `createdAtIso` was created inside the slot starting at `slotStartMs`. */
export function slotAlreadyHasRun(
  createdAtIso: string,
  slotStartMs: number,
): boolean {
  const created = Date.parse(createdAtIso);
  // No tolerance before the slot: a dispatch happens >= JITTER_MIN_MS into the
  // slot and GitHub creates `schedule:` runs late, never early, so a run meant
  // for this slot has created_at >= slot start as long as host clocks are
  // within 30 s of GitHub's (skew beyond that only causes a duplicate run).
  // A previous slot's run created before this slot never suppresses it; a very
  // late `schedule:` run created INSIDE this slot does — acceptable, because
  // that run executes and checks in for this slot.
  // Unparseable → "not this slot": fail open to a (harmless) dispatch.
  return Number.isFinite(created) && created >= slotStartMs;
}

interface RunSummary {
  id?: number;
  event?: string;
  status?: string;
  conclusion?: string | null;
  created_at?: string;
}

/** The newest run that could have covered a slot, or undefined. */
export function newestCoveringRun(
  runs: ReadonlyArray<RunSummary> | undefined,
): RunSummary | undefined {
  return (runs ?? []).find(
    (r) =>
      COVERING_EVENTS.has(String(r.event)) &&
      !(r.status === "completed" && NON_EXECUTED_CONCLUSIONS.has(String(r.conclusion))),
  );
}

export function shouldArmWatchdogClock(env: WatchdogClockDeps["env"]): {
  arm: boolean;
  hostId: string;
  reason?: "not-production" | "no-host-id";
} {
  const hostId = (env.SOLEUR_HOST_ID ?? "").trim();
  // SOLEUR_HOST_ID is injected only by ci-deploy.sh into the deployed prod and
  // canary containers; NODE_ENV=production alone is not enough (a local
  // `npm start` or the Docker image run by hand sets it). Guarded by the parity
  // test's "no workflow, action, script or e2e config sets SOLEUR_HOST_ID" row.
  if (env.NODE_ENV !== "production") {
    return { arm: false, hostId, reason: "not-production" };
  }
  if (!hostId) return { arm: false, hostId, reason: "no-host-id" };
  return { arm: true, hostId };
}

/**
 * The production mint. The installation id is looked up once (App-JWT client,
 * one round trip) and cached per clock; generateInstallationToken caches the
 * token itself (scope is part of its key), so a steady-state tick signs no JWT
 * and makes no lookup. Any failure drops the cached id so the next tick re-reads
 * it (a reinstalled App gets a new id).
 */
function makeDefaultMint(): () => Promise<string> {
  let installationId: number | null = null;
  return async () => {
    try {
      if (installationId === null) {
        const { octokit } = await createAppJwtOctokit();
        const { data } = await octokit.request(
          "GET /repos/{owner}/{repo}/installation",
          { owner: REPO_OWNER, repo: REPO_NAME },
        );
        installationId = data.id;
      }
      // Narrowest grant that can dispatch (and read runs): actions:write on
      // this one repo.
      return await generateInstallationToken(installationId, {
        minRemainingMs: TOKEN_MIN_LIFETIME_MS,
        permissions: { actions: "write" },
        repositories: [REPO_NAME],
      });
    } catch (err) {
      installationId = null;
      throw err;
    }
  };
}

async function defaultOctokitFor(token: string): Promise<GitHubRequestClient> {
  const { Octokit } = await import("@octokit/core");
  return new Octokit({ auth: token }) as unknown as GitHubRequestClient;
}

class TickTimeoutError extends Error {
  constructor() {
    super(`watchdog dispatch tick exceeded ${TICK_DEADLINE_MS} ms`);
    this.name = "TickTimeoutError";
  }
}

function redact(s: string, token: string): string {
  return token ? s.replaceAll(token, "[REDACTED-INSTALLATION-TOKEN]") : s;
}

/**
 * A NEW Error built from the redacted message — never the raw Octokit error.
 * The name carries the op (`HttpError:dispatch`) so Sentry, which groups on
 * exception type + stack, keeps mint / dedup-read / dispatch failures in
 * separate issues even though every rebuilt error has the same stack.
 */
function rebuild(err: unknown, token: string, op: string): Error {
  const e = err as { message?: unknown; name?: unknown } | null;
  const safe = new Error(redact(String(e?.message ?? err), token));
  safe.name = `${typeof e?.name === "string" ? e.name : "Error"}:${op}`;
  return safe;
}

function classify(err: unknown): { reason: Reason; status?: number } {
  if (err instanceof TickTimeoutError) return { reason: "timeout" };
  const status = (err as { status?: unknown } | null)?.status;
  return typeof status === "number"
    ? { reason: "http", status }
    : { reason: "throw" };
}

function failureTags(workflow: string, c: { reason: Reason; status?: number }) {
  const tags: Record<string, string> = { workflow, reason: c.reason };
  if (c.status !== undefined) tags.status = String(c.status);
  return tags;
}

interface EntryState {
  handledSlot: number | null;
  inFlight: boolean;
  jitterSlot: number | null;
  jitterMs: number;
  attemptSlot: number | null;
  attempts: number;
  retryAt: number;
}

export function startWatchdogDispatchClock(
  overrides: Partial<WatchdogClockDeps> = {},
): { stop: () => void } {
  const deps: WatchdogClockDeps = {
    table: overrides.table ?? WATCHDOG_DISPATCH_TABLE,
    env: overrides.env ?? process.env,
    random: overrides.random ?? Math.random,
    mint: overrides.mint ?? makeDefaultMint(),
    octokitFor: overrides.octokitFor ?? defaultOctokitFor,
    report: overrides.report ?? reportSilentFallback,
    emit: overrides.emit ?? emitWatchdogDispatch,
    // Resolved at call time so fake timers installed after import still apply.
    setInterval:
      overrides.setInterval ?? ((fn, ms) => setInterval(fn, ms) as TimerHandle),
    clearInterval:
      overrides.clearInterval ??
      ((h) => clearInterval(h as ReturnType<typeof setInterval>)),
  };

  const safeEmit = (m: WatchdogDispatchMarker) => {
    try {
      deps.emit(m);
    } catch {
      // fail-open: observability must never break the clock.
    }
  };
  const safeReport = (err: unknown, opts: SilentFallbackOptions) => {
    try {
      deps.report(err, opts);
    } catch {
      // fail-open (reporter fence): a throwing reporter must not escape the tick.
    }
  };

  const gate = shouldArmWatchdogClock(deps.env);
  const hostId = gate.hostId;
  if (!gate.arm) {
    safeEmit({ host_id: hostId, outcome: "disarmed", reason: gate.reason });
    if (deps.env.NODE_ENV === "production") {
      safeReport(null, {
        feature: FEATURE,
        op: "arm",
        message:
          "watchdog dispatch clock disarmed in production: SOLEUR_HOST_ID is empty",
        extra: { reason: gate.reason },
      });
    }
    return { stop: () => undefined };
  }

  // A row whose interval is not a positive integer would make slotStartAt
  // return NaN, which never equals handledSlot — a dispatch every poll. Drop it
  // loudly rather than storm (the parity test also refuses such a row).
  const table = deps.table.filter((e) => {
    const ok = Number.isInteger(e.intervalMinutes) && e.intervalMinutes > 0;
    if (!ok) {
      safeReport(null, {
        feature: FEATURE,
        op: "arm",
        message: `watchdog dispatch clock: invalid intervalMinutes for ${e.workflowFile}; row skipped`,
        extra: { workflow: e.workflowFile, intervalMinutes: e.intervalMinutes },
      });
    }
    return ok;
  });
  safeEmit({ host_id: hostId, outcome: "armed" });

  const state = new Map<string, EntryState>();
  for (const e of table) {
    state.set(e.workflowFile, {
      handledSlot: null,
      inFlight: false,
      jitterSlot: null,
      jitterMs: JITTER_MIN_MS,
      attemptSlot: null,
      attempts: 0,
      retryAt: 0,
    });
  }
  let stopped = false;

  function withTimeout<T>(body: (signal: AbortSignal) => Promise<T>): Promise<T> {
    const ac = new AbortController();
    let timer: ReturnType<typeof setTimeout> | undefined;
    const deadline = new Promise<never>((_, reject) => {
      timer = setTimeout(() => {
        ac.abort();
        reject(new TickTimeoutError());
      }, TICK_DEADLINE_MS);
    });
    return Promise.race([body(ac.signal), deadline]).finally(() =>
      clearTimeout(timer),
    );
  }

  async function runTickSafely(
    entry: WatchdogDispatchEntry,
    slot: number,
    st: EntryState,
  ): Promise<void> {
    const base = {
      host_id: hostId,
      workflow: entry.workflowFile,
      slot: new Date(slot).toISOString(),
    };
    const wf = { owner: REPO_OWNER, repo: REPO_NAME, workflow_id: entry.workflowFile };
    let token = "";
    let op: Op = "mint";
    let failed = false;
    try {
      await withTimeout(async (signal) => {
        token = await deps.mint();
        if (signal.aborted) return;
        op = "dedup-read";
        const gh = await deps.octokitFor(token);
        let covering: RunSummary | undefined;
        try {
          const res = await gh.request(
            "GET /repos/{owner}/{repo}/actions/workflows/{workflow_id}/runs",
            { ...wf, branch: "main", per_page: RUNS_READ_PAGE, request: { signal } },
          );
          covering = newestCoveringRun(
            (res.data as { workflow_runs?: RunSummary[] } | undefined)?.workflow_runs,
          );
        } catch (readErr) {
          if (signal.aborted) return;
          // Fail OPEN: a skipped watchdog is the defect this clock fixes; a
          // duplicate run is harmless.
          const c = classify(readErr);
          safeReport(rebuild(readErr, token, "dedup-read"), {
            feature: FEATURE,
            op: "dedup-read",
            message: "watchdog dispatch clock: runs read failed; dispatching anyway",
            extra: { workflow: entry.workflowFile, ...c },
            tags: failureTags(entry.workflowFile, c),
          });
        }
        if (signal.aborted) return;
        if (covering?.created_at && slotAlreadyHasRun(covering.created_at, slot)) {
          safeEmit({
            ...base,
            outcome: "skipped_slot_has_run",
            run_id: covering.id,
            run_event: covering.event,
          });
          return;
        }
        op = "dispatch";
        await gh.request(
          "POST /repos/{owner}/{repo}/actions/workflows/{workflow_id}/dispatches",
          { ...wf, ref: "main", request: { signal } },
        );
        if (signal.aborted) return;
        safeEmit({ ...base, outcome: "dispatched" });
      });
    } catch (err) {
      failed = true;
      const c = classify(err);
      safeReport(rebuild(err, token, op), {
        feature: FEATURE,
        op,
        message: `watchdog dispatch clock: ${op} failed for ${entry.workflowFile}`,
        extra: { workflow: entry.workflowFile, ...c },
        tags: failureTags(entry.workflowFile, c),
      });
      safeEmit({ ...base, outcome: "failed", op, ...c });
    } finally {
      // A failed tick is retried after RETRY_BACKOFF_MS, up to
      // MAX_ATTEMPTS_PER_SLOT per slot; anything else closes the slot.
      st.inFlight = false;
      st.attempts += 1;
      if (failed && st.attempts < MAX_ATTEMPTS_PER_SLOT) {
        st.retryAt = Date.now() + RETRY_BACKOFF_MS;
      } else {
        st.handledSlot = slot;
      }
    }
  }

  function poll(): void {
    if (stopped) return;
    try {
      const now = Date.now();
      for (const entry of table) {
        const st = state.get(entry.workflowFile)!;
        const slot = slotStartAt(now, entry.intervalMinutes);
        // `<=`, not `===`: a backwards clock step must not replay an older slot.
        if ((st.handledSlot !== null && slot <= st.handledSlot) || st.inFlight) continue;
        if (st.jitterSlot !== slot) {
          const r = Math.min(1, Math.max(0, deps.random()));
          st.jitterSlot = slot;
          st.jitterMs = JITTER_MIN_MS + Math.round(r * (JITTER_MAX_MS - JITTER_MIN_MS));
        }
        if (now < slot + st.jitterMs) continue;
        if (st.attemptSlot !== slot) {
          st.attemptSlot = slot;
          st.attempts = 0;
          st.retryAt = 0;
        }
        if (now < st.retryAt) continue;
        st.inFlight = true;
        void runTickSafely(entry, slot, st).catch((escaped: unknown) => {
          // Outer fence: reached only if the inner catch itself throws. The
          // process must survive and the next slot must proceed.
          st.inFlight = false;
          st.handledSlot = slot;
          safeEmit({
            host_id: hostId,
            workflow: entry.workflowFile,
            slot: new Date(slot).toISOString(),
            outcome: "tick_escaped",
          });
          safeReport(new Error("watchdog dispatch clock: a tick escaped its fences"), {
            feature: FEATURE,
            op: "tick",
            extra: {
              workflow: entry.workflowFile,
              escapedName: (() => {
                try {
                  return String((escaped as { name?: unknown } | null)?.name ?? "");
                } catch {
                  return "";
                }
              })(),
            },
          });
        });
      }
    } catch {
      safeReport(new Error("watchdog dispatch clock: poll threw"), {
        feature: FEATURE,
        op: "poll",
      });
    }
  }

  const interval = deps.setInterval(poll, POLL_MS);
  interval.unref?.();

  return {
    stop: () => {
      if (stopped) return;
      stopped = true;
      deps.clearInterval(interval);
    },
  };
}
