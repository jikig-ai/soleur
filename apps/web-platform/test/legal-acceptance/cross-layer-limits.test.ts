/**
 * #12011 PR-D (AC11, Guard 2 row 10): the key and hash limits are ONE rule counted once across layers.
 *
 * The shapes are EXTRACTED from the source of every layer, never restated here:
 *  - TypeScript: `KEY_RE` and `TEXT_HASH_RE` in server/legal-acceptance/canonical.ts (imported AND parsed from the source);
 *  - SQL: the CHECK constraints of migration 184 and the argument checks of the RPCs in 184 and 185;
 *  - bash: the `=~` patterns inside `gate_web_acceptance` in plugins/soleur/skills/ship/scripts/hold-gate-eval.sh.
 * The bearer token length is the same kind of shared limit: `TOKEN_RE` in the verify route and the two `bc_shape_ok` length
 * lines in plugins/soleur/scripts/lib/bearer-fetch.sh are extracted and both must say 48 to 256.
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
const ROUTE_SRC = read(path.join(WEB, "app/api/internal/legal-acceptance/[key]/route.ts"));
const HELPER_SRC = read(path.join(REPO, "plugins/soleur/scripts/lib/bearer-fetch.sh"));

// ── extractors (each throws on an empty result) ─────────────────────────────────────────────────────────────────

const nonEmpty = <T,>(what: string, xs: T[]): T[] => {
  if (xs.length === 0) throw new Error(`extraction found nothing: ${what}`);
  return xs;
};

/** Bash with comments removed: a `#` that starts a word outside quotes ends the line. Quoted `#` (in a pattern or a string) is kept. */
export function stripBashComments(src: string): string {
  return src
    .split("\n")
    .map((line) => {
      let quote = "";
      for (let i = 0; i < line.length; i++) {
        const c = line[i];
        if (quote) {
          if (c === quote) quote = "";
          else if (c === "\\" && quote === '"') i++;
        } else if (c === "'" || c === '"') quote = c;
        else if (c === "\\") i++;
        else if (c === "#" && (i === 0 || /\s/.test(line[i - 1]))) return line.slice(0, i);
      }
      return line;
    })
    .join("\n");
}

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
  const body = stripBashComments(rest.slice(0, end < 0 ? rest.length : end)); // a comment that names `=~ $WA_KEY_RE` is not an application
  const assigned = (name: string): string[] => [...src.matchAll(new RegExp(`^${name}='([^']+)'$`, "gm"))].map((m) => m[1]);
  const key = nonEmpty("bash WA_KEY_RE assignment", assigned("WA_KEY_RE"));
  const hash = nonEmpty("bash WA_HASH_RE assignment", assigned("WA_HASH_RE"));
  nonEmpty("bash =~ $WA_KEY_RE inside gate_web_acceptance", body.match(/=~ \$WA_KEY_RE\b/g) ?? []);
  nonEmpty("bash =~ $WA_HASH_RE inside gate_web_acceptance", body.match(/=~ \$WA_HASH_RE\b/g) ?? []);
  return { key, hash };
}

/** The route's `const TOKEN_RE = /^[...]{min,max}$/;` -> {min, max}. */
export function extractRouteTokenBounds(src: string): { min: number; max: number } {
  const m = /^const TOKEN_RE = \/\^\[[^\]]+\]\{(\d+),(\d+)\}\$\/;$/m.exec(src);
  const hit = nonEmpty("route TOKEN_RE {min,max}", m ? [m] : [])[0];
  return { min: Number(hit[1]), max: Number(hit[2]) };
}

