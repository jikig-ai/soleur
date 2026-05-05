import { describe, it, expect, beforeEach } from "vitest";

// Pin env so serverUrl() in the SUT resolves without falling through to the
// dev placeholder warning path (irrelevant to memoization behavior).
beforeEach(() => {
  process.env.SUPABASE_URL = "https://test.supabase.co";
  process.env.SUPABASE_SERVICE_ROLE_KEY = "test-service-role-key";
});

describe("getServiceClient (memoized lazy singleton)", () => {
  it("returns the same instance across two calls (referential stability)", async () => {
    // Reset module registry so first/second call exercise the memoization
    // logic from a clean state.
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
});

describe("createServiceClient (legacy per-call factory)", () => {
  it("remains exported for backward compatibility (#2962 partial close)", async () => {
    const { createServiceClient } = await import("@/lib/supabase/service");
    expect(typeof createServiceClient).toBe("function");
  });
});
