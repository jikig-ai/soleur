// Watchdog dispatch clock (#8495, ADR-248).
//
// GitHub Actions `schedule:` drops ticks: the external Inngest watchdog
// (*/15) measured one run every 2-7 h, so an Inngest outage went unseen for
// hours. This in-process poll fires `workflow_dispatch` for each row of
// WATCHDOG_DISPATCH_TABLE on a UTC wall-clock slot; dispatched runs start within
// seconds. The workflows keep their `schedule:` crons as a fallback.
//
// It is NOT an Inngest function (a watcher of Inngest cannot be scheduled by
// Inngest — ADR-033 anti-circularity) and must never import server/inngest/
// (pinned by watchdog-dispatch-clock.test.ts). It runs on every deployed web
// host; per-slot jitter plus a slot-scoped "does this slot already have a run?"
// read keep the hosts from double-dispatching (a rare collision is a harmless,
// queued duplicate — both workflows use cancel-in-progress: false).
//
// Safety: crash-handlers.ts exits the process on unhandledRejection, so every
// tick sits inside three fences (inner try/catch/finally, an outer .catch that
// emits `tick_escaped`, and fail-open report/emit wrappers). A tick is bounded
// by TICK_DEADLINE_MS. Errors are rebuilt from a token-redacted message; the
// raw Octokit error (whose request/response carry the token) is never forwarded.

import { createProbeOctokit } from "@/server/github/probe-octokit";
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
const REPO_OWNER = "jikig-ai";
const REPO_NAME = "soleur";

export const POLL_MS = 30_000;
// Jitter spreads the web hosts so the later one's read sees the earlier one's
// run. JITTER_MAX_MS is part of the Sentry margin budget documented on the
// monitors in apps/web-platform/infra/sentry/cron-monitors.tf (poll 0.5 min +
// jitter 2 min + tick <= 1.5 min + job runtime must fit inside
// checkin_margin_minutes).
export const JITTER_MIN_MS = 30_000;
export const JITTER_MAX_MS = 120_000;
export const TICK_DEADLINE_MS = 90_000;
const TOKEN_MIN_LIFETIME_MS = 5 * 60_000;

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

/** True iff a run created at `createdAtIso` belongs to the slot starting at `slotStartMs`. */
export function slotAlreadyHasRun(
  createdAtIso: string,
  slotStartMs: number,
): boolean {
  const created = Date.parse(createdAtIso);
  // No tolerance before the slot: GitHub creates `schedule:` runs late, never
  // early, and a dispatch happens >= JITTER_MIN_MS into the slot, so any run of
  // this slot has created_at >= slot start (NTP skew is far below 30 s). A run
  // from the previous slot, however late, never suppresses this one.
  // Unparseable → "not this slot": fail open to a (harmless) dispatch.
  return Number.isFinite(created) && created >= slotStartMs;
}

export function shouldArmWatchdogClock(env: WatchdogClockDeps["env"]): {
  arm: boolean;
  hostId: string;
  reason?: "not-production" | "no-host-id";
} {
  const hostId = (env.SOLEUR_HOST_ID ?? "").trim();
  // SOLEUR_HOST_ID is injected only by ci-deploy.sh into the deployed prod and
  // canary containers; NODE_ENV=production alone is not enough (a local
  // `npm start` or a future CI job can set it). Guarded by the parity test's
  // "no workflow or e2e config sets SOLEUR_HOST_ID" row.
  if (env.NODE_ENV !== "production") {
    return { arm: false, hostId, reason: "not-production" };
  }
  if (!hostId) return { arm: false, hostId, reason: "no-host-id" };
  return { arm: true, hostId };
}

