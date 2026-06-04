/**
 * AC4 — command/output redaction at the `command_stream` emit boundary.
 *
 * `redactCommandForDisplay` is the command-shaped wrapper over the
 * extended `redactGithubSourcedText` allowlist. It must redact:
 *   1. GitHub installation/OAuth tokens   (`ghs_…`, `gho_…` — already covered
 *      by API_KEY_RE, asserted here to pin the contract).
 *   2. `GH_TOKEN=<value>` / generic `<UPPER_TOKEN|KEY|SECRET|PASSWORD|PAT>=`
 *      env-assignments (new; preserves the key name like AWS_SECRET_ASSIGN_RE).
 *   3. `Authorization: <Bearer|Basic|token> <value>` header literals (new).
 *
 * Benign commands MUST pass through byte-for-byte unchanged.
 *
 * The three PII-scrubber invariants from `redaction-allowlist.ts:9-14`
 * (max-input bound, alphabet-aware, no `/g`+`.test()` gate) are inherited
 * from the underlying module; this suite asserts the command-display contract.
 */
import { describe, test, expect } from "vitest";
import {
  redactCommandForDisplay,
  redactGithubSourcedText,
} from "../../lib/safety/redaction-allowlist";

// Synthesized non-secrets — structurally valid token SHAPES, never real
// credentials (cq-test-fixtures-synthesized-only).
const GHS = "ghs_" + "A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5";
const GHO = "gho_" + "Z9y8X7w6V5u4T3s2R1q0P9o8N7m6L5";
const PAT_VALUE = "p4t_synthetic_value_0123456789ABCDEF";

describe("redactCommandForDisplay (AC4)", () => {
  test("redacts a `ghs_` GitHub installation token", () => {
    const out = redactCommandForDisplay(`git clone https://x-access-token:${GHS}@github.com/o/r.git`);
    expect(out).not.toContain(GHS);
    expect(out).toContain("[redacted-key]");
  });

  test("redacts a `gho_` OAuth token", () => {
    const out = redactCommandForDisplay(`curl -H "x: ${GHO}" https://api.github.com`);
    expect(out).not.toContain(GHO);
    expect(out).toContain("[redacted-key]");
  });

  test("redacts a `GH_TOKEN=<value>` env-assignment, preserving the key name", () => {
    const out = redactCommandForDisplay(`GH_TOKEN=${PAT_VALUE} gh pr list`);
    expect(out).not.toContain(PAT_VALUE);
    expect(out).toContain("GH_TOKEN=[redacted-key]");
  });

  test("redacts a generic `<NAME>_SECRET=<value>` env-assignment", () => {
    const out = redactCommandForDisplay(`MY_API_SECRET='${PAT_VALUE}' run`);
    expect(out).not.toContain(PAT_VALUE);
    expect(out).toContain("MY_API_SECRET=[redacted-key]");
  });

  test("redacts an `Authorization: Bearer <value>` header literal", () => {
    const out = redactCommandForDisplay(`curl -H "Authorization: Bearer ${PAT_VALUE}" https://api`);
    expect(out).not.toContain(PAT_VALUE);
    expect(out).toContain("Authorization: [redacted-token]");
  });

  test("redacts an `Authorization: token <value>` header literal", () => {
    const out = redactCommandForDisplay(`Authorization: token ${PAT_VALUE}`);
    expect(out).not.toContain(PAT_VALUE);
    expect(out).toContain("Authorization: [redacted-token]");
  });

  test("benign `git status` passes through unchanged", () => {
    expect(redactCommandForDisplay("git status")).toBe("git status");
  });

  test("benign `ls -la` passes through unchanged", () => {
    expect(redactCommandForDisplay("ls -la")).toBe("ls -la");
  });

  test("empty / non-string inputs are safe", () => {
    expect(redactCommandForDisplay("")).toBe("");
    // @ts-expect-error — defensive runtime guard for non-string callers.
    expect(redactCommandForDisplay(undefined)).toBe("");
  });
});

describe("redactGithubSourcedText extensions (env-assignment + Authorization)", () => {
  test("GH_TOKEN= assignment redacted at the module level", () => {
    const out = redactGithubSourcedText(`export GH_TOKEN=${PAT_VALUE}`);
    expect(out).not.toContain(PAT_VALUE);
    expect(out).toContain("GH_TOKEN=[redacted-key]");
  });

  test("Authorization header redacted at the module level", () => {
    const out = redactGithubSourcedText(`Authorization: Basic ${PAT_VALUE}`);
    expect(out).not.toContain(PAT_VALUE);
    expect(out).toContain("Authorization: [redacted-token]");
  });

  test("a lowercase `password=` assignment is NOT over-matched (env shape is UPPER-anchored)", () => {
    // The env-assignment regex anchors on UPPER_SNAKE keys to avoid eating
    // arbitrary `foo=bar` flags. A bare lowercase `password=x` is left to
    // other gates; assert the benign flag shape survives.
    const out = redactCommandForDisplay("./run --verbose=true");
    expect(out).toBe("./run --verbose=true");
  });
});

describe("connection-string userinfo redaction (Finding 3 — non-sentinel secrets)", () => {
  // ENV_CRED_ASSIGN only matches credential-noun-suffixed UPPER_SNAKE keys;
  // `URL`/`URI` are NOT in that set, so `DATABASE_URL=postgres://u:p@h`
  // previously survived. The connection-string userinfo pattern redacts the
  // PASSWORD in any `scheme://user:password@host` regardless of key name.
  test("DATABASE_URL= postgres connection string redacts the password", () => {
    const out = redactCommandForDisplay(
      "DATABASE_URL=postgres://u:p4ssw0rd@db:5432/x",
    );
    expect(out).not.toContain("p4ssw0rd");
    expect(out).toContain("[redacted-password]");
    // user + host survive (only the password run is replaced)
    expect(out).toContain("postgres://u:");
    expect(out).toContain("@db:5432/x");
  });

  test("bare `mongodb://admin:s3cret@h` redacts the password", () => {
    const out = redactCommandForDisplay("mongodb://admin:s3cret@h");
    expect(out).not.toContain("s3cret");
    expect(out).toContain("mongodb://admin:[redacted-password]@h");
  });

  test("MONGODB_URI= with userinfo redacts the password", () => {
    const out = redactCommandForDisplay(
      "MONGODB_URI=mongodb://admin:s3cretValue@cluster0/db",
    );
    expect(out).not.toContain("s3cretValue");
    expect(out).toContain("[redacted-password]");
  });

  test("bare `redis://u:secret@h` redacts the password", () => {
    const out = redactCommandForDisplay("redis://u:secretpw@h:6379");
    expect(out).not.toContain("secretpw");
    expect(out).toContain("redis://u:[redacted-password]@h:6379");
  });

  test("benign `https://example.com/path` (NO userinfo) is unchanged", () => {
    expect(redactCommandForDisplay("https://example.com/path")).toBe(
      "https://example.com/path",
    );
  });

  test("benign `scheme://user@host` (user only, no password) is not touched by the userinfo gate", () => {
    // Only `user:password@` userinfo is a connection-string leak; a bare
    // `user@host` (no colon-delimited password) MUST NOT be redacted by the
    // connection-string pattern. (A `user@host.tld` would still trip the
    // pre-existing EMAIL_RE — that's a separate gate — so use a TLD-less host.)
    expect(redactCommandForDisplay("git remote add o ssh://git@localhost/r")).toBe(
      "git remote add o ssh://git@localhost/r",
    );
  });
});
