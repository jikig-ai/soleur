import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { assertProdSupabaseUrl } from "@/lib/supabase/allowed-hosts";

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

    it("throws on the test placeholder host", () => {
      expect(() => assertProdSupabaseUrl("https://test.supabase.co")).toThrow(
        /placeholder/i,
      );
    });

    it("throws on placeholder.supabase.co", () => {
      expect(() =>
        assertProdSupabaseUrl("https://placeholder.supabase.co"),
      ).toThrow(/placeholder/i);
    });

    it("throws on example.supabase.co (4-char first label)", () => {
      expect(() =>
        assertProdSupabaseUrl("https://example.supabase.co"),
      ).toThrow();
    });

    it("throws on http:// (insecure protocol) for canonical ref", () => {
      expect(() =>
        assertProdSupabaseUrl("http://ifsccnjhymdmidffkzhl.supabase.co"),
      ).toThrow(/protocol|insecure|https/i);
    });

    it("throws on missing/empty value", () => {
      expect(() => assertProdSupabaseUrl(undefined)).toThrow();
      expect(() => assertProdSupabaseUrl("")).toThrow();
    });

    it("throws on subdomain-bypass attempt (https://api.soleur.ai.evil.com)", () => {
      expect(() =>
        assertProdSupabaseUrl("https://api.soleur.ai.evil.com"),
      ).toThrow();
    });

    it("throws on 19-char first label (boundary, off-by-one)", () => {
      expect(() =>
        assertProdSupabaseUrl("https://abcdefghij123456789.supabase.co"),
      ).toThrow();
    });

    it("throws on 21-char first label (boundary, off-by-one)", () => {
      expect(() =>
        assertProdSupabaseUrl("https://abcdefghij1234567890a.supabase.co"),
      ).toThrow();
    });

    it("does not throw on a canonical 20-char project ref", () => {
      expect(() =>
        assertProdSupabaseUrl("https://abcdefghij1234567890.supabase.co"),
      ).not.toThrow();
    });

    it("does not throw on the actual prd ref (ifsccnjhymdmidffkzhl)", () => {
      expect(() =>
        assertProdSupabaseUrl("https://ifsccnjhymdmidffkzhl.supabase.co"),
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
      expect(() => assertProdSupabaseUrl("not a url")).toThrow();
    });
  });

  describe("outside production", () => {
    it("does not throw on the test placeholder when NODE_ENV=test", () => {
      vi.stubEnv("NODE_ENV", "test");
      expect(() =>
        assertProdSupabaseUrl("https://test.supabase.co"),
      ).not.toThrow();
    });

    it("does not throw on the test placeholder when NODE_ENV=development", () => {
      vi.stubEnv("NODE_ENV", "development");
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
