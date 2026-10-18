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

  describe("email rule (linear time, same output)", () => {
    it("redacts emails exactly as before, including when glued to a local-part run", () => {
      expect(redact("mail jean.deruelle+x@jikigai.com now")).toBe("mail [REDACTED_EMAIL] now");
      expect(redact("a@b.co")).toBe("[REDACTED_EMAIL]");
      // The match still starts at the beginning of the whole local-part run.
      expect(redact("x_y.z%w+v@sub.example.org")).toBe("[REDACTED_EMAIL]");
      expect(redact("no at sign here")).toBe("no at sign here");
    });

    it("does not go quadratic on a long local-part-shaped run with no @", () => {
      // 100k chars took ~23 s with the unanchored rule; linear is a few ms.
      const t0 = performance.now();
      redact("a".repeat(100_000));
      redact(`${"a.".repeat(50_000)}@`);
      expect(performance.now() - t0).toBeLessThan(2_000);
    });
  });

  describe("api_keys ciphertext fields (I-cannot-spend backstop)", () => {
    // Exact equality, not not.toContain: a rule that redacts one character, or
    // all of the line, would satisfy an absence-only assertion.
    it.each([
      [
        "JSON",
        '{"provider":"anthropic","encrypted_key":"ct-secret-value","iv":"iv-secret-value","auth_tag":"tag-secret-value"}',
        '{"provider":"anthropic","encrypted_key":"[REDACTED]","iv":"[REDACTED]","auth_tag":"[REDACTED]"}',
      ],
      [
        "JSON, pretty-printed",
        '{\n  "encrypted_key": "ct secret",\n  "iv": "x"\n}',
        '{\n  "encrypted_key": "[REDACTED]",\n  "iv": "[REDACTED]"\n}',
      ],
      [
        "util.inspect",
        "{ provider: 'anthropic', encrypted_key: 'ct-secret', iv: 'iv-secret', auth_tag: 'tag-secret' }",
        "{ provider: 'anthropic', encrypted_key: '[REDACTED]', iv: '[REDACTED]', auth_tag: '[REDACTED]' }",
      ],
      [
        "query string",
        "encrypted_key=ct-secret&iv=iv-secret&auth_tag=tag-secret",
        "encrypted_key=[REDACTED]&iv=[REDACTED]&auth_tag=[REDACTED]",
      ],
    ])("redacts the %s form exactly", (_n, input, expected) => {
      expect(redact(input)).toBe(expected);
      expect(redact(expected)).toBe(expected); // idempotent
    });

    it("keeps diagnostic text that merely contains the key names (retention)", () => {
      // Shaped like what an over-broad rule eats: identifiers, paths, filenames.
      const keep = "div=keepme device_iv: keep /usr/lib/iv.so libkeyring.so.1 fetch failed: ENOENT";
      expect(redact(keep)).toBe(keep);
    });
  });
});
