import { createProbeOctokit } from "@/server/github/probe-octokit";
import { generateInstallationToken } from "@/server/github-app";
import { reportSilentFallback } from "@/server/observability";

export const REPO_OWNER = "jikig-ai";
export const REPO_NAME = "soleur";

export const SENTRY_DOMAIN_RE = /^[a-z0-9.-]+\.sentry\.io$/i;
export const SENTRY_PROJECT_RE = /^\d+$/;
export const SENTRY_PUBLIC_KEY_RE = /^[a-f0-9]{32}$/;

export interface HandlerArgs {
  event?: { data?: Record<string, unknown> };
  step: { run<T>(name: string, cb: () => Promise<T>): Promise<T> };
  logger: {
    info: (...a: unknown[]) => void;
    warn: (...a: unknown[]) => void;
    error: (...a: unknown[]) => void;
  };
}

export function redactToken(s: string, token: string): string {
  if (!token) return s;
  return s.replaceAll(token, "[REDACTED-INSTALLATION-TOKEN]");
}

export function buildAuthenticatedCloneUrl(token: string): string {
  return `https://x-access-token:${token}@github.com/${REPO_OWNER}/${REPO_NAME}.git`;
}

export async function mintInstallationToken(opts: {
  tokenMinLifetimeMs: number;
}): Promise<string> {
  const octokit = await createProbeOctokit();
  const { data: installation } = await octokit.request(
    "GET /repos/{owner}/{repo}/installation",
    { owner: REPO_OWNER, repo: REPO_NAME },
  );
  return generateInstallationToken(installation.id, {
    minRemainingMs: opts.tokenMinLifetimeMs,
  });
}

const SENTRY_HEARTBEAT_TIMEOUT_MS = 10_000;

export async function postSentryHeartbeat(args: {
  ok: boolean;
  sentryMonitorSlug: string;
  cronName: string;
  logger: HandlerArgs["logger"];
}): Promise<void> {
  const { ok, sentryMonitorSlug, cronName, logger } = args;

  if (ok) {
    try {
      const dir = "/var/lib/inngest/cron-fires";
      const { mkdir, writeFile } = await import("node:fs/promises");
      await mkdir(dir, { recursive: true });
      await writeFile(
        `${dir}/${sentryMonitorSlug}.json`,
        JSON.stringify({ last_ok_at: new Date().toISOString(), slug: sentryMonitorSlug }),
      );
    } catch {
      // Best-effort; do not block heartbeat on file-write failure
    }
  }
  const domain = process.env.SENTRY_INGEST_DOMAIN;
  const projectId = process.env.SENTRY_PROJECT_ID;
  const publicKey = process.env.SENTRY_PUBLIC_KEY;
  if (!domain || !projectId || !publicKey) {
    logger.info({ fn: cronName }, "Sentry env unset — skipping heartbeat");
    return;
  }
  if (
    !SENTRY_DOMAIN_RE.test(domain) ||
    !SENTRY_PROJECT_RE.test(projectId) ||
    !SENTRY_PUBLIC_KEY_RE.test(publicKey)
  ) {
    logger.warn({ fn: cronName }, "Sentry env malformed — skipping heartbeat");
    return;
  }
  const status = ok ? "ok" : "error";
  const url = `https://${domain}/api/${projectId}/cron/${sentryMonitorSlug}/${publicKey}/?status=${status}`;
  try {
    await fetch(url, {
      method: "POST",
      signal: AbortSignal.timeout(SENTRY_HEARTBEAT_TIMEOUT_MS),
    });
  } catch (err) {
    const e = err as Error;
    reportSilentFallback(e, {
      feature: "cron-sentry-heartbeat",
      op: "fetch",
      message: "Sentry Crons heartbeat POST failed",
      extra: { fn: cronName, status, aborted: e.name === "TimeoutError" },
    });
  }
}

