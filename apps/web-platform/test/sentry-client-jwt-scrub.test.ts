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

describe("sentry.client.config beforeSend email scrub", () => {
  // Supabase auth errors (verifyOtp/signInWithOtp) carry the user's email in
  // error.message; reportSilentFallback forwards the raw error to
  // captureException, so the email lands in exception.values[*].value. This is
  // the residual PII vector the `extra`-level discipline does not cover.
  it("scrubs email addresses from exception.values[*].value", () => {
    const event = {
      exception: {
        values: [{ value: "rate limited for ops@jikigai.com" }],
      },
    } as never;
    const out = scrubJwtFromEvent(event) as {
      exception?: { values?: Array<{ value?: string }> };
    };
    const value = out.exception?.values?.[0]?.value;
    expect(value).not.toContain("ops@jikigai.com");
    expect(value).toContain("<email-redacted>");
  });

  it("scrubs email addresses from event.message", () => {
    const event = { message: "no account for user@example.co.uk" } as never;
    const out = scrubJwtFromEvent(event) as { message?: string };
    expect(out.message).not.toContain("user@example.co.uk");
    expect(out.message).toContain("<email-redacted>");
  });

  it("leaves events without email-shaped strings unchanged", () => {
    const event = { message: "verifyOtp failed: status 429" } as never;
    const out = scrubJwtFromEvent(event) as { message?: string };
    expect(out.message).toBe("verifyOtp failed: status 429");
  });
});
