/**
 * #12197 / #12011: structural checks on the first committed legal text, `founder-acceptance-record`.
 *
 * DRAFT, HELD for counsel sign-off (PR #12342). These checks assert shape and the numbers the text states, never the
 * wording, and they pin NO sha256 literal: the retention placeholder is replaced at sign-off, which changes the bytes, so a
 * hash pinned now would be rewritten once for nothing (the sign-off PR adds the published `{version: sha256}` pin and bumps
 * `version` if the bytes change after a first merge).
 *
 * MERGE GUARD (the last describe): while counsel's sign-off is pending, a CI run is RED. A ready or merge_group run sets
 * `CI`, so an accidental ready or merge of the held draft is blocked. It fails on any placeholder-shaped token in the text
 * body AND in the card notice that shows the same retention period. Under the draft-light CI the webplat shard (and so this
 * guard) is skipped and the `test` aggregator is red by design (ADR-276); a local run is green.
 * Only counsel's sign-off PR may delete or edit the guard: nobody else "fixes" a red run by editing the text, the guard,
 * the placeholder pattern or the skip condition.
 */
import { mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { afterAll, describe, expect, it } from "vitest";
import { KEY_RE, TEXTS_DIR, getLegalText, loadLegalTexts } from "@/server/legal-acceptance/canonical";
import { LEGAL_COPY } from "@/lib/legal-acceptance-copy";
import { REQUEST_CHANGES_MAX } from "@/lib/legal-acceptance-wire";
import { FORBIDDEN_CLAIMS } from "./forbidden-claims";

const KEY = "founder-acceptance-record";
const M184 = readFileSync(path.join(__dirname, "../../supabase/migrations/184_legal_acceptance.sql"), "utf8");

/** Anything that reads as an unfinished retention period or other open item. Not a wording check: a draft-state detector. */
const PLACEHOLDER =
  /\[[^\]]*\]|\b(?:TBD|TBC|TODO)\b|\bX{2,}\b|_{3,}|to be (?:confirmed|decided|determined)|\bcounsel\b/gi;
/** Every placeholder-shaped token in a text (empty when finished). */
const placeholdersIn = (text: string): string[] => [...text.matchAll(PLACEHOLDER)].map((m) => m[0]);

const scratch: string[] = [];
afterAll(() => {
  for (const d of scratch) rmSync(d, { recursive: true, force: true });
});

/** Raw-byte problems in every committed text the loader would load: a CR, a BOM, any control or non-ASCII byte. One string per problem. */
function auditDir(dir: string): string[] {
  const out: string[] = [];
  const files = readdirSync(dir).filter((f) => f.endsWith(".md") && KEY_RE.test(f.slice(0, -3)));
  if (files.length === 0) out.push("no committed text found");
  for (const f of files) {
    const bytes = readFileSync(path.join(dir, f));
    if (bytes.includes(0x0d)) out.push(`${f}: carries a CR`);
    if (bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) out.push(`${f}: starts with a BOM`);
    const bad = bytes.findIndex((b) => b !== 0x0a && (b < 0x20 || b > 0x7e));
    if (bad >= 0) out.push(`${f}: control or non-ASCII byte 0x${bytes[bad].toString(16)} at offset ${bad}`);
  }
  return out;
}

describe("founder-acceptance-record: the committed bytes", () => {
  it("every committed text is LF-only printable ASCII with no BOM, and the directory is not empty", () => {
    expect.hasAssertions();
    expect(auditDir(TEXTS_DIR)).toEqual([]);
  });

  it("the audit bites: a CR, a non-ASCII byte, a BOM, DEL, NUL and an empty directory are each detected, a clean file is not", () => {
    expect.hasAssertions();
    const d = mkdtempSync(path.join(tmpdir(), "far-audit-"));
    scratch.push(d);
    expect(auditDir(d)).toEqual(["no committed text found"]);
    writeFileSync(path.join(d, "a.md"), "---\nversion: 1\n---\nline\r\n");
    writeFileSync(path.join(d, "b.md"), "café\n");
    writeFileSync(path.join(d, "c.md"), Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from("x\n")]));
    writeFileSync(path.join(d, "d.md"), "x\x7f\n");
    writeFileSync(path.join(d, "e.md"), "x\x00y\n");
    writeFileSync(path.join(d, "NOTES.md"), "not a key: café\n"); // uppercase: the loader skips it, so the audit does too
    const found = auditDir(d).join("\n");
    expect(found).toContain("a.md: carries a CR");
    expect(found).toMatch(/b\.md: control or non-ASCII byte 0xc3 at offset 3/);
    expect(found).toContain("c.md: starts with a BOM");
    expect(found).toMatch(/d\.md: control or non-ASCII byte 0x7f/);
    expect(found).toMatch(/e\.md: control or non-ASCII byte 0x0 at offset 1/);
    expect(found).not.toContain("NOTES.md");
    const clean = path.join(d, "clean");
    mkdirSync(clean);
    writeFileSync(path.join(clean, "ok.md"), "---\nversion: 1\n---\nplain\n");
    expect(auditDir(clean)).toEqual([]);
  });
});

