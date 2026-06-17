// #5485 — unit coverage for the two pure helpers the live-verify harness uses
// to (a) build the Playwright launch options (the runner-portability fix) and
// (b) shape the injected session cookies (characterization guard — the live
// repro proved this shape authenticates against prod; lock it so a refactor
// cannot regress the name/domain/attribute set the deployed @supabase/ssr
// middleware reads).
//
// All fixtures are synthesized — never a real token (cq-test-fixtures-synthesized-only).

import { describe, expect, it } from "vitest";

import { buildLaunchOptions, buildInjectedCookies } from "../../scripts/live-verify/run";

describe("buildLaunchOptions (runner-portability override)", () => {
  it("returns an empty object when no override is set (byte-identical to bundled chromium)", () => {
    const opts = buildLaunchOptions({});
    expect(opts).toEqual({});
    // Must NOT carry a `channel: undefined` key — that is not the same as omitting it.
    expect("channel" in opts).toBe(false);
    expect("executablePath" in opts).toBe(false);
  });

  it("passes through a browser channel when only the channel is set", () => {
    expect(buildLaunchOptions({ channel: "chrome" })).toEqual({ channel: "chrome" });
  });

  it("passes through an executablePath when only the path is set", () => {
    expect(buildLaunchOptions({ executablePath: "/usr/bin/google-chrome" })).toEqual({
      executablePath: "/usr/bin/google-chrome",
    });
  });

  it("prefers executablePath over channel when both are set (explicit binary wins)", () => {
    const opts = buildLaunchOptions({ channel: "chrome", executablePath: "/opt/chromium/chrome" });
    expect(opts).toEqual({ executablePath: "/opt/chromium/chrome" });
    expect("channel" in opts).toBe(false);
  });

  it("treats empty-string overrides as unset", () => {
    expect(buildLaunchOptions({ channel: "", executablePath: "" })).toEqual({});
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
