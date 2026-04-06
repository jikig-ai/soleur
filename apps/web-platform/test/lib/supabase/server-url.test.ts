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
});