describe("founder-acceptance-record: what the loader sees", () => {
  it("loads under the key, with a real date version and no expiry", () => {
    expect.hasAssertions();
    const entry = getLegalText(KEY);
    expect(entry.key).toBe(KEY);
    expect(entry.version).toMatch(/^\d{4}-\d{2}-\d{2}$/); // the shape, not the date: counsel's edit bumps it
    expect(Number.isNaN(Date.parse(entry.version))).toBe(false);
    expect(entry.validUntil).toBeNull();
    expect(entry.textHash).toMatch(/^[0-9a-f]{64}$/);
    expect(loadLegalTexts().has(KEY)).toBe(true);
  });
});

describe("founder-acceptance-record: what the text says", () => {
  const body = (): string => getLegalText(KEY).body;

  it("never claims more than happened (the shared forbidden words, applied to the whole file, front matter included)", () => {
    expect.hasAssertions();
    expect(getLegalText(KEY).raw).not.toMatch(FORBIDDEN_CLAIMS);
  });

  it("the forbidden-word check bites (planted strings are caught, a plain sentence is not)", () => {
    expect.hasAssertions();
    for (const s of ["This was Verified", "Legally binding", "legally-binding", "audit ready", "certified", "verifies compliance"]) {
      expect(FORBIDDEN_CLAIMS.test(s), s).toBe(true);
    }
    expect(FORBIDDEN_CLAIMS.test("Confirmed with an email code")).toBe(false);
  });

  it("every character quantity the text states is the product's note limit, and the card notice states the same one", () => {
    expect.hasAssertions();
    const stated = [...body().matchAll(/\b(\d[\d,]*)\s*(?:characters|chars)\b/gi)].map((m) => Number(m[1].replaceAll(",", "")));
    expect([...new Set(stated)], "the text must state the note limit, and only that quantity").toEqual([REQUEST_CHANGES_MAX]);
    expect(LEGAL_COPY.requestChangesNotice).toContain(String(REQUEST_CHANGES_MAX));
  });

  it("the stored-fields list is reviewed whenever the table changes: the legal_acceptance column set is pinned", () => {
    expect.hasAssertions();
    const code = M184.split("\n")
      .map((l) => l.replace(/--.*$/, ""))
      .join("\n");
    const start = code.indexOf("CREATE TABLE IF NOT EXISTS public.legal_acceptance (");
    expect(start, "the legal_acceptance table is not in migration 184").toBeGreaterThanOrEqual(0);
    const block = code.slice(start, code.indexOf("UNIQUE (founder_id, key, text_hash)", start));
    const columns = [...block.matchAll(/^\s{2}([a-z_]+)\s+(?:uuid|text|timestamptz)\b/gm)].map((m) => m[1]).sort();
    // Each column below is described (or deliberately omitted) in the text's "What is stored for each decision"; a new or
    // removed column fails here so the text is reviewed with it. Update this list AND the text together.
    expect(columns, "a legal_acceptance column was added or removed: review the text's list of what is stored").toEqual(
      [
        "id", "founder_id", "key", "text_hash", "version", "choice", "requested_edit", "method", "reauth_method",
        "reauth_at", "session_id", "event_id", "surface", "row_hash", "created_at",
      ].sort(),
    );
  });
});

describe("founder-acceptance-record: merge guard (counsel sign-off)", () => {
  it("the placeholder detector bites: each unfinished shape is found, a finished sentence is not", () => {
    expect.hasAssertions();
    for (const s of [
      "kept for [period to be confirmed by counsel].",
      "kept for [a\nwrapped bracket].",
      "kept for TBD years",
      "kept for XX days",
      "kept for ___ years",
      "kept for TODO.",
      "the period is to be confirmed.",
      "ask counsel",
    ]) {
      expect(placeholdersIn(s).length, s).toBeGreaterThan(0);
    }
    expect(placeholdersIn("kept for as long as the text is in force, and no more than ten years.")).toEqual([]);
    expect(placeholdersIn("write to <legal@jikigai.com> and you can complain to the CNIL.")).toEqual([]);
  });

  it("CI is visible to this run whenever it runs under GitHub Actions (a scrubbed CI variable would silently skip the guard)", () => {
    expect.hasAssertions();
    expect(!process.env.GITHUB_ACTIONS || Boolean(process.env.CI), "GITHUB_ACTIONS is set but CI is not: the merge guard below would be skipped").toBe(true);
  });

  it.skipIf(!process.env.CI)(
    "CI only, RED BY DESIGN while the draft is held: no placeholder-shaped token is left in the text body",
    () => {
      expect.hasAssertions();
      expect(
        placeholdersIn(getLegalText(KEY).body),
        "HELD for counsel (PR #12342): the text still has an open item. Do not edit the text, the pattern or this check to turn CI green: escalate to the operator.",
      ).toEqual([]);
    },
  );

  it.skipIf(!process.env.CI)(
    "CI only, RED BY DESIGN while the draft is held: the card notice that states the same retention period has no placeholder either",
    () => {
      expect.hasAssertions();
      expect(
        [...placeholdersIn(LEGAL_COPY.cardNotice), ...placeholdersIn(LEGAL_COPY.requestChangesNotice)],
        "HELD for counsel (PR #12342): the card notice (lib/legal-acceptance-copy.ts, pinned to the DSAR note) still has the open retention period. It is replaced in the sign-off PR together with the text; do not edit it to turn CI green.",
      ).toEqual([]);
    },
  );
});
