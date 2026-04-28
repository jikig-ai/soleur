import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { assertProdSupabaseAnonKey } from "@/lib/supabase/validate-anon-key";

const CANONICAL_URL = "https://ifsccnjhymdmidffkzhl.supabase.co";
const CUSTOM_DOMAIN_URL = "https://api.soleur.ai";
const CANONICAL_REF = "ifsccnjhymdmidffkzhl";

function fakeJwt(payload: Record<string, unknown>): string {
  const b64url = (s: string) => Buffer.from(s).toString("base64url");
  return `${b64url('{"alg":"HS256","typ":"JWT"}')}.${b64url(
    JSON.stringify(payload),
  )}.fake-signature`;
}

const canonicalAnonPayload = {
  iss: "supabase",
  role: "anon",
  ref: CANONICAL_REF,
  iat: 1700000000,
  exp: 2000000000,
};

describe("assertProdSupabaseAnonKey", () => {
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

    it("throws on missing key (undefined)", () => {
      expect(() =>
        assertProdSupabaseAnonKey(undefined, CANONICAL_URL),
      ).toThrow(/missing/i);
    });

    it("throws on empty key", () => {
      expect(() => assertProdSupabaseAnonKey("", CANONICAL_URL)).toThrow(
        /missing/i,
      );
    });

    it("throws on key without 3 dot-separated segments", () => {
      expect(() =>
        assertProdSupabaseAnonKey("not.a-jwt", CANONICAL_URL),
      ).toThrow(/segments|jwt/i);
    });

    it("throws on non-base64url middle segment", () => {
      expect(() =>
        assertProdSupabaseAnonKey("eyJhbGc.@@@@.fake-sig", CANONICAL_URL),
      ).toThrow(/payload|invalid/i);
    });

    it("throws on non-JSON payload after decode", () => {
      const garbage = `eyJhbGc.${Buffer.from("not json").toString("base64url")}.fake-sig`;
      expect(() => assertProdSupabaseAnonKey(garbage, CANONICAL_URL)).toThrow(
        /payload|json|invalid/i,
      );
    });

    it('throws on iss != "supabase"', () => {
      const jwt = fakeJwt({ ...canonicalAnonPayload, iss: "auth0" });
      expect(() => assertProdSupabaseAnonKey(jwt, CANONICAL_URL)).toThrow(
        /iss/i,
      );
    });

    it("throws on missing iss claim entirely", () => {
      const { iss: _iss, ...rest } = canonicalAnonPayload;
      const jwt = fakeJwt(rest);
      expect(() => assertProdSupabaseAnonKey(jwt, CANONICAL_URL)).toThrow(
        /iss/i,
      );
    });

    it("throws on missing role claim entirely", () => {
      const { role: _role, ...rest } = canonicalAnonPayload;
      const jwt = fakeJwt(rest);
      expect(() => assertProdSupabaseAnonKey(jwt, CANONICAL_URL)).toThrow(
        /role/i,
      );
    });

    it("throws on missing ref claim entirely", () => {
      const { ref: _ref, ...rest } = canonicalAnonPayload;
      const jwt = fakeJwt(rest);
      expect(() => assertProdSupabaseAnonKey(jwt, CANONICAL_URL)).toThrow(
        /ref|canonical/i,
      );
    });

    it("throws on uppercase ref (case-sensitive canonical regex)", () => {
      const jwt = fakeJwt({
        ...canonicalAnonPayload,
        ref: "ABCDEFGHIJ1234567890",
      });
      expect(() => assertProdSupabaseAnonKey(jwt, CANONICAL_URL)).toThrow(
        /ref|canonical/i,
      );
    });

    it('throws on role = "service_role" (security-critical: silent RLS bypass)', () => {
      const jwt = fakeJwt({ ...canonicalAnonPayload, role: "service_role" });
      expect(() => assertProdSupabaseAnonKey(jwt, CANONICAL_URL)).toThrow(
        /service_role/,
      );
    });

    it('throws on role = "authenticated"', () => {
      const jwt = fakeJwt({ ...canonicalAnonPayload, role: "authenticated" });
      expect(() => assertProdSupabaseAnonKey(jwt, CANONICAL_URL)).toThrow(
        /role/i,
      );
    });

    it('throws on ref = "test" (placeholder)', () => {
      const jwt = fakeJwt({ ...canonicalAnonPayload, ref: "test" });
      expect(() => assertProdSupabaseAnonKey(jwt, CANONICAL_URL)).toThrow(
        /ref|placeholder|canonical/i,
      );
    });

    it("throws on ref not matching ^[a-z0-9]{20}$ (19 chars)", () => {
      const jwt = fakeJwt({ ...canonicalAnonPayload, ref: "abcdefghij123456789" });
      expect(() =>
        assertProdSupabaseAnonKey(jwt, CANONICAL_URL),
      ).toThrow(/ref|canonical/i);
    });

    it("throws on ref padded to 20 chars but in placeholder set", () => {
      const jwt = fakeJwt({
        ...canonicalAnonPayload,
        ref: "placeholderxxxxxxxxx",
      });
      expect(() => assertProdSupabaseAnonKey(jwt, CANONICAL_URL)).toThrow(
        /placeholder|test-fixture/i,
      );
    });

    it("throws on ref mismatch with URL canonical first label", () => {
      const jwt = fakeJwt({
        ...canonicalAnonPayload,
        ref: "abcdefghij1234567890",
      });
      expect(() => assertProdSupabaseAnonKey(jwt, CANONICAL_URL)).toThrow(
        /mismatch|does not match/i,
      );
    });

    it("passes on canonical key matching canonical URL", () => {
      const jwt = fakeJwt(canonicalAnonPayload);
      expect(() => assertProdSupabaseAnonKey(jwt, CANONICAL_URL)).not.toThrow();
    });

    it("passes on canonical key with api.soleur.ai URL (custom domain — JWT ref is source of truth)", () => {
      const jwt = fakeJwt(canonicalAnonPayload);
      expect(() =>
        assertProdSupabaseAnonKey(jwt, CUSTOM_DOMAIN_URL),
      ).not.toThrow();
    });

    it("strips trailing CR before parsing (CR-terminated canonical JWT passes)", () => {
      const jwt = `${fakeJwt(canonicalAnonPayload)}\r`;
      expect(() => assertProdSupabaseAnonKey(jwt, CANONICAL_URL)).not.toThrow();
    });

    it("strips trailing LF before parsing (LF-terminated canonical JWT passes)", () => {
      const jwt = `${fakeJwt(canonicalAnonPayload)}\n`;
      expect(() => assertProdSupabaseAnonKey(jwt, CANONICAL_URL)).not.toThrow();
    });

    it("truncates the echoed JWT in error messages for service-role paste", () => {
      const jwt = fakeJwt({ ...canonicalAnonPayload, role: "service_role" });
      try {
        assertProdSupabaseAnonKey(jwt, CANONICAL_URL);
      } catch (e) {
        expect((e as Error).message).not.toContain(jwt);
        return;
      }
      throw new Error("expected throw");
    });
  });

  describe("outside production", () => {
    it("does not throw on a placeholder JWT when NODE_ENV=test (test-suite blast-radius gate)", () => {
      vi.stubEnv("NODE_ENV", "test");
      const jwt = fakeJwt({ ...canonicalAnonPayload, ref: "test" });
      expect(() => assertProdSupabaseAnonKey(jwt, CANONICAL_URL)).not.toThrow();
    });

    it("does not throw on missing key when NODE_ENV=development", () => {
      vi.stubEnv("NODE_ENV", "development");
      expect(() =>
        assertProdSupabaseAnonKey(undefined, CANONICAL_URL),
      ).not.toThrow();
    });
  });
});
