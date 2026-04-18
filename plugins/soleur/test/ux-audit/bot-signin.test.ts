import { describe, test, expect, beforeEach } from "bun:test";
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, rmSync } from "node:fs";
import { resolve } from "node:path";
import { tmpdir } from "node:os";
import {
  projectRef,
  cookieDomain,
} from "../../skills/ux-audit/scripts/bot-signin.ts";

const SCRIPT = resolve(
  import.meta.dir,
  "../../skills/ux-audit/scripts/bot-signin.ts",
);

const hasCreds = Boolean(
  process.env.SUPABASE_URL &&
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY &&
    process.env.UX_AUDIT_BOT_EMAIL &&
    process.env.UX_AUDIT_BOT_PASSWORD,
);

const describeIfCreds = hasCreds ? describe : describe.skip;

describeIfCreds("bot-signin", () => {
  const STATE_PATH = resolve(tmpdir(), "ux-audit-storage-state-test.json");

  beforeEach(() => {
    if (existsSync(STATE_PATH)) rmSync(STATE_PATH);
  });

  test("writes a Playwright-compatible storageState JSON to WORKSPACE/tmp/ux-audit/storage-state.json", () => {
    const r = spawnSync("bun", [SCRIPT], {
      encoding: "utf-8",
      env: { ...process.env, UX_AUDIT_STORAGE_STATE: STATE_PATH },
    });
    expect(r.status).toBe(0);
    expect(existsSync(STATE_PATH)).toBe(true);

    const raw = readFileSync(STATE_PATH, "utf-8");
    const state = JSON.parse(raw) as {
      cookies: Array<{ name: string; value: string; domain: string }>;
      origins?: Array<{ origin: string; localStorage: Array<{ name: string; value: string }> }>;
    };

    expect(Array.isArray(state.cookies)).toBe(true);
    const authCookie = state.cookies.find((c) => c.name.startsWith("sb-"));
    expect(authCookie).toBeDefined();
    expect(authCookie!.domain).toBeTruthy();

    // Assert the session contract @supabase/ssr consumes, not just "long string".
    // A future SDK version that prefixes the value (e.g. `base64-<b64>`) would
    // silently pass the length check but break downstream reads; JSON.parse
    // surfaces the drift loudly.
    const session = JSON.parse(authCookie!.value) as {
      access_token?: unknown;
      refresh_token?: unknown;
      expires_at?: unknown;
    };
    expect(typeof session.access_token).toBe("string");
    expect((session.access_token as string).length).toBeGreaterThan(20);
    expect(typeof session.refresh_token).toBe("string");
    expect(typeof session.expires_at).toBe("number");
  });

  test("fails fast on invalid password", () => {
    const r = spawnSync("bun", [SCRIPT], {
      encoding: "utf-8",
      env: {
        ...process.env,
        UX_AUDIT_BOT_PASSWORD: "wrong-password-does-not-exist",
        UX_AUDIT_STORAGE_STATE: STATE_PATH,
      },
    });
    expect(r.status).not.toBe(0);
    expect(r.stderr).toMatch(/invalid|credentials|password|401/i);
    expect(existsSync(STATE_PATH)).toBe(false);
  });
});

// Pure helpers — no creds gate. Exercised unconditionally so a regression in
// projectRef/cookieDomain surfaces even when Doppler secrets are absent.
describe("bot-signin pure helpers", () => {
  describe("projectRef", () => {
    test("extracts ref from supabase.co URL", () => {
      expect(projectRef("https://abc123.supabase.co")).toBe("abc123");
    });

    test("tolerates trailing path segments", () => {
      expect(projectRef("https://abc123.supabase.co/rest/v1/")).toBe("abc123");
    });

    test("throws on non-supabase host", () => {
      expect(() => projectRef("https://example.com")).toThrow(
        /Cannot derive project ref/,
      );
    });

    test("throws on localhost URL", () => {
      expect(() => projectRef("http://localhost:54321")).toThrow(
        /Cannot derive project ref/,
      );
    });

    test("throws on empty string", () => {
      expect(() => projectRef("")).toThrow(/Cannot derive project ref/);
    });
  });

  describe("cookieDomain", () => {
    test("returns hostname for apex domain", () => {
      expect(cookieDomain("https://soleur.ai/dashboard")).toBe("soleur.ai");
    });

    test("returns hostname for subdomain", () => {
      expect(cookieDomain("https://preview.soleur.ai")).toBe(
        "preview.soleur.ai",
      );
    });

    test("returns hostname for localhost", () => {
      expect(cookieDomain("http://localhost:3000")).toBe("localhost");
    });

    test("throws TypeError on non-URL input", () => {
      expect(() => cookieDomain("not-a-url")).toThrow(TypeError);
    });
  });
});
