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

export interface DefinerFn {
  file: string;
  /** unqualified function name (public. stripped). */
  name: string;
  /** type-vector signature, e.g. "uuid, uuid, integer" (param names + DEFAULT clauses stripped). */
  signature: string;
  /** the noise-stripped declaration header (CREATE … up to the body-start delimiter). */
  header: string;
  returnsTrigger: boolean;
}

export interface RoleStmt {
  name: string;
  signature: string;
  roles: Set<string>;
}
export interface DropStmt {
  name: string;
  signature: string;
}

export interface CorpusFile {
  file: string;
  sql: string;
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

const TYPE_ALIASES: Record<string, string> = {
  int: "integer",
  int4: "integer",
  int8: "bigint",
  int2: "smallint",
  bool: "boolean",
};

function normalizeParam(param: string): string {
  // Drop the DEFAULT / `= …` clause. `\bdefault\b` (not `default\s+…`) so the clause
  // is stripped even when its value was already removed by stripSqlNoise (a
  // string-literal default like `DEFAULT '{}'` becomes `DEFAULT` with nothing after
  // it, which `default\s+` would miss → a spurious `jsonb default` type token).
  let p = param.replace(/\s+default\b[\s\S]*$/i, "").replace(/\s*=[\s\S]*$/, "");
  // drop a leading arg-mode keyword
  p = p.replace(/^\s*(in|out|inout|variadic)\s+/i, "");
  p = p.trim().replace(/\s+/g, " ");
  if (p === "") return "";
  // `name type…` vs bare `type…`: in this corpus every CREATE param is
  // `name type` (verified: no unnamed params, no multi-word types on the param
  // side) and every REVOKE/DROP param is a bare type. If ≥2 whitespace tokens,
  // the first is the name → drop it; else the single token is the type.
  const tokens = p.split(" ");
  const typeStr = (tokens.length >= 2 ? tokens.slice(1).join(" ") : tokens[0]).toLowerCase();
  // canonicalise the base type name (handles `int` vs `integer`), preserving any
  // `[]` / `(n,m)` suffix.
  const suffixMatch = /^([a-z_ ]+)(\[\]|\(.*\))?$/.exec(typeStr);
  if (!suffixMatch) return typeStr;
  const base = suffixMatch[1].trim();
  const suffix = suffixMatch[2] ?? "";
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
    // Header = CREATE … up to the statement terminator. The body was stripped to a
    // space, so the first top-level `;` after the params is the statement end (or a
    // `begin atomic` SQL-standard body, which carries no `;` before its own `end;`).
    const semi = sql.indexOf(";", end + 1);
    const header = sql.slice(m.index!, semi === -1 ? undefined : semi);
    if (!/\bsecurity\s+definer\b/i.test(header)) continue;
    fns.push({
      file,
      name,
      signature: normalizeSignature(inner),
      header,
      returnsTrigger: /\breturns\s+trigger\b/i.test(header),
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
    out.push({ name, signature: normalizeSignature(inner), roles });
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
    out.push({ name, signature: normalizeSignature(inner) });
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
  opts: { authenticatedCallable: Set<string>; grandfather: Set<string> },
): DefinerVerdict[] {
  // Stable ordering: sort files by name so lexical migration order = apply order.
  const sorted = [...files].sort((a, b) => a.file.localeCompare(b.file));

  const events = new Map<string, FnEvent[]>();
  const revokeUnion = new Map<string, Set<string>>();

  // Monotonic sequence in document order (creates emitted before drops per file).
  // A single identity is never both created and dropped in the same file, so
  // creates-before-drops within a file cannot mis-order a real (create, drop) pair;
  // cross-file order is what decides existence, and file sort = apply order.
  let seq = 0;
  sorted.forEach((f) => {
    for (const fn of extractDefinerFns(f.file, f.sql)) {
      const k = key(fn.name, fn.signature);
      const arr = events.get(k) ?? [];
      arr.push({ order: seq++, kind: "create", fn });
      events.set(k, arr);
    }
    for (const d of parseDrops(f.sql)) {
      const k = key(d.name, d.signature);
      const arr = events.get(k) ?? [];
      arr.push({ order: seq++, kind: "drop" });
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
