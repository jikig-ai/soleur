/**
 * GitHub API egress URL guard tests (CodeQL js/request-forgery, alert #234)
 *
 * Pins the contract of server/github-url.ts — every credential-bearing GitHub
 * API request must resolve to https://api.github.com and only there — plus the
 * egress census: a per-site first-arg rule over the guarded modules, an
 * open-world membership sweep over every file that can carry a GitHub
 * credential to `fetch(`, and the octokit lane's literal-route convention.
 */
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { describe, test, expect } from "vitest";

import {
  githubApiUrl,
  assertGithubApiAbsoluteUrl,
} from "../server/github-url";

describe("githubApiUrl", () => {
  describe("rejects a path that could rebind the request authority", () => {
    test.each([
      ["@evil.example/x", "no leading slash — @ rebinds userinfo/host"],
      [".evil.example", "no leading slash — suffix-joins the host"],
      ["evil.example/x", "no leading slash"],
      ["//evil.example/x", "scheme-relative — rebinds host entirely"],
    ])("rejects %j (%s)", (path) => {
      expect(() => githubApiUrl(path)).toThrow(/egress denied/);
    });
  });

  describe("rejects dot-segments the URL parser would resolve silently", () => {
    test.each([
      "/repos/o/" + "../".repeat(2) + "x", // spelled via repeat: the repo-wide scanner counts `..` runs in source text
      "/a/%2e%2e/b",
      "/a/.%2E/b",
      "/a/%2E./b",
      "/a/..?state=open",
      "/a/./b",
    ])("rejects %j", (path) => {
      expect(() => githubApiUrl(path)).toThrow(/egress denied/);
    });
  });

  describe("rejects structurally unsafe path bytes", () => {
    test.each([
      ["/repos/o/r/x\\..", "backslash folds to / under WHATWG"],
      ["/repos/o/r#frag", "fragment truncates the path"],
      ["/a/\x01b", "control character"],
      ["/a/\u2028b", "unicode line separator"],
      ["", "empty"],
      [`/${"a".repeat(4097)}`, "over-length"],
    ])("rejects %j (%s)", (path) => {
      expect(() => githubApiUrl(path)).toThrow(/egress denied/);
    });
  });

  describe("accepts every current call-site path shape", () => {
    test.each([
      "/repos/o/r/issues",
      "/graphql",
      "/repos/o/r/issues?state=open&per_page=50",
      "/repos/o/r/git/ref/heads/feat/x",
      "/app/installations/12345",
      "/orgs/some-org/members/some-login",
    ])("accepts %j", (path) => {
      expect(githubApiUrl(path)).toBe(`https://api.github.com${path}`);
    });
  });
});

describe("assertGithubApiAbsoluteUrl", () => {
  test.each([
    "https://evil.example/x",
    "https://api.github.com@evil.example/x",
    "https://api.github.com.evil.example/x",
    "http://api.github.com/x",
    "https://api.github.com:444/x",
    "https://user:pw@api.github.com/x",
    "https://api.github.com/a/../b",
    "https://api.github.com/a/%2e%2e/b",
    "https://api.github.com./x",
    "https://api.github.com/" + "x".repeat(4097),
    "not a url",
  ])("rejects %j", (url) => {
    expect(() => assertGithubApiAbsoluteUrl(url)).toThrow(/egress denied/);
  });

  test("refusals carry the pinned error code taxonomy", () => {
    let caught: unknown;
    try {
      assertGithubApiAbsoluteUrl("https://evil.example/x");
    } catch (err) {
      caught = err;
    }
    expect(caught).toMatchObject({ code: "github_api_egress_denied" });
  });

  test.each([
    "https://api.github.com/repos/o/r",
    "https://api.github.com/app/installations?per_page=100",
    "https://api.github.com/app",
    "https://api.github.com/" + "x".repeat(4096 - "https://api.github.com/".length),
  ])("accepts %j", (url) => {
    expect(assertGithubApiAbsoluteUrl(url)).toBe(url);
  });
});

// ---------------------------------------------------------------------------
// Egress census — lexical tripwire over every file where a GitHub credential
// can reach `fetch(`. Two layers:
//
// 1. Per-site first-arg rule (census files only): `url` (bound to a guard call
//    earlier in the same file — provenance, not just the name), an inline
//    `githubEgressUrl(`/`assertGithubApiAbsoluteUrl(`, or the one named
//    compile-time literal. Deleting a chokepoint assert or adding a raw
//    `${GITHUB_API}` site fails the census.
// 2. Membership sweep (open world): any file in server/ + app/ that can carry
//    a GitHub credential to `fetch(` — matched on the URL literal, the
//    GITHUB_API const, token-mint symbols, or this module's exports — must be
//    in GUARDED_FILES or a named bucket below. A NEW file fails until
//    categorized — the point of the gate.
//
// Residual lexical limits (acknowledged, fail-closed): aliasing
// (`const f = fetch`), `fetch.call/bind`, and a shadowed `fetch`/`url` naming
// convention evade or satisfy the recognizers — the runtime asserts are the
// control; this census is the tripwire.
// ---------------------------------------------------------------------------

