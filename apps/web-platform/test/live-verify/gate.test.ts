// AC2 / AC2d — the allowlist code-gate and teardown predicate guard.
//
// These exercise the harness's pure gate functions WITHOUT launching a browser
// (run.ts guards main() behind import.meta.main, so importing is side-effect
// free). The gate must reject a wrong project ref BEFORE sign-in and a wrong
// UID/email BEFORE the browser launch; teardown must never issue a DELETE with
// an empty predicate.

import { describe, expect, it, vi } from "vitest";

import {
  bindProject,
  verifyPrincipal,
  teardownConversation,
  assertUrlHostAllowed,
  EXPECTED_EMAIL,
  type Config,
  type VerifiedPrincipal,
} from "../../scripts/live-verify/run";

// Build a syntactically-valid anon JWT whose payload carries the given ref.
// Synthetic + short — never a real token (push-protection safe).
function makeAnonJwt(ref: string): string {
  const header = Buffer.from('{"alg":"HS256"}').toString("base64url");
  const payload = Buffer.from(JSON.stringify({ ref })).toString("base64url");
  return `${header}.${payload}.sig`;
}

const REF = "abcdefghijklmnopqrst"; // 20-char canonical ref

function baseConfig(over: Partial<Config> = {}): Config {
  return {
    supabaseUrl: `https://${REF}.supabase.co`,
    anonKey: makeAnonJwt(REF),
    password: "not-reached",
    expectedUid: "11111111-1111-1111-1111-111111111111",
    expectedRef: REF,
    productionUrl: "https://app.soleur.ai",
    dryRun: false,
    ...over,
  };
}

// Minimal stub for supabase.auth.getUser().
function stubUser(id: string, email: string | undefined) {
  return {
    auth: {
      getUser: vi.fn().mockResolvedValue({
        data: { user: { id, email } },
        error: null,
      }),
    },
  } as unknown as Parameters<typeof verifyPrincipal>[0];
}

describe("project-bind (AC2 — before sign-in)", () => {
  it("accepts the custom prod domain and the canonical shape", () => {
    expect(() => assertUrlHostAllowed("https://api.soleur.ai")).not.toThrow();
    expect(() =>
      assertUrlHostAllowed(`https://${REF}.supabase.co`),
    ).not.toThrow();
  });

  it("rejects a non-allowlisted host", () => {
    expect(() => assertUrlHostAllowed("https://evil.example.com")).toThrow();
  });

  it("throws on a wrong project ref (anon JWT ref != expected)", () => {
    const cfg = baseConfig({
      anonKey: makeAnonJwt("zzzzzzzzzzzzzzzzzzzz"),
      expectedRef: REF,
    });
    expect(() => bindProject(cfg)).toThrow(/anon-key ref/);
  });

  it("passes when the ref matches", () => {
    expect(() => bindProject(baseConfig())).not.toThrow();
  });
});

describe("allowlist code-gate (AC2 — before launch)", () => {
  const cfg = baseConfig();

  it("throws on a wrong UID", async () => {
    const supabase = stubUser(
      "99999999-9999-9999-9999-999999999999",
      EXPECTED_EMAIL,
    );
    await expect(verifyPrincipal(supabase, cfg)).rejects.toThrow(
      /session UID/,
    );
  });

  it("throws on a wrong email", async () => {
    const supabase = stubUser(cfg.expectedUid, "attacker@example.com");
    await expect(verifyPrincipal(supabase, cfg)).rejects.toThrow(
      /session email/,
    );
  });

  it("returns a verified principal when UID + email match", async () => {
    const supabase = stubUser(cfg.expectedUid, EXPECTED_EMAIL);
    const verified = await verifyPrincipal(supabase, cfg);
    expect(verified.uid).toBe(cfg.expectedUid);
  });
});

describe("teardown predicate guard (AC2d)", () => {
  const cfg = baseConfig();
  const verified: VerifiedPrincipal = {
    __brand: "verified-live-verify-principal",
    uid: cfg.expectedUid,
  } as VerifiedPrincipal;

  it("is a no-op (no DELETE issued) when the conversation id is empty", async () => {
    const from = vi.fn();
    const supabase = { from } as unknown as Parameters<
      typeof teardownConversation
    >[0];

    const result = await teardownConversation(supabase, cfg, verified, "");

    expect(result.kind).toBe("CANT-RUN");
    if (result.kind === "CANT-RUN") {
      expect(result.reason).toContain("CANT-TEARDOWN-empty-predicate");
    }
    // The critical assertion: zero DB calls — no DELETE with a null filter.
    expect(from).not.toHaveBeenCalled();
  });

  it("is a no-op when the allowlisted UID is empty", async () => {
    const from = vi.fn();
    const supabase = { from } as unknown as Parameters<
      typeof teardownConversation
    >[0];
    const empty: VerifiedPrincipal = {
      __brand: "verified-live-verify-principal",
      uid: "",
    } as VerifiedPrincipal;

    const result = await teardownConversation(
      supabase,
      cfg,
      empty,
      "33333333-3333-3333-3333-333333333333",
    );

    expect(result.kind).toBe("CANT-RUN");
    expect(from).not.toHaveBeenCalled();
  });
});
