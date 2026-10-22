import { readFileSync } from "node:fs";
import path from "node:path";
import fc from "fast-check";
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
// SYNC-SITES REGISTRY. A change to the contract in lib/repo-url.ts must touch
// ALL of: lib/repo-url.ts, the ports below (sqlNormalize031 is the frozen
// historical oracle; sqlChain163/sqlBackfill163 mirror the live chain), the
// golden SQL fixture test/fixtures/sql/normalize-repo-url-163-golden.sql with
// PG_GOLDEN_163 regenerated from Postgres, and a NEW migration plus verify file
// (migration 163 is frozen once applied; a defect in it ships as 164, never an
// edit). Parity domain = URL-clean ASCII input. Out of domain (SQL cannot
// mirror, see OUT_OF_PARITY): D4 URL-parser effects (%20 path encoding,
// dot-segments, userinfo/port, numeric-host IPv4 canonicalization), D5 exotic
// Unicode whitespace, D6 rows that are not scheme://host.
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
  // PG trim() removes only U+0020 (JS trim() also removes tab, newline, ...).
  const trimmed = raw.replace(/^ +| +$/g, "");
  const schemeHost = trimmed.match(/^([^/]*\/\/[^/]+)/);
  if (!schemeHost) {
    // 031 WHERE guard skips this row → value unchanged.
    return raw;
  }
  // PG `.` matches newline; JS `.` does not.
  const rest = trimmed.match(/^[^/]*\/\/[^/]+(\/[\s\S]*)$/);
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


// ---------------------------------------------------------------------------
// Migration 163 (#10633): the corrected chain and the stored-row backfill.
// ---------------------------------------------------------------------------

const ASCII_WS_TRIM = /^[ \t\n\r\f\v]+|[ \t\n\r\f\v]+$/g;
const CLEAN_SHAPE =
  /^https?:\/\/([a-z0-9-]+[.])*[a-z][a-z0-9-]*(\/[A-Za-z0-9_~-][A-Za-z0-9._~-]*)*$/;

// JS port of the 163 canon-expr chain: ASCII-class trim, lowercase scheme+host,
// ONE tail strip over `/`, `.git` (any case) and ASCII whitespace in any
// interleaving, then null when no scheme+host remains.
function sqlChain163(raw: string): string | null {
  const t = raw.replace(ASCII_WS_TRIM, "");
  const schemeHost = t.match(/^([^/]*\/\/[^/]+)/);
  if (!schemeHost) return null;
  const rest = t.match(/^[^/]*\/\/[^/]+(\/[\s\S]*)$/);
  const canon = (schemeHost[1]!.toLowerCase() + (rest ? rest[1] : "")).replace(
    /(\/|\.git|[ \t\n\r\f\v])+$/i,
    "",
  );
  return /^[^/]*\/\/[^/]+/.test(canon) ? canon : null;
}

// What the migration writes: the chain, but only for rows where SQL provably
// equals normalizeRepoUrl (no internal whitespace, at most 2048 characters, a
// clean http(s) shape). Everything else is left exactly as stored.
function sqlBackfill163(raw: string): string {
  const canon = sqlChain163(raw);
  if (canon === null) return raw;
  const t = raw.replace(ASCII_WS_TRIM, "");
  if (/[ \t\n\r\f\v]/.test(t)) return raw;
  if (Array.from(t).length > 2048) return raw;
  return CLEAN_SHAPE.test(canon) ? canon : raw;
}

