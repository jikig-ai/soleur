import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

// Server-page test: the Settings page reads the anthropic_oauth row with a
// second query (provider, is_valid, updated_at) and derives hasOauthToken /
// oauthInEffect / oauthTokenSavedAt. "In effect" must use the SAME predicate
// as the lease (server/cc-oauth-flag.ts), never a re-implemented env check.

const USER_ID = "user-1";

type Row = { provider: string; is_valid: boolean; updated_at: string };
const state: {
  anthropic: Row | null;
  oauth: Row | null;
  oauthError: { message: string; code: string } | null;
} = {
  anthropic: null,
  oauth: null,
  oauthError: null,
};
const sentry = vi.hoisted(() => ({
  captureException: vi.fn(),
  captureMessage: vi.fn(),
  addBreadcrumb: vi.fn(),
}));
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
    // An errored oauth read still carries a matching row: the page's
    // `oauthError ? null : oauthData` guard is the only thing that hides it.
    if (call.filters.provider === "anthropic_oauth" && state.oauthError) {
      return Promise.resolve({ data: row, error: state.oauthError });
    }
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
// The REAL observability module runs (so the debounce is exercised end to end);
// only its sinks are mocked.
vi.mock("@sentry/nextjs", () => sentry);
vi.mock("@/server/logger", () => ({
  default: { error: vi.fn(), warn: vi.fn(), info: vi.fn() },
}));
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
import { __resetMirrorDebounceForTests } from "@/server/observability";

const sentryEvents = () => [
  ...sentry.captureException.mock.calls,
  ...sentry.captureMessage.mock.calls,
];

async function pageProps() {
  const el = (await SettingsPage()) as { props: Record<string, unknown> };
  return el.props;
}

let saved: string | undefined;
beforeEach(() => {
  saved = process.env.CC_OAUTH_ENABLED;
  state.anthropic = null;
  state.oauth = null;
  state.oauthError = null;
  sentry.captureException.mockReset();
  sentry.captureMessage.mockReset();
  sentry.addBreadcrumb.mockReset();
  __resetMirrorDebounceForTests();
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

  it("an oauth-query DB error is reported and renders the neutral state (no token UI)", async () => {
    process.env.CC_OAUTH_ENABLED = "1";
    state.oauthError = { message: "connection reset", code: "08006" };
    // Even if a row would have matched, an errored read must not guess one.
    state.oauth = { provider: "anthropic_oauth", is_valid: true, updated_at: "2026-10-28T10:00:00Z" };
    const p = await pageProps();
    expect(p.hasOauthToken).toBe(false);
    expect(p.oauthInEffect).toBe(false);
    expect(p.oauthTokenSavedAt).toBeNull();
    expect(sentryEvents()).toHaveLength(1);
    const [, opts] = sentry.captureMessage.mock.calls[0] as [
      string,
      { tags: Record<string, string>; extra: Record<string, unknown> },
    ];
    expect(opts.tags).toMatchObject({ feature: "settings", op: "read-oauth-credential" });
    // userId is pseudonymised at the emit boundary, never raw.
    expect(opts.extra).not.toHaveProperty("userId");
    expect(JSON.stringify(opts.extra)).not.toContain(`"${USER_ID}"`);
  });

  it("the read-error report is debounced: repeated renders while the read keeps failing fire ONE event", async () => {
    process.env.CC_OAUTH_ENABLED = "1";
    state.oauthError = { message: "connection reset", code: "08006" };
    await pageProps();
    await pageProps();
    await pageProps();
    expect(sentryEvents()).toHaveLength(1);
  });

  it("no oauth error: nothing is reported", async () => {
    process.env.CC_OAUTH_ENABLED = "1";
    await pageProps();
    expect(sentryEvents()).toHaveLength(0);
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
