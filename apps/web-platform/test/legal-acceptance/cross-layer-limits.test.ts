/**
 * #12011 PR-D (AC11, Guard 2 row 10): the key and hash limits are ONE rule counted once across layers.
 *
 * The shapes are EXTRACTED from the source of every layer, never restated here:
 *  - TypeScript: `KEY_RE` and `TEXT_HASH_RE` in server/legal-acceptance/canonical.ts (imported AND parsed from the source);
 *  - SQL: the CHECK constraints of migration 184 and the argument checks of the RPCs in 184 and 185;
 *  - bash: the `=~` patterns inside `gate_web_acceptance` in plugins/soleur/skills/ship/scripts/hold-gate-eval.sh.
 * An empty extraction FAILS (a regex that no longer finds anything must not read as "all layers agree").
 * The boundary is pinned the same way everywhere: a key of 63 characters is accepted and one of 64 is refused.
 */
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { KEY_RE, LegalTextError, TEXT_HASH_RE, parseLegalText } from "@/server/legal-acceptance/canonical";

const WEB = path.join(__dirname, "../..");
const REPO = path.join(WEB, "../..");
const read = (p: string): string => readFileSync(p, "utf8");

const CANONICAL_SRC = read(path.join(WEB, "server/legal-acceptance/canonical.ts"));
const M184 = read(path.join(WEB, "supabase/migrations/184_legal_acceptance.sql"));
const M185 = read(path.join(WEB, "supabase/migrations/185_legal_acceptance_ack.sql"));
const GATE_PATH = path.join(REPO, "plugins/soleur/skills/ship/scripts/hold-gate-eval.sh");
const GATE_SRC = read(GATE_PATH);

// ── extractors (each throws on an empty result) ─────────────────────────────────────────────────────────────────

const nonEmpty = <T,>(what: string, xs: T[]): T[] => {
  if (xs.length === 0) throw new Error(`extraction found nothing: ${what}`);
  return xs;
};

/** `export const NAME = /.../;` from a TypeScript source: the regex SOURCE text. */
export function extractTsRegex(src: string, name: string): string {
  const m = new RegExp(`export const ${name} = /(.+)/;`).exec(src);
  return nonEmpty(`TS ${name}`, m ? [m[1]] : [])[0];
}

/** SQL: every `<col> ~ '...'` (CHECK) and `<param> !~ '...'` (argument check) for the given column and parameter. */
export function extractSqlPatterns(sql: string, col: string, param: string): string[] {
  const code = sql
    .split("\n")
    .map((l) => l.replace(/--.*$/, ""))
    .join("\n");
  const re = new RegExp(`(?:\\b${col}\\s+~|\\b${param}\\s+!~)\\s+'([^']+)'`, "g");
  return nonEmpty(`SQL ${col}/${param}`, [...code.matchAll(re)].map((m) => m[1]));
}

/**
 * bash: the key and hash patterns of the web-acceptance gate. The script holds them in two variables (`WA_KEY_RE`,
 * `WA_HASH_RE`, single-quoted ERE) and `gate_web_acceptance` applies them with `=~`. Both facts are checked: the
 * assignments are extracted, and the function body must USE each variable (a pattern that is defined and never applied
 * is not a layer).
 */
export function extractBashPatterns(src: string): { key: string[]; hash: string[] } {
  const start = src.search(/^gate_web_acceptance\s*\(\)\s*\{/m);
  if (start < 0) throw new Error("extraction found nothing: gate_web_acceptance is not in the script");
  const rest = src.slice(start);
  const end = rest.search(/^\}/m);
  const body = rest.slice(0, end < 0 ? rest.length : end);
  const assigned = (name: string): string[] => [...src.matchAll(new RegExp(`^${name}='([^']+)'$`, "gm"))].map((m) => m[1]);
  const key = nonEmpty("bash WA_KEY_RE assignment", assigned("WA_KEY_RE"));
  const hash = nonEmpty("bash WA_HASH_RE assignment", assigned("WA_HASH_RE"));
  nonEmpty("bash =~ $WA_KEY_RE inside gate_web_acceptance", body.match(/=~ \$WA_KEY_RE\b/g) ?? []);
  nonEmpty("bash =~ $WA_HASH_RE inside gate_web_acceptance", body.match(/=~ \$WA_HASH_RE\b/g) ?? []);
  return { key, hash };
}

// ── probes ──────────────────────────────────────────────────────────────────────────────────────────────────────

