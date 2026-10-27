// lint-migration-api-grants.mjs — detection engine for
// lint-migration-api-grants.sh (ADR-303, the SUBORDINATE static tier of the
// two-tier table-grant guard; the runtime rls-fuzz grant gate is
// authoritative).
//
// PROPERTY (Guard 1 of the plan): every migration file checked here that
// creates a `public`-schema Data-API-visible relation (table / view /
// materialized view — temp and partition-child excluded) must carry an
// in-file api-role GRANT naming that relation — the column-list form
// `GRANT SELECT (a,b) ON TABLE <rel> TO <role>` counts, it IS api exposure —
// or a `-- soleur:no-data-api: <relation> — <reason>` sentinel (`public.`
// prefix accepted; reason REQUIRED, and the sentinel is honored ONLY inside a
// `--` line comment — one inside a block comment, string, or dollar-quoted
// body is noise, not an exemption). Tables with serial/identity columns —
// including `CREATE TABLE … (LIKE src INCLUDING ALL|IDENTITY)` copies —
// additionally need a sequence `GRANT USAGE` (post-flip sequences keep no
// USAGE default) or the sentinel; standalone `create sequence` needs the
// same. `GRANT … ON ALL TABLES/SEQUENCES IN SCHEMA public` is a blanket
// over-grant — flagged outright, never a satisfying form.
//
// PARSING: SQL noise is stripped FIRST (line comments, nested block comments,
// single-quoted strings, dollar-quoted bodies) — a `create table` inside a
// comment or a GRANT inside an `EXECUTE '…'` string must not be seen. The
// stripSqlNoise state machine below is a FAITHFUL PORT of
// test/migration-lint/definer-grants.ts › stripSqlNoise (the ADR-112
// precedent): plain JS so it runs under ambient `node` at the
// tenant-integration lint position (before setup-bun/setup-node/npm ci), and
// under bun/tsx locally. The two copies are pinned byte-for-output by
// test/migration-lint/api-grants-scan.test.ts — if you change one, change the
// other.
//
// DOCUMENTED BLIND SPOTS (subordinate tier — the live-catalog fuzz gate owns
// the residual): a relation created via dynamic `EXECUTE format('create
// table %I', …)` inside a DO block is invisible to source-form detection;
// `alter table … add column serial` on an existing table is likewise unseen.

