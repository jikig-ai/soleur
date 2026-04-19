import { describe, test, expect, beforeEach, afterEach } from "bun:test";
import { sbDelete } from "../../skills/ux-audit/scripts/bot-fixture.ts";

const ORIGINAL_FETCH = globalThis.fetch;
const ORIGINAL_SUPABASE_URL = process.env.SUPABASE_URL;
const ORIGINAL_SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

describe("bot-fixture sbDelete helper", () => {
  beforeEach(() => {
    process.env.SUPABASE_URL = "https://project-ref.supabase.co";
    process.env.SUPABASE_SERVICE_ROLE_KEY = "service-role-key-stub";
  });

  afterEach(() => {
    globalThis.fetch = ORIGINAL_FETCH;
    // Restore originals so the real integration tests in bot-fixture.test.ts
    // (which share this bun-test process) see the Doppler-injected values
    // again. `delete` when the original was unset avoids leaking a stub.
    if (ORIGINAL_SUPABASE_URL === undefined) {
      delete process.env.SUPABASE_URL;
    } else {
      process.env.SUPABASE_URL = ORIGINAL_SUPABASE_URL;
    }
    if (ORIGINAL_SERVICE_KEY === undefined) {
      delete process.env.SUPABASE_SERVICE_ROLE_KEY;
    } else {
      process.env.SUPABASE_SERVICE_ROLE_KEY = ORIGINAL_SERVICE_KEY;
    }
  });

  test("resolves silently on 2xx", async () => {
    globalThis.fetch = (async () =>
      new Response("", { status: 204 })) as typeof fetch;
    await expect(
      sbDelete("/rest/v1/messages?conversation_id=eq.abc"),
    ).resolves.toBeUndefined();
  });

  test("throws with status + body snippet on 409 conflict", async () => {
    globalThis.fetch = (async () =>
      new Response("conflict: foreign key constraint violation", {
        status: 409,
      })) as typeof fetch;
    await expect(
      sbDelete("/rest/v1/messages?conversation_id=eq.abc"),
    ).rejects.toThrow(/DELETE .* failed: 409 .*conflict/);
  });

  test("throws on 403 forbidden (RLS denial)", async () => {
    globalThis.fetch = (async () =>
      new Response("permission denied", { status: 403 })) as typeof fetch;
    await expect(
      sbDelete("/rest/v1/conversations?user_id=eq.xyz"),
    ).rejects.toThrow(/DELETE .* failed: 403 .*permission denied/);
  });

  test("truncates long error bodies to 200 chars", async () => {
    const longBody = "x".repeat(5000);
    globalThis.fetch = (async () =>
      new Response(longBody, { status: 500 })) as typeof fetch;
    try {
      await sbDelete("/rest/v1/messages?conversation_id=eq.abc");
      throw new Error("expected sbDelete to throw");
    } catch (err) {
      const msg = (err as Error).message;
      expect(msg).toMatch(/DELETE .* failed: 500/);
      // "xxx...": at most 200 xs present in the message, never 5000.
      const xRun = msg.match(/x{200,}/)?.[0] ?? "";
      expect(xRun.length).toBeLessThanOrEqual(200);
    }
  });
});
