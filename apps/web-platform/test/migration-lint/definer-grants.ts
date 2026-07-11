// DB-free SECURITY DEFINER grant-hygiene detector (#6328, ADR-112).
//
// TWO-TIER GUARD. The AUTHORITATIVE durable guard for DEFINER grant hygiene is the
// runtime `rls-authz-fuzz` AC8 gate (live `pg_proc.proacl` introspection, per-
// migration-PR — see `test/rls-fuzz/{catalog.ts,rpc-cases.ts}`). This module is the
// SUBORDINATE, no-stack, fast STATIC pre-filter: advisory fast-feedback that runs in
// the ordinary web-platform vitest suite, NEVER coverage-bearing. A non-vacuity
// parity guard (`test/rls-fuzz/rls-rpc.integration.test.ts`) ties the set this module
// detects to AC8's live enumeration so the static tier cannot silently regress.
//
// WHY IT EXISTS (#6306 blind spot): the previous static lint was case-sensitive and
// `AS $$`-body-form-only, so it silently passed over the five lowercase `security
// definer` files (incl. the exact #6306 functions and `handle_new_user`) — a green
// lint dead for a whole authoring style is false confidence. This module detects
// EVERY `CREATE ... SECURITY DEFINER` function declaration case-insensitively and
// body-form-agnostically, and computes a corpus-wide revoke-union so a service-role-
// only definer fn that keeps Supabase's CREATE-time `{public, anon, authenticated}`
// EXECUTE grants (an RLS-bypassing cross-tenant surface) is flagged.
//
// PARSING STRATEGY: strip all SQL noise (comments, dollar-quoted bodies, single-
// quoted strings) first, then match the CREATE FUNCTION *declaration header* (up to
// the body-start delimiter) — never the body. The header carries everything the
// assertions need (`security definer`, `returns trigger`, `set search_path`); the
// body is irrelevant and its `EXECUTE 'GRANT ...'` strings must not be mistaken for
// top-level grants.

import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";

export interface DefinerFn {
  file: string;
  /** unqualified function name (public. stripped, lower-cased to match pg_proc.proname). */
  name: string;
  /** type-vector signature, e.g. "uuid, uuid, integer" (param names + DEFAULT clauses stripped). */
  signature: string;
  /** the noise-stripped declaration header (CREATE … up to the body-start delimiter). */
  header: string;
  returnsTrigger: boolean;
  /** char offset of the CREATE within the file's noise-stripped SQL (for event ordering). */
  pos: number;
}

export interface RoleStmt {
  name: string;
  signature: string;
  roles: Set<string>;
}
export interface DropStmt {
  name: string;
  signature: string;
  /** char offset of the DROP within the file's noise-stripped SQL (for event ordering). */
  pos: number;
}

export interface CorpusFile {
  file: string;
  sql: string;
}

/**
 * A forward (non-down) migration file. Down files re-GRANT anon/authenticated and
 * sort lexically BEFORE their forward sibling, so they must never enter the corpus
 * (`128_…down.sql` restores the residual grants; `run-migrations.sh:125,251` skips
 * them for the same reason). Single source of truth for the forward-only convention,
 * shared by the static lint AND the rls-fuzz parity guard so the two tiers cannot
 * diverge on which files count.
 */
export function isForwardMigrationFile(name: string): boolean {
  return name.endsWith(".sql") && !name.endsWith(".down.sql");
}

/** Load the forward-only migration corpus (excludes `*.down.sql`), sorted by name. */
export function loadForwardCorpus(dir: string): CorpusFile[] {
  return readdirSync(dir)
    .filter(isForwardMigrationFile)
    .sort()
    .map((file) => ({ file, sql: readFileSync(path.join(dir, file), "utf8") }));
}

export type Classification =
  | "pass-union"
  | "returns-trigger"
  | "dropped"
  | "authenticated-callable"
  | "grandfather"
  | "violation";

export interface DefinerVerdict {
  fn: DefinerFn;
  classification: Classification;
  /** union of roles REVOKEd for this (name, signature) across the whole corpus. */
  revokedRoles: string[];
}

/** The three roles a service-role-only DEFINER fn must be revoked from. `public`
 *  is a superset of `{anon, authenticated}`, so all three are load-bearing. */
export const REQUIRED_REVOKE_ROLES = ["public", "anon", "authenticated"] as const;

// ---------------------------------------------------------------------------
// Noise stripping (comments, dollar bodies, single-quoted strings)
// ---------------------------------------------------------------------------

