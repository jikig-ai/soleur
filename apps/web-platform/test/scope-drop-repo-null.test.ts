import { describe, it, expect } from "vitest";
import { shouldDropForScope } from "@/hooks/use-conversations";
import type { Conversation } from "@/lib/types";

// Direct unit pin for the disconnected-user scope invariant
// (perf-dashboard-section-load-latency review round 2, P2 residual).
//
// The fetch path's contract for a repo-less user is an EMPTY rail — the hook
// early-returns `setConversations([])` when activeRepo.repoUrl is null. The
// realtime shared-channel check must mirror that: a repo-less
// `visibility:"workspace"` row (conv.repo_url === null === opts.repoUrl, same
// workspace_id) would otherwise LAND and diverge fetch-vs-realtime.
const baseConv = {
  id: "c1",
  user_id: "other-user",
  workspace_id: "ws-1",
  repo_url: null,
  visibility: "workspace",
  archived_at: null,
} as unknown as Conversation;

const opts = {
  workspaceId: "ws-1",
  channel: "shared" as const,
  archiveFilter: "active" as const,
};

describe("shouldDropForScope — repo-less (disconnected) user", () => {
  it("drops a repo-less workspace-visibility row that would otherwise land", () => {
    // The exact divergence the fix closed: matching workspace_id + matching
    // (null) repo_url + workspace visibility passes EVERY other clause.
    expect(
      shouldDropForScope(baseConv, { ...opts, repoUrl: null }),
    ).toBe(true);
  });

  it("drops an own-channel row for a disconnected user too (fetch invariant is an empty rail)", () => {
    expect(
      shouldDropForScope(
        { ...baseConv, visibility: "private" },
        { ...opts, channel: "own", repoUrl: null },
      ),
    ).toBe(true);
  });

  it("does not regress the connected case (repoUrl set, matching row lands)", () => {
    expect(
      shouldDropForScope(
        { ...baseConv, repo_url: "https://github.com/acme/repo" },
        { ...opts, repoUrl: "https://github.com/acme/repo" },
      ),
    ).toBe(false);
  });
});
