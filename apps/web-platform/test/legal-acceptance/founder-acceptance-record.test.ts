/**
 * #12197 / #12011: structural checks on the first committed legal text, `founder-acceptance-record`.
 *
 * SIGNED OFF as a v1 internal position (CLO agent ruling of 2026-11-07, which stands in for counsel on the operator's
 * instruction; a human lawyer's review is still owed). The ruling is persisted in
 * knowledge-base/legal/audits/2026-11-07-clo-ruling-founder-acceptance-record-12197.md.
 *
 * These checks assert shape and the numbers the text states. The published `{version: sha256}` pin and the exact key set
 * live in registry-pins.test.ts. The unfinished-marker check below is permanent and always on: it runs on every run, not
 * only under CI, and it covers the text body and both notices that state the retention period.
 */
import { mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { afterAll, describe, expect, it } from "vitest";
import { KEY_RE, TEXTS_DIR, getLegalText, loadLegalTexts } from "@/server/legal-acceptance/canonical";
import { LEGAL_COPY, LEGAL_TEXT_KIND, legalTextKind } from "@/lib/legal-acceptance-copy";
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

/** Migrations whose ALTER TABLE changes a column of any of the three tables (add, drop, rename, alter column): any such change forces a review of the stored-fields list. RLS, trigger and constraint ALTERs are not column changes. */
function alteringMigrations(files: Record<string, string>): string[] {
  return Object.entries(files)
    .filter(([, sql]) =>
      /alter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?(?:"?public"?\.)?"?legal_(?:acceptance(?:_ack)?|reauth_event)"?\s+(?:add|drop|rename|alter)\s+(?!constraint\b)/i.test(sqlCode(sql)),
    )
    .map(([f]) => f)
    .sort();
}

/** Anything that reads as an unfinished retention period or other open item. Not a wording check: an unfinished-marker detector. */
const UNFINISHED = /\[[^\]]*\]|\b(?:TBD|TBC|TODO)\b|\bX{2,}\b|_{3,}|to be (?:confirmed|decided|determined)/gi;
/** Every unfinished marker in a text (empty when finished). */
const unfinishedIn = (text: string): string[] => [...text.matchAll(UNFINISHED)].map((m) => m[0]);

/** Any retention-shaped duration: digits or a number word, then a unit; plus a bare "decade". Generic on purpose (CLO B, CTO 4). */
const DURATION =
  /\b(?:\d+|a|an|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|fifteen|twenty|thirty|forty|fifty)[\s-]*(?:years?|months?|weeks?|days?|decades?)\b|\bdecades?\b/gi;
const durationsIn = (text: string): string[] => [...text.matchAll(DURATION)].map((m) => m[0].toLowerCase().replace(/[\s-]+/g, " ")).sort();

/** The one retention phrase the CLO ruled (CLO B). The text, the card notice and the request-changes notice carry it word for word. */
const RETENTION_PERIOD = "5 years from the date of the decision";

