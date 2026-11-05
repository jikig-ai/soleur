/** #12011 PR-D: readInternalBearerSecret takes a closed-union name; the default stays the Inngest secret. */
import { afterEach, describe, expect, it, vi } from "vitest";
import { readInternalBearerSecret } from "@/lib/internal-auth";

afterEach(() => vi.unstubAllEnvs());

describe("readInternalBearerSecret", () => {
  it("defaults to INNGEST_MANUAL_TRIGGER_SECRET (the four existing callers pass no argument)", () => {
    vi.stubEnv("INNGEST_MANUAL_TRIGGER_SECRET", "inngest-fixture");
    vi.stubEnv("LEGAL_ACCEPTANCE_VERIFY_TOKEN", "verify-fixture");
    expect(readInternalBearerSecret()).toBe("inngest-fixture");
    expect(readInternalBearerSecret("INNGEST_MANUAL_TRIGGER_SECRET")).toBe("inngest-fixture");
  });

  it("reads LEGAL_ACCEPTANCE_VERIFY_TOKEN only when asked for it, and never falls back to the other secret", () => {
    vi.stubEnv("INNGEST_MANUAL_TRIGGER_SECRET", "inngest-fixture");
    vi.stubEnv("LEGAL_ACCEPTANCE_VERIFY_TOKEN", "verify-fixture");
    expect(readInternalBearerSecret("LEGAL_ACCEPTANCE_VERIFY_TOKEN")).toBe("verify-fixture");
    vi.stubEnv("LEGAL_ACCEPTANCE_VERIFY_TOKEN", "");
    expect(readInternalBearerSecret("LEGAL_ACCEPTANCE_VERIFY_TOKEN")).toBeNull();
    expect(readInternalBearerSecret()).toBe("inngest-fixture");
  });

  it("an unset or empty value is null", () => {
    vi.stubEnv("INNGEST_MANUAL_TRIGGER_SECRET", "");
    expect(readInternalBearerSecret()).toBeNull();
  });

  it("the name is a closed union (a free string does not type-check)", () => {
    // @ts-expect-error not a member of InternalBearerSecretName
    readInternalBearerSecret("SUPABASE_SERVICE_ROLE_KEY");
  });
});
