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
import { lexSql } from "../helpers/sql-lex";
import { FORBIDDEN_CLAIMS } from "./forbidden-claims";

const KEY = "founder-acceptance-record";
const MIGRATIONS = path.join(__dirname, "../../supabase/migrations");
const migrationFiles = (): string[] => readdirSync(MIGRATIONS).filter((f) => f.endsWith(".sql") && !f.endsWith(".down.sql")).sort();
const M184 = readFileSync(path.join(MIGRATIONS, "184_legal_acceptance.sql"), "utf8");
const M185 = readFileSync(path.join(MIGRATIONS, "185_legal_acceptance_ack.sql"), "utf8");

/** SQL with comments and single-quoted literals blanked (double-quoted identifiers kept). */
const sqlCode = (sql: string): string => lexSql(sql).map((t) => (t.kind === "lit" && t.text.startsWith("'") ? " " : t.text)).join("");

/** Column names of `CREATE TABLE ... <table> (...)`: comments stripped, balanced-paren body, first word of each top-level item, constraints skipped. */
function tableColumns(sql: string, table: string): string[] {
  const code = sqlCode(sql);
  const m = new RegExp(`create\\s+table\\s+(?:if\\s+not\\s+exists\\s+)?(?:public\\.)?${table}\\s*\\(`, "i").exec(code);
  if (!m) return [];
  let depth = 1;
  let i = m.index + m[0].length;
  const items: string[] = [];
  let cur = "";
  for (; i < code.length && depth > 0; i++) {
    const c = code[i];
    if (c === "(") depth++;
    else if (c === ")") {
      depth--;
      if (depth === 0) break;
    }
    if (c === "," && depth === 1) (items.push(cur), (cur = ""));
    else cur += c;
  }
  items.push(cur);
  return items
    .map((x) => x.trim().split(/\s+/)[0]?.replace(/"/g, "") ?? "")
    .filter((w) => w !== "" && !/^(constraint|unique|primary|foreign|check|exclude|like)$/i.test(w))
    .sort();
}

/** Migrations whose ALTER TABLE changes a column of either table (add, drop, rename, alter column): any such change forces a review of the stored-fields list. RLS, trigger and constraint ALTERs are not column changes. */
function alteringMigrations(files: Record<string, string>): string[] {
  return Object.entries(files)
    .filter(([, sql]) =>
      /alter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?(?:"?public"?\.)?"?legal_acceptance(?:_ack)?"?\s+(?:add|drop|rename|alter)\s+(?!constraint\b)/i.test(sqlCode(sql)),
    )
    .map(([f]) => f)
    .sort();
}

/** Anything that reads as an unfinished retention period or other open item. Not a wording check: a draft-state detector. */
const PLACEHOLDER =
  /\[[^\]]*\]|\b(?:TBD|TBC|TODO)\b|\bX{2,}\b|_{3,}|to be (?:confirmed|decided|determined)|\bcounsel\b/gi;
/** Every placeholder-shaped token in a text (empty when finished). */
const placeholdersIn = (text: string): string[] => [...text.matchAll(PLACEHOLDER)].map((m) => m[0]);
/** Every open item across the surfaces that state the retention period: the text body, the card notice and the request-changes notice. */
const heldFindings = (): string[] => [
  ...placeholdersIn(getLegalText(KEY).body).map((t) => `text body: ${t}`),
  ...placeholdersIn(LEGAL_COPY.cardNotice).map((t) => `card notice: ${t}`),
  ...placeholdersIn(LEGAL_COPY.requestChangesNotice).map((t) => `request-changes notice: ${t}`),
];

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
    writeFileSync(path.join(d, "f.md"), "x\ty\n");
    writeFileSync(path.join(d, "g.md"), "x\x1by\n");
    writeFileSync(path.join(d, "NOTES.md"), "not a key: café\n"); // uppercase: the loader skips it, so the audit does too
    const found = auditDir(d).join("\n");
    expect(found).toContain("a.md: carries a CR");
    expect(found).toMatch(/b\.md: control or non-ASCII byte 0xc3 at offset 3/);
    expect(found).toContain("c.md: starts with a BOM");
    expect(found).toMatch(/d\.md: control or non-ASCII byte 0x7f/);
    expect(found).toMatch(/e\.md: control or non-ASCII byte 0x0 at offset 1/);
    expect(found).toMatch(/f\.md: control or non-ASCII byte 0x9 at offset 1/);
    expect(found).toMatch(/g\.md: control or non-ASCII byte 0x1b at offset 1/);
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
    expect(new Date(`${entry.version}T00:00:00Z`).toISOString().slice(0, 10), "version must be a real calendar date").toBe(entry.version);
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

  const quantities = (t: string): number[] => [...t.matchAll(/\b(\d[\d,]*)\s*(?:characters|chars)\b/gi)].map((m) => Number(m[1].replaceAll(",", "")));

  it("every character quantity the text states is the product's note limit, and the card's request-changes notice states the same one", () => {
    expect.hasAssertions();
    expect([...new Set(quantities(body()))], "the text must state the note limit, and only that quantity").toEqual([REQUEST_CHANGES_MAX]);
    expect([...new Set(quantities(LEGAL_COPY.requestChangesNotice))], "the card's request-changes notice must state the same quantity").toEqual([REQUEST_CHANGES_MAX]);
    expect(quantities("up to 1,000 characters and 20 chars")).toEqual([1000, 20]);
  });

  it("the stored-fields list is reviewed whenever the tables change: both column sets are pinned and no later migration alters either table", () => {
    expect.hasAssertions();
    // Each column below is described (or deliberately omitted) in the text's "What is stored for each decision"; a new or
    // removed column fails here so the text is reviewed with it. Update these lists AND the text together.
    expect(tableColumns(M184, "legal_acceptance"), "a legal_acceptance column was added or removed: review the text's list of what is stored").toEqual(
      [
        "id", "founder_id", "key", "text_hash", "version", "choice", "requested_edit", "method", "reauth_method",
        "reauth_at", "session_id", "event_id", "surface", "row_hash", "created_at",
      ].sort(),
    );
    expect(tableColumns(M185, "legal_acceptance_ack"), "the ack table changed: review the text's sentence about the monitoring marker").toEqual(["acceptance_id", "acked_at"]);
    const files = Object.fromEntries(migrationFiles().map((f) => [f, readFileSync(path.join(MIGRATIONS, f), "utf8")]));
    expect(alteringMigrations(files), "a migration alters legal_acceptance or its ack table: review the text's list of what is stored").toEqual([]);
  });

  it("the column pin bites: a multi-word type, a trailing constraint, a comment decoy, a later ALTER and a missing table", () => {
    expect.hasAssertions();
    const sql = "CREATE TABLE IF NOT EXISTS public.t (\n  id uuid PRIMARY KEY,\n  amount numeric(10, 2) NOT NULL, -- other_col text\n  at timestamp with time zone,\n  CONSTRAINT c CHECK (amount > 0),\n  UNIQUE (id, at)\n);";
    expect(tableColumns(sql, "t")).toEqual(["amount", "at", "id"]);
    expect(tableColumns(sql, "missing")).toEqual([]);
    expect(alteringMigrations({ "190_x.sql": "ALTER TABLE public.legal_acceptance ADD COLUMN extra text;", "191_y.sql": "alter table legal_acceptance_ack drop column acked_at;", "192_z.sql": "ALTER TABLE other ADD COLUMN a int; -- ALTER TABLE legal_acceptance ADD x", "193_w.sql": "ALTER TABLE public.legal_acceptance ENABLE ROW LEVEL SECURITY;", "194_v.sql": "ALTER TABLE public.legal_acceptance ADD CONSTRAINT k CHECK (true);", "195_u.sql": "ALTER TABLE \"public\".legal_acceptance RENAME COLUMN a TO b;", "196_t.sql": "select 'alter table legal_acceptance add x';" })).toEqual(["190_x.sql", "191_y.sql", "195_u.sql"]);
    expect(tableColumns("CREATE TABLE public.t (a text DEFAULT 'x, y', b text DEFAULT ')', c int)", "t")).toEqual(["a", "b", "c"]);
  });

  it("the committed registry holds only the keys this file guards (a second text must extend the merge guard below first)", () => {
    expect.hasAssertions();
    expect([...loadLegalTexts().keys()], "a second text was added: the CI-only placeholder guard below covers only founder-acceptance-record; extend it before adding another").toEqual([KEY]);
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

  it("while the draft is held the detector sees its open items in the real data (a guard that finds nothing here is not guarding)", () => {
    expect.hasAssertions();
    // Deleted together with the guard in counsel's sign-off PR: once the retention period is written, nothing is left to find.
    const found = heldFindings();
    expect(found.some((f) => f.startsWith("text body: ")), "the retention placeholder is gone from the text body: this draft is no longer held, remove the guard in the sign-off PR").toBe(true);
    expect(found.some((f) => f.startsWith("card notice: ")), "the card notice no longer carries the retention placeholder: update it in the same PR as the text").toBe(true);
  });

  it("the retention clause is the placeholder sentence and nothing else states a period (deleted with the guard in counsel's sign-off PR)", () => {
    expect.hasAssertions();
    const b = getLegalText(KEY).body;
    expect(b).toMatch(/How long the record is kept:\s*\[[^\]]+\]\./);
    expect([...b.matchAll(/\b(?:\d+|one|two|three|four|five|six|seven|eight|nine|ten|twelve)[\s-]*(?:years?|months?|days?)\b/gi)].map((m) => m[0]), "the text states a numeric retention period before counsel confirmed it").toEqual([]);
  });

  it.skipIf(!process.env.CI)(
    "CI only, RED BY DESIGN while the draft is held: no open item is left in the text body, the card notice or the request-changes notice",
    () => {
      expect.hasAssertions();
      expect(
        heldFindings(),
        "HELD for counsel (PR #12342): the text or the card notice that states the same retention period still has an open item. Both are replaced in counsel's sign-off PR; do not edit the text, the card notice, the pattern or this check to turn CI green: escalate to the operator.",
      ).toEqual([]);
    },
  );
});
