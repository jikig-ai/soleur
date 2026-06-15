// #5388: single source of truth for parsing a server-resolved github HTTPS
// repoUrl into a validated {owner, repo}. Shared by realSdkQueryFactory (which
// gates the edit_c4_diagram tool BUILD on owner+repo) and resolveC4Eligible
// (which gates ADVERTISING the c4 FQN to the unregistered-tool mirror predicate).
//
// Sharing this is load-bearing for the #5388 AC2 false-suppression guard: if the
// two sites parsed owner/repo with independently-drifting regexes, the dispatcher
// could advertise the c4 FQN for a repoUrl the factory rejected (or vice versa),
// re-introducing the spurious-mirror / suppressed-genuine-mirror bug. owner/repo
// are CLOSED OVER from the active workspace (ADR-044) — never tool input.

// Rejects any path-shaping characters before owner/repo are trusted (mirrors
// agent-runner.ts's GITHUB_NAME_RE / cc-effective-installation.ts's local copy).
const GITHUB_NAME_RE = /^[a-zA-Z0-9._-]+$/;

/**
 * Parse the connected repo's owner + repo from a server-resolved github HTTPS
 * URL. Returns `null` for a missing/malformed URL or a segment that fails the
 * name guard (degrade silently — not a security gate; callers treat `null` as
 * "no connected repo / c4 not eligible"). Pure function of its input.
 */
export function parseConnectedRepo(
  repoUrl: string | null,
): { owner: string; repo: string } | null {
  if (!repoUrl) return null;
  try {
    const parts = new URL(repoUrl).pathname.split("/").filter(Boolean);
    const owner = parts[0];
    const repo = parts[1]?.replace(/\.git$/, "");
    if (owner && repo && GITHUB_NAME_RE.test(owner) && GITHUB_NAME_RE.test(repo)) {
      return { owner, repo };
    }
  } catch {
    /* malformed repoUrl → no owner/repo */
  }
  return null;
}
