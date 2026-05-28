import { describe, test, expect } from "vitest";
import { normalizeRepoUrl } from "@/lib/repo-url";

// TS ↔ SQL normalizeRepoUrl parity gate (ADR-044, AC7 — HARD MERGE GATE).
//
// With the installation-id uniqueness guarantee relocated from a DB
// UNIQUE constraint to the normalizeRepoUrl application contract, this
// parity is the SOLE matching contract for the webhook push-reconcile
// fan-out (Phase 081). A drift makes the reconcile match zero or wrong
// workspaces while everything else stays green — so this test is a hard
// merge gate, not advisory.
//
// `sqlNormalize031` is a faithful JS port of the regexp_replace chain in
// migration 031_normalize_repo_url.sql. It is the oracle for what the
// Postgres backfill (031) + any in-SQL normalization actually produces.
// Keep it byte-aligned with the SQL header's documented 5-step contract.
//
// All fixtures are SYNTHESIZED (cq-test-fixtures-synthesized-only) — no
// real owner/repo, no captured production data.

// Faithful JS port of migration 031's SQL normalizer (regexp_replace
// chain). The SQL extracts the scheme+host prefix via the POSIX pattern
// "^([^slash]*<doubleslash>[^slash]+)", LOWERs it, concatenates the
// case-preserved path remainder, then strips trailing slashes, then
// strips trailing repeated ".git", then strips trailing slashes again.
//
// The 031 UPDATE is guarded so that input not matching scheme+host is
// SKIPPED (left unchanged); this port mirrors that skip by returning the
// input verbatim. See migration 031 header for the byte-exact contract.
function sqlNormalize031(raw: string | null | undefined): string | null {
  if (raw == null) return null;
  const trimmed = raw.trim();
  const schemeHost = trimmed.match(/^([^/]*\/\/[^/]+)/);
  if (!schemeHost) {
    // 031 WHERE guard skips this row → value unchanged.
    return raw;
  }
  const rest = trimmed.match(/^[^/]*\/\/[^/]+(\/.*)$/);
  let working = schemeHost[1]!.toLowerCase() + (rest ? rest[1] : "");
  working = working.replace(/\/+$/g, "");
  working = working.replace(/(\.git)+$/i, "");
  working = working.replace(/\/+$/g, "");
  return working;
}

// Synthesized URL fixtures shared with test/repo-url.test.ts, extended
// with repeated-suffix (.git.git) idempotence cases (plan task 2.3).
const URL_FIXTURES: ReadonlyArray<[input: string, expected: string]> = [
  ["https://github.com/foo/bar", "https://github.com/foo/bar"],
  ["https://github.com/foo/bar.git", "https://github.com/foo/bar"],
  ["https://github.com/foo/bar.GIT", "https://github.com/foo/bar"],
  ["https://github.com/Owner/Repo.git/", "https://github.com/Owner/Repo"],
  ["HTTPS://GitHub.com/Foo/Bar", "https://github.com/Foo/Bar"],
  ["https://github.com/foo/bar///", "https://github.com/foo/bar"],
  ["https://github.com/foo/bar.git.git", "https://github.com/foo/bar"],
  ["https://github.com/foo/bar.git.git/", "https://github.com/foo/bar"],
  ["  https://github.com/foo/bar  ", "https://github.com/foo/bar"],
  ["https://github.com/Anthropic-Labs/Foo.git", "https://github.com/Anthropic-Labs/Foo"],
];

describe("normalizeRepoUrl TS ↔ SQL(031) parity — backfill URL→URL (task 2.3)", () => {
  test.each(URL_FIXTURES)(
    "TS and SQL agree on %s → %s",
    (input, expected) => {
      const ts = normalizeRepoUrl(input);
      const sql = sqlNormalize031(input);
      expect(ts).toBe(expected);
      expect(sql).toBe(expected);
      expect(ts).toBe(sql);
    },
  );

  test("repeated-suffix .git.git collapses in one pass on BOTH sides (idempotence)", () => {
    const input = "https://github.com/foo/bar.git.git";
    expect(normalizeRepoUrl(input)).toBe("https://github.com/foo/bar");
    expect(sqlNormalize031(input)).toBe("https://github.com/foo/bar");
    // Idempotent: re-normalizing the output is a fixpoint on both sides.
    const tsOnce = normalizeRepoUrl(input);
    expect(normalizeRepoUrl(tsOnce)).toBe(tsOnce);
    expect(sqlNormalize031(sqlNormalize031(input))).toBe(sqlNormalize031(input));
  });
});

// AC7 — the webhook delivers `repository.full_name` as a BARE owner/repo
// slug, NOT a URL. The reconcile MUST compose `https://github.com/${slug}`
// BEFORE normalizing, or the match against the stored repo_url (a URL)
// is zero-rows while a URL→URL parity test passes green. These fixtures
// pin the compose-before-normalize contract.
const SLUG_FIXTURES: ReadonlyArray<[fullName: string, storedUrl: string]> = [
  ["foo/bar", "https://github.com/foo/bar"],
  ["Owner/Repo", "https://github.com/Owner/Repo"],
  ["Anthropic-Labs/Foo", "https://github.com/Anthropic-Labs/Foo.git"],
  ["foo/bar", "https://github.com/foo/bar.git"],
];

describe("normalizeRepoUrl slug→URL parity — webhook compose-before-normalize (AC7)", () => {
  test("bare slug does NOT parse as a URL — composing is mandatory", () => {
    // Direct normalization of a bare slug leaves it slug-shaped (TS) or
    // skips it (SQL) — it can never equal the stored https:// URL. This
    // is the silent zero-match the compose step prevents.
    expect(normalizeRepoUrl("foo/bar")).not.toBe("https://github.com/foo/bar");
    expect(sqlNormalize031("foo/bar")).toBe("foo/bar"); // 031 skip
  });

  test.each(SLUG_FIXTURES)(
    "composed https://github.com/%s normalizes to match stored %s",
    (fullName, storedUrl) => {
      const composed = `https://github.com/${fullName}`;
      const normalizedComposed = normalizeRepoUrl(composed);
      const normalizedStored = normalizeRepoUrl(storedUrl);
      // The reconcile match key: normalize(compose(full_name)) must equal
      // normalize(workspaces.repo_url) for the same repo.
      expect(normalizedComposed).toBe(normalizedStored);
      expect(normalizedComposed).not.toBe(""); // non-empty → non-zero match
      // SQL side agrees on the composed URL.
      expect(sqlNormalize031(composed)).toBe(normalizedComposed);
    },
  );
});
