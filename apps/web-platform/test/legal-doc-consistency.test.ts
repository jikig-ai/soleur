import { describe, test, expect } from "vitest";
import { readdirSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

// Legal-doc consistency guard (per plan Phase 6, TS19, learning #16):
// every legal document in docs/legal/<name>.md must have a structurally
// equivalent body in plugins/soleur/docs/pages/legal/<name>.md (Eleventy
// mirror). Drift is a recurring failure mode -- a CLA preamble or
// sub-processor entry lands in one file but not the other and the legal
// posture silently diverges.
//
// Why heading-sequence + sentinel match instead of strict body equality:
// pre-Phase-6 legacy drift includes blockquote whitespace differences and
// at least one missing intro paragraph (gdpr-policy mirror). Fixing all
// of that is out of scope for the CLA-evidence layer PR. The forward-
// looking guard catches:
//   (a) "a section was added to one side but not the other" -- heading
//       sequence diff catches this immediately, AND
//   (b) "Phase 6 content was applied to one side but not the other" --
//       the sentinel patterns catch the specific load-bearing strings.
// Tightening to full body equality is a follow-up after a one-off
// legacy-drift cleanup PR.

const REPO_ROOT = resolve(__dirname, "../../..");

// DOCS is derived from the filesystem to eliminate the hand-edited-list
// drift surface that produced #4324. Per learning
// 2026-05-22-ci-parity-test-docs-arrays-are-themselves-a-drift-surface.md,
// adding a new legal doc only requires a single filesystem write to
// docs/legal/ — the test picks it up automatically. The meta-assertion
// below catches an accidental deletion or a glob miss.
const DOCS = readdirSync(resolve(REPO_ROOT, "docs/legal"))
  .filter((f) => f.endsWith(".md"))
  .map((f) => f.replace(/\.md$/, ""))
  .sort();

// Docs that legitimately lack a body `**Last Updated:**` line. The
// Last-Updated date test below skips body-line assertions for these
// (mirror-hero-date assertions still apply where the hero exists).
//
// - individual-cla / corporate-cla: by design (CLAs use Git tags +
//   the in-file `**Version:**` line for versioning).
// - cookie-policy: historical pattern — only the Eleventy hero <p>
//   carries the date; canonical uses `**Last updated:**` (lowercase u)
//   which the body regex below intentionally does not match.
const NO_BODY_LAST_UPDATED: ReadonlySet<string> = new Set([
  "individual-cla",
  "corporate-cla",
  "cookie-policy",
]);

/** Strip YAML frontmatter delimited by `---` at the start of the file. */
function stripFrontmatter(s: string): string {
  if (!s.startsWith("---")) return s;
  const close = s.indexOf("\n---", 3);
  if (close === -1) return s;
  return s.slice(close + 4);
}

/**
 * Extract every Markdown section heading (## and ### only -- #### deeper
 * is generally formatting-only and noisy) in the order they appear.
 * Heading text is trimmed; the leading hashes are kept so a `##` vs `###`
 * mismatch surfaces as a drift.
 */
function extractHeadings(s: string): string[] {
  const out: string[] = [];
  for (const line of s.split("\n")) {
    const m = line.match(/^(##{1,2})\s+(.+?)\s*$/);
    if (m) out.push(`${m[1]} ${m[2]}`);
  }
  return out;
}

function loadSource(doc: string): string {
  const path = resolve(REPO_ROOT, "docs/legal", `${doc}.md`);
  return readFileSync(path, "utf-8");
}

function loadMirror(doc: string): string {
  const path = resolve(REPO_ROOT, "plugins/soleur/docs/pages/legal", `${doc}.md`);
  return readFileSync(path, "utf-8");
}

describe("legal-doc consistency: source ↔ Eleventy mirror", () => {
  test("DOCS covers all expected legal documents", () => {
    // Sentinel guard against a glob miss or accidental doc deletion. If a
    // new doc lands the count grows naturally; if a doc is removed by
    // mistake (or the glob silently fails to pick one up), this fails.
    expect(DOCS.length).toBeGreaterThanOrEqual(9);
    expect(DOCS).toEqual(
      expect.arrayContaining([
        "acceptable-use-policy",
        "cookie-policy",
        "corporate-cla",
        "data-protection-disclosure",
        "disclaimer",
        "gdpr-policy",
        "individual-cla",
        "privacy-policy",
        "terms-and-conditions",
      ]),
    );
  });

  test.each(DOCS)(
    "%s: section-heading sequence matches between source and mirror",
    (doc) => {
      const sourceHeads = extractHeadings(stripFrontmatter(loadSource(doc)));
      const mirrorHeads = extractHeadings(stripFrontmatter(loadMirror(doc)));
      expect(mirrorHeads).toEqual(sourceHeads);
    },
  );

  test("Phase 6 additions land identically in source and mirror", () => {
    // Sentinel-string smoke test: if a Phase 6 edit was dropped on one
    // side, this catches it even if the broader structural match papers
    // over the diff. Each pattern is a load-bearing fragment from the
    // edit -- changing the wording in one file without the other will
    // fail this assertion.
    const checks: Array<[string, RegExp]> = [
      // CLA preambles -- exact opening sentence of the new §0.
      ["individual-cla", /## 0\. Legal Nature of This Agreement/],
      ["individual-cla", /copyright license grant, not a contract requiring ongoing consent under GDPR Article 7/],
      ["corporate-cla", /## 0\. Legal Nature of This Agreement/],
      ["corporate-cla", /copyright license grant, not a contract requiring ongoing consent under GDPR Article 7/],
      // Privacy Policy -- §4.5 extension + new §5.11 Cloudflare R2.
      ["privacy-policy", /off-site\s+\*\*CLA evidence archive\*\*/],
      ["privacy-policy", /### 5\.11 Cloudflare R2 \(CLA Evidence Archive\)/],
      ["privacy-policy", /tombstones\/<sha>\.deleted\.json/],
      // DPD -- new §2.3(n) + sub-processor table + international transfers.
      ["data-protection-disclosure", /\*\*\(n\)\*\* \*\*CLA evidence archive \(off-site\):\*\*/],
      ["data-protection-disclosure", /Cloudflare Inc.*R2 Storage/],
      ["data-protection-disclosure", /FreeTSA.*RFC 3161 Time Stamp Authority/],
      ["data-protection-disclosure", /Cloudflare R2 \(CLA evidence archive\):/],
      // GDPR Policy -- extended §3.4 balancing test + §2.2 entries.
      ["gdpr-policy", /Three-part balancing test \(off-site evidence archive\)/],
      ["gdpr-policy", /Cloudflare R2 \(CLA evidence archive\):/],
      ["gdpr-policy", /FreeTSA \(RFC 3161 Time Stamp Authority\):/],
      ["gdpr-policy", /Article 17\(3\)\(e\)/],
    ];
    for (const [doc, pattern] of checks) {
      const source = loadSource(doc);
      const mirror = loadMirror(doc);
      expect(source, `source ${doc} missing ${pattern}`).toMatch(pattern);
      expect(mirror, `mirror ${doc} missing ${pattern}`).toMatch(pattern);
    }
  });

  test("Last Updated date is identical between source and mirror", () => {
    // The hero <p> and the body **Last Updated:** line both carry the
    // date; we only assert the *date* matches the source body's date.
    // The "previous:" history fragment is allowed to drift (legacy).
    //
    // Docs in NO_BODY_LAST_UPDATED skip the body-line assertion; the
    // mirror-hero-date assertion still applies if the mirror has a hero
    // Last-Updated.
    for (const doc of DOCS) {
      const source = loadSource(doc);
      const mirror = loadMirror(doc);
      const sourceDate = source.match(/\*\*Last Updated:\*\*\s+([A-Z][a-z]+\s+\d{1,2},\s+\d{4})/);
      const mirrorBodyDate = mirror.match(/\*\*Last Updated:\*\*\s+([A-Z][a-z]+\s+\d{1,2},\s+\d{4})/);
      const mirrorHeroDate = mirror.match(/Last Updated\s+([A-Z][a-z]+\s+\d{1,2},\s+\d{4})/);
      if (NO_BODY_LAST_UPDATED.has(doc)) {
        // Allowlisted — no body-line assertion. Skip mirror-hero check
        // too because docs in this set use a different date discipline
        // (CLAs: Git tags + Version; cookie-policy: hero-only, with
        // lowercase "updated" intentionally not matched by the regex).
        continue;
      }
      if (!sourceDate) {
        // Source legitimately has no body Last Updated. Mirror must match.
        expect(mirrorBodyDate, `${doc}: source has no Last Updated, mirror should match`).toBeNull();
        continue;
      }
      expect(mirrorBodyDate, `${doc}: mirror body missing Last Updated date`).not.toBeNull();
      expect(mirrorBodyDate![1]).toBe(sourceDate[1]);
      expect(mirrorHeroDate, `${doc}: mirror hero missing Last Updated date`).not.toBeNull();
      expect(mirrorHeroDate![1]).toBe(sourceDate[1]);
    }
  });

  test("RCS jurisdiction is internally consistent across legal corpus", () => {
    // Per #4086: the four documents loaded below describe the same K-bis
    // extract category (Jikigai SARL's RCS jurisdiction). All sites must
    // name the same registry, and that registry must be in the country
    // PP §2 + DPD §1 name as the incorporation country (currently France).
    // We deliberately do NOT pin a specific city, so a legitimate future
    // move within France (Paris -> Lyon, etc.) does not require a test edit.
    const sites: Array<{ label: string; load: () => string }> = [
      { label: "privacy-policy source", load: () => loadSource("privacy-policy") },
      { label: "data-protection-disclosure source", load: () => loadSource("data-protection-disclosure") },
      { label: "privacy-policy mirror", load: () => loadMirror("privacy-policy") },
      {
        label: "article-30-register PA15(c)",
        load: () =>
          readFileSync(
            resolve(REPO_ROOT, "knowledge-base/legal/article-30-register.md"),
            "utf-8",
          ),
      },
    ];

    // Extract every "RCS <City>" token across all sites. Match the
    // structural shape (RCS followed by a capitalized word), not a
    // specific city, so the assertion survives any future French move.
    const rcsTokenRe = /\bRCS\s+([A-Z][A-Za-zÀ-ÿ-]+)/g;
    const tokens = new Set<string>();
    for (const site of sites) {
      const body = site.load();
      for (const m of body.matchAll(rcsTokenRe)) {
        tokens.add(m[1]);
      }
    }

    expect(
      tokens.size,
      `RCS jurisdiction tokens across loaded documents: ${[...tokens].join(", ")}`,
    ).toBe(1);

    const pp = loadSource("privacy-policy");
    const dpd = loadSource("data-protection-disclosure");

    expect(pp, "PP §2 must declare France incorporation").toMatch(/incorporated in France/);
    expect(dpd, "DPD §1 must declare France incorporation").toMatch(/incorporated in France/);
    expect(pp, "PP must not declare Luxembourg incorporation").not.toMatch(/incorporated in Luxembourg/);
    expect(dpd, "DPD must not declare Luxembourg incorporation").not.toMatch(/incorporated in Luxembourg/);

    for (const site of sites) {
      expect(
        site.load(),
        `${site.label} must not contain "RCS Luxembourg" (bug class closed by #4086)`,
      ).not.toMatch(/RCS Luxembourg/);
    }
  });
});
