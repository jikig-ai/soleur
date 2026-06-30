import { describe, expect, it } from "vitest";

import { redact } from "../../scripts/live-verify/redact";

// AC3 (deepen security P0-4): the live-verify harness captures WS/DOM/network
// from a REAL prod session, so the scrubber must remove secrets by STRUCTURAL
// LOCATION — not just a free-text JWT shape. All fixtures are synthesized via
// concatenation (cq-test-fixtures-synthesized-only + push-protection): no
// contiguous provider-token literal exists in source.
const FAKE_JWT = "eyJ" + "hbGciOi" + ".eyJzdWIiOiJ4" + ".s1Gn4tur3_AbC-dEf";

describe("redact", () => {
  it("redacts access_token in a WebSocket connect URL query param", () => {
    const ws = `wss://api.example.co/realtime/v1/websocket?apikey=anon123&access_token=${FAKE_JWT}&vsn=1.0`;
    const out = redact(ws);
    expect(out).not.toContain(FAKE_JWT);
    expect(out).not.toContain("anon123");
    // structure preserved so the artifact is still readable
    expect(out).toContain("access_token=");
    expect(out).toContain("apikey=");
  });

  it("redacts an Authorization: Bearer request header", () => {
    const out = redact(`Authorization: Bearer ${FAKE_JWT}`);
    expect(out).not.toContain(FAKE_JWT);
    expect(out.toLowerCase()).toContain("authorization:");
  });

  it("redacts an sb-<ref>-auth-token cookie value", () => {
    const cookie = `sb-abcdefghijklmnopqrst-auth-token=${FAKE_JWT}; Path=/; HttpOnly`;
    const out = redact(cookie);
    expect(out).not.toContain(FAKE_JWT);
    expect(out).toContain("sb-abcdefghijklmnopqrst-auth-token=");
    expect(out).toContain("Path=/");
  });

  it("redacts a CHUNKED sb-<ref>-auth-token.N cookie value", () => {
    const cookie = `sb-abcdefghijklmnopqrst-auth-token.0=${FAKE_JWT}; Path=/; HttpOnly`;
    const out = redact(cookie);
    expect(out).not.toContain(FAKE_JWT);
    expect(out).toContain("sb-abcdefghijklmnopqrst-auth-token.0=");
    expect(out).toContain("Path=/");
  });

  it("redacts the @supabase/ssr `base64-<blob>` session value (no JWT dots)", () => {
    // The SSR cookie value embeds access_token + refresh_token + email inside an
    // opaque base64url blob with no `.` separators — security review P1.
    const blob = "base64-" + ("AbCdEf0123456789_-".repeat(3)); // ≥40 base64url chars
    const out = redact(`captured cookie value: ${blob} end`);
    expect(out).not.toContain(blob);
    expect(out).toContain("[REDACTED_SB_SESSION]");
    expect(out).toContain("end");
  });

  it("redacts refresh_token / access_token JSON keys", () => {
    const refresh = "rT_" + "0123456789abcdefXYZ";
    const json = `{"access_token":"${FAKE_JWT}","refresh_token":"${refresh}","expires_in":3600}`;
    const out = redact(json);
    expect(out).not.toContain(FAKE_JWT);
    expect(out).not.toContain(refresh);
    expect(out).toContain("expires_in");
  });

  it("redacts a bare JWT shape anywhere", () => {
    expect(redact(`token is ${FAKE_JWT} ok`)).not.toContain(FAKE_JWT);
  });

  it("redacts email addresses", () => {
    const out = redact("user live-verify@soleur.ai signed in");
    expect(out).not.toContain("live-verify@soleur.ai");
    expect(out).toContain("signed in");
  });

  it("passes benign text through unchanged", () => {
    const benign = "Recent Conversations rail rendered with 3 rows; status=active";
    expect(redact(benign)).toBe(benign);
  });

  it("redacts repeated occurrences (no stateful /g + .test() footgun)", () => {
    const twice = `${FAKE_JWT} and again ${FAKE_JWT}`;
    expect(redact(twice)).not.toContain(FAKE_JWT);
  });

  // #5487 review: the live-verify GHA job runs under `doppler run -c prd` and
  // `gh api` with GH_TOKEN; a CLI crash could surface those tokens in stderr,
  // which the job tees to the run log + a Sentry crash-tail event. The harness's
  // own threat model (Supabase synthetic principal) did not cover them.
  it("redacts a Doppler service token shape", () => {
    const dp = "dp." + "st." + "prd." + "AbCdSyntheticDopplerTokenValue0123456789";
    const out = redact(`doppler: error: invalid token ${dp}`);
    expect(out).not.toContain(dp);
    expect(out).toContain("[REDACTED_DOPPLER]");
  });

  it("redacts GitHub token shapes (PAT + fine-grained)", () => {
    const ghp = "ghp_" + "0123456789AbCdEfGhIjKlMnOpQrSt";
    const pat = "github_pat_" + "11ABCDEF0" + "0123456789abcdefABCDEF";
    const out = redact(`remote: ${ghp} and ${pat}`);
    expect(out).not.toContain(ghp);
    expect(out).not.toContain(pat);
    expect(out).toContain("[REDACTED_GH_TOKEN]");
  });

  it("redacts a bare base64- SSR session blob not preceded by a cookie name", () => {
    const blob = "base64-" + "x".repeat(60);
    const out = redact(`stderr dump: session=${blob} done`);
    expect(out).not.toContain(blob);
    expect(out).toContain("[REDACTED_SB_SESSION]");
  });
});
