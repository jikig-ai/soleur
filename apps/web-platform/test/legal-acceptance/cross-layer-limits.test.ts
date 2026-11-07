/**
 * #12011 PR-D (AC11, Guard 2 row 10): the key and hash limits are ONE rule counted once across layers.
 *
 * The shapes are EXTRACTED from the source of every layer, never restated here:
 *  - TypeScript: `KEY_RE` and `TEXT_HASH_RE` in server/legal-acceptance/canonical.ts (imported AND parsed from the source);
 *  - SQL: the CHECK constraints of migration 184 and the argument checks of the RPCs in 184 and 185;
 *  - bash: the `=~` patterns inside `gate_web_acceptance` in plugins/soleur/skills/ship/scripts/hold-gate-eval.sh.
 * The bearer token length is the same kind of shared limit: `TOKEN_RE` in the verify route and the two `bc_shape_ok` length
 * lines in plugins/soleur/scripts/lib/bearer-fetch.sh are extracted and both must say 48 to 256.
 * The minted bearer token (#12196, apps/web-platform/infra/legal-acceptance-secrets.tf) is the same kind of shared limit: its
 * generators are parsed out of EVERY infra .tf file and held against the route's bound (the last describe in this file).
 * An empty extraction FAILS (a regex that no longer finds anything must not read as "all layers agree").
 * The boundary is pinned the same way everywhere: a key of 63 characters is accepted and one of 64 is refused.
 */
import { spawnSync } from "node:child_process";
import { readFileSync, readdirSync } from "node:fs";
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

// ── the minted token (apps/web-platform/infra/legal-acceptance-secrets.tf) against the route bound ─────────────
// #12196. Nothing else reads the .tf, so a generator drifting below the route's lower bound, a `special = true`, a second
// secret under the same name or an `ignore_changes` would ship green and answer 503 (or never reach Doppler) in production.
// The population is every `doppler_secret` under apps/web-platform/infra/*.tf named LEGAL_ACCEPTANCE_VERIFY_TOKEN (never
// "the two in the new file"), plus the `random_password` each one references. All reads happen inside the `it` bodies: a throw
// at collection would break every other test in this file.

const TOKEN_NAME = "LEGAL_ACCEPTANCE_VERIFY_TOKEN";
const INFRA = path.join(WEB, "infra");

/** HCL with `#`, `//` and block comments removed; a comment marker inside a double-quoted string is kept. */
export function stripHclComments(src: string): string {
  let out = "";
  let inStr = false;
  let i = 0;
  while (i < src.length) {
    const c = src[i];
    const n = src[i + 1];
    if (inStr) {
      out += c;
      if (c === "\\") {
        out += n ?? "";
        i += 2;
        continue;
      }
      if (c === '"') inStr = false;
      i++;
      continue;
    }
    if (c === '"') {
      inStr = true;
      out += c;
      i++;
    } else if (c === "#" || (c === "/" && n === "/")) {
      while (i < src.length && src[i] !== "\n") i++;
    } else if (c === "/" && n === "*") {
      const e = src.indexOf("*/", i + 2);
      out += " ";
      i = e < 0 ? src.length : e + 2;
    } else {
      out += c;
      i++;
    }
  }
  return out;
}

/** Index of the `}` that matches the `{` at `open` (strings skipped), or -1. */
function matchBrace(src: string, open: number): number {
  let depth = 0;
  let inStr = false;
  for (let i = open; i < src.length; i++) {
    const c = src[i];
    if (inStr) {
      if (c === "\\") i++;
      else if (c === '"') inStr = false;
    } else if (c === '"') inStr = true;
    else if (c === "{") depth++;
    else if (c === "}" && --depth === 0) return i;
  }
  return -1;
}

export type HclResource = { type: string; name: string; file: string; attrs: Record<string, string>; nested: string[]; raw: string };

