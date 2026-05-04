import { describe, it, expect } from "vitest";
import { scrubJwtFromEvent } from "@/sentry.client.config";

function fakeJwt(): string {
  // 3 dot-separated base64url segments, eyJ-prefixed (matches validator output).
  return "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJvbGUiOiJhbm9uIn0.fake-signature"; // gitleaks:allow # issue:#3194 synthesized JWT (fake-signature literal) for scrubber test
}

describe("sentry.client.config beforeSend JWT scrub", () => {
  it("scrubs JWTs from event.message", () => {
    const event = { message: `boom (preview: ${fakeJwt()})` } as never;
    const out = scrubJwtFromEvent(event) as { message?: string };
    expect(out.message).not.toContain("eyJ");
    expect(out.message).toContain("<jwt-redacted>");
  });

  it("scrubs JWTs from exception.values[*].value", () => {
    const event = {
      exception: {
        values: [
          { value: `NEXT_PUBLIC_SUPABASE_ANON_KEY iss="x" (preview: ${fakeJwt()})` },
        ],
      },
    } as never;
    const out = scrubJwtFromEvent(event) as {
      exception?: { values?: Array<{ value?: string }> };
    };
    const value = out.exception?.values?.[0]?.value;
    expect(value).not.toContain("eyJ");
    expect(value).toContain("<jwt-redacted>");
  });

  it("leaves events without JWT-shaped strings unchanged", () => {
    const event = {
      message: "plain error",
      exception: { values: [{ value: "stack frame text" }] },
    } as never;
    const out = scrubJwtFromEvent(event) as {
      message?: string;
      exception?: { values?: Array<{ value?: string }> };
    };
    expect(out.message).toBe("plain error");
    expect(out.exception?.values?.[0]?.value).toBe("stack frame text");
  });
});
