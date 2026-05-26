import { describe, test, expect } from "bun:test";
import { resolve } from "node:path";
import { mkdtempSync, readFileSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";

const REPO_ROOT = resolve(import.meta.dir, "../../..");
const BOT_FIXTURE = resolve(
  REPO_ROOT,
  "plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts",
);
const BOT_SIGNIN = resolve(
  REPO_ROOT,
  "plugins/soleur/skills/ux-audit/scripts/bot-signin.ts",
);

describe("bot-fixture exports", () => {
  test("exports seed as a function", async () => {
    const mod = await import(BOT_FIXTURE);
    expect(typeof mod.seed).toBe("function");
  });

  test("exports reset as a function", async () => {
    const mod = await import(BOT_FIXTURE);
    expect(typeof mod.reset).toBe("function");
  });
});

describe("bot-signin exports", () => {
  test("exports signIn as a function", async () => {
    const mod = await import(BOT_SIGNIN);
    expect(typeof mod.signIn).toBe("function");
  });

  test("exports writeStorageState as a function", async () => {
    const mod = await import(BOT_SIGNIN);
    expect(typeof mod.writeStorageState).toBe("function");
  });

  test("writeStorageState produces correct cookie structure", async () => {
    const mod = await import(BOT_SIGNIN);
    const tmpDir = mkdtempSync(resolve(tmpdir(), "bot-signin-test-"));
    const outPath = resolve(tmpDir, "storage-state.json");

    try {
      const mockSession = {
        access_token: "test-access-token",
        refresh_token: "test-refresh-token",
        expires_in: 3600,
        expires_at: Math.floor(Date.now() / 1000) + 3600,
        token_type: "bearer",
        user: { id: "test-user-id" },
      };

      mod.writeStorageState(
        mockSession,
        outPath,
        "https://testref.supabase.co",
        "https://app.example.com",
      );

      const written = JSON.parse(readFileSync(outPath, "utf-8"));
      expect(written.cookies).toHaveLength(1);
      expect(written.cookies[0].name).toBe("sb-testref-auth-token");
      expect(written.cookies[0].domain).toBe("app.example.com");
      expect(written.cookies[0].secure).toBe(true);
      expect(written.cookies[0].sameSite).toBe("Lax");
      expect(written.origins).toEqual([]);

      const stat = statSync(outPath);
      expect(stat.mode & 0o777).toBe(0o600);
    } finally {
      rmSync(tmpDir, { recursive: true, force: true });
    }
  });
});
