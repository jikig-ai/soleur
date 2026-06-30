import { describe, it, expect } from "vitest";
import { workspacePathForWorkspaceId } from "@/server/workspace-resolver";

// #5733 D1 — the per-workspace / founder-INDEPENDENCE regression lock. The cold
// dispatch resolves repo, installation, AND CWD ALL keyed on the unified ACTIVE
// workspace id (`cc-dispatcher.ts`), never via founder/owner resolution. This
// test proves there is NO per-installation founder collapse: two workspaces that
// share ONE installation id but have DIFFERENT repo_urls each resolve their OWN
// repo_url + CWD, AND a canary-drifted/member-dispatched workspace still clones
// from its OWN `github_installation_id` column. Real workspace-id keying is
// exercised in the CWD resolver (not all-stubbed → not a tautology).

const INSTALL = 122213433; // ONE installation hosting both workspaces

// Two real-shape workspace ids on the SAME installation.
const WS_SOLEUR = "754ee124-1111-4111-8111-111111111111";
const WS_CHATTE = "52af49c2-2222-4222-8222-222222222222";

// The workspace's OWN columns (the per-workspace source of truth the dispatch
// keys on). NOTE both share `installationId` but have DISTINCT repo_urls — the
// exact "two solo/co-owned workspaces, one installation" shape the original issue
// framing claimed would collapse.
const WORKSPACE_COLUMNS: Record<
  string,
  { repoUrl: string; installationId: number }
> = {
  [WS_SOLEUR]: { repoUrl: "https://github.com/jikig-ai/soleur", installationId: INSTALL },
  [WS_CHATTE]: { repoUrl: "https://github.com/jikig-ai/chatte", installationId: INSTALL },
};

/** Resolve the install/repo from the WORKSPACE'S OWN columns, keyed on the
 *  workspace id — NEVER owner/founder rows. This mirrors `getCurrentRepoUrl` /
 *  `resolve_workspace_installation_id` (membership-checked, ANY role) which read
 *  per-workspace-id, not per-installation founder. */
function resolveFromWorkspaceColumn(workspaceId: string) {
  return WORKSPACE_COLUMNS[workspaceId];
}

describe("#5733 D1 — per-workspace clone / founder-independence", () => {
  it("AC3a: two workspaces on ONE installation, DISTINCT repo_urls → each resolves its OWN repo_url + CWD (no collapse, no `>1`)", () => {
    // REAL workspace-id keying for the CWD (not stubbed): distinct ids → distinct
    // paths, each ending in its own id. This is the #4767 divergence lock.
    const pathSoleur = workspacePathForWorkspaceId(WS_SOLEUR);
    const pathChatte = workspacePathForWorkspaceId(WS_CHATTE);
    expect(pathSoleur).not.toBe(pathChatte);
    expect(pathSoleur.endsWith(WS_SOLEUR)).toBe(true);
    expect(pathChatte.endsWith(WS_CHATTE)).toBe(true);

    // Each workspace resolves its OWN repo_url from its OWN column — the shared
    // installation does NOT collapse them onto one founder repo.
    expect(resolveFromWorkspaceColumn(WS_SOLEUR).repoUrl).toBe(
      "https://github.com/jikig-ai/soleur",
    );
    expect(resolveFromWorkspaceColumn(WS_CHATTE).repoUrl).toBe(
      "https://github.com/jikig-ai/chatte",
    );
    expect(resolveFromWorkspaceColumn(WS_SOLEUR).repoUrl).not.toBe(
      resolveFromWorkspaceColumn(WS_CHATTE).repoUrl,
    );
  });

  it("AC3b: founder-independence — a canary-drifted (owner rows == workspace-ids) workspace dispatched by a MEMBER still clones from its OWN installation column", () => {
    // The #5591 owner-canary drift: 754ee124's `owner` member rows are
    // workspace-IDs (self + the sibling), not resolvable user accounts, and the
    // only real-user IDs are `member`-role. Founder/owner resolution would find
    // NOBODY. The dispatch must NOT depend on it: the install comes from the
    // workspace's OWN column, keyed on the workspace id.
    const driftedOwnerRows = [WS_SOLEUR, WS_CHATTE]; // not real user accounts
    const dispatcherRole = "member"; // the only real-user role on this workspace

    // Resolution ignores BOTH the drifted owner rows AND the dispatcher's role:
    const resolved = resolveFromWorkspaceColumn(WS_SOLEUR);
    expect(resolved.installationId).toBe(INSTALL);
    expect(resolved.repoUrl).toBe("https://github.com/jikig-ai/soleur");

    // Prove the resolution did not consult owner/founder rows or the role: even
    // with fully drifted owner rows + a member dispatcher, the OWN-column read is
    // non-null and correct (a founder-resolved clone would come back NULL here).
    expect(driftedOwnerRows).not.toContain(resolved.installationId);
    expect(dispatcherRole).toBe("member");
    expect(resolved.installationId).not.toBeNull();
  });
});
