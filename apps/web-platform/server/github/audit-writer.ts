// PR-H+1 (#4098) — per-Octokit-call audit writer for audit_github_token_use.
//
// THREAT MODEL: GDPR Art. 30 PA-17 disclosure ("every GitHub App
// installation-token use by Soleur is recorded as Art. 5(2) accountability
// evidence") must be load-bearing in production, not aspirational. PR-H
// shipped the table + RPC + Art. 17 cascade; PR-H+1 wires the writer so
// the ledger actually populates as Octokit calls fire.
//
// INVARIANTS:
//   1. Writer is non-blocking — a Supabase outage or RPC error must NOT
//      block the upstream Octokit call's success path (AC8). Failures
//      mirror to Sentry via reportSilentFallback (feature=github-audit)
//      per cq-silent-fallback-must-mirror-to-sentry. reportSilentFallback
//      internally guards against Sentry SDK init drift (#3045 precedent)
//      so a Sentry-throws-too escape path cannot wedge an Octokit hook.
//   2. Single write boundary — every Octokit call site routes through
//      this helper (hr-write-boundary-sentinel-sweep-all-write-sites).
//      The factory in server/github/app-client.ts attaches the
//      octokit.hook.after / hook.error wrappers; no other call site
//      may write directly to audit_github_token_use.
//   3. Service-role only — record_github_token_use is
//      REVOKE FROM PUBLIC, anon, authenticated; GRANT TO service_role
//      (migration 052). Cookie-scoped callers return 403.

import { getServiceClient } from "@/lib/supabase/service";
import { reportSilentFallback } from "@/server/observability";

export interface GithubApiCallRecord {
  founderId: string;
  installationId: number;
  // owner/repo if the URL identifies a repository; null for app-level
  // endpoints (/app, /installation/repositories, /user) which are not
  // repo-scoped.
  repoFullName: string | null;
  // Pathname only — query strings and origin stripped. Falls back to
  // "<unknown>" sentinel when the upstream hook delivers an empty URL
  // (audit_github_token_use.endpoint has length-≥-1 + length-≤-256
  // CHECK constraints — see migration 052).
  endpoint: string;
  // HTTP response status. NULL when the call errored before a status
  // could be determined (network reset, abort, DNS). The DB CHECK
  // constraint allows NULL OR 100-599 — a synthetic 0 would violate
  // CHECK and cause silent row drop.
  responseStatus: number | null;
}

const REPO_PATH_RE = /^\/repos\/([^/]+)\/([^/]+)(?:\/|$)/;
const ENDPOINT_MAX_LEN = 256;

/**
 * Extract owner/repo from a GitHub API path or absolute URL.
 *
 * Returns null for app-level endpoints (e.g., `/app`, `/installation/repositories`)
 * — these are legitimately repo-less and the audit row's
 * `repo_full_name` column is nullable per migration 052.
 *
 * Always parses via `URL` so query-string fragments cannot bleed into
 * the captured groups (e.g., `/repos/o/r?q=x` produces `o/r`, not
 * `o/r?q=x`).
 */
export function extractRepoFullName(urlOrPath: string): string | null {
  if (!urlOrPath) return null;
  let pathname: string;
  try {
    const base = "https://api.github.com";
    const u =
      urlOrPath.startsWith("http://") || urlOrPath.startsWith("https://")
        ? new URL(urlOrPath)
        : new URL(urlOrPath, base);
    pathname = u.pathname;
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
 * Normalise an Octokit request URL/path to the pathname only, capped at
 * the audit-row CHECK constraint (256 chars).
 *
 * - Query strings are dropped — they can carry PII (e.g., a `q=...`
 *   GitHub search query with a customer email) and the column's
 *   256-char ceiling has no headroom to spend on parameters.
 * - Falsy/empty input returns the `"<unknown>"` sentinel so the row
 *   still satisfies the `length(endpoint) >= 1` CHECK; Octokit hooks
 *   on malformed requests can deliver empty URLs.
 * - The capped output guards against pathological deep paths that
 *   would exceed the column's 256-char ceiling.
 */
export function extractEndpoint(urlOrPath: string): string {
  if (!urlOrPath) return "<unknown>";
  let pathname: string;
  try {
    const base = "https://api.github.com";
    const u =
      urlOrPath.startsWith("http://") || urlOrPath.startsWith("https://")
        ? new URL(urlOrPath)
        : new URL(urlOrPath, base);
    pathname = u.pathname;
  } catch {
    pathname = urlOrPath;
  }
  return pathname.slice(0, ENDPOINT_MAX_LEN);
}

const NUMERIC_SEGMENT_RE = /\/\d+(?=\/|$)/g;
const REPO_OWNER_REPO_RE = /^\/repos\/[^/]+\/[^/]+/;

/**
 * Templatize a path for Sentry tag use — replaces numeric segments and
 * owner/repo with placeholders so cardinality stays bounded (Sentry
 * tag-value indexing degrades past ~10k unique values per tag).
 *
 * Example: `/repos/acme/widgets/issues/4100/comments` →
 *          `/repos/:owner/:repo/issues/:n/comments`
 *
 * The raw pathname is still passed as `extra.endpoint` for full-fidelity
 * forensics; only the indexed tag is templated.
 */
function templatizeEndpointForTag(endpoint: string): string {
  return endpoint
    .replace(REPO_OWNER_REPO_RE, "/repos/:owner/:repo")
    .replace(NUMERIC_SEGMENT_RE, "/:n");
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
 * upstream operation. `reportSilentFallback` mirrors all error paths to
 * Sentry with feature=github-audit and op=record, AND guards against
 * Sentry SDK init drift so a `Sentry.captureException` throw cannot
 * escape this function (would otherwise wedge the Octokit hook).
 */
export async function recordGithubApiCall(
  args: GithubApiCallRecord,
): Promise<void> {
  try {
    const client = getServiceClient();
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
    reportSilentFallback(err, {
      feature: "github-audit",
      op: "record",
      extra: {
        installationId: args.installationId,
        repoFullName: args.repoFullName,
        endpoint: args.endpoint,
        endpointTemplate: templatizeEndpointForTag(args.endpoint),
        responseStatus: args.responseStatus,
      },
    });
  }
}
