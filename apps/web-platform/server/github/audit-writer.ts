// PR-H+1 (#4098) — per-Octokit-call audit writer for audit_github_token_use.
//
// THREAT MODEL: GDPR Art. 30 PA-16 disclosure ("every GitHub App
// installation-token use by Soleur is recorded as Art. 5(2) accountability
// evidence") must be load-bearing in production, not aspirational. PR-H
// shipped the table + RPC + Art. 17 cascade; PR-H+1 wires the writer so
// the ledger actually populates as Octokit calls fire.
//
// INVARIANTS:
//   1. Writer is non-blocking — a Supabase outage or RPC error must NOT
//      block the upstream Octokit call's success path (AC8). Failures
//      mirror to Sentry via captureException with surface=github-audit-writer
//      tag (cq-silent-fallback-must-mirror-to-sentry).
//   2. Single write boundary — every Octokit call site routes through
//      this helper (hr-write-boundary-sentinel-sweep-all-write-sites).
//      The factory in server/github/app-client.ts attaches the
//      octokit.hook.after / hook.error wrappers; no other call site
//      may write directly to audit_github_token_use.
//   3. Service-role only — record_github_token_use is
//      REVOKE FROM PUBLIC, anon, authenticated; GRANT TO service_role
//      (migration 052). Cookie-scoped callers return 403.

import { createServiceClient } from "@/lib/supabase/service";
import * as Sentry from "@sentry/nextjs";

export interface GithubApiCallRecord {
  founderId: string;
  installationId: number;
  // owner/repo if the URL identifies a repository; null for app-level
  // endpoints (/app, /installation/repositories, /user) which are not
  // repo-scoped.
  repoFullName: string | null;
  // Pathname only — query strings and origin stripped. The audit row
  // shape encodes "which API surface was touched", not "with what
  // parameters" (parameters can contain PII; the dedup-safe shape is
  // path-only).
  endpoint: string;
  responseStatus: number;
}

const REPO_PATH_RE = /^\/repos\/([^/]+)\/([^/]+)(?:\/|$)/;

/**
 * Extract owner/repo from a GitHub API path or absolute URL.
 *
 * Returns null for app-level endpoints (e.g., `/app`, `/installation/repositories`)
 * — these are legitimately repo-less and the audit row's
 * `repo_full_name` column is nullable per migration 052.
 */
export function extractRepoFullName(urlOrPath: string): string | null {
  if (!urlOrPath) return null;
  let pathname: string;
  try {
    if (urlOrPath.startsWith("http://") || urlOrPath.startsWith("https://")) {
      pathname = new URL(urlOrPath).pathname;
    } else {
      pathname = urlOrPath;
    }
  } catch {
    return null;
  }
  const match = REPO_PATH_RE.exec(pathname);
  if (!match) return null;
  const [, owner, repo] = match;
  if (!owner || !repo) return null;
  return `${owner}/${repo}`;
}

/**
 * Normalise an Octokit request URL/path to the pathname only.
 *
 * Query strings are dropped because (a) audit-row CHECK constraint
 * caps `endpoint` at 256 chars (migration 052) and a `per_page=100`
 * suffix would consume that budget for no audit-shape gain, and (b)
 * query parameters can carry PII (e.g., a `q=...` GitHub search query
 * with a customer email).
 */
export function extractEndpoint(urlOrPath: string): string {
  if (!urlOrPath) return "";
  try {
    const base = "https://api.github.com";
    const u =
      urlOrPath.startsWith("http://") || urlOrPath.startsWith("https://")
        ? new URL(urlOrPath)
        : new URL(urlOrPath, base);
    return u.pathname;
  } catch {
    return urlOrPath;
  }
}

/**
 * Records a single Octokit response in `audit_github_token_use`.
 *
 * Called from server/github/app-client.ts's `octokit.hook.after` /
 * `octokit.hook.error` handlers. The hook fires once per Octokit
 * request regardless of retry.
 *
 * Failures are non-blocking per AC8. The agent action's success is the
 * load-bearing signal; a single audit row miss must not wedge the
 * upstream operation.
 */
export async function recordGithubApiCall(
  args: GithubApiCallRecord,
): Promise<void> {
  try {
    const client = createServiceClient();
    const { error } = await client.rpc("record_github_token_use", {
      p_founder_id: args.founderId,
      p_installation_id: args.installationId,
      p_repo_full_name: args.repoFullName,
      p_endpoint: args.endpoint,
      p_response_status: args.responseStatus,
    });
    if (error) {
      throw new Error(error.message ?? "record_github_token_use RPC error");
    }
  } catch (err) {
    Sentry.captureException(err, {
      tags: {
        surface: "github-audit-writer",
        endpoint: args.endpoint,
      },
    });
  }
}
