import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

// Server-page test: the Settings page reads the anthropic_oauth row with a
// second query (provider, is_valid, updated_at) and derives hasOauthToken /
// oauthInEffect / oauthTokenSavedAt. "In effect" must use the SAME predicate
// as the lease (server/cc-oauth-flag.ts), never a re-implemented env check.

const USER_ID = "user-1";

type Row = { provider: string; is_valid: boolean; updated_at: string };
const state: { anthropic: Row | null; oauth: Row | null } = {
  anthropic: null,
  oauth: null,
};
const apiKeysCalls: Array<{ select: string; filters: Record<string, unknown>; terminal: string }> = [];

function apiKeysChain() {
  const call = { select: "", filters: {} as Record<string, unknown>, terminal: "" };
  const chain: Record<string, unknown> = {};
  chain.select = (cols: string) => {
    call.select = cols;
    return chain;
  };
  chain.eq = (col: string, val: unknown) => {
    call.filters[col] = val;
    return chain;
  };
  chain.limit = () => chain;
  const finish = (terminal: string) => {
    call.terminal = terminal;
    apiKeysCalls.push(call);
    const row =
      call.filters.provider === "anthropic_oauth" ? state.oauth : state.anthropic;
    return Promise.resolve({ data: row, error: null });
  };
  chain.single = () => finish("single");
  chain.maybeSingle = () => finish("maybeSingle");
  return chain;
}

vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({
    auth: { getUser: async () => ({ data: { user: { id: USER_ID, email: "a@b.com" } } }) },
  }),
  createServiceClient: () => ({
    from: (table: string) => {
      if (table === "api_keys") return apiKeysChain();
      return {
        select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: null }) }) }),
      };
    },
  }),
}));
vi.mock("next/navigation", () => ({ redirect: vi.fn() }));
vi.mock("@/server/workspace-resolver", () => ({
  resolveActiveWorkspace: async () => ({ ok: false }),
}));
vi.mock("@/server/workspace-identity-resolver", () => ({
  resolveWorkspaceIdentityForSettings: async () => null,
}));
vi.mock("@/lib/repo-status", () => ({
  resolveNeedsReconnect: async () => false,
}));
vi.mock("@/components/settings/settings-content", () => ({
  SettingsContent: () => null,
}));

import SettingsPage from "@/app/(dashboard)/dashboard/settings/page";

async function pageProps() {
  const el = (await SettingsPage()) as { props: Record<string, unknown> };
  return el.props;
}

let saved: string | undefined;
beforeEach(() => {
  saved = process.env.CC_OAUTH_ENABLED;
  state.anthropic = null;
  state.oauth = null;
  apiKeysCalls.length = 0;
});
afterEach(() => {
  if (saved === undefined) delete process.env.CC_OAUTH_ENABLED;
  else process.env.CC_OAUTH_ENABLED = saved;
});

describe("settings/page.tsx — anthropic_oauth row (#11524)", () => {
  it("queries the oauth row with provider, is_valid, updated_at via maybeSingle", async () => {
    process.env.CC_OAUTH_ENABLED = "1";
    await pageProps();
    const oauthCall = apiKeysCalls.find((c) => c.filters.provider === "anthropic_oauth");
    expect(oauthCall).toBeDefined();
    expect(oauthCall!.select).toBe("provider, is_valid, updated_at");
    expect(oauthCall!.filters.user_id).toBe(USER_ID);
    expect(oauthCall!.terminal).toBe("maybeSingle");
  });

  it("no row: hasOauthToken false, not in effect", async () => {
    process.env.CC_OAUTH_ENABLED = "1";
    const p = await pageProps();
    expect(p.hasOauthToken).toBe(false);
    expect(p.oauthInEffect).toBe(false);
    expect(p.oauthTokenSavedAt).toBeNull();
  });

  it("row + valid + kill-switch on: in effect, savedAt threaded", async () => {
    process.env.CC_OAUTH_ENABLED = "true";
    state.oauth = { provider: "anthropic_oauth", is_valid: true, updated_at: "2026-10-28T10:00:00Z" };
    const p = await pageProps();
    expect(p.hasOauthToken).toBe(true);
    expect(p.oauthInEffect).toBe(true);
    expect(p.oauthTokenSavedAt).toBe("2026-10-28T10:00:00Z");
  });

  it("row + valid + kill-switch OFF: stored but NOT in effect (still removable)", async () => {
    delete process.env.CC_OAUTH_ENABLED;
    state.oauth = { provider: "anthropic_oauth", is_valid: true, updated_at: "2026-10-28T10:00:00Z" };
    const p = await pageProps();
    expect(p.hasOauthToken).toBe(true);
    expect(p.oauthInEffect).toBe(false);
  });

  it("row + invalid + kill-switch on: stored but NOT in effect", async () => {
    process.env.CC_OAUTH_ENABLED = "1";
    state.oauth = { provider: "anthropic_oauth", is_valid: false, updated_at: "2026-10-28T10:00:00Z" };
    const p = await pageProps();
    expect(p.hasOauthToken).toBe(true);
    expect(p.oauthInEffect).toBe(false);
  });

  it("hasApiKey keeps its meaning (anthropic row, valid), independent of the oauth row", async () => {
    process.env.CC_OAUTH_ENABLED = "1";
    state.oauth = { provider: "anthropic_oauth", is_valid: true, updated_at: "2026-10-28T10:00:00Z" };
    const p = await pageProps();
    expect(p.hasApiKey).toBe(false);
    state.anthropic = { provider: "anthropic", is_valid: true, updated_at: "2026-10-27T10:00:00Z" };
    const p2 = await pageProps();
    expect(p2.hasApiKey).toBe(true);
    expect(p2.apiKeyProvider).toBe("anthropic");
  });
});

describe("server/cc-oauth-flag.ts — shared predicate", () => {
  it("is the exact lease predicate ('1' | 'true')", async () => {
    const { isCcOauthEnabled } = await import("@/server/cc-oauth-flag");
    for (const [v, want] of [
      ["1", true],
      ["true", true],
      ["0", false],
      ["TRUE", false],
      ["", false],
      [undefined, false],
    ] as const) {
      if (v === undefined) delete process.env.CC_OAUTH_ENABLED;
      else process.env.CC_OAUTH_ENABLED = v;
      expect(isCcOauthEnabled()).toBe(want);
    }
  });

  it("byok-lease.ts and settings/page.tsx import it instead of redefining it", async () => {
    const { readFileSync } = await import("node:fs");
    const lease = readFileSync("server/byok-lease.ts", "utf8");
    const page = readFileSync("app/(dashboard)/dashboard/settings/page.tsx", "utf8");
    expect(lease).toMatch(/from "\.\/cc-oauth-flag"/);
    expect(lease).not.toMatch(/function isCcOauthEnabled/);
    expect(page).toMatch(/from "@\/server\/cc-oauth-flag"/);
  });
});