const k = (n: number, c = "a") => c.repeat(n);
const KEY_PROBES: Array<[string, boolean]> = [
  [k(1), true],
  [k(62), true],
  [k(63), true], // the limit: accepted everywhere
  [k(64), false], // one past the limit: refused everywhere
  ["", false],
  ["-abc", false], // leading hyphen
  ["a-b-c", true],
  ["a-", true],
  ["0abc", true],
  ["Abc", false],
  ["a_b", false],
  ["a.b", false],
  ["../etc", false],
  ["a b", false],
  ["aé", false],
];
const HASH_PROBES: Array<[string, boolean]> = [
  ["a".repeat(64), true],
  ["0123456789abcdef".repeat(4), true],
  ["a".repeat(63), false],
  ["a".repeat(65), false],
  ["A".repeat(64), false], // uppercase hex
  ["a".repeat(63) + "g", false],
  ["", false],
  [" " + "a".repeat(63), false],
];

/** Does bash accept `value` under the ERE `pattern` (the same `[[ =~ ]]` the script uses)? */
function bashAccepts(pattern: string, value: string): boolean {
  const r = spawnSync("bash", ["-c", '[[ "$1" =~ $2 ]]', "_", value, pattern], { encoding: "utf8", env: { ...process.env, LC_ALL: "C" } });
  return r.status === 0;
}
const jsAccepts = (source: string, value: string): boolean => new RegExp(source).test(value);

// ── comparisons ─────────────────────────────────────────────────────────────────────────────────────────────────

describe("extractors fail loudly on an empty extraction", () => {
  it("TS, SQL and bash extractors throw when the source no longer contains the pattern", () => {
    expect(() => extractTsRegex("export const OTHER = /x/;", "KEY_RE")).toThrow(/found nothing/);
    expect(() => extractSqlPatterns("-- key ~ '^x$' only in a comment\nselect 1;", "key", "p_key")).toThrow(/found nothing/);
    expect(() => extractBashPatterns("nothing here")).toThrow(/found nothing/);
    expect(() => extractBashPatterns("gate_web_acceptance() {\n  :\n}\n")).toThrow(/found nothing/);
    expect(() => extractBashPatterns("WA_KEY_RE='^a$'\nWA_HASH_RE='^b$'\ngate_web_acceptance() {\n  :\n}\n")).toThrow(/found nothing/);
  });
  it("a widened pattern in one layer is detected by the comparison (negative control)", () => {
    const widened = extractTsRegex(CANONICAL_SRC, "KEY_RE").replace("{0,62}", "{0,63}");
    expect(jsAccepts(widened, k(64))).toBe(true); // the mutation would let 64 through...
    expect(widened).not.toBe(KEY_RE.source); // ...and the equality below would be red
  });
});

describe("negative controls on the REAL sources", () => {
  it("a widened bash key, an uppercase bash hash and a widened SQL CHECK are each detected as a mismatch", () => {
    if (!GATE_SRC.includes("web-acceptance")) return; // bash leg absent: see the TODO in the bash describe
    const wideKey = extractBashPatterns(GATE_SRC.replace("{0,62}$'\nWA_HASH_RE", () => "{0,63}$'\nWA_HASH_RE")).key[0];
    expect(wideKey).not.toBe(KEY_RE.source);
    expect(bashAccepts(wideKey, k(64))).toBe(true);
    const upperHash = extractBashPatterns(GATE_SRC.replace("WA_HASH_RE='^[0-9a-f]", "WA_HASH_RE='^[0-9a-fA-F]")).hash[0];
    expect(upperHash).not.toBe(TEXT_HASH_RE.source);
    expect(bashAccepts(upperHash, "A".repeat(64))).toBe(true);
    const wideSql = extractSqlPatterns(M184.replaceAll("{0,62}", "{0,63}"), "key", "p_key")[0];
    expect(wideSql).not.toBe(KEY_RE.source);
  });
});