const APP_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
// `(?<!\w)` excludes `mockFetch(`/`fetchWithRetry(` (no paren after `fetch`)
// but still sees member access like `globalThis.fetch(` — a member-access
// site is a real egress and must satisfy the first-arg rule too.
const FETCH_SITE = /(?<!\w)fetch\s*\(/g;
const NAMED_EXEMPTION = "`https://api.github.com/app`";

// A `//` that is not part of `://` starts a line comment — a `fetch(` inside
// one is prose, not a call site, and comment text inside a fetch's argument
// list is not part of its first argument.
const LINE_COMMENT = /(^|[^:])\/\/.*$/;

function isCommentSite(src: string, index: number): boolean {
  const lineStart = src.lastIndexOf("\n", index) + 1;
  if (LINE_COMMENT.test(src.slice(lineStart, index))) return true;
  // Inside an unclosed `/* */` block comment (docblocks contain `fetch(` and
  // `octokit.request()` prose — count delimiters before the site).
  const before = src.slice(0, index);
  const opens = before.split("/*").length - 1;
  const closes = before.split("*/").length - 1;
  return opens > closes;
}

interface FetchSite {
  head: string;
  index: number;
}

function fetchSites(rel: string): { src: string; sites: FetchSite[] } {
  const src = readFileSync(join(APP_ROOT, rel), "utf8");
  const sites = [...src.matchAll(FETCH_SITE)]
    .filter((m) => !isCommentSite(src, m.index))
    .map((m) => ({
      index: m.index,
      head: src
        .slice(m.index + m[0].length, m.index + m[0].length + 400)
        .split("\n")
        .map((line) => line.replace(LINE_COMMENT, "$1"))
        .join("\n")
        .trimStart(),
    }));
  return { src, sites };
}

// Files whose `fetch(` sites must satisfy the first-arg rule (per-site counts
// pinned — a new site in one of these files fails the count).
const GUARDED_FILES: Array<[string, number]> = [
  ["server/github-api.ts", 2],
  ["server/github-app.ts", 2],
  ["server/release-notes.ts", 1],
  ["server/inngest/functions/cron-weekly-release-digest.ts", 1],
];

// Files allowed to contain `fetch(` + a GitHub credential signal without
// entering the guard — each must still be a named category, not an omission.
const SANCTIONED_OTHER_FILES: Record<string, string> = {
  // User-OAuth token + OAuth client_secret (Basic) — different credential
  // class than the App JWT / installation token this guard pins.
  "app/api/auth/github-resolve/callback/route.ts": "user-OAuth lane",
  // Validates a user-supplied PAT against /user — the user's own credential.
  "server/token-validators.ts": "user-supplied PAT validation",
  // Allowlist-bounded probe fetches — no credential attached.
  "server/inngest/functions/_predicate-validator.ts": "unauthenticated probe",
};

// These files carry a GitHub-credential signal (a token mint) alongside a
// `fetch(` — but the minted token exits via the Octokit or git/subprocess
// lanes (out of assembly, see plan › attack-surface table) and the `fetch(`
// sites in them target other vendors.
const MINT_BUT_OTHER_LANE_FILES = [
  "server/inngest/functions/cron-bug-fixer.ts",
  "server/inngest/functions/cron-gh-pages-cert-reissue.ts",
  "server/inngest/functions/cron-github-app-drift-guard.ts",
  "server/inngest/functions/cron-linkedin-token-check.ts",
  "server/inngest/functions/cron-membership-health.ts",
  "server/inngest/functions/_cron-shared.ts",
  "server/inngest/functions/cron-ux-audit.ts",
  "server/inngest/functions/event-cf-token-expiry-check.ts",
  "server/inngest/functions/event-scheduled-reminder.ts",
  "server/inngest/functions/oneshot-gdpr-gate-50d-eval.ts",
];

// A file "can carry a GitHub credential to fetch(" when it contains a fetch
// site AND any GitHub-API signal: the literal origin, the GITHUB_API const,
// a token-mint symbol, or a guard export.
const GH_CREDENTIAL_SIGNAL =
  /api\.github\.com|GITHUB_API|generateInstallationToken|mintInstallationToken|createAppJwt|githubEgressUrl|assertGithubApiAbsoluteUrl|githubApiUrl|githubFetch|getInstallationOctokit/;

const SCAN_DIRS = ["server", "app"];

function listTsFiles(dir: string): string[] {
  const out: string[] = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, entry.name);
    if (entry.isDirectory()) out.push(...listTsFiles(p));
    else if (entry.name.endsWith(".ts")) out.push(p);
  }
  return out;
}