/**
 * Remove everything a top-level SQL parse must ignore, replacing each stripped
 * span with a single space so token boundaries survive:
 *   - `--` line comments
 *   - `/* *\/` block comments (Postgres allows nesting)
 *   - `'...'` single-quoted string literals (`''` escape)
 *   - `$$...$$` / `$tag$...$tag$` dollar-quoted bodies/strings
 * Positional params (`$1`) are left intact. A left-to-right state machine is used
 * because these constructs interact (a `--` inside a dollar body is NOT a comment,
 * a `$$` inside a line comment is NOT a dollar-quote), which naive ordered
 * `.replace()` passes get wrong (035/053/068 carry block comments; 068 has real
 * grants; plpgsql bodies carry `EXECUTE 'GRANT ...'`).
 */
export function stripSqlNoise(sql: string): string {
  let out = "";
  let i = 0;
  const n = sql.length;
  while (i < n) {
    const c = sql[i];
    const two = sql.slice(i, i + 2);

    if (two === "--") {
      const nl = sql.indexOf("\n", i);
      out += " ";
      if (nl === -1) break;
      i = nl; // preserve the newline
      continue;
    }

    if (two === "/*") {
      let depth = 1;
      i += 2;
      while (i < n && depth > 0) {
        const t = sql.slice(i, i + 2);
        if (t === "/*") {
          depth++;
          i += 2;
        } else if (t === "*/") {
          depth--;
          i += 2;
        } else {
          i++;
        }
      }
      out += " ";
      continue;
    }

    if (c === "'") {
      i++;
      while (i < n) {
        if (sql[i] === "'" && sql[i + 1] === "'") {
          i += 2;
          continue;
        }
        if (sql[i] === "'") {
          i++;
          break;
        }
        i++;
      }
      out += " ";
      continue;
    }

    if (c === "$") {
      const m = /^\$([A-Za-z_][A-Za-z0-9_]*)?\$/.exec(sql.slice(i, i + 64));
      if (m) {
        const tag = m[0];
        const end = sql.indexOf(tag, i + tag.length);
        out += " ";
        i = end === -1 ? n : end + tag.length;
        continue;
      }
    }

    out += c;
    i++;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Signature normalization (type vector)
// ---------------------------------------------------------------------------

/** Split a comma list at TOP-LEVEL commas only (parens/brackets are nested). */
function splitTopLevel(s: string): string[] {
  const parts: string[] = [];
  let depth = 0;
  let cur = "";
  for (const ch of s) {
    if (ch === "(" || ch === "[") depth++;
    else if (ch === ")" || ch === "]") depth--;
    if (ch === "," && depth === 0) {
      parts.push(cur);
      cur = "";
    } else {
      cur += ch;
    }
  }
  if (cur.trim() !== "" || parts.length > 0) parts.push(cur);
  return parts;
}

// Canonicalise cross-spellings so a CREATE-side spelling matches its REVOKE/DROP-side
// spelling (both hand-written, occasionally divergent). Keyed by the base type name.
const TYPE_ALIASES: Record<string, string> = {
  int: "integer",
  int4: "integer",
  int8: "bigint",
  int2: "smallint",
  bool: "boolean",
  decimal: "numeric",
  varchar: "character varying",
  char: "character",
  float4: "real",
  float8: "double precision",
  timestamptz: "timestamp with time zone",
  timetz: "time with time zone",
};

// The first word of a Postgres type. Used to decide, in a whitespace-split param,
// whether token[0] is a param NAME (`p_x uuid`) or the START OF A (possibly
// multi-word) TYPE with no name (`double precision`, a bare REVOKE/DROP arg). A
// param name is never a type keyword, so "token[0] is a type head ⇒ no name" is
// robust for both single- and multi-word types — the fix for the prior
// "always drop token[0]" heuristic that mangled `double precision` → `precision`.
const TYPE_HEAD_WORDS = new Set([
  "uuid", "text", "integer", "int", "int2", "int4", "int8", "bigint", "smallint",
  "boolean", "bool", "numeric", "decimal", "real", "double", "money", "jsonb", "json",
  "date", "timestamp", "timestamptz", "time", "timetz", "interval", "bytea",
  "character", "char", "varchar", "bit", "inet", "cidr", "macaddr", "xml",
  "serial", "bigserial", "smallserial", "float", "float4", "float8",
]);

/** Strip an array `[]` or parametric `(n,m)` suffix and lower-case a type token. */
function typeBase(token: string): string {
  return token.replace(/(\[\]|\(.*\)).*$/, "").trim().toLowerCase();
}

function normalizeParam(param: string): string {
  // Drop the DEFAULT / `= …` clause. `\bdefault\b` (not `default\s+…`) so the clause
  // is stripped even when its value was already removed by stripSqlNoise (a
  // string-literal default like `DEFAULT '{}'` becomes `DEFAULT` with nothing after
  // it, which `default\s+` would miss → a spurious `jsonb default` type token).
  let p = param.replace(/\s+default\b[\s\S]*$/i, "").replace(/\s*=[\s\S]*$/, "");
  // drop a leading arg-mode keyword (OUT params ARE kept in the vector — this corpus
  // has none, and OUT-param identity-arg exclusion is out of scope; a future OUT
  // param would fail LOUD as a signature mismatch, never a silent pass).
  p = p.replace(/^\s*(in|out|inout|variadic)\s+/i, "");
  p = p.trim().replace(/\s+/g, " ");
  if (p === "") return "";
  const tokens = p.split(" ");
  // token[0] is a type head → no param name, the whole thing is a (multi-word) type.
  // Otherwise token[0] is the param name; the rest is the type.
  const typeStr = (
    tokens.length === 1 || TYPE_HEAD_WORDS.has(typeBase(tokens[0]))
      ? tokens.join(" ")
      : tokens.slice(1).join(" ")
  ).toLowerCase();
  // canonicalise the base type name (int↔integer, timestamptz↔timestamp with time
  // zone, …), preserving any `[]` / `(n,m)` suffix. Normalise inner-paren whitespace
  // so `numeric(10, 2)` (CREATE) matches `numeric(10,2)` (REVOKE).
  const suffixMatch = /^([a-z_ ]+)(\[\]|\(.*\))?$/.exec(typeStr);
  if (!suffixMatch) return typeStr.replace(/\s*,\s*/g, ",");
  const base = suffixMatch[1].trim();
  const suffix = (suffixMatch[2] ?? "").replace(/\s*,\s*/g, ",");
  return (TYPE_ALIASES[base] ?? base) + suffix;
}

/** Reduce a parameter list (CREATE or REVOKE/GRANT/DROP form) to a canonical type vector. */
export function normalizeSignature(params: string): string {
  const trimmed = params.trim();
  if (trimmed === "") return "";
  return splitTopLevel(trimmed)
    .map(normalizeParam)
    .filter((t) => t.length > 0)
    .join(", ");
}

// ---------------------------------------------------------------------------
// Balanced-paren helpers
// ---------------------------------------------------------------------------

function readBalancedParens(s: string, openIdx: number): { inner: string; end: number } {
  let depth = 0;
  for (let i = openIdx; i < s.length; i++) {
    if (s[i] === "(") depth++;
    else if (s[i] === ")") {
      depth--;
      if (depth === 0) return { inner: s.slice(openIdx + 1, i), end: i };
    }
  }
  return { inner: "", end: -1 };
}

// ---------------------------------------------------------------------------
// CREATE FUNCTION detection
// ---------------------------------------------------------------------------

const CREATE_FN_RE = /\bcreate\s+(?:or\s+replace\s+)?function\s+(?:public\.)?([a-z_][a-z0-9_]*)\s*\(/gi;

/**
 * Detect every `CREATE ... SECURITY DEFINER` function in one migration file.
 * Case-insensitive, body-form-agnostic (the header up to the body-start delimiter
 * is all that is read). Non-DEFINER functions are skipped.
 */
export function extractDefinerFns(file: string, rawSql: string): DefinerFn[] {
  const sql = stripSqlNoise(rawSql);
  const fns: DefinerFn[] = [];
  for (const m of sql.matchAll(CREATE_FN_RE)) {
    const name = m[1]!;
    const parenStart = m.index! + m[0].length - 1;
    const { inner, end } = readBalancedParens(sql, parenStart);
    if (end === -1) continue;
    // Header = CREATE … up to the first `;` after the params. Dollar-quoted bodies
    // were blanked by stripSqlNoise, so for the common `AS $$…$$;` form that `;` is
    // the statement terminator. For a `BEGIN ATOMIC … END;` SQL-standard body (NOT
    // dollar-quoted, so NOT blanked) the first `;` lands INSIDE the body — but every
    // function-level attribute we read (SECURITY DEFINER, RETURNS, SET search_path)
    // precedes BEGIN ATOMIC, so the truncated header still contains them. We only
    // ever read the header for keyword presence, never the body, so the truncation is
    // harmless (the corpus has zero BEGIN ATOMIC fns today regardless).
    const semi = sql.indexOf(";", end + 1);
    const header = sql.slice(m.index!, semi === -1 ? undefined : semi);
    if (!/\bsecurity\s+definer\b/i.test(header)) continue;
    fns.push({
      file,
      // lower-case to match pg_proc.proname (unquoted idents fold lower); keeps the
      // allowlist / parity keys aligned even if a future fn is defined mixed-case.
      name: name.toLowerCase(),
      signature: normalizeSignature(inner),
      header,
      returnsTrigger: /\breturns\s+trigger\b/i.test(header),
      pos: m.index!,
    });
  }
  return fns;
}

// ---------------------------------------------------------------------------
// GRANT / REVOKE / DROP parsing
// ---------------------------------------------------------------------------

function parseRoleStmts(
  sql: string,
  head: RegExp,
  roleKeyword: "from" | "to",
): RoleStmt[] {
  const stripped = stripSqlNoise(sql);
  const out: RoleStmt[] = [];
  const tailRe = new RegExp(`^\\s*${roleKeyword}\\s+([^;]+);`, "i");
  for (const m of stripped.matchAll(head)) {
    const name = m[1]!;
    const parenStart = m.index! + m[0].length - 1;
    const { inner, end } = readBalancedParens(stripped, parenStart);
    if (end === -1) continue;
    const tm = tailRe.exec(stripped.slice(end + 1));
    if (!tm) continue;
    const roles = new Set(
      tm[1]!
        .split(",")
        .map((r) => r.trim().toLowerCase())
        .filter(Boolean),
    );
    out.push({ name: name.toLowerCase(), signature: normalizeSignature(inner), roles });
  }
  return out;
}

export function parseRevokes(sql: string): RoleStmt[] {
  return parseRoleStmts(
    sql,
    /\brevoke\s+(?:all(?:\s+privileges)?|execute)\s+on\s+function\s+(?:public\.)?([a-z_][a-z0-9_]*)\s*\(/gi,
    "from",
  );
}

// NOTE: parseGrants is deliberately NOT consulted by classifyDefinerFns. The static
// tier models only REVOKEs (the revoke-union), never net grant state — a
// `revoke-all-3 → later GRANT to authenticated` sequence is the runtime AC8 gate's
// domain (live `proacl`), a documented residual (see classifyDefinerFns). It is
// exported + tested for use by callers doing their own grant introspection.
export function parseGrants(sql: string): RoleStmt[] {
  return parseRoleStmts(
    sql,
    /\bgrant\s+execute\s+on\s+function\s+(?:public\.)?([a-z_][a-z0-9_]*)\s*\(/gi,
    "to",
  );
}

/**
 * Non-vacuity / live-catalog-parity check (ADR-112, plan Phase 4 / AC10). Returns
 * the names of live SECURITY DEFINER functions that the static detector does NOT
 * find over `corpus`. A non-empty result means the static tier under-detects
 * relative to the authoritative live catalog and must not be trusted — it is the
 * guard that keeps "zero silent skips" from being self-referential (the static tier
 * grading its own homework). Callers pass `securityDefinerAuthenticatedFns` /
 * `allSecurityDefinerFns` catalog names from the migrated DB.
 */
export function staticallyUndetectedDefinerFns(
  liveNames: string[],
  corpus: CorpusFile[],
): string[] {
  const detected = new Set(
    corpus.flatMap((c) => extractDefinerFns(c.file, c.sql)).map((f) => f.name),
  );
  return [...new Set(liveNames)].filter((n) => !detected.has(n)).sort();
}

export function parseDrops(sql: string): DropStmt[] {
  const stripped = stripSqlNoise(sql);
  const out: DropStmt[] = [];
  const re = /\bdrop\s+function\s+(?:if\s+exists\s+)?(?:public\.)?([a-z_][a-z0-9_]*)\s*\(/gi;
  for (const m of stripped.matchAll(re)) {
    const name = m[1]!;
    const parenStart = m.index! + m[0].length - 1;
    const { inner, end } = readBalancedParens(stripped, parenStart);
    if (end === -1) continue;
    out.push({ name: name.toLowerCase(), signature: normalizeSignature(inner), pos: m.index! });
  }
  return out;
}

// ---------------------------------------------------------------------------
// Corpus resolution: the revoke-union classifier
// ---------------------------------------------------------------------------

const key = (name: string, signature: string) => `${name}(${signature})`;

interface FnEvent {
  order: number;
  kind: "create" | "drop";
  fn?: DefinerFn;
}

/**
 * Classify every SECURITY DEFINER function across the corpus.
 *
 * CALLER CONTRACT: pass FORWARD migrations only — exclude `*.down.sql`. Down files
 * sort lexically BEFORE their forward `.sql` and re-GRANT anon/authenticated
 * (`128_…down.sql` restores the residual grants), which would poison the
 * revoke-union; `run-migrations.sh:125,251` skips them for the same reason.
 *
 * Identity = (name, type-signature). For each identity, the LATEST create/drop
 * event decides existence (a DROP-without-later-recreate is excluded — the dropped
 * 3-arg `acquire_conversation_slot` must not false-VIOLATE). An active definer fn is:
 *   - `returns-trigger`   → excluded (trigger fns have no GRANT EXECUTE path)
 *   - `authenticated-callable` → in the caller-supplied allowlist (the AC8 registry)
 *   - `grandfather`       → in the caller-supplied grandfather allowlist
 *   - `pass-union`        → the corpus REVOKEs it from all of {public, anon, authenticated}
 *   - `violation`         → none of the above (a residual-grant surface)
 *
 * The classifier does NOT re-implement `has_function_privilege()` — AC8 computes net
 * grant state exactly at runtime. The revoke-then-DROP+CREATE-without-re-revoke case
 * is a documented residual the static union does not model; AC8 owns it.
 */
export function classifyDefinerFns(
  files: CorpusFile[],
  opts: { authenticatedCallable: ReadonlySet<string>; grandfather: ReadonlySet<string> },
): DefinerVerdict[] {
  // Stable ordering: sort files by name so lexical migration order = apply order.
  const sorted = [...files].sort((a, b) => a.file.localeCompare(b.file));

  const events = new Map<string, FnEvent[]>();
  const revokeUnion = new Map<string, Set<string>>();

  // Order events by TRUE source position: (fileIndex, charOffset-within-file). A
  // single migration can `DROP FUNCTION f(sig); CREATE FUNCTION f(sig)` the SAME
  // identity (e.g. 067 check_my_revocation) — a creates-before-drops-per-file scheme
  // would mis-rank the recreate BEFORE the drop and mark a live fn `dropped`,
  // silently skipping its assertions. extractDefinerFns/parseDrops both carry `pos`
  // (offset in the identically noise-stripped SQL), so positions are comparable
  // within a file; file sort = apply order across files. FILE_STRIDE must exceed any
  // migration file length so cross-file order always dominates intra-file offset.
  const FILE_STRIDE = 1e9;
  sorted.forEach((f, fileIdx) => {
    const base = fileIdx * FILE_STRIDE;
    for (const fn of extractDefinerFns(f.file, f.sql)) {
      const k = key(fn.name, fn.signature);
      const arr = events.get(k) ?? [];
      arr.push({ order: base + fn.pos, kind: "create", fn });
      events.set(k, arr);
    }
    for (const d of parseDrops(f.sql)) {
      const k = key(d.name, d.signature);
      const arr = events.get(k) ?? [];
      arr.push({ order: base + d.pos, kind: "drop" });
      events.set(k, arr);
    }
    for (const r of parseRevokes(f.sql)) {
      const k = key(r.name, r.signature);
      const set = revokeUnion.get(k) ?? new Set<string>();
      for (const role of r.roles) set.add(role);
      revokeUnion.set(k, set);
    }
  });

  const verdicts: DefinerVerdict[] = [];
  for (const [k, evs] of events) {
    const last = [...evs].sort((a, b) => a.order - b.order).at(-1)!;
    if (last.kind === "drop") {
      // dropped-without-recreate — represent it with its latest create (for context)
      const lastCreate = evs.filter((e) => e.kind === "create").sort((a, b) => a.order - b.order).at(-1);
      if (lastCreate?.fn) {
        verdicts.push({ fn: lastCreate.fn, classification: "dropped", revokedRoles: [] });
      }
      continue;
    }
    const fn = last.fn!;
    const revoked = revokeUnion.get(k) ?? new Set<string>();
    const revokedRoles = [...revoked].sort();

    let classification: Classification;
    if (fn.returnsTrigger) {
      classification = "returns-trigger";
    } else if (opts.authenticatedCallable.has(fn.name)) {
      classification = "authenticated-callable";
    } else if (opts.grandfather.has(fn.name) || opts.grandfather.has(key(fn.name, fn.signature))) {
      classification = "grandfather";
    } else if (REQUIRED_REVOKE_ROLES.every((role) => revoked.has(role))) {
      classification = "pass-union";
    } else {
      classification = "violation";
    }
    verdicts.push({ fn, classification, revokedRoles });
  }
  return verdicts;
}