// PG_GOLDEN_163: produced by POSTGRES, not by the ports. Regenerate with the
// recipe in test/fixtures/sql/normalize-repo-url-163-golden.sql (dev, SELECT
// only) and paste the output; never fill it from the JS ports above.
const PG_GOLDEN_163: ReadonlyArray<readonly [raw: string, pg031: string | null, pg163Chain: string | null, pg163Backfill: string | null]> = [
  ["http://a.aa .git", "http://a.aa ", "http://a.aa", "http://a.aa .git"],
  ["http://a.aa /", "http://a.aa ", "http://a.aa", "http://a.aa /"],
  ["a://A .git", "a://a ", "a://a", "a://A .git"],
  ["http://a.aa\t.git", "http://a.aa\t", "http://a.aa", "http://a.aa\t.git"],
  ["http://a.aa/\n.git/", "http://a.aa/\n", "http://a.aa", "http://a.aa/\n.git/"],
  ["https://github.com/foo/bar/.git/.git", "https://github.com/foo/bar/.git", "https://github.com/foo/bar", "https://github.com/foo/bar"],
  ["https://github.com/foo/bar.GIT\t/", "https://github.com/foo/bar.GIT\t", "https://github.com/foo/bar", "https://github.com/foo/bar.GIT\t/"],
  ["\thttps://github.com/foo/bar\n", "\thttps://github.com/foo/bar\n", "https://github.com/foo/bar", "https://github.com/foo/bar"],
  ["https://x/y .git", "https://x/y ", "https://x/y", "https://x/y .git"],
  ["http://a.aa/ \n.git/ ", "http://a.aa/ \n", "http://a.aa", "http://a.aa/ \n.git/ "],
  ["http://a.aa/./x", "http://a.aa/./x", "http://a.aa/./x", "http://a.aa/./x"],
  ["http://a.aa:80/x", "http://a.aa:80/x", "http://a.aa:80/x", "http://a.aa:80/x"],
  ["http://.git", "http:", null, "http://.git"],
  ["http://a.aa ", "http://a.aa", "http://a.aa", "http://a.aa"],
  ["https://github.com/Foo/Bar/ ", "https://github.com/Foo/Bar", "https://github.com/Foo/Bar", "https://github.com/Foo/Bar"],
  ["HTTPS://GitHub.com/foo/bar.git/", "https://github.com/foo/bar", "https://github.com/foo/bar", "https://github.com/foo/bar"],
  ["https://github.com/o .git", "https://github.com/o ", "https://github.com/o", "https://github.com/o .git"],
  ["https://u:p@Host/x", "https://u:p@host/x", "https://u:p@host/x", "https://u:p@Host/x"],
  ["https://0/x", "https://0/x", "https://0/x", "https://0/x"],
  ["a://A", "a://a", "a://a", "a://A"],
  ["https://github.com/Owner/Repo", "https://github.com/Owner/Repo", "https://github.com/Owner/Repo", "https://github.com/Owner/Repo"],
  ["foo/bar", "foo/bar", null, "foo/bar"],
];

const GOLDEN_SCRIPT = readFileSync(
  path.resolve(__dirname, "fixtures/sql/normalize-repo-url-163-golden.sql"),
  "utf8",
);
const golden = new Map(PG_GOLDEN_163.map((r) => [r[0], r] as const));

// Shielded whitespace: a strip exposes whitespace it was shielding. A space
// shield is admitted in HOST position only (a space after a path segment is
// `%20` in TS, so it is out of the parity domain).
const SHIELDED_WS_FIXTURES: ReadonlyArray<[raw: string, expected: string]> = [
  ["http://a.aa .git", "http://a.aa"],
  ["http://a.aa /", "http://a.aa"],
  ["a://A .git", "a://a"],
  ["http://a.aa\t.git", "http://a.aa"],
  ["http://a.aa/\n.git/", "http://a.aa"],
  ["https://github.com/foo/bar/.git/.git", "https://github.com/foo/bar"],
  ["https://github.com/foo/bar.GIT\t/", "https://github.com/foo/bar"],
  ["\thttps://github.com/foo/bar\n", "https://github.com/foo/bar"],
];

// Where migration 031's chain differs from the TS contract (D1, D2, D3).
const D031_DEFECTS: ReadonlyArray<[label: string, raw: string]> = [
  ["D1 no re-trim", "http://a.aa .git"],
  ["D2 not interleaving-complete", "https://github.com/foo/bar/.git/.git"],
  ["D3 space-only trim", "\thttps://github.com/foo/bar\n"],
];

