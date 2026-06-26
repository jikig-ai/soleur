// The single accessor seam for the Workstream board (the "same shared fn" rule):
// BOTH the HTTP route (app/api/workstream/issues) AND the agent read tool
// (server/workstream/workstream-tools) import this directly — the tool never
// self-calls the route.
//
// v2 re-backs the board on the active workspace's REAL connected GitHub repo via
// the ADR-044 resolution chain (membership-checked installation token, NEVER a
// PAT, never request input). The fabricated seed is GONE — no data may ever be
// shown that the user's own repo didn't produce.
//
// Empty-vs-throw (load-bearing — CPO / observability):
//   - The throw-guarantee is scoped to the GitHub LIST call only: once we have a
//     repo + installation, a listRepoIssues failure (404/403/5xx) THROWS so the
//     route → 502 and the tool → isError. A list failure must NEVER masquerade
//     as "no issues."
//   - return [] (honest empty board) when no repo is connected OR no installation
//     id resolves (lost grant — mirrored to Sentry here). NOTE: the upstream
//     resolvers (getCurrentRepoUrl, resolveInstallationId) FAIL-OPEN to null on
//     transient DB/auth errors too — those also collapse to [] here, but they
//     mirror to Sentry UPSTREAM, so a degraded resolve is still observable.

import {
  githubIssueToWorkstreamIssue,
  type WorkstreamIssue,
} from "@/lib/workstream";
import { getCurrentRepoUrl } from "@/server/current-repo-url";
import { parseConnectedRepo } from "@/server/github-repo-parse";
import { resolveInstallationId } from "@/server/resolve-installation-id";
import { resolveEffectiveInstallationId } from "@/server/cc-effective-installation";
import { listRepoIssues } from "@/server/github-read-tools";
import { reportSilentFallback } from "@/server/observability";

/**
 * Read the active workspace's connected-repo issues, mapped to the board model.
 * owner/repo + installation derive ONLY from the server-resolved active
 * workspace (ADR-044) — never request input — so there is no cross-tenant read.
 */
export async function getWorkstreamIssues(
  userId: string,
): Promise<WorkstreamIssue[]> {
  const repoUrl = await getCurrentRepoUrl(userId);
  const parsed = parseConnectedRepo(repoUrl);
  if (!parsed) return []; // honest empty: no repo connected

  const stored = await resolveInstallationId(userId);
  const installationId = await resolveEffectiveInstallationId({
    userId,
    installationId: stored,
    repoUrl,
  });
  if (installationId === null) {
    // repoUrl present but no installation resolvable (revoked/lost grant) — this
    // is a degraded read, not "no issues": mirror to Sentry, then empty board
    // (cq-silent-fallback-must-mirror-to-sentry).
    reportSilentFallback(new Error("no installation for connected repo"), {
      feature: "workstream",
      op: "no-installation",
      extra: { userId },
    });
    return [];
  }

  // Throws on any GitHub API failure (404/403/5xx) — caller surfaces 502/isError.
  const raw = await listRepoIssues(installationId, parsed.owner, parsed.repo);
  return raw.map(githubIssueToWorkstreamIssue);
}
