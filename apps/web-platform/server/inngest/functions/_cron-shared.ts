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
