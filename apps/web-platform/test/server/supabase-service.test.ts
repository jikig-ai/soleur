import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";

// Capture original env values at module load so `afterEach` can restore
// them — env mutations leak across files when vitest reuses workers, which
// has caused parallel-run failures in unrelated component tests that
// rely on `SUPABASE_URL` / `NEXT_PUBLIC_SUPABASE_URL` being set.
const ORIGINAL_ENV = {
  SUPABASE_URL: process.env.SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY: process.env.SUPABASE_SERVICE_ROLE_KEY,
  NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
};

function restoreEnv(key: keyof typeof ORIGINAL_ENV) {
  if (ORIGINAL_ENV[key] === undefined) {
    delete process.env[key];
  } else {
    process.env[key] = ORIGINAL_ENV[key];
  }
}

// Pin env so serverUrl() in the SUT resolves without falling through to the
// dev placeholder warning path (irrelevant to memoization behavior).
// `vi.resetModules()` is mandatory: vitest's module cache survives across
// test cases unless explicitly reset, so the singleton from one case
// would leak into the next.
beforeEach(() => {
  vi.resetModules();
  process.env.SUPABASE_URL = "https://test.supabase.co";
  process.env.SUPABASE_SERVICE_ROLE_KEY = "test-service-role-key";
});

afterEach(() => {
  restoreEnv("SUPABASE_URL");
  restoreEnv("SUPABASE_SERVICE_ROLE_KEY");
  restoreEnv("NEXT_PUBLIC_SUPABASE_URL");
});

describe("getServiceClient (memoized lazy singleton)", () => {
  it("returns the same instance across two calls (referential stability)", async () => {
    const { getServiceClient } = await import("@/lib/supabase/service");
    const first = getServiceClient();
    const second = getServiceClient();
    expect(second).toBe(first);
  });

  it("returns the same instance across many calls", async () => {
    const { getServiceClient } = await import("@/lib/supabase/service");
    const first = getServiceClient();
    for (let i = 0; i < 5; i++) {
      expect(getServiceClient()).toBe(first);
    }
  });

  it("returns a different instance after vi.resetModules() (proves the singleton lives in the module, not the call site)", async () => {
    const mod1 = await import("@/lib/supabase/service");
    const first = mod1.getServiceClient();
    vi.resetModules();
    const mod2 = await import("@/lib/supabase/service");
    const second = mod2.getServiceClient();
    expect(second).not.toBe(first);
  });

  it("does not call createClient eagerly at module load (lazy)", async () => {
    // Wipe env BEFORE the first import to verify import side-effects don't
    // call createServiceClient — if the singleton were eager at module load,
    // the missing env vars would throw inside serverUrl() during import.
    delete process.env.SUPABASE_URL;
    delete process.env.NEXT_PUBLIC_SUPABASE_URL;
    delete process.env.SUPABASE_SERVICE_ROLE_KEY;

    // Should NOT throw at import time.
    const mod = await import("@/lib/supabase/service");
    expect(typeof mod.getServiceClient).toBe("function");
  });

  it("does not cache the rejection if construction throws — next call retries", async () => {
    // First call: env-missing under NODE_ENV=test -> serverUrl() throws ->
    // singleton stays null because the assignment RHS never resolves.
    delete process.env.SUPABASE_URL;
    delete process.env.NEXT_PUBLIC_SUPABASE_URL;
    const { getServiceClient } = await import("@/lib/supabase/service");
    expect(() => getServiceClient()).toThrow(/Missing SUPABASE_URL/);

    // Restore env and retry — should succeed because the prior failure
    // never persisted into `serviceClientSingleton`. Failure-mode
    // amplification (one transient init error poisoning every subsequent
    // caller) is the exact behavior to guard against.
    process.env.SUPABASE_URL = "https://test.supabase.co";
    expect(() => getServiceClient()).not.toThrow();
  });
});

describe("createServiceClient (legacy per-call factory)", () => {
  it("remains exported for backward compatibility (#2962 partial close)", async () => {
    const { createServiceClient, getServiceClient } = await import(
      "@/lib/supabase/service"
    );
    expect(typeof createServiceClient).toBe("function");
    // Each call to `createServiceClient` returns a fresh instance — distinct
    // from the singleton accessor's cached one.
    const a = createServiceClient();
    const b = createServiceClient();
    const singleton = getServiceClient();
    expect(a).not.toBe(b);
    expect(a).not.toBe(singleton);
  });
});