/** The helper's `bc_shape_ok` length lines, found by their exact text: `[ "${#1}" -ge N ] || return 1` and `-le N`. */
export function extractHelperTokenBounds(src: string): { min: number; max: number } {
  const start = src.search(/^bc_shape_ok\(\)/m);
  if (start < 0) throw new Error("extraction found nothing: bc_shape_ok is not in the helper");
  const rest = src.slice(start);
  const end = rest.search(/^\}/m);
  const body = rest.slice(0, end < 0 ? rest.length : end);
  const ge = nonEmpty("helper -ge line", [...body.matchAll(/^\s*\[ "\$\{#1\}" -ge (\d+) \] \|\| return 1\s*$/gm)]);
  const le = nonEmpty("helper -le line", [...body.matchAll(/^\s*\[ "\$\{#1\}" -le (\d+) \] \|\| return 1\s*$/gm)]);
  if (ge.length !== 1 || le.length !== 1) throw new Error("expected exactly one -ge and one -le length line in bc_shape_ok");
  return { min: Number(ge[0][1]), max: Number(le[0][1]) };
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
    expect(() =>
      extractBashPatterns("WA_KEY_RE='^a$'\nWA_HASH_RE='^b$'\ngate_web_acceptance() {\n  # [[ $k =~ $WA_KEY_RE ]] && [[ $h =~ $WA_HASH_RE ]]\n  : # =~ $WA_KEY_RE =~ $WA_HASH_RE\n}\n"),
    ).toThrow(/found nothing/);
    expect(
      extractBashPatterns("WA_KEY_RE='^a#$'\nWA_HASH_RE='^b$'\ngate_web_acceptance() {\n  [[ $k =~ $WA_KEY_RE ]] && [[ $h =~ $WA_HASH_RE ]] # ok\n}\n"),
    ).toEqual({ key: ["^a#$"], hash: ["^b$"] });
    expect(() => extractRouteTokenBounds("const TOKEN_RE = /^[a-z]+$/;")).toThrow(/found nothing/);
    expect(() => extractHelperTokenBounds("nothing here")).toThrow(/bc_shape_ok is not in the helper/);
    expect(() => extractHelperTokenBounds("bc_shape_ok() {\n  :\n}\n")).toThrow(/found nothing/);
    expect(() => extractHelperTokenBounds('bc_shape_ok() {\n  [ "${#1}" -ge 48 ] || return 1\n}\n')).toThrow(/found nothing/);
  });
});

describe("negative controls on the REAL sources", () => {
  it("a widened bash key, an uppercase bash hash and a widened SQL CHECK are each detected as a mismatch", () => {
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
  // Extraction is unconditional: an empty extraction throws at collection time, so the gate can never lose its key and hash
  // patterns without this suite going red.
  const bash = extractBashPatterns(GATE_SRC);

  it("the key and hash patterns exist (non-empty extraction)", () => {
    expect(bash.key.length).toBeGreaterThan(0);
    expect(bash.hash.length).toBeGreaterThan(0);
  });
  it("bash accepts a 63-character key and refuses 64, a leading hyphen and uppercase; the hash is lowercase hex of exactly 64", () => {
    for (const p of bash.key) {
      for (const [v, ok] of KEY_PROBES) expect(bashAccepts(p, v), `${p} ${JSON.stringify(v)}`).toBe(ok);
    }
    for (const p of bash.hash) {
      for (const [v, ok] of HASH_PROBES) expect(bashAccepts(p, v), `${p} ${JSON.stringify(v)}`).toBe(ok);
    }
  });
  it("the bash patterns are the TypeScript ones, character for character", () => {
    for (const p of bash.key) expect(p).toBe(KEY_RE.source);
    for (const p of bash.hash) expect(p).toBe(TEXT_HASH_RE.source);
  });
});

describe("bearer token length (verify route TOKEN_RE and the helper's bc_shape_ok)", () => {
  const route = extractRouteTokenBounds(ROUTE_SRC);
  const helper = extractHelperTokenBounds(HELPER_SRC);

  it("both layers say 48 to 256", () => {
    expect(route).toEqual({ min: 48, max: 256 });
    expect(helper).toEqual({ min: 48, max: 256 });
  });
  it("the two layers agree with each other", () => {
    expect(helper).toEqual(route);
  });
  it("the extractors see a one-character drift in either layer (negative control on the real sources)", () => {
    expect(extractRouteTokenBounds(ROUTE_SRC.replace("{48,256}", "{32,256}"))).not.toEqual(helper);
    expect(extractHelperTokenBounds(HELPER_SRC.replace("-le 256 ]", "-le 512 ]"))).not.toEqual(route);
  });
  it("the route regex accepts 48 and 256 characters and refuses 47 and 257 (the real regex, not a restatement)", () => {
    const re = new RegExp(/^const TOKEN_RE = \/(.+)\/;$/m.exec(ROUTE_SRC)![1]);
    expect(re.test("a".repeat(47))).toBe(false);
    expect(re.test("a".repeat(48))).toBe(true);
    expect(re.test("a".repeat(256))).toBe(true);
    expect(re.test("a".repeat(257))).toBe(false);
  });
});
