import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { assertProdSupabaseUrl } from "@/lib/supabase/validate-url";

describe("assertProdSupabaseUrl", () => {
  beforeEach(() => {
    vi.unstubAllEnvs();
  });

  afterEach(() => {
    vi.unstubAllEnvs();
  });

  describe("in production", () => {
    beforeEach(() => {
      vi.stubEnv("NODE_ENV", "production");
    });

    it.each([
      "test.supabase.co",
      "placeholder.supabase.co",
      "example.supabase.co",
      "localhost",
      "0.0.0.0",
    ])("throws on placeholder host %s", (host) => {
      expect(() => assertProdSupabaseUrl(`https://${host}`)).toThrow(
        /placeholder/i,
      );
    });

    it("throws on http:// (insecure protocol) for canonical ref", () => {
      expect(() =>
        assertProdSupabaseUrl("http://ifsccnjhymdmidffkzhl.supabase.co"),
      ).toThrow(/https/i);
    });

    it("throws on missing value (undefined)", () => {
      expect(() => assertProdSupabaseUrl(undefined)).toThrow(/missing/i);
    });

    it("throws on empty value", () => {
      expect(() => assertProdSupabaseUrl("")).toThrow(/missing/i);
    });

    it("throws on subdomain-bypass attempt (https://api.soleur.ai.evil.com)", () => {
      expect(() =>
        assertProdSupabaseUrl("https://api.soleur.ai.evil.com"),
      ).toThrow(/not canonical|allowlist/i);
    });

    it("throws on 19-char first label (boundary, off-by-one)", () => {
      expect(() =>
        assertProdSupabaseUrl("https://abcdefghij123456789.supabase.co"),
      ).toThrow(/not canonical|allowlist/i);
    });

    it("throws on 21-char first label (boundary, off-by-one)", () => {
      expect(() =>
        assertProdSupabaseUrl("https://abcdefghij1234567890a.supabase.co"),
      ).toThrow(/not canonical|allowlist/i);
    });

    it("throws on uppercase first label (case-sensitivity pin)", () => {
      // URL parser lowercases the hostname, so this passes — proves canonical
      // regex's `[a-z0-9]` IS load-bearing on the lowercased form.
      expect(() =>
        assertProdSupabaseUrl("https://ABCDEFGHIJ1234567890.supabase.co"),
      ).not.toThrow();
    });

    it("throws on hyphenated 20-char ref (real refs are alnum)", () => {
      expect(() =>
        assertProdSupabaseUrl("https://abcdefghij-234567890.supabase.co"),
      ).toThrow(/not canonical|allowlist/i);
    });

    it("throws on userinfo (https://user:pass@api.soleur.ai)", () => {
      expect(() =>
        assertProdSupabaseUrl("https://user:pass@api.soleur.ai"),
      ).toThrow(/userinfo/i);
    });

    it("throws on port-bearing URL (https://api.soleur.ai:8443)", () => {
      expect(() =>
        assertProdSupabaseUrl("https://api.soleur.ai:8443"),
      ).toThrow(/port/i);
    });

    it("does not throw on a canonical 20-char project ref", () => {
      expect(() =>
        assertProdSupabaseUrl("https://abcdefghij1234567890.supabase.co"),
      ).not.toThrow();
    });

    it("does not throw on the api.soleur.ai custom domain", () => {
      expect(() =>
        assertProdSupabaseUrl("https://api.soleur.ai"),
      ).not.toThrow();
    });

    it("does not throw on api.soleur.ai with trailing path/query", () => {
      expect(() =>
        assertProdSupabaseUrl("https://api.soleur.ai/auth/v1?x=1"),
      ).not.toThrow();
    });

    it("throws on a malformed URL", () => {
      expect(() => assertProdSupabaseUrl("not a url")).toThrow(/invalid/i);
    });

    it("truncates the echoed value in the error message for long inputs", () => {
      const longSecret = "x".repeat(200);
      try {
        assertProdSupabaseUrl(longSecret);
      } catch (e) {
        expect((e as Error).message).not.toContain(longSecret);
        expect((e as Error).message).toMatch(/…/);
        return;
      }
      throw new Error("expected throw");
    });
  });

  describe("outside production", () => {
    it("does not throw on the test placeholder when NODE_ENV=test", () => {
      vi.stubEnv("NODE_ENV", "test");
      expect(() =>
        assertProdSupabaseUrl("https://test.supabase.co"),
      ).not.toThrow();
    });

    it("does not throw on missing value when NODE_ENV=development", () => {
      vi.stubEnv("NODE_ENV", "development");
      expect(() => assertProdSupabaseUrl(undefined)).not.toThrow();
    });
  });
});
