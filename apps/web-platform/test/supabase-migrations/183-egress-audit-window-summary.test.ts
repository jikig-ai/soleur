import { describe, it, expect } from "vitest";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { PAGE_LIMIT, RPC_DENIAL_PREFIX } from "@/lib/egress-audit/summary";
import { ATTACK_SQL, CLASSIFIED_DEFINER_FN_NAMES } from "../rls-fuzz/rpc-cases";

// Migration-shape and body-parity test for 183_egress_audit_window_summary.sql (#11238).
// Offline text lint. Behaviour that needs an auth boundary or real rows (per-window inclusion, cross-tenant,
// grants as the engine sees them, live parity with the 177 function) runs in the live-database harness:
// test/rls-fuzz/egress-audit-rollup.integration.test.ts (RLS_FUZZ_LOCAL=1, local database only).
//
// This file pins what DIFFERS from migration 177 (signature without defaults, the CASE map, statement order,
// the window-derived v_lo, grants, down file, verify rows) and, in Guard 1, that everything ELSE is the
// 177 body (clamp, sums, top-N, materialization, slack bounds): those are pinned once, by comparing the two
// bodies, not a second time here. The 177 file is read-only here: it is the oracle and is immutable.
//
// The SQL allowlist (24h / 7d / 30d) is checked against TIME_WINDOWS in the helpers test, not here.

const MIG = path.join(__dirname, "../../supabase/migrations");
const UP = path.join(MIG, "183_egress_audit_window_summary.sql");
const DOWN = path.join(MIG, "183_egress_audit_window_summary.down.sql");
const VERIFY = path.join(__dirname, "../../supabase/verify/183_egress_audit_window_summary.sql");
const UP_177 = path.join(MIG, "177_egress_audit_summary_rpc.sql");

