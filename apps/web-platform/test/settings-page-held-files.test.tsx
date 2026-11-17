import { describe, it, expect, vi, beforeEach } from "vitest";

// Server-page test for the #12714 held-files notice (D29(3), D29(5), TW1-b's Settings half, AC18/AC19).
// - the count is read with the SERVICE client from `workspaces` in a SEPARATE select (D33(1)), keyed on the id the page's
//   single `resolveActiveWorkspace` call returned (never a fresh `current_workspace_id` read, never the user id); the
//   repo-status select is unchanged, so a missing migration 187 can never turn the card into "not connected";
// - the publish-route predicate is called with the VIEWER's user id and that same workspace id, and only when a notice
//   could render (ready repo, a count in 1..10000);
// - a predicate that throws reads as "unknown" (the transient copy), never as "unavailable".

const USER_ID = "user-viewer";
const WS_ACTIVE = "ws-active";

const state: {
  active: { ok: true; workspaceId: string } | { ok: false };
  ws: Record<string, unknown> | null;
  heldError: { message: string; code: string } | null;
} = { active: { ok: true, workspaceId: WS_ACTIVE }, ws: null, heldError: null };

const REPO_STATUS_SELECT = "repo_url, repo_status, repo_last_synced_at, github_installation_id";

const wsCalls: Array<{ select: string; eq: [string, unknown] | null }> = [];
const predicate = vi.hoisted(() => vi.fn());
const mirror = vi.hoisted(() => vi.fn());

vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({
    auth: { getUser: async () => ({ data: { user: { id: USER_ID, email: "a@b.com" } } }) },
  }),
  createServiceClient: () => ({
    from: (table: string) => {
      if (table === "workspaces") {
        const call = { select: "", eq: null as [string, unknown] | null };
        wsCalls.push(call);
        const chain = {
          select: (cols: string) => {
            call.select = cols;
            return chain;
          },
          eq: (col: string, val: unknown) => {
            call.eq = [col, val];
            return chain;
          },
          maybeSingle: async () => {
            if (!/kb_sync_held/.test(call.select)) {
              const { kb_sync_held_files: _held, ...repo } = state.ws ?? {};
              return { data: state.ws ? repo : null, error: null };
            }
            if (state.heldError) return { data: null, error: state.heldError };
            return { data: state.ws ? { kb_sync_held_files: state.ws.kb_sync_held_files ?? null } : null, error: null };
          },
        };
        return chain;
      }
      const chain: Record<string, unknown> = {};
      chain.select = () => chain;
      chain.eq = () => chain;
      chain.limit = () => chain;
      chain.single = async () => ({ data: null, error: null });
      chain.maybeSingle = async () => ({ data: null, error: null });
      return chain;
    },
  }),
}));
vi.mock("next/navigation", () => ({ redirect: vi.fn() }));
vi.mock("@/server/observability", () => ({ mirrorWithDebounce: mirror }));
vi.mock("@/server/workspace-resolver", () => ({
  resolveActiveWorkspace: async () => state.active,
}));
vi.mock("@/server/workspace-identity-resolver", () => ({
  resolveWorkspaceIdentityForSettings: async () => null,
}));
vi.mock("@/lib/repo-status", () => ({
  resolveNeedsReconnect: async () => false,
}));
vi.mock("@/server/cc-oauth-flag", () => ({ isCcOauthEnabled: () => false }));
vi.mock("@/server/cc-github-push", () => ({ isCcGithubPushRouteAvailable: predicate }));
vi.mock("@/components/settings/settings-content", () => ({
  SettingsContent: () => null,
}));

import SettingsPage from "@/app/(dashboard)/dashboard/settings/page";

async function pageProps() {
  const el = (await SettingsPage()) as { props: Record<string, unknown> };
  return el.props;
}

const READY = {
  repo_url: "https://github.com/acme-co/web-platform",
  repo_status: "ready",
  repo_last_synced_at: "2026-11-16T12:00:00Z",
  github_installation_id: 42,
};