/** Every `resource "T" "N" { ... }` of the given files: top-level attributes and the names of directly nested blocks only. */
export function parseHclResources(files: Record<string, string>): HclResource[] {
  const out: HclResource[] = [];
  for (const [file, text] of Object.entries(files)) {
    const src = stripHclComments(text);
    for (const m of src.matchAll(/^[ \t]*resource\s+"([^"]+)"\s+"([^"]+)"\s*\{/gm)) {
      const open = m.index + m[0].length - 1;
      const close = matchBrace(src, open);
      if (close < 0) throw new Error(`unbalanced braces in ${file} (resource ${m[1]}.${m[2]})`);
      const body = src.slice(open + 1, close);
      let top = "";
      const nested: string[] = [];
      for (let i = 0; i < body.length; i++) {
        if (body[i] === "{") {
          const end = matchBrace(body, i);
          if (end < 0) throw new Error(`unbalanced braces inside ${file} (resource ${m[1]}.${m[2]})`);
          const id = /([A-Za-z_][\w-]*)\s*(?:"[^"]*"\s*)*$/.exec(top);
          if (id) nested.push(id[1]);
          top += "{}";
          i = end;
        } else top += body[i];
      }
      const attrs: Record<string, string> = {};
      for (const line of top.split("\n")) {
        const a = /^\s*([A-Za-z_]\w*)\s*=\s*(.*?)\s*$/.exec(line);
        if (a) attrs[a[1]] = a[2];
      }
      out.push({ type: m[1], name: m[2], file, attrs, nested, raw: body });
    }
  }
  return out;
}

const unquote = (v: string | undefined): string | undefined => {
  const m = v === undefined ? null : /^"(.*)"$/.exec(v);
  return m ? m[1] : undefined;
};

/**
 * Every way the Terraform files can mint LEGAL_ACCEPTANCE_VERIFY_TOKEN in a way the route would refuse, or in a way that
 * would not reach Doppler on a regenerate. Returns the violations; throws when the population is empty (an extraction that
 * found nothing must not read as "all members agree").
 */
export function tokenViolations(files: Record<string, string>, bounds: { min: number; max: number }): string[] {
  const all = parseHclResources(files);
  const secrets = nonEmpty(
    `doppler_secret named ${TOKEN_NAME} in the infra .tf files`,
    all.filter((r) => r.type === "doppler_secret" && (unquote(r.attrs.name) === TOKEN_NAME || r.name.includes("legal_acceptance_verify_token"))),
  );
  const v: string[] = [];
  const named = secrets.filter((r) => unquote(r.attrs.name) === TOKEN_NAME);
  if (named.length !== 2) v.push(`expected exactly 2 doppler_secret blocks named ${TOKEN_NAME}, found ${named.length}`);
  const configs = named.map((r) => unquote(r.attrs.config)).sort();
  if (JSON.stringify(configs) !== JSON.stringify(["dev", "prd"])) v.push(`configs must be exactly dev and prd, found ${JSON.stringify(configs)}`);
  const generators = new Set<string>();
  for (const s of secrets) {
    const id = `doppler_secret.${s.name}`;
    if (unquote(s.attrs.name) !== TOKEN_NAME) v.push(`${id}: name is not ${TOKEN_NAME}`);
    if (unquote(s.attrs.project) !== "soleur") v.push(`${id}: project must be "soleur"`);
    if (unquote(s.attrs.visibility) !== "masked") v.push(`${id}: visibility must be "masked"`);
    if (s.nested.includes("lifecycle") || /\bignore_changes\b/.test(s.raw)) v.push(`${id}: no lifecycle or ignore_changes (a -replace must reach Doppler)`);
    const ref = /^random_password\.([A-Za-z0-9_-]+)\.result$/.exec(s.attrs.value ?? "");
    if (!ref) {
      v.push(`${id}: value must be random_password.<generator>.result, found ${JSON.stringify(s.attrs.value)}`);
      continue;
    }
    if (generators.has(ref[1])) v.push(`${id}: generator ${ref[1]} is shared with the other config (dev and prd must differ)`);
    generators.add(ref[1]);
    const gen = all.find((r) => r.type === "random_password" && r.name === ref[1]);
    if (!gen) {
      v.push(`${id}: generator random_password.${ref[1]} is not defined in the infra files`);
      continue;
    }
    const len = /^\d+$/.test(gen.attrs.length ?? "") ? Number(gen.attrs.length) : NaN;
    if (!(len >= bounds.min && len <= bounds.max)) v.push(`random_password.${gen.name}: length ${JSON.stringify(gen.attrs.length)} is outside the route bound ${bounds.min} to ${bounds.max}`);
    if (gen.attrs.special !== "false") v.push(`random_password.${gen.name}: special must be written as false (the provider default is true), found ${JSON.stringify(gen.attrs.special)}`);
  }
  return v;
}

describe("the minted token (legal-acceptance-secrets.tf) against the route bound", () => {
  const infra = (): Record<string, string> =>
    Object.fromEntries(
      readdirSync(INFRA)
        .filter((f) => f.endsWith(".tf"))
        .map((f) => [f, read(path.join(INFRA, f))]),
    );
  const bounds = () => extractRouteTokenBounds(ROUTE_SRC);
  const FILE = "legal-acceptance-secrets.tf";
  const block = (files: Record<string, string>, type: string, name: string): { start: number; end: number } => {
    const src = files[FILE];
    const start = src.search(new RegExp(`^resource "${type}" "${name}" \\{`, "m"));
    if (start < 0) throw new Error(`mutation target not found: ${type}.${name}`);
    return { start, end: matchBrace(src, src.indexOf("{", start)) + 1 };
  };
  /** The real file with one resource's text rewritten; asserts the mutation LANDED. */
  const mutate = ([type, name]: readonly [string, string], edit: (b: string) => string): Record<string, string> => {
    const files = infra();
    const { start, end } = block(files, type, name);
    const before = files[FILE];
    const after = before.slice(0, start) + edit(before.slice(start, end)) + before.slice(end);
    expect(after, `mutation of ${type}.${name} did not land`).not.toBe(before);
    return { ...files, [FILE]: after };
  };
  const PRD_GEN = ["random_password", "legal_acceptance_verify_token_prd"] as const;
  const DEV_GEN = ["random_password", "legal_acceptance_verify_token_dev"] as const;
  const PRD_SEC = ["doppler_secret", "legal_acceptance_verify_token_prd"] as const;
  const DEV_SEC = ["doppler_secret", "legal_acceptance_verify_token_dev"] as const;

  it("the real files mint exactly two masked secrets (dev, prd) from two distinct 48-character alphanumeric generators", () => {
    const files = infra();
    expect(tokenViolations(files, bounds())).toEqual([]);
    const res = parseHclResources(files);
    expect(res.filter((r) => r.type === "doppler_secret" && unquote(r.attrs.name) === TOKEN_NAME)).toHaveLength(2);
    expect(res.filter((r) => r.type === "random_password" && r.name.startsWith("legal_acceptance_verify_token_"))).toHaveLength(2);
    expect(bounds()).toEqual({ min: 48, max: 256 });
  });

  it("an empty extraction throws instead of reading as agreement (rename both, no file, comments only)", () => {
    expect(() => tokenViolations({}, bounds())).toThrow(/found nothing/);
    expect(() => tokenViolations({ [FILE]: "# resource \"doppler_secret\" \"x\" {}\n" }, bounds())).toThrow(/found nothing/);
    const renamed = infra();
    renamed[FILE] = renamed[FILE].replaceAll(TOKEN_NAME, "SOMETHING_ELSE").replaceAll("legal_acceptance_verify_token", "other_token");
    expect(() => tokenViolations(renamed, bounds())).toThrow(/found nothing/);
  });

  it("a generator below the lower bound, above the upper bound or off the exact class is detected", () => {
    for (const gen of [PRD_GEN, DEV_GEN]) {
      expect(tokenViolations(mutate(gen, (b) => b.replace(/length\s*=\s*48/, () => "length = 32")), bounds()).join("\n")).toMatch(/outside the route bound/);
      expect(tokenViolations(mutate(gen, (b) => b.replace(/length\s*=\s*48/, () => "length = 300")), bounds()).join("\n")).toMatch(/outside the route bound/);
      expect(tokenViolations(mutate(gen, (b) => b.replace(/special\s*=\s*false/, () => "special = true")), bounds()).join("\n")).toMatch(/special must be written as false/);
      expect(tokenViolations(mutate(gen, (b) => b.replace(/^\s*special\s*=\s*false\n/m, () => "")), bounds()).join("\n")).toMatch(/special must be written as false/);
      expect(tokenViolations(mutate(gen, (b) => b.replace(/special\s*=\s*false/, () => "# special = false")), bounds()).join("\n")).toMatch(/special must be written as false/);
    }
  });

  it("a resource written on one line is parsed, not skipped (and is judged like any other)", () => {
    const one = mutate(PRD_GEN, () => 'resource "random_password" "legal_acceptance_verify_token_prd" { length = 48 }');
    expect(parseHclResources(one).find((r) => r.name === "legal_acceptance_verify_token_prd")?.attrs.length).toBe("48");
    expect(tokenViolations(one, bounds()).join("\n")).toMatch(/special must be written as false/);
  });

  it("a second secret under the same name in ANOTHER file is detected (the population is directory-wide)", () => {
    const files = infra();
    files["zz-extra.tf"] = 'resource "doppler_secret" "extra" {\n  project = "soleur"\n  config = "stg"\n  name = "LEGAL_ACCEPTANCE_VERIFY_TOKEN"\n  value = random_password.legal_acceptance_verify_token_prd.result\n  visibility = "masked"\n}\n';
    const v = tokenViolations(files, bounds()).join("\n");
    expect(v).toMatch(/exactly 2 doppler_secret blocks/);
    expect(v).toMatch(/configs must be exactly dev and prd/);
  });

  it("dev and prd sharing a generator is detected", () => {
    const shared = mutate(DEV_SEC, (b) => b.replace("legal_acceptance_verify_token_dev.result", () => "legal_acceptance_verify_token_prd.result"));
    expect(tokenViolations(shared, bounds()).join("\n")).toMatch(/shared with the other config/);
  });

  it("a value that is not a generator reference (literal, variable, hex) is detected", () => {
    for (const value of ['"literal-value"', "var.token", "random_id.x.hex"]) {
      const files = mutate(PRD_SEC, (b) => b.replace(/value\s*=\s*random_password\.[\w-]+\.result/, () => `value = ${value}`));
      expect(tokenViolations(files, bounds()).join("\n"), value).toMatch(/value must be random_password/);
    }
  });

  it("ignore_changes or any lifecycle block on a secret is detected; one on a SIBLING resource is not attributed to it", () => {
    for (const sec of [PRD_SEC, DEV_SEC]) {
      const ic = mutate(sec, (b) => b.replace(/\}\s*$/, () => "  lifecycle {\n    ignore_changes = [value]\n  }\n}"));
      expect(tokenViolations(ic, bounds()).join("\n")).toMatch(/no lifecycle or ignore_changes/);
    }
    const sibling = infra();
    sibling["zz-sibling.tf"] = 'resource "doppler_secret" "unrelated" {\n  project = "soleur"\n  config = "prd"\n  name = "OTHER"\n  value = "x"\n  lifecycle {\n    ignore_changes = [value]\n  }\n}\n';
    expect(tokenViolations(sibling, bounds())).toEqual([]);
  });

  it("must-PASS inputs that are not the canonical text: attributes reordered, a trailing comment, length 64", () => {
    const reordered = mutate(PRD_GEN, (b) => b.replace(/^(\s*length\s*=\s*48\n)(\s*special\s*=\s*false\n)/m, (_m, a: string, c: string) => c + a));
    expect(tokenViolations(reordered, bounds())).toEqual([]);
    const commented = mutate(DEV_GEN, (b) => b.replace(/length\s*=\s*48/, () => "length = 48 # the route lower bound"));
    expect(tokenViolations(commented, bounds())).toEqual([]);
    const sixtyFour = mutate(PRD_GEN, (b) => b.replace(/length\s*=\s*48/, () => "length = 64"));
    expect(tokenViolations(sixtyFour, bounds())).toEqual([]);
  });

  it("the comment stripper keeps a marker inside a string and drops the three comment forms", () => {
    expect(stripHclComments('a = "x # y" # c\nb = 1 // d\n/* e\nf */ g = 2')).toBe('a = "x # y" \nb = 1 \n  g = 2');
  });
});
