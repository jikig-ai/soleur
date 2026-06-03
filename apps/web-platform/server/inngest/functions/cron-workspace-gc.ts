// cron-workspace-gc — ephemeral cron-clone garbage collector (2026-06-03, #4882).
//
// WHY THIS SHAPE: every cron that clones the soleur repo does
// `mkdtemp(join(resolveCronWorkspaceRoot(), "soleur-<cronName>-"))`
// (_cron-claude-eval-substrate.ts setupEphemeralWorkspace). Cleanup is a
// caller-side `finally { rm }` — which OOM / ENOSPC / SIGKILL bypass by
// definition. Leaked `soleur-*` clones (~100 MB each) then accumulated on the
// shared 20 GB Hetzner volume until it filled and the org-workspace KB
// reconcile's `git pull` ENOSPC'd silently (the 2026-06-02 freeze: zero
// kb_sync_history rows written after 07:46). An IN-PROCESS sweeper is the only
// thing that survives a killed clone — so this cron statfs-reports the cron-clone
// root (`resolveCronWorkspaceRoot()` = `/workspaces` in prod), removes aged
// `soleur-*` dirs there, statfs again, and posts a Sentry Crons heartbeat.
//
// NOTE: the `.cron` subdir isolation (#4886) was reverted — a deploy-critical-path
// `mkdir /mnt/data/workspaces/.cron` ENOSPC-deadlocked the deploy on the already-
// full volume. So the GC sweeps `/workspaces` DIRECTLY — the same path the leaked
// clones live in — which is also what reclaims the existing leak. This is safe
// because the `soleur-` prefix guard is the load-bearing protection (see below),
// not the subdir. Dedicated-volume isolation is deferred to #4891.
//
// Modeled verbatim on cron-supabase-disk-io.ts. In-process (NOT dispatch-hybrid):
// pure local fs, no claude / no BYOK / no subprocess / no credentials — so it
// owns its own SENTRY_MONITOR_SLUG and runs in-container against the mounted
// volume. ADR-033 invariants: all IO inside step.run (I1); no claude/BYOK (I2);
// no long-running subprocess (I3); deterministic step.run returns (I5); emits no
// Inngest events (I6).
//
// DESTRUCTIVE-SWEEP SAFETY is structural, not advisory: the sweep matches ONLY
// the `soleur-` prefix (UUID workspace dirs are 36-char `[0-9a-f-]`, never
// `soleur-*`), is maxdepth 1, and age-gated > 1h. The prefix guard is the sole
// load-bearing protection now that the GC sweeps `/workspaces` (where the UUID
// dirs also live) — a 36-char UUID dir can never satisfy `startsWith("soleur-")`,
// so it is provably unreachable regardless of CRON_WORKSPACE_ROOT's value.
// cron-workspace-gc.test.ts asserts a UUID dir is never swept (even when old).
//
// Plan: knowledge-base/project/plans/2026-06-03-fix-cron-workspace-gc-and-kb-reconcile-isolation-plan.md

import { statfs, readdir, rm, stat } from "node:fs/promises";
import { join } from "node:path";
import { inngest } from "@/server/inngest/client";
import {
  reportSilentFallback,
  warnSilentFallback,
} from "@/server/observability";
import {
  freeMb,
  resolveCronWorkspaceRoot,
  postSentryHeartbeat,
  DEFAULT_CRON_WORKSPACE_MIN_FREE_MB,
  type HandlerArgs,
} from "./_cron-shared";

// Re-export the shared disk-free helper so its unit test (and any future
// consumer) can import it from this module's public surface unchanged.
export { freeMb };

// =============================================================================
// Constants
// =============================================================================

export const SENTRY_MONITOR_SLUG = "scheduled-workspace-gc";
// Matches the prefix setupEphemeralWorkspace mkdtemps (`soleur-${cronName}-`).
export const CRON_DIR_PREFIX = "soleur-";
// Sweep dirs older than this. Tunable via CRON_WORKSPACE_GC_MAX_AGE_MS so a
// pathologically slow clone is never reaped mid-flight (the active-clone window
// is minutes; 1h is generous headroom).
export const DEFAULT_MAX_AGE_MS = 60 * 60 * 1000;

