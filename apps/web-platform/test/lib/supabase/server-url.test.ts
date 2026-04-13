import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { serverUrl } from "@/lib/supabase/service";

describe("serverUrl", () => {
  const originalEnv = process.env;

  beforeEach(() => {
    process.env = { ...originalEnv };
  });

  afterEach(() => {
    process.env = originalEnv;
  });

  it("returns SUPABASE_URL when set", () => {
    process.env.SUPABASE_URL = "https://direct.supabase.co";
    process.env.NEXT_PUBLIC_SUPABASE_URL = "https://custom.domain.com";

    expect(serverUrl()).toBe("https://direct.supabase.co");
  });

  it("falls back to NEXT_PUBLIC_SUPABASE_URL when SUPABASE_URL is not set", () => {
    delete process.env.SUPABASE_URL;
    process.env.NEXT_PUBLIC_SUPABASE_URL = "https://custom.domain.com";

    expect(serverUrl()).toBe("https://custom.domain.com");
  });

  it("falls back to NEXT_PUBLIC_SUPABASE_URL when SUPABASE_URL is empty string", () => {
    process.env.SUPABASE_URL = "";
    process.env.NEXT_PUBLIC_SUPABASE_URL = "https://custom.domain.com";

    expect(serverUrl()).toBe("https://custom.domain.com");
  });

  it("throws when both SUPABASE_URL and NEXT_PUBLIC_SUPABASE_URL are missing in production", () => {
    process.env = { ...originalEnv, NODE_ENV: "production" };
    delete process.env.SUPABASE_URL;
    delete process.env.NEXT_PUBLIC_SUPABASE_URL;

    expect(() => serverUrl()).toThrow(
      "Missing SUPABASE_URL and NEXT_PUBLIC_SUPABASE_URL",
    );
  });

  it("returns placeholder URL in dev mode when both vars are missing", () => {
    process.env = { ...originalEnv, NODE_ENV: "development" };
    delete process.env.SUPABASE_URL;
    delete process.env.NEXT_PUBLIC_SUPABASE_URL;

    const url = serverUrl();
    expect(url).toBe("https://placeholder.supabase.co");
  });

  it("throws when NODE_ENV is undefined and both vars are missing", () => {
    const { NODE_ENV: _, SUPABASE_URL: __, NEXT_PUBLIC_SUPABASE_URL: ___, ...envWithout } = originalEnv;
    process.env = envWithout as typeof process.env;

    expect(() => serverUrl()).toThrow(
      "Missing SUPABASE_URL and NEXT_PUBLIC_SUPABASE_URL",
    );
  });
});