/** The dated safeguard (CLO 4a): once the 5-year end is near, a text that still says the deletion step is not built must not ship. */
const NOT_BUILT_DEADLINE = "2030-11-07T00:00:00Z";
function notBuiltOverdue(now: Date, body: string): string | null {
  if (now.getTime() < Date.parse(NOT_BUILT_DEADLINE)) return null;
  return body.includes("has not yet built")
    ? "The text still says Jikigai has not yet built the step that deletes a record. Build it (#12080), then publish a new version without that sentence."
    : null;
}

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
    expect(tableColumns(M184, "legal_reauth_event"), "the request-record table changed: review the text's paragraph about request records (the paragraph that starts Each decision also uses a short-lived request record)").toEqual(
      ["attempts", "consumed_at", "created_at", "expires_at", "id", "key", "session_id", "superseded_at", "text_hash", "user_id", "verified_at", "version"],
    );
    const files = Object.fromEntries(migrationFiles().map((f) => [f, readFileSync(path.join(MIGRATIONS, f), "utf8")]));
    expect(alteringMigrations(files), "a migration alters legal_acceptance, its ack table or legal_reauth_event: review the text's list of what is stored").toEqual([]);
  });

  it("the column pin bites: a multi-word type, a trailing constraint, a comment decoy, a later ALTER and a missing table", () => {
    expect.hasAssertions();
    const sql = "CREATE TABLE IF NOT EXISTS public.t (\n  id uuid PRIMARY KEY,\n  amount numeric(10, 2) NOT NULL, -- other_col text\n  at timestamp with time zone,\n  CONSTRAINT c CHECK (amount > 0),\n  UNIQUE (id, at)\n);";
    expect(tableColumns(sql, "t")).toEqual(["amount", "at", "id"]);
    expect(tableColumns(sql, "missing")).toEqual([]);
    expect(alteringMigrations({ "190_x.sql": "ALTER TABLE public.legal_acceptance ADD COLUMN extra text;", "191_y.sql": "alter table legal_acceptance_ack drop column acked_at;", "192_z.sql": "ALTER TABLE other ADD COLUMN a int; -- ALTER TABLE legal_acceptance ADD x", "193_w.sql": "ALTER TABLE public.legal_acceptance ENABLE ROW LEVEL SECURITY;", "194_v.sql": "ALTER TABLE public.legal_acceptance ADD CONSTRAINT k CHECK (true);", "195_u.sql": "ALTER TABLE \"public\".legal_acceptance RENAME COLUMN a TO b;", "196_t.sql": "select 'alter table legal_acceptance add x';", "197_s.sql": "ALTER TABLE public.legal_reauth_event ADD COLUMN extra text;", "198_r.sql": "ALTER TABLE public.legal_reauth_event ENABLE ROW LEVEL SECURITY;" })).toEqual(["190_x.sql", "191_y.sql", "195_u.sql", "197_s.sql"]);
    expect(tableColumns("CREATE TABLE public.t (a text DEFAULT 'x, y', b text DEFAULT ')', c int)", "t")).toEqual(["a", "b", "c"]);
  });
});

describe("founder-acceptance-record: no unfinished marker (always on, every run)", () => {
  it("the unfinished-marker detector bites: each unfinished shape is found, a finished sentence is not", () => {
    expect.hasAssertions();
    for (const s of [
      "kept for [the period].",
      "kept for [a\nwrapped bracket].",
      "kept for TBD years",
      "kept for XX days",
      "kept for ___ years",
      "kept for TODO.",
      "the period is to be confirmed.",
    ]) {
      expect(unfinishedIn(s).length, s).toBeGreaterThan(0);
    }
    expect(unfinishedIn("kept for 5 years from the date of the decision.")).toEqual([]);
    expect(unfinishedIn("write to <legal@jikigai.com> and you can complain to the CNIL.")).toEqual([]);
  });

  it("the text body, the card notice and the request-changes notice carry no unfinished marker", () => {
    expect.hasAssertions();
    expect(unfinishedIn(getLegalText(KEY).body), "text body").toEqual([]);
    expect(unfinishedIn(LEGAL_COPY.cardNotice), "card notice").toEqual([]);
    expect(unfinishedIn(LEGAL_COPY.requestChangesNotice), "request-changes notice").toEqual([]);
  });
});