describe("TypeScript (canonical.ts)", () => {
  it("the parsed source equals the imported regex, so the extractor reads the real thing", () => {
    expect(extractTsRegex(CANONICAL_SRC, "KEY_RE")).toBe(KEY_RE.source);
    expect(extractTsRegex(CANONICAL_SRC, "TEXT_HASH_RE")).toBe(TEXT_HASH_RE.source);
  });
  it("key probes: 63 accepted, 64 refused (KEY_RE and parseLegalText)", () => {
    for (const [v, ok] of KEY_PROBES) expect(KEY_RE.test(v), JSON.stringify(v)).toBe(ok);
    const doc = "---\nversion: 1\n---\nText.\n";
    expect(parseLegalText(k(63), doc).key).toBe(k(63));
    expect(() => parseLegalText(k(64), doc)).toThrow(LegalTextError);
  });
  it("hash probes", () => {
    for (const [v, ok] of HASH_PROBES) expect(TEXT_HASH_RE.test(v), JSON.stringify(v)).toBe(ok);
  });
});

describe("SQL (migration 184 CHECKs, 184 and 185 RPC argument checks)", () => {
  const keyPatterns = { "184": extractSqlPatterns(M184, "key", "p_key"), "185": extractSqlPatterns(M185, "key", "p_key") };
  const hashPatterns = { "184": extractSqlPatterns(M184, "text_hash", "p_text_hash"), "185": extractSqlPatterns(M185, "text_hash", "p_text_hash") };

  it("every key and hash predicate in both migrations equals the TypeScript regex (no layer drifts)", () => {
    // 184: two CHECK columns (acceptance and intent) plus four RPC argument checks; 185: the two RPCs.
    expect(keyPatterns["184"].length).toBeGreaterThanOrEqual(6);
    expect(hashPatterns["184"].length).toBeGreaterThanOrEqual(6);
    expect(keyPatterns["185"]).toHaveLength(2);
    expect(hashPatterns["185"]).toHaveLength(2);
    for (const p of [...keyPatterns["184"], ...keyPatterns["185"]]) expect(p).toBe(KEY_RE.source);
    for (const p of [...hashPatterns["184"], ...hashPatterns["185"]]) expect(p).toBe(TEXT_HASH_RE.source);
  });
  it("the SQL patterns accept a 63-character key and refuse 64, uppercase hex and a leading hyphen", () => {
    for (const p of [...keyPatterns["184"], ...keyPatterns["185"]]) {
      for (const [v, ok] of KEY_PROBES) expect(jsAccepts(p, v), `${p} ${JSON.stringify(v)}`).toBe(ok);
    }
    for (const p of [...hashPatterns["184"], ...hashPatterns["185"]]) {
      for (const [v, ok] of HASH_PROBES) expect(jsAccepts(p, v), `${p} ${JSON.stringify(v)}`).toBe(ok);
    }
  });
});

describe("bash (hold-gate-eval.sh, gate_web_acceptance)", () => {
  // TODO(PR-D, plugins/ agent): the `web-acceptance` gate is written by another implementer in parallel. Until the string
  // `web-acceptance` appears in the script this leg is SKIPPED; once it does, the leg runs and an empty extraction FAILS
  // (so the gate can never land without its key and hash patterns being checked against the other layers).
  const present = GATE_SRC.includes("web-acceptance");
  const bash = present ? extractBashPatterns(GATE_SRC) : { key: [] as string[], hash: [] as string[] };

  it.skipIf(!present)("the key and hash patterns exist (non-empty extraction)", () => {
    expect(bash.key.length).toBeGreaterThan(0);
    expect(bash.hash.length).toBeGreaterThan(0);
  });
  it.skipIf(!present)("bash accepts a 63-character key and refuses 64, a leading hyphen and uppercase; the hash is lowercase hex of exactly 64", () => {
    for (const p of bash.key) {
      for (const [v, ok] of KEY_PROBES) expect(bashAccepts(p, v), `${p} ${JSON.stringify(v)}`).toBe(ok);
    }
    for (const p of bash.hash) {
      for (const [v, ok] of HASH_PROBES) expect(bashAccepts(p, v), `${p} ${JSON.stringify(v)}`).toBe(ok);
    }
  });
  it.skipIf(!present)("the bash patterns are the TypeScript ones, character for character", () => {
    for (const p of bash.key) expect(p).toBe(KEY_RE.source);
    for (const p of bash.hash) expect(p).toBe(TEXT_HASH_RE.source);
  });
  it("skip guard: the leg is skipped only while the gate is absent from the script", () => {
    // If this fails, the script gained a web-acceptance gate whose body this test cannot find: fix the extractor.
    if (present) expect(/^gate_web_acceptance\s*\(\)\s*\{/m.test(GATE_SRC)).toBe(true);
    else expect(GATE_SRC).not.toMatch(/gate_web_acceptance/);
  });
});