import { readFileSync, realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";

export const API_ROLES = new Set(["anon", "authenticated", "service_role"]);

// ---------------------------------------------------------------------------
// Noise stripping — faithful port of test/migration-lint/definer-grants.ts
// (stripSqlNoise, ~line 100). Keep the two copies in lockstep; the parity test
// in test/migration-lint/api-grants-scan.test.ts diffs their outputs.
// ---------------------------------------------------------------------------

/**
 * Remove everything a top-level SQL parse must ignore, replacing each stripped
 * span with a single space so token boundaries survive:
 *   - `--` line comments
 *   - `/* *\/` block comments (Postgres allows nesting)
 *   - `'...'` single-quoted string literals (`''` escape)
 *   - `$$...$$` / `$tag$...$tag$` dollar-quoted bodies/strings
 * Positional params (`$1`) are left intact. A left-to-right state machine is
 * used because these constructs interact (a `--` inside a dollar body is NOT
 * a comment, a `$$` inside a line comment is NOT a dollar-quote).
 */
export function stripSqlNoise(sql) {
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

/**
 * Sibling profile for GRANT detection: strip `--`/`/* *\/` comments and
 * single-quoted strings but PRESERVE dollar-quoted bodies verbatim (`$` is an
 * ordinary char here).
 *
 * WHY the asymmetry: CREATE detection must NOT see inside function/DO bodies —
 * a `create table` there is deferred/dynamic creation (the documented
 * runtime-tier blind spot; GRANTing it in-file is impossible since it does not
 * exist at apply time). GRANT detection has the OPPOSITE need: the corpus's
 * own conditional-grant convention is a literal `GRANT` inside
 * `DO $$ BEGIN IF to_regclass(…) IS NOT NULL THEN GRANT … END IF; END $$;`
 * (the to_regclass pattern — migration 174 is 179 statements of exactly that
 * shape). Strip dollar bodies for grants and the corpus convention false-reds.
 * `EXECUTE 'GRANT …'` strings inside the body stay correctly invisible —
 * single-quoted strings are still stripped. Residual: `EXECUTE $tag$GRANT…$tag$`
 * (a nested dollar STRING) would count — the same dynamic-execute blind spot,
 * already owned by the runtime gate.
 */
export function stripSqlNoisePreserveBodies(sql) {
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
      i = nl;
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

    out += c;
    i++;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Balanced-paren helper (ported from the same precedent module).
// ---------------------------------------------------------------------------

function readBalancedParens(s, openIdx) {
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

/** Split a comma list at TOP-LEVEL commas only (parens/brackets are nested). */
function splitTopLevel(s) {
  const parts = [];
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

// ---------------------------------------------------------------------------
// Detectors (all operate on NOISE-STRIPPED sql)
// ---------------------------------------------------------------------------

const SCHEMA_NAME = String.raw`(?:"?([a-z_][a-z0-9_]*)"?\s*\.\s*)?"?([a-z_][a-z0-9_]*)"?`;
const TABLE_MOD = "(temp(?:orary)?|unlogged|foreign)";
const CREATE_TABLE_RE = new RegExp(
  String.raw`\bcreate\s+(?:(?:global|local)\s+)?${TABLE_MOD}?\s*table\s+(?:if\s+not\s+exists\s+)?${SCHEMA_NAME}`,
  "gi",
);
const CREATE_VIEW_RE = new RegExp(
  String.raw`\bcreate\s+(?:or\s+replace\s+)?view\s+(?:if\s+not\s+exists\s+)?${SCHEMA_NAME}`,
  "gi",
);
const CREATE_MATVIEW_RE = new RegExp(
  String.raw`\bcreate\s+(?:or\s+replace\s+)?materialized\s+view\s+(?:if\s+not\s+exists\s+)?${SCHEMA_NAME}`,
  "gi",
);
const CREATE_SEQ_RE = new RegExp(
  String.raw`\bcreate\s+(temp(?:orary)?\s+)?sequence\s+(?:if\s+not\s+exists\s+)?${SCHEMA_NAME}`,
  "gi",
);

const PARTITION_OF_RE = /\bpartition\s+of\b/i;
const SERIAL_RE = /\b(?:bigserial|smallserial|serial\d*)\b/i;
const IDENTITY_RE = /\bgenerated\s+(?:always|by\s+default)\s+as\s+identity\b/i;
// `CREATE TABLE t (LIKE src INCLUDING ALL|INCLUDING IDENTITY)` materializes
// serial/identity columns copied from `src` — the backing sequence needs the
// same USAGE arm even though no serial/identity keyword appears in the span.
// (`INCLUDING ALL EXCLUDING IDENTITY` still triggers — over-requiring is the
// safe direction; the sentinel is the escape.)
const LIKE_COPY_RE = /\blike\b[\s\S]*\bincluding\s+(?:all|identity)\b/i;
const CONSTRAINT_HEADS = new Set([
  "primary", "foreign", "unique", "check", "constraint", "exclude", "like",
]);

/** The tail of a statement: text from `start` to the next `;` (noise-stripped — literals are already gone). */
function stmtSpan(stripped, start) {
  const semi = stripped.indexOf(";", start);
  return stripped.slice(start, semi === -1 ? stripped.length : semi);
}

/**
 * Every public relation a file creates. `kind` ∈ table|view|matview|sequence;
 * `seqColumns` lists the expected backing-sequence names
 * (`<table>_<col>_seq`) for serial/identity columns — `null` when an
 * identity/serial keyword was present but no column names could be derived
 * (e.g. a `like`-copy), in which case a presence-of-any sequence grant
 * satisfies the arm.
 */
export function extractCreates(stripped) {
  const out = [];
  const push = (m, kind, modIdx) => {
    const modifier = modIdx !== undefined ? (m[modIdx] ?? "").toLowerCase() : "";
    if (modifier.startsWith("temp")) return; // temp relations live in pg_temp, never `public`
    const schema = (m[modIdx === undefined ? 1 : modIdx + 1] ?? "").toLowerCase();
    if (schema && schema !== "public") return; // explicitly another schema — not ours
    const name = (m[modIdx === undefined ? 2 : modIdx + 2] ?? "").toLowerCase();
    const span = stmtSpan(stripped, m.index);
    if (kind === "table" && PARTITION_OF_RE.test(span)) return; // partition children inherit the parent's ACL
    out.push({ name, kind, start: m.index, end: m.index + m[0].length, span });
  };
  for (const m of stripped.matchAll(CREATE_TABLE_RE)) push(m, "table", 1);
  for (const m of stripped.matchAll(CREATE_VIEW_RE)) push(m, "view", undefined);
  for (const m of stripped.matchAll(CREATE_MATVIEW_RE)) push(m, "matview", undefined);
  for (const m of stripped.matchAll(CREATE_SEQ_RE)) push(m, "sequence", 1);
  return out;
}

/**
 * Detect serial/identity columns in a table create's parenthesized list;
 * returns expected sequence names, null when column names cannot be derived
 * (the caller then requires ANY sequence USAGE grant in the file). A
 * `LIKE src INCLUDING ALL|IDENTITY` copy returns null — the copied identity
 * columns' sequence names live in the SOURCE table's definition, not this
 * span.
 */
function autoSeqNames(create, stripped) {
  if (!(SERIAL_RE.test(create.span) || IDENTITY_RE.test(create.span) || LIKE_COPY_RE.test(create.span))) return [];
  const paren = stripped.indexOf("(", create.end - 1);
  if (paren === -1 || paren >= create.start + create.span.length) return null;
  const { inner, end } = readBalancedParens(stripped, paren);
  if (end === -1) return null;
  const names = [];
  for (const item of splitTopLevel(inner)) {
    const t = item.trim();
    const head = /^"?([a-z_][a-z0-9_]*)"?/i.exec(t)?.[1]?.toLowerCase();
    if (!head || CONSTRAINT_HEADS.has(head)) continue;
    if (SERIAL_RE.test(t) || IDENTITY_RE.test(t)) names.push(`${create.name}_${head}_seq`);
  }
  return names.length ? names : null;
}

/**
 * api-role grants on relations, keyed by normalized bare name.
 * `ON TABLE` keyword optional (Postgres default object type for GRANT is the
 * table family). Sequence grants tracked separately — the serial/identity arm
 * requires USAGE (or ALL) specifically.
 */
export function extractGrants(stripped) {
  const tableGrants = new Map(); // name -> Set<apiRole>
  const seqUsage = new Map(); // name -> Set<apiRole> holding USAGE/ALL

  const record = (m, seq) => {
    const schema = (m[2] ?? "").toLowerCase();
    if (schema && schema !== "public") return;
    const name = (m[3] ?? "").toLowerCase();
    const roles = (m[4] ?? "")
      .split(",")
      // First identifier of each segment is the role name — tolerates
      // `to anon with grant option`, `to group admins`, quoted roles.
      .map((seg) => (/^(?:group\s+)?"?([a-z_][a-z0-9_]*)"?/i.exec(seg.trim())?.[1] ?? "").toLowerCase());
    const granted = roles.filter((r) => API_ROLES.has(r));
    if (!granted.length) return;
    const verbs = m[1].toUpperCase();
    if (seq) {
      if (!/\bUSAGE\b/.test(verbs) && !/^ALL\b/.test(verbs)) return;
      const set = seqUsage.get(name) ?? new Set();
      for (const r of granted) set.add(r);
      seqUsage.set(name, set);
    } else {
      const set = tableGrants.get(name) ?? new Set();
      for (const r of granted) set.add(r);
      tableGrants.set(name, set);
    }
  };

  const GRANT_TABLE = new RegExp(
    String.raw`\bgrant\s+([a-z_,\s]+?)\s+on\s+(?:table\s+)?${SCHEMA_NAME}\s+to\s+([^;]+?)\s*;`,
    "gi",
  );
  for (const m of stripped.matchAll(GRANT_TABLE)) record(m, false);

  // Column-list form: `GRANT SELECT (a,b) ON TABLE t TO authenticated`
  // (comma-separated multi-privilege lists `SELECT (a), UPDATE (b)` match too).
  // A column-level grant IS api exposure for the relation — the corpus's own
  // 006/079 deliberate splits use it — so it satisfies the relation arm
  // exactly like a table-level grant would. Group layout matches `record`.
  const GRANT_TABLE_COL = new RegExp(
    String.raw`\bgrant\s+([a-z_]+\s*\([^)]*\)\s*(?:,\s*[a-z_]+\s*\([^)]*\)\s*)*)\s+on\s+(?:table\s+)?${SCHEMA_NAME}\s+to\s+([^;]+?)\s*;`,
    "gi",
  );
  for (const m of stripped.matchAll(GRANT_TABLE_COL)) record(m, false);

  const GRANT_SEQ = new RegExp(
    String.raw`\bgrant\s+([a-z_,\s]+?)\s+on\s+sequence\s+${SCHEMA_NAME}\s+to\s+([^;]+?)\s*;`,
    "gi",
  );
  for (const m of stripped.matchAll(GRANT_SEQ)) record(m, true);

  return { tableGrants, seqUsage };
}

/**
 * `GRANT … ON ALL TABLES|SEQUENCES IN SCHEMA <s> TO <roles>` — a schema-wide
 * blanket grant, NOT a satisfying form: it grants every existing public
 * relation indiscriminately, which is the over-exposure the guard exists to
 * prevent. Returned as a violation when the target schema is `public` and at
 * least one api role is in the TO-list, so the form can neither silently pass
 * nor fail opaquely. Scanned on the body-preserving strip (a literal blanket
 * GRANT inside a `DO $$ … $$` still counts — same reasoning as GRANTs).
 */
export function extractBlanketGrants(preservedStripped) {
  const out = [];
  const GRANT_ALL = /\bgrant\s+([a-z_,\s()]+?)\s+on\s+all\s+(tables|sequences)\s+in\s+schema\s+"?([a-z_][a-z0-9_]*)"?\s+to\s+([^;]+?)\s*;/gi;
  for (const m of preservedStripped.matchAll(GRANT_ALL)) {
    const schema = (m[3] ?? "").toLowerCase();
    if (schema !== "public") continue;
    const roles = (m[4] ?? "")
      .split(",")
      .map((seg) => (/^(?:group\s+)?"?([a-z_][a-z0-9_]*)"?/i.exec(seg.trim())?.[1] ?? "").toLowerCase())
      .filter((r) => API_ROLES.has(r));
    if (!roles.length) continue;
    out.push(`GRANT … ON ALL ${m[2].toUpperCase()} IN SCHEMA public TO ${roles.join(", ")}`);
  }
  return out;
}

/**
 * `-- soleur:no-data-api: [public.]<relation> — <reason>` sentinels.
 *
 * Honored ONLY inside `--` line comments — a marker inside a `/* *\/` block
 * comment, a `'…'` literal, or a `$$…$$`/`$tag$` body is prose inside noise,
 * not a top-level sentinel (a raw-text scan would let a commented-out
 * example or an `EXECUTE '… -- soleur:…'` string exempt a real relation).
 * The scan therefore re-runs the same state machine instead of a bare
 * matchAll. The `<relation>` accepts an optional `public.` qualifier
 * (unquoted or `"public"."t"`-ish) so the sentinel reads like the GRANT it
 * replaces. Reason is REQUIRED; `null` reason flags a violation when the
 * sentinel is consulted.
 */
export function extractSentinels(raw) {
  const out = new Map(); // name -> {reason: string|null}
  const re = /soleur:no-data-api[ \t]*:[ \t]*(?:"?public"?\s*\.\s*)?"?([a-z_][a-z0-9_]*)"?[ \t]*(?:[—–-][ \t]*([^\n]*))?/gi;
  let i = 0;
  const n = raw.length;
  while (i < n) {
    const c = raw[i];
    const two = raw.slice(i, i + 2);

    if (two === "--") {
      const nl = raw.indexOf("\n", i);
      const comment = raw.slice(i + 2, nl === -1 ? n : nl);
      for (const m of comment.matchAll(re)) {
        out.set(m[1].toLowerCase(), { reason: (m[2] ?? "").trim() || null });
      }
      if (nl === -1) break;
      i = nl; // preserve the newline
      continue;
    }

    if (two === "/*") {
      let depth = 1;
      i += 2;
      while (i < n && depth > 0) {
        const t = raw.slice(i, i + 2);
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
      continue;
    }

    if (c === "'") {
      i++;
      while (i < n) {
        if (raw[i] === "'" && raw[i + 1] === "'") {
          i += 2;
          continue;
        }
        if (raw[i] === "'") {
          i++;
          break;
        }
        i++;
      }
      continue;
    }

    if (c === "$") {
      const m = /^\$([A-Za-z_][A-Za-z0-9_]*)?\$/.exec(raw.slice(i, i + 64));
      if (m) {
        const tag = m[0];
        const end = raw.indexOf(tag, i + tag.length);
        i = end === -1 ? n : end + tag.length;
        continue;
      }
    }

    i++;
  }
  return out;
}

const FIX_HINT =
  "Grant only the roles/verbs the API actually needs — anon usually needs NOTHING;\n" +
  "  table-level and column-list (`GRANT SELECT (a,b) ON TABLE <rel> TO <role>`) forms both satisfy.\n" +
  "  BOTH write sites are required, or the fuzz parity gate reds later:\n" +
  "    1. this file: e.g. GRANT SELECT ON TABLE public.<rel> TO authenticated;\n" +
  "    2. test/rls-fuzz/table-grants.ts: an OVERRIDES `exposed({…})` entry mirroring the GRANTs\n" +
  "       (the authoritative gate asserts effective == registered, both directions).\n" +
  "  To opt out of the Data API entirely, also BOTH sites:\n" +
  "    1. this file: `-- soleur:no-data-api: <rel> — <reason>` (reason REQUIRED);\n" +
  "    2. test/rls-fuzz/table-grants.ts: an INTERNAL entry carrying that reason.\n" +
  "  `GRANT … ON ALL TABLES|SEQUENCES IN SCHEMA public` is NOT accepted (blanket over-grant).\n" +
  "  See ADR-303; the authoritative gate is test/rls-fuzz/rls-grants.integration.test.ts.";

/**
 * Check one migration file's text. Returns a list of violation strings
 * (empty = pass).
 */
export function checkSql(raw) {
  const stripped = stripSqlNoise(raw);
  const creates = extractCreates(stripped);
  // Grants scan a DIFFERENT noise profile (see stripSqlNoisePreserveBodies):
  // literal GRANTs inside `DO $$ … THEN GRANT … $$` are the corpus's
  // conditional-grant convention and must count.
  const preserved = stripSqlNoisePreserveBodies(raw);
  const { tableGrants, seqUsage } = extractGrants(preserved);
  const sentinels = extractSentinels(raw);
  const violations = [];

  for (const b of extractBlanketGrants(preserved)) {
    violations.push(
      `uses '${b}' — a schema-wide blanket grant is not a per-relation grant: it gives an api role privileges on EVERY existing public relation. Grant only the relation(s) this migration creates, with only the verbs the API needs.`,
    );
  }

  for (const c of creates) {
    const sent = sentinels.get(c.name);
    if (sent !== undefined) {
      if (!sent.reason) {
        violations.push(
          `sentinel '-- soleur:no-data-api: ${c.name} — <reason>' has no reason — the reason is REQUIRED (a reason-free exemption is an allowlist entry with no rationale)`,
        );
      }
      continue;
    }
    if (c.kind === "sequence") {
      if (!seqUsage.has(c.name)) {
        violations.push(
          `creates public sequence '${c.name}' without a sequence GRANT USAGE or sentinel (post-flip sequences keep no api-role USAGE default).\n  ${FIX_HINT}`,
        );
      }
      continue;
    }
    if (!tableGrants.has(c.name)) {
      violations.push(
        `creates public ${c.kind} '${c.name}' without an api-role GRANT naming it, or a soleur:no-data-api sentinel.\n  ${FIX_HINT}`,
      );
    }
    const seqs = autoSeqNames(c, stripped);
    if (seqs === null) {
      // serial/identity keyword present but column names underivable — accept
      // any sequence USAGE grant in the file (the runtime gate names the real
      // sequence if this guess is wrong).
      if (seqUsage.size === 0) {
        violations.push(
          `'${c.name}' has a serial/identity column whose backing sequence name cannot be derived — requires 'GRANT USAGE ON SEQUENCE public.<seq> TO <api-role>' or the sentinel.\n  ${FIX_HINT}`,
        );
      }
    } else {
      for (const seq of seqs) {
        if (!seqUsage.has(seq)) {
          violations.push(
            `'${c.name}' has serial/identity columns — requires 'GRANT USAGE ON SEQUENCE public.${seq} TO <api-role>' or the sentinel (post-flip sequences keep no USAGE default).\n  ${FIX_HINT}`,
          );
        }
      }
    }
  }
  return violations;
}

/** Lint a list of files; prints ::error:: lines + a summary. Exit: 0 clean, 1 violations, 2 invocation error. */
export function main(files) {
  let violations = 0;
  let relations = 0;
  for (const file of files) {
    let raw;
    try {
      raw = readFileSync(file, "utf8");
    } catch (e) {
      console.error(`::error::lint-migration-api-grants: cannot read ${file}: ${e.message}`);
      return 2;
    }
    const label = file.split("/").pop();
    if (label.endsWith(".down.sql")) continue; // operator-only rollback siblings, never applied
    const stripped = stripSqlNoise(raw);
    relations += extractCreates(stripped).length;
    for (const v of checkSql(raw)) {
      console.error(`::error::${label}: ${v.split("\n").join("\n::error::  ")}`);
      violations++;
    }
  }
  if (violations > 0) {
    console.error("");
    console.error(`::error::lint-migration-api-grants: ${violations} ungranted public relation(s)`);
    return 1;
  }
  console.log(`lint-migration-api-grants: ${files.length} file(s) checked, ${relations} relation(s) scanned, no violations.`);
  return 0;
}

const invokedAsMain = (() => {
  try {
    return process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url);
  } catch {
    return false;
  }
})();

if (invokedAsMain) {
  const files = process.argv.slice(2);
  if (!files.length) {
    console.error("usage: lint-migration-api-grants.mjs <file.sql> [file.sql ...]");
    process.exit(2);
  }
  process.exit(main(files));
}