// What the backfill does to a stored value. 031-shaped stored forms are
// rewritten to the TS form; everything the eligibility guard rejects is left
// untouched (the setup route's write boundary keeps these shapes out in practice).
const BACKFILL_FIXTURES: ReadonlyArray<[raw: string, written: string]> = [
  ["http://a.aa ", "http://a.aa"],
  ["https://github.com/Foo/Bar/ ", "https://github.com/Foo/Bar"],
  ["HTTPS://GitHub.com/foo/bar.git/", "https://github.com/foo/bar"],
  ["https://github.com/Owner/Repo", "https://github.com/Owner/Repo"],
  ["https://github.com/o .git", "https://github.com/o .git"],
  ["http://a.aa .git", "http://a.aa .git"],
  ["https://u:p@Host/x", "https://u:p@Host/x"],
  ["http://a.aa:80/x", "http://a.aa:80/x"],
  ["http://a.aa/./x", "http://a.aa/./x"],
  ["https://0/x", "https://0/x"],
  ["http://.git", "http://.git"],
  ["a://A", "a://A"],
];

// Inputs where TS and the 163 chain legitimately differ, pinning BOTH sides.
const OUT_OF_PARITY: ReadonlyArray<[raw: string, ts: string, sql: string | null]> = [
  ["https://x/y .git", "https://x/y%20", "https://x/y"],
  ["http://a.aa/ \n.git/ ", "http://a.aa/%20", "http://a.aa"],
  ["http://a.aa/./x", "http://a.aa/x", "http://a.aa/./x"],
  ["http://a.aa:80/x", "http://a.aa/x", "http://a.aa:80/x"],
  ["http://.git", "http:", null],
];

describe("163 golden table (Postgres is the oracle for the ports)", () => {
  test("every fixture raw appears in PG_GOLDEN_163", () => {
    const raws = [
      ...SHIELDED_WS_FIXTURES.map((f) => f[0]),
      ...D031_DEFECTS.map((f) => f[1]),
      ...BACKFILL_FIXTURES.map((f) => f[0]),
      ...OUT_OF_PARITY.map((f) => f[0]),
    ];
    for (const raw of raws) expect(golden.has(raw), JSON.stringify(raw)).toBe(true);
  });

  test("the table has exactly the rows the generator script declares", () => {
    const block = GOLDEN_SCRIPT.split("-- golden-rows begin")[1]!.split("-- golden-rows end")[0]!;
    const declared = block.split("\n").filter((l) => /^\s*\(.*\),?\s*$/.test(l)).length;
    expect(declared).toBeGreaterThan(0);
    expect(PG_GOLDEN_163.length).toBe(declared);
  });

  test.each(PG_GOLDEN_163.map((r) => [JSON.stringify(r[0]), r] as const))(
    "ports equal Postgres for %s",
    (_label, [raw, pg031, pg163Chain, pg163Backfill]) => {
      expect(sqlNormalize031(raw)).toBe(pg031);
      expect(sqlChain163(raw)).toBe(pg163Chain);
      expect(sqlBackfill163(raw)).toBe(pg163Backfill);
    },
  );
});

describe("normalizeRepoUrl TS ↔ SQL(163) chain parity — shielded whitespace (#10633)", () => {
  test("fixture list floor", () => {
    expect(SHIELDED_WS_FIXTURES.length).toBeGreaterThanOrEqual(8);
  });

  test.each(SHIELDED_WS_FIXTURES.map((f) => [JSON.stringify(f[0]), ...f] as const))(
    "TS, SQL(163) and expected agree on %s",
    (_label, raw, expected) => {
      expect(normalizeRepoUrl(raw)).toBe(expected);
      expect(sqlChain163(raw)).toBe(expected);
    },
  );

  test.each(D031_DEFECTS.map((f) => [f[0], f[1]] as const))(
    "the frozen 031 chain differs from the contract: %s",
    (_label, raw) => {
      expect(sqlNormalize031(raw)).not.toBe(normalizeRepoUrl(raw));
      expect(sqlChain163(raw)).toBe(normalizeRepoUrl(raw));
    },
  );
});

describe("163 backfill — what a stored row becomes", () => {
  test("fixture list floor", () => {
    expect(BACKFILL_FIXTURES.length).toBeGreaterThanOrEqual(8);
  });

  test.each(BACKFILL_FIXTURES.map((f) => [JSON.stringify(f[0]), ...f] as const))(
    "%s",
    (_label, raw, written) => {
      expect(sqlBackfill163(raw)).toBe(written);
      // The written value is what the TS normalizer would produce for the old
      // one whenever the row changes (readers compare against the TS output).
      if (written !== raw) expect(written).toBe(normalizeRepoUrl(raw));
    },
  );

  test("re-running the backfill on its own output changes nothing", () => {
    for (const [raw] of BACKFILL_FIXTURES) {
      const once = sqlBackfill163(raw);
      expect(sqlBackfill163(once)).toBe(once);
    }
  });
});