const read = (p: string): string => (existsSync(p) ? readFileSync(p, "utf8") : "");
const stripComments = (s: string): string => s.replace(/\/\*[\s\S]*?\*\//g, "").replace(/--[^\n]*/g, "");
const up = read(UP);
const down = read(DOWN);
const verify = read(VERIFY);
const up177 = read(UP_177);
const upExec = stripComments(up);
const downExec = stripComments(down);
const verifyExec = stripComments(verify);

const NAME = "get_egress_audit_window_summary";
const NAME_177 = "get_egress_audit_summary";
const SIG = `public.${NAME}(uuid, integer, text, text)`;
const escapeRe = (t: string): string => t.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const DENIAL_PREFIX_VALUE = "egress audit: ";

// ---------------------------------------------------------------------------
// Guard 1 chokepoint: body parity between the 177 function and the 183 function.
// Both bodies flow through extractStatement -> collapse -> normalize. Never anchor on a bare function name: it
// also matches REVOKE / GRANT / COMMENT lines, and the two names share a prefix.
// ---------------------------------------------------------------------------

/** The `CREATE OR REPLACE FUNCTION public.<name>(` ... `$$;` statement, comments stripped; "" when absent. */
const extractStatement = (sql: string, name: string): string =>
  stripComments(sql).match(new RegExp(`CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+public\\.${name}\\s*\\([\\s\\S]*?\\$\\$;`, "i"))?.[0] ?? "";

/** Whitespace collapsed AND spacing around ( ) , ; removed OUTSIDE string literals, so a reflowed `(\n x` equals `(x`. */
const collapse = (s: string): string =>
  s
    // SQL string literals are kept byte-for-byte: spacing inside '( other)' is data, not layout
    .split(/('(?:[^']|'')*')/)
    .map((part, i) => (i % 2 === 1 ? part : part.replace(/\s+/g, " ").replace(/\s*([(),;])\s*/g, "$1")))
    .join("")
    .replace(/ {2,}/g, " ")
    .trim();

type Norm = { from: string; to: string; side: "177" | "183" };
const TOKEN_DECL = "@@LO_DECL@@";
// The explicit, exact, line-level list of permitted differences. Nothing else may differ. The DECLARE block is
// never dropped: v_limit, v_now, v_last and v_result stay in the comparison.
const NORMALIZATIONS: Norm[] = [
  { side: "177", from: collapse("v_lo timestamptz := now() - interval '30 days';"), to: TOKEN_DECL },
  { side: "183", from: collapse("v_span interval; v_lo timestamptz;"), to: TOKEN_DECL },
  {
    side: "183",
    from: collapse(
      `v_span := CASE p_window WHEN '24h' THEN interval '24 hours' WHEN '7d' THEN interval '7 days' WHEN '30d' THEN interval '30 days' END;
       IF v_span IS NULL THEN RAISE EXCEPTION 'egress audit: invalid window' USING ERRCODE = '22023'; END IF;`,
    ),
    to: "",
  },
  { side: "183", from: collapse("v_lo := v_now - v_span;"), to: "" },
];

const STATEMENT_FLOOR = 15; // the 177 statement has 19 `;`; a failed extraction must not compare two empty strings

/** Normalize one extracted statement: (a) signature + name, then the line-level list for that side. */
const normalizeBody = (stmt: string, side: "177" | "183", norms: Norm[]): string => {
  let c = collapse(stmt);
  c = c.replace(/^CREATE OR REPLACE FUNCTION public\.\w+\(.*?\)RETURNS/i, "CREATE OR REPLACE FUNCTION <NAME>(<PARAMS>)RETURNS");
  for (const n of norms.filter((x) => x.side === side)) {
    const parts = c.split(n.from);
    // each permitted difference must be present exactly once, or the comparison is not the one specified
    if (parts.length !== 2) throw new Error(`normalization (${side}) matched ${parts.length - 1} times: ${n.from.slice(0, 60)}`);
    c = parts.join(n.to);
  }
  return c;
};

/** The guard. Throws on a vacuous extraction; returns both normalized bodies for comparison. */
const parityBodies = (sql177: string, sql183: string, norms: Norm[] = NORMALIZATIONS): { a: string; b: string } => {
  const s177 = extractStatement(sql177, NAME_177);
  const s183 = extractStatement(sql183, NAME);
  for (const [label, s] of [["177", s177], ["183", s183]] as const) {
    if (s === "" || (s.match(/;/g) ?? []).length < STATEMENT_FLOOR) throw new Error(`vacuous extraction for ${label}`);
  }
  return { a: normalizeBody(s177, "177", norms), b: normalizeBody(s183, "183", norms) };
};
const parityHolds = (sql177: string, sql183: string, norms?: Norm[]): boolean => {
  const { a, b } = parityBodies(sql177, sql183, norms);
  return a === b;
};

// ---------------------------------------------------------------------------
// Order and tenant chokepoints (functions so the mutation rows can feed mutated text through them)
// ---------------------------------------------------------------------------
const bodyOf = (execSql: string): string => execSql.match(/\$\$\s*DECLARE[\s\S]*?BEGIN([\s\S]*?)\$\$;/i)?.[1] ?? "";

/** Statement-order violations in a 183-shaped (comment-stripped) text; [] when the order is the specified one. */
const orderViolations = (execSql: string): string[] => {
  const body = bodyOf(execSql);
  const out: string[] = [];
  const authzAt = body.indexOf("workspace membership required");
  const jtiAt = body.indexOf("is_jti_denied_from_jwt()");
  const jtiEnd = body.indexOf("END IF;", jtiAt) + "END IF;".length;
  const decisionAt = body.indexOf("invalid decision filter");
  const windowAt = body.indexOf("invalid window");
  const probeAt = body.search(/IF\s+v_limit\s*=\s*0\s+THEN/i);
  const firstWindowRef = body.indexOf("p_window"); // the signature is outside `body` (it starts after BEGIN)
  if (!(authzAt > -1 && jtiAt > authzAt)) out.push("membership before jti");
  if (!(decisionAt > jtiAt)) out.push("decision after jti");
  if (!(windowAt > decisionAt)) out.push("window message after decision");
  if (!(probeAt > windowAt)) out.push("probe after window");
  if (!(firstWindowRef > jtiEnd)) out.push("p_window not referenced before the jti statement ends");
  if (!(firstWindowRef > decisionAt)) out.push("p_window not referenced before the decision check");
  // v_lo is derived from v_span and must be assigned after the window check, before the probe reads it, and
  // never used earlier: the normalization in Guard 1 deletes this line wherever it sits, so position is pinned here
  const spanAt = body.search(/\bv_span\s*:=\s*CASE\s+p_window/);
  const loAt = body.search(/\bv_lo\s*:=\s*v_now\s*-\s*v_span\s*;/);
  if (!(spanAt > decisionAt)) out.push("window CASE after the decision check");
  if (!(loAt > windowAt)) out.push("v_lo assigned after the window check");
  if (!(loAt > -1 && loAt < probeAt)) out.push("v_lo assigned before the probe");
  if (body.search(/\bv_lo\b/) !== loAt) out.push("v_lo used before it is assigned");
  return out;
};

const tenantPredicates = (execSql: string): number => (execSql.match(/\bworkspace_id\s*=\s*p_workspace_id\b/g) ?? []).length;
// any mention of the table (JOIN, comma join, unqualified or quoted FROM all count), not only `FROM public.<table>`
const tableReads = (execSql: string): number => (execSql.match(/\bworkspace_egress_audit_rollup\b/g) ?? []).length;

describe("183_egress_audit_window_summary.sql (shape)", () => {
  it("all three files exist and 177 (the oracle) is present", () => {
    expect(up).not.toBe("");
    expect(down).not.toBe("");
    expect(verify).not.toBe("");
    expect(up177).not.toBe("");
  });

  it("defines exactly one function with exactly four parameters and no DEFAULT anywhere in the parameter list", () => {
    expect(upExec.match(/CREATE\s+(OR\s+REPLACE\s+)?FUNCTION/gi)).toHaveLength(1);
    expect(upExec).toMatch(new RegExp(`CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+public\\.${NAME}\\s*\\(`, "i"));
    const params = upExec.match(new RegExp(`FUNCTION\\s+public\\.${NAME}\\s*\\(([\\s\\S]*?)\\)\\s*RETURNS`, "i"))?.[1] ?? "";
    expect(params.replace(/\s+/g, " ").trim()).toBe("p_workspace_id uuid, p_limit integer, p_decision text, p_window text");
    expect(params).not.toMatch(/\bDEFAULT\b|=/i);
  });

  it("is SECURITY DEFINER + STABLE with search_path pinned incl. pg_temp and plan_cache_mode = force_custom_plan", () => {
    const header = upExec.match(/CREATE\s+OR\s+REPLACE\s+FUNCTION[\s\S]*?AS\s+\$\$/i)?.[0] ?? "";
    expect(header).toMatch(/SECURITY\s+DEFINER/i);
    expect(header).toMatch(/\bSTABLE\b/i);
    expect(header).toMatch(/SET\s+search_path\s*=\s*public,\s*pg_temp/i);
    expect(header).toMatch(/SET\s+plan_cache_mode\s*=\s*force_custom_plan\b/i);
  });

  it("does not touch the 177 function: no mention of its name in executable code, no DROP, no ALTER", () => {
    expect(upExec).not.toMatch(new RegExp(`\\b${NAME_177}\\b`));
    expect(upExec).not.toMatch(/\bDROP\b|\bALTER\b/i);
  });

  it("RPC_DENIAL_PREFIX is exactly 'egress audit: ' (single literal pin of the value)", () => {
    expect(RPC_DENIAL_PREFIX).toBe(DENIAL_PREFIX_VALUE);
  });

  it("the membership check is the first statement after BEGIN and raises 42501 with a constant message", () => {
    const firstStmt = bodyOf(upExec).trimStart();
    expect(firstStmt).toMatch(
      /^IF\s+auth\.uid\(\)\s+IS\s+NULL\s+OR\s+NOT\s+public\.is_workspace_member\(p_workspace_id,\s*auth\.uid\(\)\)\s+THEN/i,
    );
    const authz = firstStmt.match(/^IF[\s\S]*?END\s+IF;/i)?.[0] ?? "";
    expect(authz).toContain(`'${RPC_DENIAL_PREFIX}workspace membership required'`);
    expect(authz).toMatch(/ERRCODE\s*=\s*'42501'/);
    expect(authz).not.toMatch(/%|format\(|\|\|/);
  });

  it("the jti denylist check is the second statement, checked once as a statement", () => {
    const body = bodyOf(upExec);
    const afterAuthz = body.trimStart().replace(/^IF[\s\S]*?END\s+IF;\s*/i, "");
    expect(afterAuthz).toMatch(
      new RegExp(
        `^IF\\s+public\\.is_jti_denied_from_jwt\\(\\)\\s+THEN\\s+RAISE\\s+EXCEPTION\\s+'${escapeRe(RPC_DENIAL_PREFIX)}token denied'\\s+USING\\s+ERRCODE\\s*=\\s*'42501'\\s*;\\s*END\\s+IF;`,
        "i",
      ),
    );
    expect(body.match(/is_jti_denied_from_jwt\(\)/g)).toHaveLength(1);
  });

  it("order: membership -> jti -> p_decision -> p_window -> the p_limit = 0 probe; p_window is not referenced before the jti statement ends", () => {
    expect(orderViolations(upExec)).toEqual([]);
    // the signature contains p_window, so the scan runs on the text after BEGIN; in the body it appears exactly once
    expect(bodyOf(upExec).match(/\bp_window\b/g)).toHaveLength(1);
  });

  it("in-body messages are four, in order: membership, token, decision, window; each starts with RPC_DENIAL_PREFIX", () => {
    const messages = [...upExec.matchAll(/RAISE\s+EXCEPTION\s+'([^']*)'/gi)].map((m) => m[1]);
    expect(messages).toEqual([
      `${RPC_DENIAL_PREFIX}workspace membership required`,
      `${RPC_DENIAL_PREFIX}token denied`,
      `${RPC_DENIAL_PREFIX}invalid decision filter`,
      `${RPC_DENIAL_PREFIX}invalid window`,
    ]);
    for (const m of messages) expect(m.startsWith(RPC_DENIAL_PREFIX)).toBe(true);
    expect(upExec).toMatch(/'egress audit: invalid window'\s+USING\s+ERRCODE\s*=\s*'22023'/);
    // only the two authz denials are 42501
    expect(upExec.match(/ERRCODE\s*=\s*'42501'/g)).toHaveLength(2);
  });

  it("the window is derived by a CASE map to a literal interval: no ELSE, no cast, no concatenation, no dynamic SQL", () => {
    expect(upExec).toMatch(
      /v_span\s*:=\s*CASE\s+p_window\s+WHEN\s+'24h'\s+THEN\s+interval\s+'24 hours'\s+WHEN\s+'7d'\s+THEN\s+interval\s+'7 days'\s+WHEN\s+'30d'\s+THEN\s+interval\s+'30 days'\s+END\s*;/,
    );
    const caseBlock = upExec.match(/CASE\s+p_window[\s\S]*?\bEND\s*;/i)?.[0] ?? "";
    expect(caseBlock).not.toMatch(/\bELSE\b/i);
    expect(upExec).not.toMatch(/p_window\s*::/);
    expect(upExec).not.toMatch(/p_window\s*\|\|/);
    expect(upExec).not.toMatch(/\|\|\s*p_window/);
    expect(upExec).not.toMatch(/\bformat\s*\(/i);
    expect(upExec).not.toMatch(/\bEXECUTE\b\s+(format|')/i);
    expect(upExec.replace(/GRANT\s+EXECUTE\s+ON\s+FUNCTION/gi, "")).not.toMatch(/\bEXECUTE\b/i);
  });

  it("v_lo has no initializer and is v_now - v_span; v_span and v_lo are assigned only after the p_decision check", () => {
    expect(upExec).toMatch(/\bv_span\s+interval\s*;/);
    expect(upExec).toMatch(/\bv_lo\s+timestamptz\s*;/);
    expect(upExec).not.toMatch(/v_lo\s+timestamptz\s*:=/);
    expect(upExec).toMatch(/\bv_lo\s*:=\s*v_now\s*-\s*v_span\s*;/);
    const body = bodyOf(upExec);
    const decisionAt = body.indexOf("invalid decision filter");
    expect(decisionAt).toBeGreaterThan(-1);
    expect(body.search(/\bv_span\s*:=/)).toBeGreaterThan(decisionAt);
    expect(body.search(/\bv_lo\s*:=/)).toBeGreaterThan(decisionAt);
    expect(body.match(/\bv_span\s*:=/g)).toHaveLength(1);
    expect(body.match(/\bv_lo\s*:=/g)).toHaveLength(1);
  });

  it("every read keeps last_seen >= v_lo and <= v_now and both 15-minute bucket slack bounds", () => {
    expect((upExec.match(/\blast_seen\s*>=\s*v_lo\b/g) ?? []).length).toBe(3);
    expect((upExec.match(/\blast_seen\s*<=\s*v_now\b/g) ?? []).length).toBe(3);
    expect(upExec).toMatch(/t\.bucket_start\s*>=\s*v_lo\s*-\s*interval\s*'15 minutes'/i);
    expect(upExec).toMatch(/b\.bucket_start\s*>=\s*v_lo\s*-\s*interval\s*'15 minutes'/i);
    // the window start and end reported to the client are the derived v_lo and v_now
    expect(upExec.match(/'window',\s*jsonb_build_object\('start',\s*v_lo,\s*'end',\s*v_now\)/g)).toHaveLength(2);
  });

  it("tenant boundary: workspace_id = p_workspace_id appears exactly once per read of the rollup table", () => {
    const reads = tableReads(upExec);
    expect(reads).toBe(3); // the probe's outer query and inner subquery, and the w CTE
    expect(tenantPredicates(upExec)).toBe(reads);
  });

  it("the p_limit clamp is COALESCE(p_limit, 200) inside LEAST(GREATEST(..., 0), 500) and PAGE_LIMIT equals that literal (no signature default)", () => {
    const m = upExec.match(/\bv_limit\s*:=\s*LEAST\(\s*GREATEST\(\s*COALESCE\(\s*p_limit\s*,\s*(\d+)\s*\)\s*,\s*0\s*\)\s*,\s*(\d+)\s*\)\s*;/i);
    expect(m).not.toBeNull();
    expect(PAGE_LIMIT).toBe(Number(m?.[1]));
    expect(Number(m?.[2])).toBe(500);
    expect(PAGE_LIMIT).toBeGreaterThanOrEqual(1);
    expect(PAGE_LIMIT).toBeLessThanOrEqual(500);
  });

  it("revokes from PUBLIC, anon, authenticated and service_role by name, then grants authenticated only", () => {
    expect(upExec).toMatch(
      new RegExp(`REVOKE\\s+ALL\\s+ON\\s+FUNCTION\\s+${escapeRe(SIG)}\\s+FROM\\s+PUBLIC,\\s*anon,\\s*authenticated,\\s*service_role\\s*;`, "i"),
    );
    const grants = [...upExec.matchAll(/GRANT\s+EXECUTE\s+ON\s+FUNCTION[\s\S]*?;/gi)].map((m) => m[0]);
    expect(grants).toHaveLength(1);
    expect(grants[0]).toMatch(new RegExp(`ON\\s+FUNCTION\\s+${escapeRe(SIG)}\\s+TO\\s+authenticated\\s*;`, "i"));
    const grantees = grants[0].split(/\bTO\b/i)[1] ?? "";
    expect(grantees).not.toMatch(/anon|service_role|PUBLIC/i);
  });

  it("adds no table grant, no policy, no trigger, no statement_timeout clause and never selects source_host", () => {
    expect(upExec).not.toMatch(/\bCREATE\s+POLICY\b/i);
    expect(upExec).not.toMatch(/\bGRANT\s+(SELECT|INSERT|UPDATE|DELETE|ALL)\b/i);
    expect(upExec).not.toMatch(/\bCREATE\s+(OR\s+REPLACE\s+)?TRIGGER\b/i);
    expect(upExec).not.toMatch(/statement_timeout/i);
    expect(upExec).not.toMatch(/source_host/);
  });

  it("returns the typed contract keys; the 'window' object has exactly start and end", () => {
    for (const key of ["'window'", "'truncated'", "'summary'", "'rows'", "'overflow'", "'last_request_at'"]) {
      expect(upExec).toContain(key);
    }
    const windowObjs = [...upExec.matchAll(/'window',\s*jsonb_build_object\(([^)]*)\)/g)].map((m) => m[1].replace(/\s+/g, " "));
    expect(windowObjs).toEqual(["'start', v_lo, 'end', v_now", "'start', v_lo, 'end', v_now"]);
  });

  it("the COMMENT ON FUNCTION names the exact signature and the window", () => {
    expect(upExec).toMatch(new RegExp(`COMMENT\\s+ON\\s+FUNCTION\\s+${escapeRe(SIG)}\\s+IS`, "i"));
  });

  it(".down.sql drops exactly the new function and nothing else", () => {
    expect(downExec.match(/\bDROP\b/gi)).toHaveLength(1);
    expect(downExec.match(new RegExp(`DROP\\s+FUNCTION\\s+IF\\s+EXISTS\\s+${escapeRe(SIG)}\\s*;`, "gi"))).toHaveLength(1);
    expect(downExec).not.toMatch(/DROP\s+TABLE/i);
    expect(downExec).not.toMatch(new RegExp(`\\b${NAME_177}\\b`));
  });
});

describe("nothing else in the migration file", () => {
  // Guard 1 pins the function body; this pins everything AROUND it. A statement outside the function (a view, a DO
  // block, a table grant, a TRUNCATE) is not read by any parity or order check, so the file is a closed list of heads.
  const functionStmt = extractStatement(up, NAME);
  const topLevelStatements = upExec
    .replace(functionStmt, "")
    .split(/;[ \t]*(?:\r?\n|$)/)
    .map((x) => x.replace(/\s+/g, " ").trim())
    .filter(Boolean);

  it("is the one function plus REVOKE, GRANT and COMMENT for the exact signature, and nothing else", () => {
    expect(functionStmt).not.toBe("");
    expect(topLevelStatements).toHaveLength(3);
    expect(topLevelStatements[0]).toMatch(/^REVOKE ALL ON FUNCTION /i);
    expect(topLevelStatements[1]).toMatch(/^GRANT EXECUTE ON FUNCTION /i);
    expect(topLevelStatements[2]).toMatch(/^COMMENT ON FUNCTION /i);
    for (const x of topLevelStatements) expect(x).toContain(SIG);
  });

  it("an appended statement of another kind is detected", () => {
    const appended = `${upExec}\nTRUNCATE public.workspace_egress_audit_rollup;\nDO $x$ BEGIN UPDATE public.workspace_egress_audit_rollup SET request_count = 0; END $x$;\n`;
    const rest = appended
      .replace(functionStmt, "")
      .split(/;[ \t]*(?:\r?\n|$)/)
      .map((x) => x.replace(/\s+/g, " ").trim())
      .filter(Boolean);
    expect(rest.length).toBeGreaterThan(3);
  });
});

describe("a third copy of the read body cannot arrive unnoticed (ADR-288 retirement path)", () => {
  // The two member-readable definer functions over the rollup table are 177 and 183, and Guard 1 compares exactly two
  // bodies. A third authenticated-granted reader would pass every default-suite check, so the set is pinned: adding
  // one is a conscious edit of this list (and of the ADR's retirement path), not a silent copy.
  it("exactly migrations 177 and 183 grant EXECUTE to authenticated on a function that reads the rollup table", () => {
    const readers = readdirSync(MIG)
      .filter((f) => f.endsWith(".sql") && !f.endsWith(".down.sql"))
      .filter((f) => {
        const exec = stripComments(readFileSync(path.join(MIG, f), "utf8"));
        return /\bworkspace_egress_audit_rollup\b/.test(exec) && /GRANT\s+EXECUTE\s+ON\s+FUNCTION[^;]*\bTO\s+authenticated\b/i.test(exec);
      });
    expect(readers).toEqual(["177_egress_audit_summary_rpc.sql", "183_egress_audit_window_summary.sql"]);
  });
});

describe("harness registration (default-suite assertions, AC7/AC8 without a database)", () => {
  it("ATTACK_SQL classifies both read functions and CLASSIFIED_DEFINER_FN_NAMES carries both names", () => {
    expect(Object.keys(ATTACK_SQL)).toEqual(expect.arrayContaining([NAME_177, NAME]));
    expect(CLASSIFIED_DEFINER_FN_NAMES.has(NAME_177)).toBe(true);
    expect(CLASSIFIED_DEFINER_FN_NAMES.has(NAME)).toBe(true);
  });

  it("the windowed attack passes four arguments and a valid window, so the denial under test is the membership one", () => {
    const sql = ATTACK_SQL[NAME]?.({ wsA: "00000000-0000-0000-0000-00000000000a" } as never) ?? "";
    expect(sql).toMatch(new RegExp(`select\\s+${NAME}\\('[^']+',\\s*200,\\s*null,\\s*'30d'\\)`));
  });

  it("the extractor anchors on CREATE ... FUNCTION: each name extracts one statement and neither extraction contains the other's name", () => {
    const s177 = extractStatement(up177, NAME_177);
    const s183 = extractStatement(up, NAME);
    expect(s177).not.toBe("");
    expect(s183).not.toBe("");
    expect(s177).not.toContain(NAME);
    expect(s183).not.toContain(`${NAME_177}(`);
  });
});

describe("Guard 1 - body parity between the 177 function and the 183 function", () => {
  it("holds on the real files (non-vacuous: both extractions exceed the statement floor)", () => {
    const { a, b } = parityBodies(up177, up);
    expect(a.length).toBeGreaterThan(1000);
    expect(a).toBe(b);
  });

  it("the normalization is the exact, named list: the declaration, the CASE/22023 block, the v_lo assignment, the signature", () => {
    expect(NORMALIZATIONS.map((n) => [n.side, n.to])).toEqual([
      ["177", TOKEN_DECL],
      ["183", TOKEN_DECL],
      ["183", ""],
      ["183", ""],
    ]);
  });

  // Mutation rows: each edit MUST drive the guard RED.
  const dropFromSegment = (sql: string, segmentStart: RegExp, needle: string): string => {
    const at = sql.search(segmentStart);
    expect(at).toBeGreaterThan(-1);
    const from = sql.indexOf(needle, at);
    expect(from).toBeGreaterThan(-1);
    return sql.slice(0, from) + sql.slice(from + needle.length);
  };

  it("mutation 1: dropping `AND t.last_seen <= v_now` from the w CTE, or from the probe's outer query, is detected", () => {
    const needle = "AND t.last_seen <= v_now";
    const inW = dropFromSegment(up, /WITH\s+w\s+AS/, needle);
    const inProbe = dropFromSegment(up, /SELECT\s+max\(t\.last_seen\)/, needle);
    expect(inW).not.toBe(up);
    expect(inProbe).not.toBe(up);
    expect(parityHolds(up177, inW)).toBe(false);
    expect(parityHolds(up177, inProbe)).toBe(false);
  });

  it("mutation 2: removing any one `workspace_id = p_workspace_id` predicate reds both the parity guard and the exact tenant count", () => {
    // the three table reads: the probe's outer query (WHERE ...), the inner subquery (WHERE ...), the w CTE (WHERE ...)
    const preds = [...up.matchAll(/(?:t|b)\.workspace_id\s*=\s*p_workspace_id/g)];
    expect(preds).toHaveLength(3);
    for (const p of preds) {
      const idx = p.index as number;
      const mutated = up.slice(0, idx) + "TRUE" + up.slice(idx + p[0].length);
      expect(parityHolds(up177, mutated), `parity after dropping predicate at ${idx}`).toBe(false);
      expect(tenantPredicates(stripComments(mutated))).not.toBe(tableReads(stripComments(mutated)));
    }
  });

  it("mutation 3: an extractor that finds nothing in the 177 file fails on the non-empty floor instead of passing on two empty strings", () => {
    const renamed = up177.replace(new RegExp(`FUNCTION\\s+public\\.${NAME_177}\\s*\\(`), "FUNCTION public.renamed_fn(");
    expect(extractStatement(renamed, NAME_177)).toBe("");
    expect(() => parityBodies(renamed, up)).toThrow(/vacuous extraction for 177/);
    expect(() => parityBodies(up177, "")).toThrow(/vacuous extraction for 183/);
  });

  it("mutation 4: moving the p_window CASE block above the jti statement reds the order check", () => {
    const block = upExec.match(/v_span\s*:=\s*CASE\s+p_window[\s\S]*?END\s+IF;\s*/i)?.[0] ?? "";
    expect(block).toContain("invalid window");
    const without = upExec.replace(block, "");
    const jtiIf = without.search(/IF\s+public\.is_jti_denied_from_jwt\(\)/i);
    expect(jtiIf).toBeGreaterThan(-1);
    const moved = without.slice(0, jtiIf) + block + without.slice(jtiIf);
    expect(orderViolations(upExec)).toEqual([]);
    expect(orderViolations(moved).length).toBeGreaterThan(0);
    expect(orderViolations(moved)).toContain("p_window not referenced before the jti statement ends");
  });

  it("mutation 5 (harness row): with the normalization replaced by the identity the legitimate window difference makes the guard fail, so it compares", () => {
    expect(parityHolds(up177, up, [])).toBe(false);
  });

  it("mutation 6: moving `v_lo := v_now - v_span;` after the probe, or above the CASE, reds the order check (Guard 1 deletes that line wherever it sits)", () => {
    const line = "v_lo := v_now - v_span;";
    expect(upExec).toContain(line);
    const without = upExec.replace(line, "");
    const afterProbe = without.replace(/WITH\s+w\s+AS/i, `${line}\n  WITH w AS`);
    const aboveCase = without.replace(/v_span\s*:=\s*CASE\s+p_window/i, `${line}\n  v_span := CASE p_window`);
    expect(afterProbe).not.toBe(without);
    expect(aboveCase).not.toBe(without);
    expect(orderViolations(upExec)).toEqual([]);
    expect(orderViolations(afterProbe)).toContain("v_lo assigned before the probe");
    expect(orderViolations(aboveCase).length).toBeGreaterThan(0);
  });

  it("mutation 7: spacing inside a string literal is data - '(other)' vs '( other)' reds parity; layout outside literals does not", () => {
    expect(up).toContain("'(other)'");
    const mutated = up.replace("'(other)'", "'( other)'");
    expect(mutated).not.toBe(up);
    expect(parityHolds(up177, mutated)).toBe(false);
  });

  it("mutation 8: a tenant predicate that survives only inside a block comment is not a predicate", () => {
    const m = up.match(/(?:t|b)\.workspace_id\s*=\s*p_workspace_id/);
    expect(m).not.toBeNull();
    const idx = m?.index as number;
    const mutated = up.slice(0, idx) + "TRUE /* " + m?.[0] + " */" + up.slice(idx + (m?.[0].length ?? 0));
    expect(tenantPredicates(stripComments(mutated))).not.toBe(tableReads(stripComments(mutated)));
    expect(parityHolds(up177, mutated)).toBe(false);
  });

  it("must-pass: extra comments and reflowed whitespace in the 183 body still hold parity (the guard is not a byte equality)", () => {
    // reflow the code only (a comma inside a `--` comment must not spill onto an uncommented line)
    // string literals are data (see mutation 7), so the reflow touches only the text between them
    const reflowed = stripComments(up)
      .split(/('(?:[^']|'')*')/)
      .map((part, i) => (i % 2 === 1 ? part : part.replace(/,/g, ",\n      ").replace(/\(/g, "(\n   ")))
      .join("")
      .replace(/^BEGIN$/m, "BEGIN -- extra comment\n  -- another comment");
    expect(reflowed).toContain("-- extra comment");
    expect(reflowed).not.toBe(up);
    expect(parityHolds(up177, reflowed)).toBe(true);
  });
});

describe("the verify sentinel asserts the live catalog PREDICATES for the exact signature", () => {
  const rows = new Map<string, string>();
  for (const seg of verifyExec.split(/\bUNION\s+ALL\b/i)) {
    const name = seg.match(/SELECT\s+'([a-z_]+)'/i)?.[1];
    if (name) rows.set(name, seg.replace(/\s+/g, " ").replace(/\(\s+/g, "(").replace(/\s+\)/g, ")"));
  }
  const FN = "'public\\.get_egress_audit_window_summary\\(uuid, integer, text, text\\)'";
  const RP = `to_regprocedure\\(${FN}\\)`;
  const predicates: Record<string, RegExp> = {
    egress_window_summary_is_definer: new RegExp(`CASE WHEN COALESCE\\(\\(SELECT p\\.prosecdef FROM pg_proc p WHERE p\\.oid = ${RP}\\), false\\) THEN 0 ELSE 1 END`),
    egress_window_summary_is_stable: new RegExp(`CASE WHEN COALESCE\\(\\(SELECT p\\.provolatile = 's' FROM pg_proc p WHERE p\\.oid = ${RP}\\), false\\) THEN 0 ELSE 1 END`),
    egress_window_summary_search_path_pinned: new RegExp(`CASE WHEN EXISTS \\(SELECT 1 FROM pg_proc p, unnest\\(p\\.proconfig\\) c WHERE p\\.oid = ${RP} AND c LIKE 'search_path=%pg_temp%'\\) THEN 0 ELSE 1 END`),
    egress_window_summary_plan_cache_mode_custom: new RegExp(`CASE WHEN EXISTS \\(SELECT 1 FROM pg_proc p, unnest\\(p\\.proconfig\\) c WHERE p\\.oid = ${RP} AND c = 'plan_cache_mode=force_custom_plan'\\) THEN 0 ELSE 1 END`),
    egress_window_summary_checks_jti_denylist: new RegExp(`CASE WHEN EXISTS \\(SELECT 1 FROM pg_proc p WHERE p\\.oid = ${RP} AND p\\.prosrc LIKE '%is_jti_denied_from_jwt\\(\\)%'\\) THEN 0 ELSE 1 END`),
    egress_window_summary_validates_window: new RegExp(`CASE WHEN EXISTS \\(SELECT 1 FROM pg_proc p WHERE p\\.oid = ${RP} AND p\\.prosrc LIKE '%egress audit: invalid window%' AND p\\.prosrc LIKE '%CASE p_window%'\\) THEN 0 ELSE 1 END`),
    egress_window_summary_anon_revoked: new RegExp(`CASE WHEN has_function_privilege\\('anon', ${FN}, 'EXECUTE'\\) THEN 1 ELSE 0 END`),
    egress_window_summary_service_role_revoked: new RegExp(`CASE WHEN has_function_privilege\\('service_role', ${FN}, 'EXECUTE'\\) THEN 1 ELSE 0 END`),
    egress_window_summary_public_revoked: new RegExp(`CASE WHEN EXISTS \\(SELECT 1 FROM pg_proc p, aclexplode\\(p\\.proacl\\) a WHERE p\\.oid = ${RP} AND a\\.grantee = 0 AND a\\.privilege_type = 'EXECUTE'\\) OR EXISTS \\(SELECT 1 FROM pg_proc p WHERE p\\.oid = ${RP} AND p\\.proacl IS NULL\\) THEN 1 ELSE 0 END`),
    egress_window_summary_authenticated_granted: new RegExp(`CASE WHEN has_function_privilege\\('authenticated', ${FN}, 'EXECUTE'\\) THEN 0 ELSE 1 END`),
    egress_window_summary_grantee_set_is_only_authenticated: new RegExp(`FROM pg_proc p, aclexplode\\(p\\.proacl\\) a WHERE p\\.oid = ${RP} AND a\\.privilege_type = 'EXECUTE' AND a\\.grantee IS DISTINCT FROM \\(SELECT oid FROM pg_roles WHERE rolname = 'authenticated'\\) AND a\\.grantee IS DISTINCT FROM \\(SELECT proowner FROM pg_proc WHERE oid = ${RP}\\)\\) = 0 THEN 0 ELSE 1 END`),
  };

  it("has exactly the eleven expected rows, with check names distinct from 177's", () => {
    expect([...rows.keys()].sort()).toEqual(Object.keys(predicates).sort());
    const names177 = new Set(
      stripComments(read(path.join(__dirname, "../../supabase/verify/177_egress_audit_summary_rpc.sql")))
        .split(/\bUNION\s+ALL\b/i)
        .map((s) => s.match(/SELECT\s+'([a-z_]+)'/i)?.[1])
        .filter(Boolean),
    );
    for (const n of rows.keys()) expect(names177.has(n)).toBe(false);
  });

  it.each(Object.entries(predicates))("%s has its predicate and polarity", (name, re) => {
    expect([name, re.test(rows.get(name) ?? "")]).toEqual([name, true]);
  });

  it("every row ends at its CASE ... END::int (nothing is appended after the predicate to neuter it)", () => {
    for (const [name, seg] of rows) {
      expect([name, /THEN [01] ELSE [01] END::int( AS bad)? ?;? ?$/.test(seg.trim())]).toEqual([name, true]);
    }
  });

  it("existence goes through to_regprocedure (a ::regprocedure cast would raise instead of reporting bad = 1) and never a bare cast", () => {
    expect(verifyExec).not.toMatch(/::regprocedure/i);
    expect(verifyExec).toMatch(/to_regprocedure\(/);
    // no other function's signature is addressed
    for (const m of verifyExec.matchAll(/public\.get_egress_audit[a-z_]*\([^)]*\)/g)) expect(m[0]).toBe(SIG);
  });

  it("the jti check names the very function the migration calls (a typo'd name would pass a bare-name check)", () => {
    const jtiName = upExec.match(/\bpublic\.(is_jti_denied_from_jwt)\(\)/)?.[1] ?? "";
    expect(jtiName).toBe("is_jti_denied_from_jwt");
    expect(rows.get("egress_window_summary_checks_jti_denylist") ?? "").toContain(`LIKE '%${jtiName}()%'`);
  });
});