const CRON_NAME = "cron-workspace-gc";

// =============================================================================
// Pure helpers (unit-tested without fs)
// =============================================================================

// `freeMb` (bavail-based disk-free arithmetic) is imported + re-exported from
// _cron-shared above — single source of truth shared with warnIfCronWorkspaceLowOnDisk.

// A dir is sweepable iff it is a leaked cron clone (soleur- prefix) AND older
// than the max-age. The prefix guard is load-bearing: a 36-char UUID
// KB-workspace dir must never satisfy it, regardless of age.
export function isSweepable(
  name: string,
  ageMs: number,
  maxAgeMs: number,
): boolean {
  return name.startsWith(CRON_DIR_PREFIX) && ageMs > maxAgeMs;
}

// =============================================================================
// Handler
// =============================================================================

export async function cronWorkspaceGcHandler({
  step,
  logger,
}: HandlerArgs): Promise<{ sweptCount: number; freedMb: number; root: string }> {
  const root = resolveCronWorkspaceRoot();
  const maxAgeMs =
    Number(process.env.CRON_WORKSPACE_GC_MAX_AGE_MS) || DEFAULT_MAX_AGE_MS;
  const floorMb =
    Number(process.env.CRON_WORKSPACE_MIN_FREE_MB) ||
    DEFAULT_CRON_WORKSPACE_MIN_FREE_MB;

  const swept = await step.run("workspace-gc-sweep", async () => {
    const now = Date.now();

    // statfs BEFORE. ENOENT on the root means this env has no mounted volume
    // (local dev / CI / fresh box) — an expected degraded state, not a failure:
    // there is nothing to sweep, so short-circuit without paging (mirrors
    // session-metrics getActiveWorkspaceCount). Any OTHER statfs error is a real
    // silent fallback and goes to Sentry, but is still non-fatal.
    let freeMbBefore: number | null = null;
    try {
      freeMbBefore = freeMb(await statfs(root));
    } catch (err) {
      if ((err as NodeJS.ErrnoException)?.code === "ENOENT") {
        logger.info(
          { fn: CRON_NAME, root },
          "cron workspace root absent (ENOENT) — nothing to sweep",
        );
        return { sweptCount: 0, freeMbBefore: null, freeMbAfter: null, freedMb: 0 };
      }
      reportSilentFallback(err, {
        feature: CRON_NAME,
        op: "workspace-gc-statfs-before",
        message: "Could not statfs cron workspace root before sweep (non-fatal)",
        extra: { fn: CRON_NAME, root },
      });
    }

    // List the cron-clone root. ENOENT here is the same degraded state.
    let names: string[] = [];
    try {
      names = await readdir(root);
    } catch (err) {
      if ((err as NodeJS.ErrnoException)?.code === "ENOENT") {
        return {
          sweptCount: 0,
          freeMbBefore,
          freeMbAfter: freeMbBefore,
          freedMb: 0,
        };
      }
      reportSilentFallback(err, {
        feature: CRON_NAME,
        op: "workspace-gc-readdir",
        message: "Could not read cron workspace root (non-fatal)",
        extra: { fn: CRON_NAME, root },
      });
    }

    let sweptCount = 0;
    for (const name of names) {
      // Cheap prefix gate first — skip the stat() syscall for non-cron dirs
      // (the UUID KB-workspace dirs), so we never even touch their inode.
      if (!name.startsWith(CRON_DIR_PREFIX)) continue;
      const full = join(root, name);
      // Per-dir try/catch: a single EACCES/ENOENT (a racing clone removing its
      // own dir, a permission quirk) must NEVER abort the sweep — report it once
      // and keep reclaiming the rest.
      try {
        const st = await stat(full);
        if (!st.isDirectory()) continue;
        const ageMs = now - st.mtimeMs;
        if (!isSweepable(name, ageMs, maxAgeMs)) continue;
        await rm(full, { recursive: true, force: true });
        sweptCount += 1;
      } catch (err) {
        reportSilentFallback(err, {
          feature: CRON_NAME,
          op: "workspace-gc-rm",
          message: "Failed to reclaim a leaked cron-clone dir (non-fatal)",
          extra: { fn: CRON_NAME, dir: full },
        });
      }
    }

    // statfs AFTER (non-fatal on error; freedMb falls back to 0 if either probe
    // is unavailable).
    let freeMbAfter: number | null = null;
    try {
      freeMbAfter = freeMb(await statfs(root));
    } catch (err) {
      reportSilentFallback(err, {
        feature: CRON_NAME,
        op: "workspace-gc-statfs-after",
        message: "Could not statfs cron workspace root after sweep (non-fatal)",
        extra: { fn: CRON_NAME, root },
      });
    }
    const freedMb =
      freeMbBefore != null && freeMbAfter != null
        ? freeMbAfter - freeMbBefore
        : 0;

    // Structured every-run record to app stdout (pino). The durable Sentry path
    // is the heartbeat (liveness) + the warn below (actionable low-disk) — Vector
    // does not ship app stdout to Better Stack, so the actionable signal must be
    // a Sentry event, not a log line.
    logger.info(
      { fn: CRON_NAME, root, freeMbBefore, freeMbAfter, freedMb, sweptCount },
      "workspace GC sweep complete",
    );

    // Actionable Sentry signal: the volume is STILL under the free-space floor
    // after reclaiming everything sweepable — i.e. the leak is outpacing the GC
    // or non-cron data is the pressure. Carries the full before/after payload so
    // the operator sees the trend without SSH (#4882's divergence-alert sibling
    // owns content drift; this owns capacity).
    if (freeMbAfter != null && freeMbAfter < floorMb) {
      warnSilentFallback(
        new Error(
          `cron workspace volume low after GC: ${freeMbAfter} MB free < ${floorMb} MB floor at ${root} (freed ${freedMb} MB, swept ${sweptCount})`,
        ),
        {
          feature: CRON_NAME,
          op: "workspace-gc-low-after-sweep",
          message: "Cron workspace volume still low after GC sweep",
          extra: {
            fn: CRON_NAME,
            root,
            freeMbBefore,
            freeMbAfter,
            freedMb,
            sweptCount,
          },
        },
      );
    }

    return { sweptCount, freeMbBefore, freeMbAfter, freedMb };
  });

  // Heartbeat: ok = the sweep RAN (not findings-present). A clean run that
  // reclaims 0 dirs is GREEN; a missed check-in (scheduler dead / fn dropped) is
  // what turns the monitor red.
  await step.run("sentry-heartbeat", async () => {
    await postSentryHeartbeat({
      ok: true,
      sentryMonitorSlug: SENTRY_MONITOR_SLUG,
      cronName: CRON_NAME,
      logger,
    });
  });

  return { sweptCount: swept.sweptCount, freedMb: swept.freedMb, root };
}

// =============================================================================
// Registration
// =============================================================================

export const cronWorkspaceGc = inngest.createFunction(
  {
    id: "cron-workspace-gc",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    // Every 6 hours — frequent enough to keep leaked clones from accumulating
    // into an ENOSPC, infrequent enough to add negligible IO (a readdir + a few
    // rm). (Cron literal kept OUT of the JSDoc header above: a `*/6` inside a
    // `/** */` block closes the comment and breaks esbuild.)
    { cron: "0 */6 * * *" },
    // Enables on-demand firing via /soleur:trigger-cron with zero SSH — the
    // disk-reclaim lever for un-wedging a full volume.
    { event: "cron/workspace-gc.manual-trigger" },
  ],
  cronWorkspaceGcHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
