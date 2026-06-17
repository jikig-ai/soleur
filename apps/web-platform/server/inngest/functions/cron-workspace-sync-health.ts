// Workspace sync-health probe — detects workspaces that are connected
// (repo_status='ready') but UNREACHABLE by the webhook-driven reconcile
// because their github_installation_id is NULL.
//
// Why this exists: KB sync is driven entirely by the GitHub push webhook,
// which resolves target workspaces with
//   WHERE github_installation_id = <push.installation.id> AND repo_url = <repo>
// (workspace-reconcile-on-push.ts). A workspace whose github_installation_id
// is NULL — e.g. a legacy connection that predates the GitHub App model, or a
// row left behind by an incomplete re-auth — can NEVER match that filter, so
// it silently never syncs AND writes zero kb_sync_history rows (it never even
// enters the fan-out loop). That exact state froze the founder's own KB for
// ~5 weeks before anyone noticed, because nothing was loud.
//
// This cron makes that class loud: a daily read-only scan that reports each
// `repo_status='ready' AND github_installation_id IS NULL` workspace to Sentry
// via reportSilentFallback. It mutates nothing (a state flip to 'error' would
// 409 the /api/kb/tree read and BLANK the user's tree — strictly worse than a
// stale-but-visible tree), so there is no migration and no UI change.
//
// ADR-033 invariants: I1 (all IO inside step.run), I2 (no claude/BYOK),
// I5 (deterministic step.run return shapes), I6 (emits no Inngest events).

import { inngest } from "@/server/inngest/client";
import { reportSilentFallback } from "@/server/observability";
import { getDefaultBranchHeadCommitAt } from "@/server/github-app";
import { resolveInstallationIdForWorkspace } from "@/server/resolve-installation-id-for-workspace";
import { postSentryHeartbeat, type HandlerArgs } from "./_cron-shared";

const SENTRY_MONITOR_SLUG = "cron-workspace-sync-health";
const SENTRY_FEATURE = "workspace-sync-health";

// Arm 3 (#4717) — went-quiet detection tuning.
// Cross-clock guard: the default-branch HEAD `committer.date` comes from GitHub's
// clock, lastOk from ours. The slack must exceed GitHub↔our NTP skew (sub-second
// in practice); 5min is generous headroom. It is NOT a tuning knob — keep it a
// file-local literal. (committer.date is client-rewritable; see the arm-3 block.)
const FRESHNESS_SLACK_MS = 5 * 60 * 1000;
// Staleness floor. A blank or `0` env var must NOT yield a 0-day firehose, so the
// guard rejects non-finite AND non-positive values (mirrors WORKSPACE_RECONCILE_
// IGNORE_REPOS — non-secret, .env.example, not Doppler).
const KB_WENT_QUIET_MAX_GAP_DAYS = (() => {
  const n = Number(process.env.KB_WENT_QUIET_MAX_GAP_DAYS);
  return Number.isFinite(n) && n > 0 ? n : 3;
})();

interface ScanResult {
  ok: boolean;
  findings: { workspaceId: string; repoUrl: string | null }[];
  error: string | null;
}

