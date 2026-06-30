// #5485 — unit coverage for the two pure helpers the live-verify harness uses
// to (a) build the Playwright launch options (the runner-portability fix) and
// (b) shape the injected session cookies (characterization guard — the live
// repro proved this shape authenticates against prod; lock it so a refactor
// cannot regress the name/domain/attribute set the deployed @supabase/ssr
// middleware reads).
//
// All fixtures are synthesized — never a real token (cq-test-fixtures-synthesized-only).

import { describe, expect, it } from "vitest";

import {
  buildLaunchOptions,
  buildInjectedCookies,
  pollFreshConversationId,
} from "../../scripts/live-verify/run";

// Minimal supabase query-builder stub: every chained method returns the same
// object; the terminal `.limit()` resolves to `{ data }`, shifting one response
// per poll so a multi-iteration test can model "empty, then a row appears".
function makeSupabaseStub(responses: Array<Array<{ id: string }>>) {
  let call = 0;
  const chain = {
    from: () => chain,
    select: () => chain,
    eq: () => chain,
    gt: () => chain,
    order: () => chain,
    limit: () =>
      Promise.resolve({ data: responses[Math.min(call++, responses.length - 1)] ?? [] }),
  };
  return chain as never;
}

const VERIFIED = { __brand: "verified-live-verify-principal", uid: "u-1" } as never;
const UUID = "0123abcd-1234-5678-9abc-def012345678";

describe("buildLaunchOptions (runner-portability override)", () => {
  // Override branches carry the Wayland GPU-crash stabilization flags; the
  // no-override (CI) branch stays `{}` byte-identical. Rationale: see the
  // buildLaunchOptions comment in scripts/live-verify/run.ts.
  const WAYLAND_ARGS = ["--ozone-platform=x11", "--disable-gpu"];

  it("returns an empty object when no override is set (byte-identical to bundled chromium)", () => {
    const opts = buildLaunchOptions({});
    expect(opts).toEqual({});
    // Must NOT carry a `channel: undefined` key — that is not the same as omitting it.
    expect("channel" in opts).toBe(false);
    expect("executablePath" in opts).toBe(false);
    // CI path must NEVER carry the override-only stabilization args (ubuntu-latest
    // headless bundled chromium has no X server for --ozone-platform=x11).
    expect("args" in opts).toBe(false);
  });

  it("passes through a browser channel + Wayland-stabilization args when only the channel is set", () => {
    expect(buildLaunchOptions({ channel: "chrome" })).toEqual({
      channel: "chrome",
      args: WAYLAND_ARGS,
    });
  });

  it("passes through an executablePath + Wayland-stabilization args when only the path is set", () => {
    expect(buildLaunchOptions({ executablePath: "/usr/bin/google-chrome" })).toEqual({
      executablePath: "/usr/bin/google-chrome",
      args: WAYLAND_ARGS,
    });
  });

  it("prefers executablePath over channel when both are set (explicit binary wins) and still carries the args", () => {
    const opts = buildLaunchOptions({ channel: "chrome", executablePath: "/opt/chromium/chrome" });
    expect(opts).toEqual({ executablePath: "/opt/chromium/chrome", args: WAYLAND_ARGS });
    expect("channel" in opts).toBe(false);
  });

  it("treats empty-string overrides as unset (no override → no args)", () => {
    const opts = buildLaunchOptions({ channel: "", executablePath: "" });
    expect(opts).toEqual({});
    expect("args" in opts).toBe(false);
  });
});

describe("pollFreshConversationId (materialization signal, not URL nav)", () => {
  it("returns the conversation id when a fresh row is present", async () => {
    const supabase = makeSupabaseStub([[{ id: UUID }]]);
    const id = await pollFreshConversationId(supabase, VERIFIED, "2026-01-01T00:00:00Z", 5_000);
    expect(id).toBe(UUID);
  });

  it("returns null when no row materializes before the deadline", async () => {
    // timeoutMs 0 → the do/while runs exactly once, sees no row, and breaks
    // before any 1s sleep (keeps the unit test instant).
    const supabase = makeSupabaseStub([[]]);
    const id = await pollFreshConversationId(supabase, VERIFIED, "2026-01-01T00:00:00Z", 0);
    expect(id).toBeNull();
  });

  it("ignores a non-uuid id shape (never returns a malformed id)", async () => {
    const supabase = makeSupabaseStub([[{ id: "not-a-uuid" }]]);
    const id = await pollFreshConversationId(supabase, VERIFIED, "2026-01-01T00:00:00Z", 0);
    expect(id).toBeNull();
  });
});

describe("buildInjectedCookies (deployed-reader-matching shape)", () => {
  const APP_HOST = "app.soleur.ai";

  it("maps a single synthetic cookie to the deployed-reader shape", () => {
    const jar: Array<[string, { value: string }]> = [
      ["sb-api-auth-token", { value: "base64-SYNTHETIC_SESSION_VALUE" }],
    ];
    const out = buildInjectedCookies(jar, APP_HOST);
    expect(out).toEqual([
      {
        name: "sb-api-auth-token",
        value: "base64-SYNTHETIC_SESSION_VALUE",
        domain: APP_HOST,
        path: "/",
        // httpOnly MUST be false so the @supabase/ssr browser client can read
        // the session from document.cookie on client-guarded routes (#5485) —
        // httpOnly:true caused an intermittent /login bounce.
        httpOnly: false,
        secure: true,
        sameSite: "Lax",
      },
    ]);
  });

  it("injects a browser-readable (non-httpOnly) cookie so client hydration sees the session", () => {
    const jar: Array<[string, { value: string }]> = [
      ["sb-api-auth-token", { value: "base64-X" }],
    ];
    const [cookie] = buildInjectedCookies(jar, APP_HOST);
    expect(cookie.httpOnly).toBe(false);
  });

  it("scopes the cookie to the app host, never the supabase host", () => {
    const jar: Array<[string, { value: string }]> = [
      ["sb-api-auth-token", { value: "base64-X" }],
    ];
    const [cookie] = buildInjectedCookies(jar, APP_HOST);
    expect(cookie.domain).toBe(APP_HOST);
    expect(cookie.domain).not.toContain("supabase");
    expect(cookie.domain).not.toContain("api.soleur.ai");
  });

  it("re-injects every chunk 1:1 preserving chunk-suffix names", () => {
    const jar: Array<[string, { value: string }]> = [
      ["sb-api-auth-token.0", { value: "base64-PART0" }],
      ["sb-api-auth-token.1", { value: "PART1" }],
    ];
    const out = buildInjectedCookies(jar, APP_HOST);
    expect(out.map((c) => c.name)).toEqual(["sb-api-auth-token.0", "sb-api-auth-token.1"]);
    expect(out.every((c) => c.domain === APP_HOST && c.secure && c.sameSite === "Lax")).toBe(true);
  });

  it("returns an empty array for an empty jar (no fabricated cookies)", () => {
    expect(buildInjectedCookies([], APP_HOST)).toEqual([]);
  });
});