describe("founder-acceptance-record: the retention period has one source (CLO B)", () => {
  const body = (): string => getLegalText(KEY).body;
  const count = (hay: string, needle: string): number => hay.split(needle).length - 1;
  /** The paragraph that names the request records (CLO A5); the only place a 30-day figure belongs. */
  const requestRecordParagraph = (): string => {
    const p = body().split("\n\n").find((x) => x.startsWith("Each decision also uses a short-lived request record"));
    expect(p, "the request-record paragraph (CLO A5) is missing").toBeDefined();
    return p as string;
  };

  it("the duration detector bites: digits, number words, a year, weeks, a decade", () => {
    expect.hasAssertions();
    expect(durationsIn("7 years, seven years, a year, twenty years, 3 weeks, a decade, ten-year, 30 days")).toEqual(
      ["30 days", "3 weeks", "7 years", "a decade", "a year", "seven years", "ten year", "twenty years"].sort(),
    );
    expect(durationsIn("kept for the decision")).toEqual([]);
  });

  it("the text states the period exactly twice, and every duration in the body is 5 years (x4) or 30 days (x2)", () => {
    expect.hasAssertions();
    expect(count(body(), RETENTION_PERIOD), "the retention phrase in the text body").toBe(2);
    expect(durationsIn(body()), "every duration token in the text body").toEqual(["30 days", "30 days", "5 years", "5 years", "5 years", "5 years"]);
  });

  it("30 days appears only in the request-record paragraph, and that paragraph is not covered by the 5 years", () => {
    expect.hasAssertions();
    const p = requestRecordParagraph();
    expect(durationsIn(p)).toEqual(["30 days", "30 days", "5 years"]);
    expect(body().replace(p, ""), "a 30-day figure outside the request-record paragraph").not.toMatch(/30 days/);
    expect(p).toContain("is not covered by the 5 years above");
    expect(p, "the text must never promise a hard 30-day bound for request records").toContain("so one can last longer than 30 days");
  });

  it("the 30 days the text states is the interval the database purge uses", () => {
    expect.hasAssertions();
    const purge = /DELETE FROM public\.legal_reauth_event WHERE created_at < now\(\) - interval '(\d+) days'/.exec(M184);
    expect(purge, "the purge statement in migration 184 changed: review the text's request-record paragraph").not.toBeNull();
    const stated = /older than (\d+) days/.exec(requestRecordParagraph());
    expect(stated, "the request-record paragraph must say older than N days").not.toBeNull();
    expect((stated as RegExpExecArray)[1]).toBe((purge as RegExpExecArray)[1]);
  });

  it("the card notice and the request-changes notice carry the same phrase once, and no other duration", () => {
    expect.hasAssertions();
    expect(count(LEGAL_COPY.cardNotice, RETENTION_PERIOD)).toBe(1);
    expect(count(LEGAL_COPY.requestChangesNotice, RETENTION_PERIOD)).toBe(1);
    expect(durationsIn(LEGAL_COPY.cardNotice)).toEqual(["5 years"]);
    expect(durationsIn(LEGAL_COPY.requestChangesNotice)).toEqual(["5 years"]);
    expect(body()).toContain(`How long the record is kept: ${RETENTION_PERIOD}, and then Jikigai deletes it.`);
  });

  it("the dated safeguard: from 2030-11-07 the text must no longer say the deletion step is not built (#12080)", () => {
    expect.hasAssertions();
    expect(notBuiltOverdue(new Date(NOT_BUILT_DEADLINE), "x has not yet built y")).toContain("#12080");
    expect(notBuiltOverdue(new Date("2030-11-06T23:59:59Z"), "x has not yet built y")).toBeNull();
    expect(notBuiltOverdue(new Date("2031-01-01T00:00:00Z"), "the step is built")).toBeNull();
    expect(notBuiltOverdue(new Date(), body()), "#12080 must be built, and the text re-published without 'has not yet built'").toBeNull();
  });
});

describe("founder-acceptance-record: the declared kind and its title", () => {
  it("the key has a declared kind, and the first line of every acknowledgement text has no double quote and no newline", () => {
    expect.hasAssertions();
    expect(legalTextKind(KEY)).toBe("acknowledgement");
    const keys = Object.keys(LEGAL_TEXT_KIND).filter((k) => LEGAL_TEXT_KIND[k] === "acknowledgement");
    expect(keys.length).toBeGreaterThan(0);
    for (const k of keys) {
      const first = getLegalText(k).body.split("\n")[0];
      expect(first, `${k}: the title line is quoted in the card, so it carries no double quote`).not.toContain('"');
      expect(first.length, `${k}: the title line must fit the label guard`).toBeLessThanOrEqual(120);
    }
  });
});
