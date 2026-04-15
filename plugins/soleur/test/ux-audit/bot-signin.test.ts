import { describe, test, expect, beforeEach } from "bun:test";
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, rmSync } from "node:fs";
import { resolve } from "node:path";
import { tmpdir } from "node:os";

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
    expect(authCookie!.value.length).toBeGreaterThan(20);
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
