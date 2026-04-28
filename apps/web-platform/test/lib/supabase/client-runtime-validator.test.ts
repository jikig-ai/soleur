import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";

// vi.hoisted: vi.mock factories run before const initialization.
const { reportSilentFallbackSpy } = vi.hoisted(() => ({
  reportSilentFallbackSpy: vi.fn(),
}));

vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: reportSilentFallbackSpy,
  warnSilentFallback: vi.fn(),
}));

const CANONICAL_REF = "ifsccnjhymdmidffkzhl";
const CANONICAL_URL = `https://${CANONICAL_REF}.supabase.co`;

function fakeJwt(payload: Record<string, unknown>): string {
  const b64url = (s: string) => Buffer.from(s).toString("base64url");
  return `${b64url('{"alg":"HS256","typ":"JWT"}')}.${b64url(
    JSON.stringify(payload),
  )}.fake-signature`;
}

const VALID_ANON_KEY = fakeJwt({
  iss: "supabase",
  role: "anon",
  ref: CANONICAL_REF,
  iat: 1700000000,
  exp: 2000000000,
});

describe("lib/supabase/client module-load wrapper", () => {
  beforeEach(() => {
    vi.unstubAllEnvs();
    reportSilentFallbackSpy.mockClear();
    vi.resetModules();
  });

  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it("emits a Sentry event tagged 'supabase-validator-throw' before re-throwing on bad anon key", async () => {
    vi.stubEnv("NODE_ENV", "production");
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", CANONICAL_URL);
    vi.stubEnv(
      "NEXT_PUBLIC_SUPABASE_ANON_KEY",
      fakeJwt({
        iss: "supabase",
        role: "service_role",
        ref: CANONICAL_REF,
      }),
    );

    await expect(import("@/lib/supabase/client")).rejects.toThrow(
      /role="service_role"/,
    );

    expect(reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    const [errArg, optionsArg] = reportSilentFallbackSpy.mock.calls[0]!;
    expect(errArg).toBeInstanceOf(Error);
    expect(optionsArg).toMatchObject({
      feature: "supabase-validator-throw",
      op: "module-load",
    });
  });

  it("emits a Sentry event tagged 'supabase-validator-throw' before re-throwing on bad URL", async () => {
    vi.stubEnv("NODE_ENV", "production");
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "https://test.supabase.co");
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", VALID_ANON_KEY);

    await expect(import("@/lib/supabase/client")).rejects.toThrow(
      /NEXT_PUBLIC_SUPABASE_URL is a placeholder host/,
    );

    expect(reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    const [, optionsArg] = reportSilentFallbackSpy.mock.calls[0]!;
    expect(optionsArg).toMatchObject({
      feature: "supabase-validator-throw",
      op: "module-load",
    });
  });

  it("does NOT emit a Sentry event when validators pass", async () => {
    vi.stubEnv("NODE_ENV", "production");
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", CANONICAL_URL);
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", VALID_ANON_KEY);

    await expect(import("@/lib/supabase/client")).resolves.toBeDefined();
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("does NOT emit a Sentry event in development (validators are no-op outside production)", async () => {
    vi.stubEnv("NODE_ENV", "development");
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "https://test.supabase.co");
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", "not-a-jwt");

    await expect(import("@/lib/supabase/client")).resolves.toBeDefined();
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });
});
