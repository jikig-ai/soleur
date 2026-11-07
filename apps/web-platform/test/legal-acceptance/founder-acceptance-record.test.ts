/**
 * #12197 / #12011: structural checks on the first committed legal text, `founder-acceptance-record`.
 *
 * DRAFT, HELD for counsel sign-off (PR #12342). These checks are what counsel's edit rewrites, so they live in ONE deletable
 * file. They assert shape and the numbers the text states, never the wording, and they pin NO sha256 literal: the retention
 * placeholder is replaced at sign-off, which changes the bytes, so a hash pinned now would be rewritten once for nothing
 * (the sign-off PR adds the published `{version: sha256}` pin).
 *
 * The merge guard at the end FAILS under `CI` while a bracketed placeholder (`[period to be confirmed by counsel]`) is still
 * in the body. A ready or merge_group run sets `CI`, so an accidental ready or merge of the held draft is blocked by CI;
 * a local run and the draft-light CI run stay green.
 */
import { mkdirSync, mkdtempSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { TEXTS_DIR, getLegalText, loadLegalTexts } from "@/server/legal-acceptance/canonical";
import { REQUEST_CHANGES_MAX } from "@/lib/legal-acceptance-wire";

const KEY = "founder-acceptance-record";
// The same words legal-copy.test.ts forbids in the card deck: the text never claims more than happened.
const FORBIDDEN = /verified|reviewed|legally binding|audit-ready|compliant/i;
const PLACEHOLDER = /\[[^\]\n]*\]/;

/** Raw-byte problems in every committed text: a CR, a non-ASCII byte, a BOM. Returns one string per problem (empty is clean). */
function auditDir(dir: string): string[] {
  const out: string[] = [];
  const files = readdirSync(dir).filter((f) => f.endsWith(".md") && f !== "README.md");
  if (files.length === 0) out.push("no committed text found");
  for (const f of files) {
    const bytes = readFileSync(path.join(dir, f));
    if (bytes.includes(0x0d)) out.push(`${f}: carries a CR`);
    if (bytes.some((b) => b > 0x7f)) out.push(`${f}: carries a byte above 0x7F`);
    if (bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) out.push(`${f}: starts with a BOM`);
  }
  return out;
}

describe("founder-acceptance-record: the committed bytes", () => {
  it("every committed text is LF-only ASCII with no BOM, and the directory is not empty", () => {
    expect.hasAssertions();
    expect(auditDir(TEXTS_DIR)).toEqual([]);
  });

  it("the audit bites: a CR, a non-ASCII byte, a BOM and an empty directory are each detected", () => {
    expect.hasAssertions();
    const d = mkdtempSync(path.join(tmpdir(), "far-audit-"));
    expect(auditDir(d)).toEqual(["no committed text found"]);
    writeFileSync(path.join(d, "a.md"), "---\nversion: 1\n---\nline\r\n");
    writeFileSync(path.join(d, "b.md"), "café\n");
    writeFileSync(path.join(d, "c.md"), Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from("x\n")]));
    const found = auditDir(d);
    expect(found).toContain("a.md: carries a CR");
    expect(found).toContain("b.md: carries a byte above 0x7F");
    expect(found).toContain("c.md: starts with a BOM");
    const clean = path.join(d, "clean");
    mkdirSync(clean);
    writeFileSync(path.join(clean, "ok.md"), "---\nversion: 1\n---\nplain\n");
    expect(auditDir(clean)).toEqual([]);
  });
});

describe("founder-acceptance-record: what the loader sees", () => {
  it("loads under the key, with a date version and no expiry", () => {
    expect.hasAssertions();
    const entry = getLegalText(KEY);
    expect(entry.key).toBe(KEY);
    expect(entry.version).toMatch(/^\d{4}-\d{2}-\d{2}$/); // the shape, not the date: counsel's edit bumps it
    expect(entry.validUntil).toBeNull();
    expect(entry.textHash).toMatch(/^[0-9a-f]{64}$/);
    expect(loadLegalTexts().has(KEY)).toBe(true);
  });
});

describe("founder-acceptance-record: what the body says", () => {
  const body = (): string => getLegalText(KEY).body;

  it("never claims more than happened (the card deck's forbidden words)", () => {
    expect.hasAssertions();
    expect(body()).not.toMatch(FORBIDDEN);
  });

  it("the forbidden-word check bites (a planted string is caught)", () => {
    expect.hasAssertions();
    expect(FORBIDDEN.test("This was Verified")).toBe(true);
    expect(FORBIDDEN.test("Legally binding")).toBe(true);
    expect(FORBIDDEN.test("The record is kept")).toBe(false);
  });

  it("the note limit it states is the product's limit", () => {
    expect.hasAssertions();
    const stated = [...body().matchAll(/up to (\d+) characters/g)].map((m) => Number(m[1]));
    expect(stated, "the text must state the note limit exactly once").toEqual([REQUEST_CHANGES_MAX]);
  });
});

describe("founder-acceptance-record: merge guard (counsel sign-off)", () => {
  it.skipIf(!process.env.CI)("no bracketed placeholder is left in the body (a ready or merge run is RED until counsel's edit lands)", () => {
    expect.hasAssertions();
    expect(getLegalText(KEY).body, "a bracketed placeholder is still in the text: counsel has not signed off").not.toMatch(PLACEHOLDER);
  });

  it("the guard's pattern bites (a bracketed placeholder is caught, a plain sentence is not)", () => {
    expect.hasAssertions();
    expect(PLACEHOLDER.test("kept for [period to be confirmed by counsel].")).toBe(true);
    expect(PLACEHOLDER.test("kept for as long as the text is in force.")).toBe(false);
  });
});
