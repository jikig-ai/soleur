import { describe, test, expect } from "vitest";
import { readFileSync } from "node:fs";
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

// Phase 6 touches these five docs in both source and mirror. Other legal
// docs (cookie-policy, disclaimer, etc.) are out of scope for this PR;
// adding them later is a one-line extension here.
const DOCS = [
  "individual-cla",
  "corporate-cla",
  "privacy-policy",
  "data-protection-disclosure",
  "gdpr-policy",
] as const;

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
    for (const doc of DOCS) {
      const source = loadSource(doc);
      const mirror = loadMirror(doc);
      const sourceDate = source.match(/\*\*Last Updated:\*\*\s+([A-Z][a-z]+\s+\d{1,2},\s+\d{4})/);
      const mirrorBodyDate = mirror.match(/\*\*Last Updated:\*\*\s+([A-Z][a-z]+\s+\d{1,2},\s+\d{4})/);
      const mirrorHeroDate = mirror.match(/Last Updated\s+([A-Z][a-z]+\s+\d{1,2},\s+\d{4})/);
      // The CLA docs have no Last Updated -- skip them.
      if (!sourceDate) {
        expect(mirrorBodyDate, `${doc}: source has no Last Updated, mirror should match`).toBeNull();
        continue;
      }
      expect(mirrorBodyDate, `${doc}: mirror body missing Last Updated date`).not.toBeNull();
      expect(mirrorBodyDate![1]).toBe(sourceDate[1]);
      expect(mirrorHeroDate, `${doc}: mirror hero missing Last Updated date`).not.toBeNull();
      expect(mirrorHeroDate![1]).toBe(sourceDate[1]);
    }
  });
});