beforeEach(() => {
  state.active = { ok: true, workspaceId: WS_ACTIVE };
  state.ws = null;
  state.heldError = null;
  wsCalls.length = 0;
  predicate.mockReset();
  mirror.mockReset();
});

describe("settings/page.tsx — held-files notice (#12714)", () => {
  it("reads kb_sync_held_files in a SEPARATE service select keyed on resolveActiveWorkspace's id (D33(1))", async () => {
    state.ws = { ...READY, kb_sync_held_files: 3 };
    predicate.mockResolvedValue("available");
    await pageProps();
    expect(wsCalls).toHaveLength(2);
    const repo = wsCalls.find((c) => !/kb_sync_held/.test(c.select));
    const held = wsCalls.find((c) => /kb_sync_held/.test(c.select));
    // The repo-status select is exactly what it was before #12714.
    expect(repo?.select).toBe(REPO_STATUS_SELECT);
    expect(repo?.eq).toEqual(["id", WS_ACTIVE]);
    expect(held?.select).toBe("kb_sync_held_files");
    expect(held?.eq).toEqual(["id", WS_ACTIVE]);
  });

  it("a failing held select (column missing) keeps the card connected, shows no notice, and mirrors once (D33(1))", async () => {
    state.ws = { ...READY, kb_sync_held_files: 3 };
    state.heldError = { message: 'column workspaces.kb_sync_held_files does not exist', code: "42703" };
    const p = await pageProps();
    expect(p.repoStatus).toBe("ready");
    expect(p.repoUrl).toBe(READY.repo_url);
    expect(p.repoLastSyncedAt).toBe(READY.repo_last_synced_at);
    expect(p.heldFiles).toBeNull();
    expect(predicate).not.toHaveBeenCalled();
    expect(mirror).toHaveBeenCalledTimes(1);
    expect(mirror.mock.calls[0][1]).toMatchObject({ feature: "settings", op: "read-held-files" });
  });

  it("calls the route predicate with the VIEWER's user id and the active workspace id, and threads the result", async () => {
    state.ws = { ...READY, kb_sync_held_files: 3 };
    predicate.mockResolvedValue("available");
    const p = await pageProps();
    expect(predicate).toHaveBeenCalledTimes(1);
    expect(predicate).toHaveBeenCalledWith({ userId: USER_ID, workspaceId: WS_ACTIVE });
    expect(p.heldFiles).toBe(3);
    expect(p.heldRoute).toBe("available");
  });

  it.each(["unavailable", "unknown"] as const)("threads a %s predicate result", async (r) => {
    state.ws = { ...READY, kb_sync_held_files: 2 };
    predicate.mockResolvedValue(r);
    expect((await pageProps()).heldRoute).toBe(r);
  });

  it("a predicate that throws reads as 'unknown' (transient copy, never the no-route sentence) and is mirrored", async () => {
    state.ws = { ...READY, kb_sync_held_files: 2 };
    predicate.mockRejectedValue(new Error("flag service down"));
    const p = await pageProps();
    expect(p.heldRoute).toBe("unknown");
    expect(p.heldFiles).toBe(2);
    expect(mirror).toHaveBeenCalledTimes(1);
    expect(mirror.mock.calls[0][1]).toMatchObject({ feature: "settings", op: "held-files-route-predicate" });
  });

  it("does not call the predicate when no notice can render (0, null, out of bounds, repo not ready)", async () => {
    for (const ws of [
      { ...READY, kb_sync_held_files: 0 },
      { ...READY, kb_sync_held_files: null },
      { ...READY, kb_sync_held_files: 10_001 },
      { ...READY, repo_status: "cloning", kb_sync_held_files: 3 },
      null,
    ]) {
      state.ws = ws;
      await pageProps();
    }
    expect(predicate).not.toHaveBeenCalled();
  });

  it("an unresolvable active workspace reads nothing and passes no count", async () => {
    state.active = { ok: false };
    const p = await pageProps();
    expect(wsCalls).toHaveLength(0);
    expect(p.heldFiles).toBeNull();
    expect(mirror).not.toHaveBeenCalled();
    expect(predicate).not.toHaveBeenCalled();
  });
});