// ---------------------------------------------------------------------------
// Output-verification helper — closes the silent-no-op gap (#4689/#4686/#4684).
//
// A scheduled producer can exit 0 without producing its `scheduled-<task>`
// output (e.g. the spawned claude exhausts --max-turns before the final
// "create the issue" step, or its `gh issue create` dead-ends). The
// exit-code-only heartbeat (`ok: spawnResult.ok`) then stayed GREEN while the
// producer went quiet — the silent-failure gap that let four producers go
// dark unnoticed until the separate cron-cloud-task-heartbeat watchdog's
// issue-count caught it (weeks later).
//
// "Produced output" = a `scheduled-<task>`-labeled issue CREATED OR UPDATED in
// the run window. The update case matters: roadmap-review's DEDUP RULE comments
// on the most-recent existing issue (instead of creating a new one) when a fire
// from the last 6 days exists — a healthy outcome that creates no new issue.
// Filtering on updated_at (via the GitHub `since` param) credits that
// dedup-comment as output, so a manual-trigger-same-week does NOT false-red.
// Within a producer's ~50-min run window only the producer itself touches its
// own labeled issues (daily-triage runs at a different hour), so updated_at
// moving == the producer did something.
//
// Callers gate their Sentry heartbeat on this result so a quiet producer turns
// its OWN per-function monitor red, with no dependency on the watchdog. Reuses
// the watchdog's read shape (GET /repos/{owner}/{repo}/issues — see
// cron-cloud-task-heartbeat.ts) for parity. Read-only: never creates or
// mutates an issue.
//
// The octokit is injectable purely so unit tests can drive the read shape
// without the App-JWT mint path; production callers omit it and the helper
// mints a probe client itself.
export async function verifyScheduledIssueCreated(args: {
  label: string;
  sinceIso: string;
  octokit?: Awaited<ReturnType<typeof createProbeOctokit>>;
}): Promise<boolean> {
  const { label, sinceIso, octokit } = args;
  const sinceMs = new Date(sinceIso).getTime();
  if (Number.isNaN(sinceMs)) {
    // A NaN lower bound makes every `>=` comparison false and would silently
    // red-flag a healthy producer. Surface the bad input loudly instead.
    throw new Error(
      `verifyScheduledIssueCreated: invalid sinceIso "${sinceIso}"`,
    );
  }

  const client = octokit ?? (await createProbeOctokit());
  const res = await client.request("GET /repos/{owner}/{repo}/issues", {
    owner: REPO_OWNER,
    repo: REPO_NAME,
    labels: label,
    state: "all",
    // `since` filters by updated_at server-side (create OR comment in window).
    since: sinceIso,
    sort: "updated",
    direction: "desc",
    per_page: 5,
    headers: { "X-GitHub-Api-Version": "2022-11-28" },
  });

  // Belt-and-suspenders client-side guard (the server `since` is inclusive and
  // authoritative; this defends against a stub/mock that ignores `since`).
  const issues = res.data as Array<{ updated_at: string }>;
  return issues.some(
    (issue) => new Date(issue.updated_at).getTime() >= sinceMs,
  );
}

// ---------------------------------------------------------------------------
// Output-aware heartbeat resolver — the value each always-create producer
// feeds to postSentryHeartbeat instead of the bare spawn exit code.
//
// Semantics (deliberately asymmetric to avoid alert noise):
//   - spawn failed             → ok:false (verify skipped; the spawn error is
//                                already reported upstream).
//   - spawn ok, issue present  → ok:true.
//   - spawn ok, issue ABSENT   → ok:false + `scheduled-output-missing` event.
//                                This is the silent-no-op the fix targets.
//   - spawn ok, verify THREW   → ok:true (inconclusive: a GitHub-list hiccup
//                                must NOT red-flag a producer that may well
//                                have succeeded) + `verify-output-failed`
//                                event so the inconclusive check is visible.
//
// Only a DEFINITIVE "queried fine, no issue in the run window" flips the
// monitor red. Used by the always-create spawn producers (roadmap, content,
// competitive); strategy-review is pure-TS and legitimately creates zero
// issues on an all-clean run, so it keeps its errors-based heartbeat.
export async function resolveOutputAwareOk(args: {
  spawnOk: boolean;
  label: string;
  runStartedAt: string;
  cronName: string;
  octokit?: Awaited<ReturnType<typeof createProbeOctokit>>;
}): Promise<boolean> {
  const { spawnOk, label, runStartedAt, cronName, octokit } = args;
  if (!spawnOk) return false;

  let issueCreated: boolean;
  try {
    issueCreated = await verifyScheduledIssueCreated({
      label,
      sinceIso: runStartedAt,
      octokit,
    });
  } catch (err) {
    reportSilentFallback(err, {
      feature: cronName,
      op: "verify-output-failed",
      message: `Could not verify ${label} output (heartbeat left at spawn result)`,
      extra: { fn: cronName, label, runStartedAt },
    });
    // Inconclusive — do not downgrade a possibly-successful run.
    return true;
  }

  if (!issueCreated) {
    reportSilentFallback(
      new Error(
        `${cronName} exited 0 but created no "${label}" issue in the run window (since ${runStartedAt})`,
      ),
      {
        feature: cronName,
        op: "scheduled-output-missing",
        message: "Scheduled producer exited cleanly but produced no output issue",
        extra: { fn: cronName, label, runStartedAt },
      },
    );
  }
  return issueCreated;
}