describe("GitHub API egress census", () => {
  test.each(GUARDED_FILES)("%s: all %i fetch sites take a guarded url", (rel, expectedCount) => {
    const { src, sites } = fetchSites(rel);
    expect(sites.length).toBe(expectedCount);
    for (const { head, index } of sites) {
      let guarded: boolean;
      if (/^url\s*[,)]/.test(head)) {
        // Provenance, not just the name: the file must contain a guard call
        // on `url` BEFORE this fetch site — deleting the chokepoint assert
        // fails here even though the fetch line is unchanged.
        guarded = /(?:githubEgressUrl|assertGithubApiAbsoluteUrl)\(url\b/.test(
          src.slice(0, index),
        );
      } else if (
        head.startsWith("githubEgressUrl(") ||
        head.startsWith("assertGithubApiAbsoluteUrl(")
      ) {
        // The call must BE the whole first argument — a suffix concat
        // (`githubEgressUrl(url) + x`) is unguarded output.
        guarded =
          /^(?:githubEgressUrl|assertGithubApiAbsoluteUrl)\([^)]*\)\s*[,)]/.test(
            head,
          );
      } else if (head.startsWith(NAMED_EXEMPTION)) {
        // The exemption is the whole literal — `…/app` + suffix` must fail:
        // what follows the literal must end the first argument.
        guarded = /^\s*[,)]/.test(head.slice(NAMED_EXEMPTION.length));
      } else {
        guarded = false;
      }
      expect(
        guarded,
        `${rel} fetch() first arg ${JSON.stringify(head.slice(0, 60))}`,
      ).toBe(true);
    }
  });

  test("membership sweep: every file able to carry a GitHub credential to fetch( is categorized", () => {
    const sanctioned = new Set([
      ...GUARDED_FILES.map(([rel]) => rel),
      ...Object.keys(SANCTIONED_OTHER_FILES),
      ...MINT_BUT_OTHER_LANE_FILES,
    ]);
    const offenders: string[] = [];
    for (const dir of SCAN_DIRS) {
      for (const rel of listTsFiles(join(APP_ROOT, dir))) {
        const normalized = rel.slice(APP_ROOT.length + 1);
        const src = readFileSync(rel, "utf8");
        const hasFetch = FETCH_SITE.test(src);
        FETCH_SITE.lastIndex = 0;
        if (!hasFetch || !GH_CREDENTIAL_SIGNAL.test(src)) continue;
        if (!sanctioned.has(normalized)) offenders.push(normalized);
      }
    }
    expect(
      offenders,
      "uncategorized file(s) carrying a GitHub-credential signal next to fetch( — add to GUARDED_FILES or a named bucket",
    ).toEqual([]);
  });

  test("membership sweep: sanctioned files still exist and still match their signal", () => {
    const all = new Set([
      ...Object.keys(SANCTIONED_OTHER_FILES),
      ...MINT_BUT_OTHER_LANE_FILES,
    ]);
    const stale: string[] = [];
    for (const rel of all) {
      const full = join(APP_ROOT, rel);
      if (!existsSync(full)) {
        stale.push(`${rel} (missing)`);
        continue;
      }
      const src = readFileSync(full, "utf8");
      const hasFetch = FETCH_SITE.test(src);
      FETCH_SITE.lastIndex = 0;
      if (!hasFetch || !GH_CREDENTIAL_SIGNAL.test(src)) {
        stale.push(`${rel} (no longer matches — remove from the census)`);
      }
    }
    expect(stale).toEqual([]);
  });

  // Octokit is out-of-assembly by convention: every octokit.request call site
  // must pass a "VERB /route" literal template (endpoint params are
  // percent-encoded inside the SDK). A full-URL or non-literal first arg
  // would attach the credential to caller-controlled egress.
  test("octokit lane: every octokit.request( takes a literal route template", () => {
    const OKTOKIT_SITE = /(?<!\w)octokit\.request\(\s*/g;
    const offenders: string[] = [];
    for (const dir of SCAN_DIRS) {
      for (const rel of listTsFiles(join(APP_ROOT, dir))) {
        const src = readFileSync(rel, "utf8");
        for (const m of src.matchAll(OKTOKIT_SITE)) {
          if (isCommentSite(src, m.index)) continue;
          const head = src.slice(m.index + m[0].length, m.index + m[0].length + 40).trimStart();
          if (head.startsWith('"')) continue;
          // undo/route.ts:278 binds `route` to a ternary of two literal
          // templates — pinned here so the exemption can't widen silently.
          if (
            rel.endsWith("undo/route.ts") &&
            head.startsWith("route") &&
            /const route =\s*\n?\s*handle\.kind === "pr_review_comment"/.test(src)
          ) {
            continue;
          }
          offenders.push(`${rel} @${m.index}: ${JSON.stringify(head.slice(0, 40))}`);
        }
      }
    }
    expect(offenders).toEqual([]);
  });
});
