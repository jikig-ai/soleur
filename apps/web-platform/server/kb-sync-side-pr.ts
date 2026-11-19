// ---------------------------------------------------------------------------
// KB sync side PR: the never-auto-merged pull request `soleur/kb-sync` -> `D` in the user's own repo (#5426), and the D17
// table both halves of the KB sync key on (#12718, ruling D28(3)).
//
// The push side (server/kb-sync-publish.ts) re-checks the PR when the side branch already carries HEAD's KB; the pull side
// (server/kb-sync-pull.ts) reads the same table before adopting a side tip. A leaf: it imports neither kb-sync-publish.ts
// nor push-branch.ts. github-app is imported dynamically (sibling tests mock git-auth but not github-app).
// ---------------------------------------------------------------------------

import { KB_SYNC_SIDE_BRANCH } from "./kb-sync-remote";

const KB_SYNC_PR_TITLE = "Soleur: knowledge-base sync";

function kbSyncPrBody(defaultBranch: string): string {
  return [
    "Soleur keeps your knowledge-base in sync after every session.",
    "",
    `Your default branch (\`${defaultBranch}\`) is protected, so these`,
    `knowledge-base updates were routed to the \`${KB_SYNC_SIDE_BRANCH}\` branch`,
    "instead of being pushed directly.",
    "",
    "Merge this PR whenever you're ready — Soleur will never auto-merge it.",
    "Future sessions accrete onto this same branch and PR.",
  ].join("\n");
}

/** Find or create the never-auto-merged PR `soleur/kb-sync` -> `D` in the user's own repo. */
export async function ensureKbSyncPr(installationId: number, owner: string, repo: string, D: string): Promise<string> {
  const { createPullRequest, findOpenPullRequest } = await import("./github-app");
  const existing = await findOpenPullRequest(installationId, owner, repo, KB_SYNC_SIDE_BRANCH, D);
  if (existing) return existing.htmlUrl;
  const pr = await createPullRequest(installationId, owner, repo, KB_SYNC_SIDE_BRANCH, D, KB_SYNC_PR_TITLE, kbSyncPrBody(D));
  return pr.htmlUrl;
}

/** Create the PR (no lookup): the caller has just read that none exists on `P`. Throws on failure. */
export async function createKbSyncPr(installationId: number, owner: string, repo: string, D: string): Promise<void> {
  const { createPullRequest } = await import("./github-app");
  await createPullRequest(installationId, owner, repo, KB_SYNC_SIDE_BRANCH, D, KB_SYNC_PR_TITLE, kbSyncPrBody(D));
}

/**
 * The D17 table over ONE GET (`state=all`) of the side branch's PRs:
 *   - `open`: an open PR (GitHub keeps its head on the branch tip, `P`);
 *   - `declined`: a closed, unmerged PR whose head is `P` (the Owner declined this exact content; never reopened);
 *   - `merged`: a merged PR whose head is `P`;
 *   - `none`: no PR on `P` (a re-clone after `pr_failed`, or a deleted PR);
 *   - `unknown`: the GET failed (any cause): fail toward no duplicate PR and no write (D23).
 */
export type SidePrState = "open" | "declined" | "merged" | "none" | "unknown";

export async function readSidePrState(installationId: number, owner: string, repo: string, D: string, P: string): Promise<SidePrState> {
  const { listPullRequestsForHead } = await import("./github-app");
  let prs: Awaited<ReturnType<typeof listPullRequestsForHead>>;
  try {
    prs = await listPullRequestsForHead(installationId, owner, repo, KB_SYNC_SIDE_BRANCH, D);
  } catch {
    return "unknown";
  }
  if (prs.some((pr) => pr.state === "open")) return "open";
  const onP = prs.filter((pr) => pr.headSha === P);
  if (onP.some((pr) => !pr.merged)) return "declined";
  return onP.length > 0 ? "merged" : "none";
}
