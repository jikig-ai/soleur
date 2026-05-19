import { describe, it, expect } from "vitest";
import { redactGithubSourcedText } from "./redaction-allowlist";

// Golden-fixture tests for PR-H redaction allowlist extension.
// PII shapes per learning 2026-04-17-pii-regex-scrubber-three-invariants:
//   1. Max-input bound (DoS-resistant).
//   2. Alphabet-aware UUID match.
//   3. No /g+.test() — every assertion is single-shot per call.

describe("redactGithubSourcedText", () => {
  describe("empty / non-string input", () => {
    it("returns empty string on empty input", () => {
      expect(redactGithubSourcedText("")).toBe("");
    });

    it("returns empty string on non-string input (defensive)", () => {
      // @ts-expect-error — exercising defensive runtime guard.
      expect(redactGithubSourcedText(null)).toBe("");
      // @ts-expect-error — exercising defensive runtime guard.
      expect(redactGithubSourcedText(undefined)).toBe("");
    });
  });

  describe("email redaction", () => {
    it("redacts a single email", () => {
      const out = redactGithubSourcedText("ping me at alice@example.com please");
      expect(out).toBe("ping me at [redacted-email] please");
    });

    it("redacts multiple emails in one body", () => {
      const out = redactGithubSourcedText(
        "primary: founder@jikigai.com fallback: ops@jikigai.com",
      );
      expect(out).toContain("[redacted-email]");
      expect(out).not.toContain("@jikigai.com");
    });
  });

  describe("phone redaction", () => {
    it("redacts an E.164-ish US phone", () => {
      const out = redactGithubSourcedText("call +1-415-555-0100 for backup");
      expect(out).toContain("[redacted-phone]");
      expect(out).not.toContain("415-555-0100");
    });

    it("does NOT match version-like strings (1.2.3-rc.4)", () => {
      const out = redactGithubSourcedText("see release notes for 1.2.3-rc.4 and 4.5.6");
      expect(out).toBe("see release notes for 1.2.3-rc.4 and 4.5.6");
    });
  });

  describe("UUID redaction", () => {
    it("redacts a v4 UUID", () => {
      const out = redactGithubSourcedText(
        "ticket-id: 550e8400-e29b-41d4-a716-446655440000",
      );
      expect(out).toBe("ticket-id: [redacted-uuid]");
    });

    it("does NOT match the GitHub repo slug shape (org/name)", () => {
      const out = redactGithubSourcedText("repo jikig-ai/soleur opened a PR");
      expect(out).toBe("repo jikig-ai/soleur opened a PR");
    });
  });

  describe("API-key shaped redaction", () => {
    it("redacts a ghp_ PAT", () => {
      const out = redactGithubSourcedText(
        `token leaked: ${"ghp"+"_"}abcdefghijklmnopqrstuvwxyz0123`,
      );
      expect(out).toContain("[redacted-key]");
      expect(out).not.toContain(`${"ghp"+"_"}abcdefghijklmnopqrstuvwxyz`);
    });

    it("redacts an sk-ant- key", () => {
      const out = redactGithubSourcedText(
        `anthropic key: ${"sk"+"-"+"ant"+"-"}api03-AAAAAAAAAAAAAAAAAAAAAAAAAAA`,
      );
      expect(out).toContain("[redacted-key]");
    });

    it("redacts an Stripe live secret", () => {
      const out = redactGithubSourcedText(
        `stripe: ${"sk"+"_"+"live"+"_"}abcdefghijklmnopqrstuvwx`,
      );
      expect(out).toContain("[redacted-key]");
    });

    it("redacts an AWS access key id", () => {
      const out = redactGithubSourcedText(
        `AWS_ACCESS_KEY_ID=${"AKI"+"A"}IOSFODNN7EXAMPLE in the env`,
      );
      expect(out).toContain("[redacted-key]");
      expect(out).not.toContain(`${"AKI"+"A"}IOSFODNN7EXAMPLE`);
    });

    it("redacts an AWS secret access key in assignment shape", () => {
      const out = redactGithubSourcedText(
        `AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY in env`,
      );
      expect(out).toContain("[redacted-key]");
      expect(out).not.toContain("wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY");
    });

    it("redacts a fine-grained GitHub PAT (github_pat_)", () => {
      const out = redactGithubSourcedText(
        `token: ${"github"+"_pat_"}11AAAAAAAAAAAAAAAAAAA1_${"a".repeat(59)} suffix`,
      );
      expect(out).toContain("[redacted-key]");
      expect(out).not.toContain(`${"github"+"_pat_"}11`);
    });

    it("redacts a Slack bot token (xoxb-)", () => {
      const out = redactGithubSourcedText(
        `slack: ${"xox"+"b"}-123456789012-1234567890123-abcdefghijklmnopqrstuvwx`,
      );
      expect(out).toContain("[redacted-key]");
    });
  });

  describe("IPv6 redaction", () => {
    it("redacts a full-form IPv6", () => {
      const out = redactGithubSourcedText(
        "beacon to 2001:0db8:85a3:0000:0000:8a2e:0370:7334 over TLS",
      );
      expect(out).toContain("[redacted-ip]");
      expect(out).not.toContain("2001:0db8:85a3");
    });

    it("redacts a compressed-form IPv6", () => {
      const out = redactGithubSourcedText(
        "blocked fe80::1ff:fe23:4567:890a at edge",
      );
      expect(out).toContain("[redacted-ip]");
      expect(out).not.toContain("fe80::1ff");
    });
  });

  describe("JWT redaction", () => {
    it("redacts a JWT-shaped triple", () => {
      const jwt =
        "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTYifQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"; // gitleaks:allow issue:#4090 canonical jwt.io test fixture (sub=123456), signed with published demo secret "your-256-bit-secret"
      const out = redactGithubSourcedText(`token=${jwt} sent`);
      expect(out).toContain("[redacted-jwt]");
      expect(out).not.toContain("eyJ");
    });
  });

  describe("IPv4 redaction", () => {
    it("redacts a public IPv4", () => {
      const out = redactGithubSourcedText("blocked 198.51.100.42 at edge");
      expect(out).toBe("blocked [redacted-ip] at edge");
    });
  });

  describe("invariants (learning 2026-04-17)", () => {
    it("invariant 1: max-input bound truncates to MAX_INPUT_LEN", () => {
      const oversize = "a".repeat(64_500);
      const out = redactGithubSourcedText(oversize);
      // 64_000 chars + 3-char truncation marker, no false positives.
      expect(out.endsWith("[…]")).toBe(true);
      // Marker added after redaction so it's never matched as PII.
      expect(out).not.toContain("[redacted-");
    });

    it("invariant 2: alphabet-aware UUID match (rejects malformed)", () => {
      // 'g' is not a hex digit — must NOT match.
      const out = redactGithubSourcedText(
        "fake: gggggggg-e29b-41d4-a716-446655440000",
      );
      expect(out).toContain("gggggggg-");
      expect(out).not.toContain("[redacted-uuid]");
    });

    it("invariant 3: no stateful /g+.test() — repeated calls are idempotent", () => {
      // If a regex with /g flag were used in a .test() loop, lastIndex
      // would drift across calls. Each call here re-creates the
      // replacement state via .replace().
      const input = "alice@example.com twice";
      const a = redactGithubSourcedText(input);
      const b = redactGithubSourcedText(input);
      const c = redactGithubSourcedText(input);
      expect(a).toBe(b);
      expect(b).toBe(c);
      expect(a).toBe("[redacted-email] twice");
    });
  });

  describe("source variants (Phase 4 / Phase 6 callers)", () => {
    it("pr_title source: redacts email in a PR title", () => {
      const out = redactGithubSourcedText(
        "fix: rotate alice@example.com webhook secret",
        { source: "pr_title" },
      );
      expect(out).toContain("[redacted-email]");
    });

    it("issue_body source: redacts API key in an issue body", () => {
      const out = redactGithubSourcedText(
        `Stack trace pointed to ${"ghp"+"_"}abcdefghijklmnopqrstuvwxyz0123 in env`,
        { source: "issue_body" },
      );
      expect(out).toContain("[redacted-key]");
    });

    it("cve_description source: redacts IPv4 in advisory text", () => {
      const out = redactGithubSourcedText(
        "Exploit beaconed to 198.51.100.42 over TLS",
        { source: "cve_description" },
      );
      expect(out).toBe("Exploit beaconed to [redacted-ip] over TLS");
    });
  });
});