async function defaultMint(): Promise<string> {
  const octokit = await createProbeOctokit();
  const { data: installation } = await octokit.request(
    "GET /repos/{owner}/{repo}/installation",
    { owner: REPO_OWNER, repo: REPO_NAME },
  );
  // Narrowest grant that can dispatch (and read runs): actions:write on this
  // one repo. The scope is part of generateInstallationToken's cache key.
  return generateInstallationToken(installation.id, {
    minRemainingMs: TOKEN_MIN_LIFETIME_MS,
    permissions: { actions: "write" },
    repositories: [REPO_NAME],
  });
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

/** A NEW Error built from the redacted message — never the raw Octokit error. */
function rebuild(err: unknown, token: string): Error {
  const e = err as { message?: unknown; name?: unknown } | null;
  const safe = new Error(redact(String(e?.message ?? err), token));
  if (typeof e?.name === "string") safe.name = e.name;
  return safe;
}

function classify(err: unknown): { reason: Reason; status?: number } {
  if (err instanceof TickTimeoutError) return { reason: "timeout" };
  const status = (err as { status?: unknown } | null)?.status;
  return typeof status === "number"
    ? { reason: "http", status }
    : { reason: "throw" };
}

interface RunSummary {
  id?: number;
  event?: string;
  created_at?: string;
}

interface EntryState {
  handledSlot: number | null;
  inFlight: boolean;
  jitterSlot: number | null;
  jitterMs: number;
}

export function startWatchdogDispatchClock(
  overrides: Partial<WatchdogClockDeps> = {},
): { stop: () => void } {
  const deps: WatchdogClockDeps = {
    table: overrides.table ?? WATCHDOG_DISPATCH_TABLE,
    env: overrides.env ?? process.env,
    random: overrides.random ?? Math.random,
    mint: overrides.mint ?? defaultMint,
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
  safeEmit({ host_id: hostId, outcome: "armed" });

  const state = new Map<string, EntryState>();
  for (const e of deps.table) {
    state.set(e.workflowFile, {
      handledSlot: null,
      inFlight: false,
      jitterSlot: null,
      jitterMs: JITTER_MIN_MS,
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
    try {
      await withTimeout(async (signal) => {
        token = await deps.mint();
        if (signal.aborted) return;
        op = "dedup-read";
        const gh = await deps.octokitFor(token);
        let newest: RunSummary | undefined;
        try {
          const res = await gh.request(
            "GET /repos/{owner}/{repo}/actions/workflows/{workflow_id}/runs",
            { ...wf, per_page: 1, request: { signal } },
          );
          newest = (res.data as { workflow_runs?: RunSummary[] } | undefined)
            ?.workflow_runs?.[0];
        } catch (readErr) {
          if (signal.aborted) return;
          // Fail OPEN: a skipped watchdog is the defect this clock fixes; a
          // duplicate run is harmless.
          const c = classify(readErr);
          safeReport(rebuild(readErr, token), {
            feature: FEATURE,
            op: "dedup-read",
            message: "watchdog dispatch clock: runs read failed; dispatching anyway",
            extra: { workflow: entry.workflowFile, ...c },
          });
        }
        if (signal.aborted) return;
        if (newest?.created_at && slotAlreadyHasRun(newest.created_at, slot)) {
          safeEmit({
            ...base,
            outcome: "skipped_slot_has_run",
            run_id: newest.id,
            run_event: newest.event,
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
      const c = classify(err);
      safeReport(rebuild(err, token), {
        feature: FEATURE,
        op,
        message: `watchdog dispatch clock: ${op} failed for ${entry.workflowFile}`,
        extra: { workflow: entry.workflowFile, ...c },
      });
      safeEmit({ ...base, outcome: "failed", op, ...c });
    } finally {
      // A failed slot is NOT retried by this host: the other host's clock and
      // the next slot cover it.
      st.inFlight = false;
      st.handledSlot = slot;
    }
  }

  function poll(): void {
    if (stopped) return;
    try {
      const now = Date.now();
      for (const entry of deps.table) {
        const st = state.get(entry.workflowFile);
        if (!st) continue;
        const slot = slotStartAt(now, entry.intervalMinutes);
        if (st.handledSlot === slot || st.inFlight) continue;
        if (st.jitterSlot !== slot) {
          const r = Math.min(1, Math.max(0, deps.random()));
          st.jitterSlot = slot;
          st.jitterMs = JITTER_MIN_MS + Math.round(r * (JITTER_MAX_MS - JITTER_MIN_MS));
        }
        if (now < slot + st.jitterMs) continue;
        st.inFlight = true;
        void runTickSafely(entry, slot, st).catch((escaped: unknown) => {
          // Outer fence. Unreachable by design (Guard 2 pins it); if it ever
          // fires, the process must survive and the next slot must proceed.
          st.inFlight = false;
          st.handledSlot = slot;
          safeEmit({
            host_id: hostId,
            workflow: entry.workflowFile,
            slot: new Date(slot).toISOString(),
            outcome: "tick_escaped",
          });
          safeReport(rebuild(escaped, ""), {
            feature: FEATURE,
            op: "tick",
            message: "watchdog dispatch clock: a tick escaped its fences",
            extra: { workflow: entry.workflowFile },
          });
        });
      }
    } catch (err) {
      safeReport(rebuild(err, ""), {
        feature: FEATURE,
        op: "poll",
        message: "watchdog dispatch clock: poll threw",
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