describe("OUT_OF_PARITY — the documented gap, pinned on both sides", () => {
  test.each(OUT_OF_PARITY.map((f) => [JSON.stringify(f[0]), ...f] as const))(
    "%s",
    (_label, raw, ts, sql) => {
      expect(normalizeRepoUrl(raw)).toBe(ts);
      expect(sqlChain163(raw)).toBe(sql);
      expect(ts).not.toBe(sql);
    },
  );
});

describe("TS ↔ SQL(163) parity and backfill safety (property)", () => {
  const letterLabel = fc
    .tuple(
      fc.constantFrom(..."abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ".split("")),
      fc.string({ unit: fc.constantFrom(..."abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".split("")), maxLength: 5 }),
    )
    .map(([a, b]) => a + b);
  const hostArb = fc.array(letterLabel, { minLength: 1, maxLength: 3 }).map((l) => l.join("."));
  const segArb = fc.string({
    unit: fc.constantFrom(..."abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-".split("")),
    minLength: 1,
    maxLength: 6,
  });
  const tailArb = fc.constantFrom("", "/", ".git", ".GIT", ".git.git/", "/.git/.git", "\t.git", "\n/");
  const shieldArb = fc.constantFrom(" .git", " /", " .git/ ");
  const padArb = fc.constantFrom("", " ", "\t", "\n");

  // Host-position shields only exist with zero path segments.
  const urlCleanArb = fc
    .tuple(
      fc.constantFrom("https", "http", "HTTPS"),
      hostArb,
      fc.array(segArb, { maxLength: 3 }),
      tailArb,
      shieldArb,
      padArb,
      padArb,
    )
    .map(([scheme, host, segs, tail, shield, lead, trail]) => {
      const body = `${scheme}://${host}${segs.map((s) => "/" + s).join("")}`;
      return lead + body + (segs.length === 0 ? shield : tail) + trail;
    });

  test("P1: TS equals the 163 chain on URL-clean input", () => {
    fc.assert(
      fc.property(urlCleanArb, (x) => {
        expect(sqlChain163(x)).toBe(normalizeRepoUrl(x));
      }),
    );
  });

  // Adversarial pieces for the safety property: everything the URL parser or the
  // eligibility guard treats specially.
  const pieceArb = fc.constantFrom(
    "%20", "%2e", "/./", "/..", ":80", "@", "?q=A", "#F", "//", ".git", " ", "\n", "\t",
    "/", "x", "A", "0", ".", "-", "https://", "http://", "a://", "ftp://",
  );
  const adversarialArb = fc.oneof(
    fc.array(pieceArb, { maxLength: 8 }).map((p) => p.join("")),
    fc.string({ maxLength: 20 }),
    fc.tuple(fc.constantFrom("https://", "http://"), fc.array(pieceArb, { maxLength: 6 })).map(([h, p]) => h + "h" + p.join("")),
    fc.integer({ min: 2040, max: 2056 }).map((n) => "https://h.io/" + "a".repeat(Math.max(0, n - 13)) + " "),
  );

  test("P2: the backfill only writes what normalizeRepoUrl would return", () => {
    fc.assert(
      fc.property(adversarialArb, (x) => {
        const written = sqlBackfill163(x);
        if (written !== x) expect(written).toBe(normalizeRepoUrl(x));
        expect(sqlBackfill163(written)).toBe(written);
      }),
    );
  });

  test("negative control: a backfill without the eligibility guard breaks P2", () => {
    const unguarded = (x: string) => sqlChain163(x) ?? x;
    const counterexamples = ["https://github.com/o .git", "https://u:p@Host/x", "http://a.aa:80/x"];
    const broken = counterexamples.filter((x) => {
      const w = unguarded(x);
      return w !== x && w !== normalizeRepoUrl(x);
    });
    expect(broken.length).toBeGreaterThan(0);
  });
});