export async function cronWorkspaceSyncHealthHandler({
  step,
  logger,
}: HandlerArgs): Promise<ScanResult> {
  // Step 1: scan workspaces for the ready-but-unreconcilable class.
  const scan = await step.run("scan-ready-null-installation", async (): Promise<ScanResult> => {
    const { createServiceClient } = await import("@/lib/supabase/service");
    const service = createServiceClient();
    const { data, error } = await service
      .from("workspaces")
      .select("id, repo_url")
      .eq("repo_status", "ready")
      .is("github_installation_id", null);
    if (error) {
      reportSilentFallback(error, {
        feature: SENTRY_FEATURE,
        op: "scan",
        message: "Workspace sync-health scan failed",
      });
      return { ok: false, findings: [], error: error.message };
    }
    const rows = (data as { id: string; repo_url: string | null }[] | null) ?? [];
    return {
      ok: true,
      findings: rows.map((r) => ({ workspaceId: r.id, repoUrl: r.repo_url })),
      error: null,
    };
  });

  // Step 2: report each unreachable workspace. Each is a workspace the user
  // believes is connected ('ready') but that the reconcile can never select.
  if (scan.ok && scan.findings.length > 0) {
    await step.run("report-unreachable-workspaces", async () => {
      for (const f of scan.findings) {
        reportSilentFallback(
          new Error("ready workspace has NULL github_installation_id — unreachable by reconcile"),
          {
            feature: SENTRY_FEATURE,
            op: "ready-null-installation",
            extra: { workspaceId: f.workspaceId, repoUrl: f.repoUrl },
            message:
              "Workspace is repo_status=ready but github_installation_id is NULL — KB sync can never run; needs GitHub App re-authorization",
          },
        );
      }
      return { reported: scan.findings.length };
    });
  }

  // Step 2b (item 2, #4712): ready + INSTALLED workspaces whose owner's LATEST
  // kb_sync_history row is ok:false — a persistent recorded sync failure that
  // item-1's NULL-install scan can never catch (those write zero rows). This
  // class IS installed, so the webhook reaches it, but the sync keeps failing
  // and the user just sees a stale tree. kb_sync_history lives on `users` only
  // (ADR-044 mirrored repo cols — not history — to workspaces), so this scan
  // still reads `users` for the history; the INSTALL is resolved per-row from
  // the user's solo `workspaces` row via resolveInstallationIdForWorkspace
  // (#5470 — the legacy `users` install predicate is dropped ahead of PR-2b's
  // column drop, which removes that column). Read-only; reports in-place and
  // deliberately does NOT widen the function's ScanResult return.
  await step.run("scan-stale-sync-failed", async (): Promise<{ reported: number }> => {
    const { createServiceClient } = await import("@/lib/supabase/service");
    const service = createServiceClient();
    const { data, error } = await service
      .from("users")
      .select("id, kb_sync_history")
      .eq("repo_status", "ready");
    if (error) {
      reportSilentFallback(error, {
        feature: SENTRY_FEATURE,
        op: "scan-stale",
        message: "Stale-sync-failed scan failed",
      });
      return { reported: 0 };
    }
    const rows = (data as { id: string; kb_sync_history: unknown }[] | null) ?? [];
    let reported = 0;
    for (const r of rows) {
      // Latest row only (at(-1)) — NOT .some(): a since-recovered repo whose
      // history contains an old ok:false must not fire. Legacy {date,count}
      // rows and ok:true rows are excluded by the `'ok' in latest` guard.
      const history = Array.isArray(r.kb_sync_history) ? r.kb_sync_history : [];
      const latest = history.at(-1);
      if (
        typeof latest === "object" &&
        latest !== null &&
        "ok" in latest &&
        (latest as { ok: unknown }).ok === false
      ) {
        // Resolve the install from the user's solo workspace. A null result
        // (not connected) is the dropped install predicate's per-row
        // equivalent — skip, do not report. Newly-connected users (whose legacy
        // `users` install column is NULL but whose `workspaces` row is
        // populated) are now CAUGHT here, where the old `users` predicate
        // false-negatively excluded them (#5470 Test Scenario 6).
        const install = await resolveInstallationIdForWorkspace(r.id, service);
        if (install === null) continue;
        reportSilentFallback(
          new Error("ready+installed workspace's latest KB sync failed"),
          {
            feature: SENTRY_FEATURE,
            op: "stale-sync-failed",
            // reportSilentFallback hashes extra.userId → userIdHash. Static
            // Error message above carries no PII (deepen security note).
            extra: { userId: r.id },
            message:
              "Latest kb_sync_history row is ok:false on an installed workspace — KB stale despite installed app; needs investigation",
          },
        );
        reported++;
      }
    }
    return { reported };
  });

  // Step 2c (item 3, #4717): the WENT-QUIET class — ready + INSTALLED users
  // whose LATEST kb_sync_history row is ok:true but whose repo's DEFAULT branch
  // has commits that were never synced (webhook pushes stopped → zero new rows →
  // the latest row stays ok:true forever and looks healthy). kb_sync_history can
  // never reveal this (went-quiet erases its own record), so the signal is
  // out-of-band: GitHub's default-branch HEAD commit date vs. the last ok:true
  // sync. Fire only when BOTH (a) the repo pushed since the last sync (+slack,
  // cross-clock) AND (b) the last sync is older than N days — clause (a)
  // suppresses the idle-repo false positive. Scans `users` (mirrors arm 2 → the
  // two arms partition by latest-row ok-polarity; never double-report).
  //
  // DEFAULT BRANCH is the correct probe target (not "any branch"): the reconcile
  // only ever syncs the default branch — webhook-push-reconcilable.ts drops
  // non-default-branch pushes, tags, and deletions — so default-branch HEAD is
  // exactly "the content we should have synced." This is also why a feature-
  // branch push can't false-positive here. NOTE: GitHub's `committer.date` is
  // client-rewritable (rebase/amend/fabricated date); a force-push that backdates
  // HEAD could mask a real change (false negative) or future-dating could over-
  // fire — both rare, accepted at p3 (plan Risks).
  //
  // Legacy-tail blind spot: a user whose latest row is a legacy {date,count} row
  // (no `ok` key) is deliberately skipped — we cannot assert freshness from it.
  // Largely moot (the legacy writer is RLS-blocked; only pre-existing historical
  // data can have a legacy tail), but it IS an accepted coverage gap, not health.
  //
  // Heartbeat isolation is STRUCTURAL: the heartbeat is its own later step.run and
  // consumes only arm-1's `scan.ok` — it never reads arm-3 state. The try/catch
  // below is belt-and-suspenders (keeps this step's return clean); do NOT fold the
  // heartbeat into this step on the belief the try/catch alone protects it.
  await step.run("scan-went-quiet", async (): Promise<{ wentQuiet: number }> => {
    try {
      const { createServiceClient } = await import("@/lib/supabase/service");
      const service = createServiceClient();
      const { data, error } = await service
        .from("users")
        .select("id, repo_url, kb_sync_history")
        .eq("repo_status", "ready");
      if (error) {
        reportSilentFallback(error, {
          feature: SENTRY_FEATURE,
          op: "scan-went-quiet",
          message: "Went-quiet scan failed",
        });
        return { wentQuiet: 0 };
      }
      const rows =
        (data as
          | {
              id: string;
              repo_url: string | null;
              kb_sync_history: unknown;
            }[]
          | null) ?? [];
      const now = Date.now();
      const maxGapMs = KB_WENT_QUIET_MAX_GAP_DAYS * 24 * 60 * 60 * 1000;
      let wentQuiet = 0;
      for (const r of rows) {
        // Need a repo to probe; the install is resolved per-row below (from the
        // user's solo workspace) just before the GitHub probe that consumes it.
        if (!r.repo_url) continue;
        // Latest row only — `at(-1).ok === true` is the went-quiet gate AND the
        // mutual-exclusion boundary with arm 2 (which fires on `ok === false`).
        // The `'ok' in latest` guard excludes legacy {date,count} rows.
        const history = Array.isArray(r.kb_sync_history) ? r.kb_sync_history : [];
        const latest = history.at(-1);
        if (
          typeof latest !== "object" ||
          latest === null ||
          !("ok" in latest) ||
          (latest as { ok: unknown }).ok !== true
        ) {
          continue;
        }
        // `at` is a required KbSyncRow field; the NaN guard is defensive only.
        const atStr = (latest as { at?: unknown }).at;
        const lastOkSyncAt = typeof atStr === "string" ? Date.parse(atStr) : NaN;
        if (Number.isNaN(lastOkSyncAt)) continue;
        if (now - lastOkSyncAt <= maxGapMs) continue; // fresh — clause (b) fails

        // owner/repo from the user's own repo_url (NOT _cron-shared constants,
        // which point at Soleur's own repo). Mirrors workspace-reconcile-on-push's
        // repoSlug. repo_url is canonical `https://github.com/owner/repo` at write
        // time (normalizeRepoUrl), so a falsy owner/repo here is a near-impossible
        // legacy/malformed row — skipping it silently is benign (the helper
        // encodeURIComponent-guards the segments regardless).
        const slug = r.repo_url
          .replace(/^https?:\/\/[^/]+\//i, "")
          .replace(/\.git$/i, "");
        const [owner, repo] = slug.split("/");
        if (!owner || !repo) continue;

        // Resolve the install from the user's solo workspace (replaces the
        // dropped `users` install select+predicate, #5470). Null → not
        // connected → skip, exactly as the old predicate filtered it out.
        const install = await resolveInstallationIdForWorkspace(r.id, service);
        if (install === null) continue;

        let headCommitAt: number | null;
        try {
          headCommitAt = await getDefaultBranchHeadCommitAt(
            install,
            owner,
            repo,
          );
        } catch (err) {
          // One unreachable repo (revoked install, deleted repo) must not abort
          // the scan for everyone else.
          reportSilentFallback(err, {
            feature: SENTRY_FEATURE,
            op: "went-quiet-probe",
            extra: { userId: r.id },
            message: "Went-quiet GitHub probe failed",
          });
          continue;
        }
        if (headCommitAt === null) continue; // empty repo — nothing to sync

        // Clause (b) already held above; check clause (a) (cross-clock slack).
        if (headCommitAt > lastOkSyncAt + FRESHNESS_SLACK_MS) {
          reportSilentFallback(
            new Error(
              "ready+installed user went quiet — default-branch commits since last sync but no new kb_sync_history row",
            ),
            {
              feature: SENTRY_FEATURE,
              op: "went-quiet",
              // reportSilentFallback hashes extra.userId → userIdHash; no PII in
              // the static message above.
              extra: { userId: r.id },
              message:
                "KB went quiet — the default branch has commits the workspace never synced; needs investigation",
            },
          );
          wentQuiet++;
        }
      }
      logger.info(
        { fn: "cron-workspace-sync-health", wentQuiet },
        "Went-quiet scan complete",
      );
      return { wentQuiet };
    } catch (err) {
      reportSilentFallback(err, {
        feature: SENTRY_FEATURE,
        op: "scan-went-quiet",
        message: "Went-quiet scan threw unexpectedly",
      });
      return { wentQuiet: 0 };
    }
  });

  // Step 3: Sentry heartbeat. ok = the scan itself ran (findings are expected
  // signal, not a probe failure).
  await step.run("sentry-heartbeat", async () => {
    await postSentryHeartbeat({
      ok: scan.ok,
      sentryMonitorSlug: SENTRY_MONITOR_SLUG,
      cronName: "cron-workspace-sync-health",
      logger,
    });
  });

  return scan;
}

export const cronWorkspaceSyncHealth = inngest.createFunction(
  {
    id: "cron-workspace-sync-health",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "23 6 * * *" },
    { event: "cron/workspace-sync-health.manual-trigger" },
  ],
  cronWorkspaceSyncHealthHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
