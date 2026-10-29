import { describe, expect, it } from "vitest";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { APPROVAL_TRANSITIONS } from "@/server/approval/service";
import { APPROVAL_REQUIRED_TOOLS } from "@/server/approval/tools";

// Static shape tests for migration 180 (#4672). The BEHAVIOURAL proof of the consume predicate, the status machine,
// decide_approval, the revoke, the principal re-check, the caps and the erasure delete runs against a real database
// (test/server/approval-request.tenant-isolation.test.ts, collected by tenant-integration.yml, plus
// supabase/verify/180_approval_request.sql). This file is the cheap backstop: it TOKENIZES the SQL (comments
// removed, string literals respected, parentheses tracked) and compares the consume / decide WHERE clauses, the
// transition tuples and the grant / policy sets as SETS, so `OR true`, a commented-out conjunct, an inverted
// polarity, a loosened expiry, a TRUNCATE grant or an extra permissive policy are RED. The MUTATIONS block at the
// bottom applies each of the surviving mutants of the earlier String.includes version to the RAW migration text and
// asserts the checker notices (a checker that cannot go red is vacuous).

const DIR = path.join(__dirname, "../../supabase");
const UP = path.join(DIR, "migrations/180_approval_request.sql");
const DOWN = path.join(DIR, "migrations/180_approval_request.down.sql");
const VERIFY = path.join(DIR, "verify/180_approval_request.sql");

const read = (p: string): string => (existsSync(p) ? readFileSync(p, "utf8") : "");
const rawSql = read(UP);
const norm = (s: string) => s.replace(/\s+/g, " ").trim();

/** Remove line comments and block comments (not nested); single-quoted literals (with '' escapes) are copied through intact. */
export function stripSql(src: string): string {
  let out = "";
  let i = 0;
  const n = src.length;
  while (i < n) {
    const two = src.slice(i, i + 2);
    if (two === "--") {
      while (i < n && src[i] !== "\n") i++;
      continue;
    }
    if (two === "/*") {
      const end = src.indexOf("*/", i + 2);
      i = end < 0 ? n : end + 2;
      out += " ";
      continue;
    }
    if (src[i] === "'") {
      let j = i + 1;
      while (j < n) {
        if (src[j] === "'") {
          if (src[j + 1] === "'") {
            j += 2;
            continue;
          }
          break;
        }
        j++;
      }
      out += src.slice(i, j + 1);
      i = j + 1;
      continue;
    }
    out += src[i];
    i++;
  }
  return out;
}

const isWord = (c: string | undefined) => c !== undefined && /[A-Za-z0-9_]/.test(c);

/** Split on a keyword at paren depth 0, outside string literals. */
export function splitTopLevel(expr: string, keyword: "AND" | "OR"): string[] {
  const parts: string[] = [];
  let depth = 0;
  let last = 0;
  for (let i = 0; i < expr.length; i++) {
    const c = expr[i];
    if (c === "'") {
      i++;
      while (i < expr.length && !(expr[i] === "'" && expr[i + 1] !== "'")) i += expr[i] === "'" ? 2 : 1;
      continue;
    }
    if (c === "(") depth++;
    else if (c === ")") depth--;
    else if (depth === 0 && !isWord(expr[i - 1]) && expr.slice(i, i + keyword.length).toUpperCase() === keyword && !isWord(expr[i + keyword.length])) {
      parts.push(expr.slice(last, i));
      last = i + keyword.length;
      i = last - 1;
    }
  }
  parts.push(expr.slice(last));
  return parts.map(norm).filter((x) => x.length > 0);
}

/** Position of the first top-level (depth 0, outside literals) occurrence of a keyword at or after `from`. */
function topLevelIndex(src: string, keyword: string, from = 0): number {
  let depth = 0;
  for (let i = from; i < src.length; i++) {
    const c = src[i];
    if (c === "'") {
      i++;
      while (i < src.length && !(src[i] === "'" && src[i + 1] !== "'")) i += src[i] === "'" ? 2 : 1;
      continue;
    }
    if (c === "(") depth++;
    else if (c === ")") depth--;
    else if (depth === 0 && keyword === ";" && c === ";") return i;
    else if (depth === 0 && keyword !== ";" && !isWord(src[i - 1]) && src.slice(i, i + keyword.length).toUpperCase() === keyword && !isWord(src[i + keyword.length])) return i;
  }
  return -1;
}

/** The body of one function (CREATE OR REPLACE ... to its terminating `$tag$;`), from COMMENT-STRIPPED sql. */
export function fnBody(strippedSql: string, name: string): string {
  const re = new RegExp(`CREATE OR REPLACE FUNCTION public\\.${name}\\([\\s\\S]*?\\n\\$(\\w*)\\$;`, "i");
  const m = re.exec(strippedSql);
  return m ? m[0] : "";
}

export interface UpdateStmt {
  set: string;
  where: string[]; // top-level AND conjuncts
  whereRaw: string;
}

/** Every `UPDATE public.approval_request ... ;` statement of a function body, tokenized into SET and WHERE conjuncts. */
export function updateStatements(body: string): UpdateStmt[] {
  const out: UpdateStmt[] = [];
  const re = /UPDATE public\.approval_request\b/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(body))) {
    const end = topLevelIndex(body, ";", m.index);
    const stmt = body.slice(m.index, end < 0 ? body.length : end);
    const setAt = topLevelIndex(stmt, "SET");
    const whereAt = topLevelIndex(stmt, "WHERE", setAt);
    const retAt = topLevelIndex(stmt, "RETURNING", whereAt < 0 ? setAt : whereAt);
    const set = norm(stmt.slice(setAt + 3, whereAt < 0 ? (retAt < 0 ? stmt.length : retAt) : whereAt));
    const whereRaw = whereAt < 0 ? "" : norm(stmt.slice(whereAt + 5, retAt < 0 ? stmt.length : retAt));
    out.push({ set, where: splitTopLevel(whereRaw, "AND"), whereRaw });
  }
  return out;
}

const BARE_TRUE = /^(true|1\s*=\s*1|\(\s*true\s*\))$/i;

/** Problems with one WHERE: the conjunct SET must equal `expected`; no OR at any depth; no bare true. */
function whereIssues(u: UpdateStmt | undefined, expected: readonly string[]): string[] {
  if (!u) return ["statement missing"];
  const issues: string[] = [];
  if (splitTopLevel(u.whereRaw, "OR").length > 1) issues.push("top-level OR");
  if (/\bOR\b/i.test(u.whereRaw)) issues.push("OR in predicate");
  for (const c of u.where) if (BARE_TRUE.test(c)) issues.push(`bare true: ${c}`);
  const got = new Set(u.where);
  for (const e of expected) if (!got.has(e)) issues.push(`missing conjunct: ${e}`);
  for (const g of got) if (!expected.includes(g)) issues.push(`unexpected conjunct: ${g}`);
  return issues;
}

const CONSUME_CONJUNCTS = [
  "id = p_id",
  "status = 'approved'",
  "expires_at > now()",
  "action_sha256 = p_hash",
  "conversation_id = p_conversation",
  "public.is_workspace_owner(workspace_id, decided_by)",
  "public.is_workspace_member(workspace_id, requested_by_user_id)",
] as const;
const CONSUME_SET = "status = 'consumed', consumed_at = now()";

export function consumeIssues(raw: string): string[] {
  const body = fnBody(stripSql(raw), "consume_approval");
  if (!body) return ["consume_approval missing"];
  const ups = updateStatements(body);
  if (ups.length !== 1) return [`expected exactly one UPDATE, got ${ups.length}`];
  const issues = whereIssues(ups[0], CONSUME_CONJUNCTS);
  if (ups[0].set !== CONSUME_SET) issues.push(`set clause: ${ups[0].set}`);
  return issues;
}

/** decide_approval: UPDATE set, ordering of the checks, and the polarity of the Owner / expiry / closed tests. */
export function decideIssues(raw: string): string[] {
  const body = norm(fnBody(stripSql(raw), "decide_approval"));
  if (!body) return ["decide_approval missing"];
  const issues: string[] = [];
  const ups = updateStatements(fnBody(stripSql(raw), "decide_approval"));
  const expectUps: Array<[string, string[]]> = [
    ["status = 'expired', expired_at = now()", ["id = v_row.id"]],
    ["status = 'rejected', revoked_at = now(), revoked_by = auth.uid()", ["id = v_row.id", "status = 'approved'"]],
    [
      "status = CASE WHEN p_decision = 'approve' THEN 'approved' ELSE 'rejected' END, decided_by = auth.uid(), decided_at = now()",
      ["id = v_row.id", "status = 'pending'"],
    ],
  ];
  if (ups.length !== expectUps.length) issues.push(`expected ${expectUps.length} UPDATEs, got ${ups.length}`);
  for (const [set, where] of expectUps) {
    const u = ups.find((x) => x.set === set);
    if (!u) issues.push(`no UPDATE with set: ${set}`);
    else issues.push(...whereIssues(u, where).map((x) => `${set}: ${x}`));
  }
  const must = [
    "v_ok := FOUND AND COALESCE(public.is_workspace_owner(v_ws, auth.uid()), false); IF NOT v_ok THEN RAISE EXCEPTION 'approval: not authorized' USING ERRCODE = '42501'; END IF;",
    "IF v_row.status IN ('pending', 'approved') AND v_row.expires_at <= now() THEN",
    "IF NOT FOUND OR v_closed THEN RETURN jsonb_build_object('outcome', 'closed'",
    "IF public.is_jti_denied_from_jwt() THEN",
    "IF p_decision IS NULL OR p_decision NOT IN ('approve', 'deny') THEN",
  ];
  for (const m of must) if (!body.includes(m)) issues.push(`missing: ${m.slice(0, 70)}`);
  const at = (needle: string) => body.indexOf(needle);
  // Ordering: Owner check BEFORE the row lock; expiry above the already-decided blocks; closed only on the pending path.
  if (!(at("is_workspace_owner(v_ws") >= 0 && at("is_workspace_owner(v_ws") < at("FOR UPDATE"))) issues.push("owner check must precede FOR UPDATE");
  if (!(at("v_row.expires_at <= now()") >= 0 && at("v_row.expires_at <= now()") < at("v_row.status = 'consumed'"))) issues.push("expiry must precede the decided blocks");
  if (!(at("v_row.status = 'expired'") >= 0 && at("v_row.status = 'expired'") < at("v_row.status = 'rejected'"))) issues.push("expired must precede rejected");
  if (!(at("outcome', 'closed'") > at("v_row.status = 'approved' THEN"))) issues.push("closed check must come after the approved/revoke branch");
  if (!(at("is_jti_denied_from_jwt()") >= 0 && at("is_jti_denied_from_jwt()") < at("is_workspace_owner(v_ws"))) issues.push("jti check must precede the owner check");
  return issues;
}

/** The `(OLD.status, NEW.status) NOT IN (...)` tuples of the guard trigger, as `from>to`. */
export function transitionTuples(raw: string): string[] {
  const body = norm(fnBody(stripSql(raw), "approval_request_guard"));
  const key = "(OLD.status, NEW.status) NOT IN (";
  const at = body.indexOf(key);
  if (at < 0) return [];
  let depth = 1;
  let i = at + key.length;
  const start = i;
  for (; i < body.length && depth > 0; i++) {
    if (body[i] === "(") depth++;
    else if (body[i] === ")") depth--;
  }
  const inner = body.slice(start, i - 1);
  return [...inner.matchAll(/\(\s*'(\w+)'\s*,\s*'(\w+)'\s*\)/g)].map((m) => `${m[1]}>${m[2]}`).sort();
}

/** The closed set of table grants and policies on approval_request. */
export function grantIssues(raw: string): string[] {
  const code = stripSql(raw);
  const issues: string[] = [];
  const stmts = code.split(";").map(norm);
  const tableGrants = stmts.filter((x) => /^GRANT\b/i.test(x) && /\bTABLE\b|\bON\s+(ALL|public\.approval_request)/i.test(x));
  const approvalGrants = tableGrants.filter((x) => /approval_request/.test(x));
  if (approvalGrants.length !== 1 || approvalGrants[0] !== "GRANT SELECT ON TABLE public.approval_request TO authenticated") {
    issues.push(`table grants must be exactly SELECT to authenticated, got: ${JSON.stringify(approvalGrants)}`);
  }
  if (stmts.filter((x) => /^REVOKE ALL ON TABLE public\.approval_request FROM PUBLIC, anon, authenticated, service_role$/.test(x)).length !== 1) {
    issues.push("missing REVOKE ALL on the table");
  }
  if (stmts.some((x) => /ALTER DEFAULT PRIVILEGES/i.test(x))) issues.push("default privileges changed");
  const policies = stmts.filter((x) => /^CREATE POLICY\b/i.test(x) && /ON public\.approval_request\b/.test(x));
  const expected = [
    "CREATE POLICY approval_request_owner_select ON public.approval_request FOR SELECT TO authenticated USING ( public.is_workspace_owner(workspace_id, auth.uid()) )",
    "CREATE POLICY approval_request_jti_not_denied ON public.approval_request AS RESTRICTIVE FOR ALL TO authenticated USING (NOT public.is_jti_denied_from_jwt()) WITH CHECK (NOT public.is_jti_denied_from_jwt())",
  ];
  if (policies.length !== expected.length || !expected.every((e) => policies.includes(e))) {
    issues.push(`policy set must be exactly the Owner SELECT + restrictive jti policy, got: ${JSON.stringify(policies)}`);
  }
  return issues;
}

const sql = rawSql;
const code = stripSql(sql);

describe("files exist (up, down, verify)", () => {
  it("ships the migration, its down and the verify sentinel", () => {
    expect(existsSync(UP)).toBe(true);
    expect(existsSync(DOWN)).toBe(true);
    expect(existsSync(VERIFY)).toBe(true);
  });
});

describe("tokenizer self-checks (the checker must be able to go red)", () => {
  it("strips line and block comments but not a comment marker inside a string literal", () => {
    expect(stripSql("a -- b\nc /* d */ e")).toBe("a \nc   e");
    expect(stripSql("x = '--not a comment' -- real")).toBe("x = '--not a comment' ");
    expect(stripSql("x = 'it''s' AND y")).toBe("x = 'it''s' AND y");
  });

  it("splits on a top-level AND only (not inside parentheses or literals)", () => {
    expect(splitTopLevel("a = 1 AND (b = 2 AND c = 3) AND d = 'x AND y'", "AND")).toEqual(["a = 1", "(b = 2 AND c = 3)", "d = 'x AND y'"]);
    expect(splitTopLevel("a = 1 OR b = 2", "OR")).toEqual(["a = 1", "b = 2"]);
    expect(splitTopLevel("candidate = 1 AND brand = 2", "AND")).toEqual(["candidate = 1", "brand = 2"]);
  });
});

describe("table, constraints, indexes", () => {
  it("creates approval_request with RLS enabled and the eight slice-1 tool names in the CHECK", () => {
    expect(code).toMatch(/CREATE TABLE IF NOT EXISTS public\.approval_request/);
    expect(code).toMatch(/ALTER TABLE public\.approval_request ENABLE ROW LEVEL SECURITY/);
    for (const t of APPROVAL_REQUIRED_TOOLS) expect(code).toContain(`'${t}'`);
    expect(code).toMatch(/status\s+text\s+NOT NULL DEFAULT 'pending'/);
    for (const s of ["pending", "approved", "rejected", "expired", "consumed"]) expect(code).toContain(`'${s}'`);
    expect(code).toMatch(/action_sha256\s+text\s+NOT NULL/);
    expect(code).toMatch(/\^\[0-9a-f\]\{64\}\$/);
  });

  it("has the user columns as ON DELETE SET NULL and the workspace as ON DELETE CASCADE", () => {
    expect(norm(code)).toMatch(/requested_by_user_id uuid NULL REFERENCES public\.users\(id\) ON DELETE SET NULL/);
    expect(norm(code)).toMatch(/decided_by uuid NULL REFERENCES public\.users\(id\) ON DELETE SET NULL/);
    expect(norm(code)).toMatch(/revoked_by uuid NULL REFERENCES public\.users\(id\) ON DELETE SET NULL/);
    expect(norm(code)).toMatch(/workspace_id uuid NOT NULL REFERENCES public\.workspaces\(id\) ON DELETE CASCADE/);
  });

  it("has the write-once revoke pair, constrained to a rejected row", () => {
    expect(norm(code)).toMatch(/revoked_at timestamptz NULL/);
    expect(norm(code)).toMatch(/CONSTRAINT approval_request_revoked_pairing CHECK \(\(revoked_at IS NULL OR status = 'rejected'\) AND \(revoked_by IS NULL OR revoked_at IS NOT NULL\)\)/);
  });

  it("has the unique partial index that makes a live (conversation, hash) idempotent", () => {
    expect(norm(code)).toMatch(
      /CREATE UNIQUE INDEX IF NOT EXISTS approval_request_live_uniq ON public\.approval_request \(conversation_id, action_sha256\) WHERE status IN \('pending', 'approved'\)/,
    );
  });

  it("has an all-status index for the request count and a sweep index", () => {
    expect(norm(code)).toMatch(/ON public\.approval_request \(conversation_id, action_sha256\);/);
    expect(norm(code)).toMatch(/\(status, expires_at\)/);
  });

  it("has the pending-cap, scrub and FK indexes (partial)", () => {
    const n = norm(code);
    expect(n).toMatch(/CREATE INDEX IF NOT EXISTS approval_request_ws_pending_idx ON public\.approval_request \(workspace_id\) WHERE status = 'pending'/);
    expect(n).toMatch(
      /CREATE INDEX IF NOT EXISTS approval_request_scrub_idx ON public\.approval_request \(\(COALESCE\(consumed_at, expired_at, revoked_at, decided_at\)\)\) WHERE canonical_action IS NOT NULL AND status IN \('rejected', 'expired', 'consumed'\)/,
    );
    for (const col of ["requested_by_user_id", "decided_by", "revoked_by"]) {
      expect(n).toMatch(new RegExp(`ON public\\.approval_request \\(${col}\\) WHERE ${col} IS NOT NULL`));
    }
  });

  it("asserts the inbox_item (workspace_id, dedup_key) unique index as a precondition", () => {
    expect(norm(code)).toMatch(/indexdef LIKE '%\(workspace_id, dedup_key\)%'/);
    expect(code).toMatch(/Precondition failed: the unique partial index on public\.inbox_item/);
  });

  it("annotates every personal-data column with a lawful basis and states the retention", () => {
    expect((sql.match(/-- LAWFUL_BASIS:/g) ?? []).length).toBeGreaterThanOrEqual(4);
    for (const col of ["requested_by_user_id", "decided_by", "revoked_by", "canonical_action"]) {
      const m = new RegExp(`\\n  ${col}\\s`).exec(sql);
      expect(m, `column definition of ${col}`).not.toBeNull();
      const before = sql.slice(Math.max(0, (m?.index ?? 0) - 700), m?.index ?? 0);
      expect(before, col).toMatch(/LAWFUL_BASIS/);
    }
    expect(sql).toMatch(/30 days/i);
    expect(sql).toMatch(/RETENTION:/i);
  });

  it("carries no stale claims: no 'provisional', no 'momentary lock', no 'deleted with the workspace'", () => {
    expect(sql).not.toMatch(/provisional/i);
    expect(sql).not.toMatch(/momentary lock/i);
    expect(sql).not.toMatch(/deleted with the workspace/i);
    expect(sql).not.toMatch(/Each batch is bounded/);
  });
});

describe("RLS and Data API grants (ADR-303): closed grant and policy set", () => {
  it("revokes every privilege from every api role, grants SELECT to authenticated ONLY, and has exactly the two policies", () => {
    expect(grantIssues(sql)).toEqual([]);
  });

  it("the owner SELECT policy and the restrictive jti policy are the only policies", () => {
    expect(norm(code)).toMatch(/approval_request_jti_not_denied/);
    expect(norm(code)).not.toMatch(/CREATE POLICY \w+ ON public\.approval_request FOR (ALL|INSERT|UPDATE|DELETE)/);
  });
});

const RPCS = {
  create_approval_request: { grant: "service_role", sig: "create_approval_request( p_workspace_id uuid, p_conversation_id uuid, p_requested_by uuid, p_tool_name text, p_action_sha256 text, p_canonical_action jsonb, p_ttl_seconds integer DEFAULT 86400 )" },
  decide_approval: { grant: "authenticated", sig: "decide_approval( p_id uuid, p_decision text )" },
  consume_approval: { grant: "service_role", sig: "consume_approval( p_id uuid, p_hash text, p_conversation uuid )" },
  get_approval_status: { grant: "service_role", sig: "get_approval_status(p_id uuid)" },
  list_live_approvals: { grant: "service_role", sig: "list_live_approvals(p_conversation uuid)" },
  sweep_approvals: { grant: "service_role", sig: "sweep_approvals()" },
  anonymise_approval_request: { grant: "service_role", sig: "anonymise_approval_request(p_user_id uuid)" },
} as const;

describe("RPC hygiene (cq-pg-security-definer-search-path-pin-pg-temp)", () => {
  for (const [name, spec] of Object.entries(RPCS)) {
    describe(name, () => {
      const body = fnBody(code, name);
      it("exists, is SECURITY DEFINER and pins search_path = public, pg_temp", () => {
        expect(body.length).toBeGreaterThan(0);
        expect(norm(body)).toContain(spec.sig);
        expect(body).toMatch(/SECURITY DEFINER/);
        expect(body).toMatch(/SET search_path = public, pg_temp/);
      });

      it(`REVOKEs from PUBLIC, anon, authenticated, service_role then grants EXECUTE to ${spec.grant} only`, () => {
        const re = new RegExp(`REVOKE ALL ON FUNCTION public\\.${name}\\([^)]*\\)\\s+FROM PUBLIC, anon, authenticated, service_role;`, "i");
        expect(code).toMatch(re);
        const grants = [...code.matchAll(new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${name}\\([^)]*\\)\\s+TO (\\w+);`, "gi"))].map((m) => m[1]);
        expect(grants).toEqual([spec.grant]);
      });
    });
  }

  it("the grant differs between decide (authenticated) and every other rpc (service_role), with the reason recorded", () => {
    expect(sql).toMatch(/why the grant differs/i);
  });

  it("every service-role rpc refuses a caller that carries a user identity", () => {
    for (const name of ["create_approval_request", "consume_approval", "get_approval_status", "list_live_approvals", "sweep_approvals", "anonymise_approval_request"]) {
      expect(fnBody(code, name), name).toMatch(/auth\.uid\(\) IS NOT NULL/);
    }
  });

  it("anonymise has no dead current_user guard (a SECURITY DEFINER function always sees its owner)", () => {
    expect(fnBody(code, "anonymise_approval_request")).not.toMatch(/current_user/);
  });

  it("the write-once trigger function is pinned and revoked too", () => {
    const body = fnBody(code, "approval_request_guard");
    expect(body).toMatch(/SECURITY DEFINER/);
    expect(body).toMatch(/SET search_path = public, pg_temp/);
    expect(norm(code)).toMatch(/REVOKE ALL ON FUNCTION public\.approval_request_guard\(\) FROM PUBLIC, anon, authenticated, service_role/);
  });

  it("the inbox settle helper takes the workspace id and every caller passes one", () => {
    expect(norm(fnBody(code, "approval_request_inbox_settle"))).toContain("approval_request_inbox_settle(p_workspace_id uuid, p_approval_id uuid, p_mode text)");
    const calls = [...code.matchAll(/public\.approval_request_inbox_settle\(([^)]*)\)/g)].map((m) => norm(m[1]));
    const callSites = calls.filter((c) => !/^p_workspace_id uuid/.test(c) && c !== "uuid, uuid, text");
    expect(callSites.length).toBeGreaterThanOrEqual(5);
    for (const c of callSites) expect(c, c).toMatch(/^(v_row|v_stale|r)\.workspace_id, (v_row|v_stale|r)\.id, '(acted|fyi)'$/);
  });
});

describe("Guard 1: consume predicate (tokenized; behavioural proof is the tenant-isolation integration test)", () => {
  it("the single atomic UPDATE has EXACTLY the expected conjunct set and SET clause, no OR, no bare true", () => {
    expect(consumeIssues(sql)).toEqual([]);
  });

  it("consume never reads the hash or conversation from anywhere but its parameters", () => {
    const body = fnBody(code, "consume_approval");
    expect(body).not.toMatch(/\bNEW\./);
    expect(body).toMatch(/RETURNING/);
  });

  it("the reason lookup reports the principal-change codes after expiry and before the bind mismatches", () => {
    const b = norm(fnBody(code, "consume_approval"));
    const at = (x: string) => b.indexOf(x);
    expect(at("'expired'")).toBeGreaterThan(0);
    expect(at("'expired'")).toBeLessThan(at("'decider_not_owner'"));
    expect(at("'decider_not_owner'")).toBeLessThan(at("'requester_not_member'"));
    expect(at("'requester_not_member'")).toBeLessThan(at("'wrong_conversation'"));
    expect(b).toMatch(/COALESCE\(public\.is_workspace_owner\(v_row\.workspace_id, v_row\.decided_by\), false\)/);
    expect(b).toMatch(/COALESCE\(public\.is_workspace_member\(v_row\.workspace_id, v_row\.requested_by_user_id\), false\)/);
  });
});

describe("decide_approval", () => {
  const body = norm(fnBody(code, "decide_approval"));

  it("derives the actor from auth.uid() and has no actor parameter", () => {
    expect(body).toMatch(/auth\.uid\(\)/);
    expect(body).not.toMatch(/p_actor|p_user_id|p_decided_by/);
  });

  it("is tokenized-clean: Owner check before the row lock with one error for missing and non-owner, expiry above the decided blocks, closed on the pending path only", () => {
    expect(decideIssues(sql)).toEqual([]);
    expect((body.match(/approval: not authorized/g) ?? []).length).toBe(1);
  });

  it("returns a distinct outcome per case and validates the decision", () => {
    for (const o of ["decided", "unchanged", "already_decided", "conflict", "revoked", "expired", "closed"]) expect(body).toContain(`'${o}'`);
    expect(body).toMatch(/p_decision NOT IN \('approve', 'deny'\)/);
  });

  it("revokes an approved row through the deny decision and records who and when", () => {
    expect(body).toMatch(/SET status = 'rejected', revoked_at = now\(\), revoked_by = auth\.uid\(\)/);
  });

  it("moves the linked inbox item out of the action_required count in the same transaction", () => {
    expect(body).toMatch(/approval_request_inbox_settle/);
    const helper = norm(fnBody(code, "approval_request_inbox_settle"));
    expect(helper).toMatch(/acted_at/);
    expect(helper).toMatch(/severity = 'info'/);
    expect(helper).toMatch(/workspace_id = p_workspace_id/);
  });
});

describe("create_approval_request", () => {
  const body = norm(fnBody(code, "create_approval_request"));

  it("is idempotent on the live unique index and writes the inbox item with a content-free title", () => {
    expect(body).toMatch(/ON CONFLICT \(conversation_id, action_sha256\) WHERE status IN \('pending', 'approved'\) DO NOTHING/);
    expect(body).toMatch(/'action_required'/);
    expect(body).toMatch(/'approval_required'/);
    expect(body).toMatch(/dedup_key/);
    expect(body).toMatch(/ON CONFLICT \(workspace_id, dedup_key\) WHERE dedup_key IS NOT NULL DO NOTHING/);
  });

  it("expires an overdue live row for the same action before inserting, so it can never wedge the unique index", () => {
    expect(body).toMatch(/status = 'expired'/);
    expect(body).toMatch(/expires_at <= now\(\)/);
  });

  it("validates the hash shape, the conversation/workspace pairing and the requester membership", () => {
    expect(body).toMatch(/\^\[0-9a-f\]\{64\}\$/);
    expect(body).toMatch(/archived_at/);
    expect(body).toMatch(/public\.is_workspace_member\(p_workspace_id, p_requested_by\)/);
  });

  it("counts the request across ALL statuses", () => {
    expect(body).toMatch(/SELECT count\(\*\) INTO v_count FROM public\.approval_request WHERE conversation_id = p_conversation_id AND action_sha256 = p_action_sha256;/);
  });

  it("caps pending requests (5 per conversation AP429, 20 per workspace AP430) only for a new request, before the INSERT", () => {
    expect(body).toMatch(/status = 'pending' AND expires_at > now\(\)\) >= 5 THEN RAISE EXCEPTION 'approval: too many pending requests' USING ERRCODE = 'AP429'/);
    expect(body).toMatch(/status = 'pending' AND expires_at > now\(\)\) >= 20 THEN RAISE EXCEPTION 'approval: too many pending requests' USING ERRCODE = 'AP430'/);
    expect(body.indexOf("AP429")).toBeLessThan(body.indexOf("INSERT INTO public.approval_request"));
    expect(body.indexOf("AP430")).toBeLessThan(body.indexOf("INSERT INTO public.approval_request"));
    expect(body.indexOf("IF NOT EXISTS ( SELECT 1 FROM public.approval_request WHERE conversation_id = p_conversation_id AND action_sha256 = p_action_sha256 AND status IN ('pending', 'approved') )")).toBeGreaterThan(0);
  });

  it("returns notify (coalesced over 10 minutes per workspace) and expires_at", () => {
    expect(body).toMatch(/x\.created_at > now\(\) - interval '10 minutes'/);
    expect(body).toMatch(/'notify', v_notify, 'expires_at', v_row\.expires_at/);
  });
});

describe("write-once trigger and carve-outs", () => {
  const body = norm(fnBody(code, "approval_request_guard"));

  it("is a BEFORE INSERT OR UPDATE OR DELETE row trigger", () => {
    expect(norm(code)).toMatch(/CREATE TRIGGER approval_request_guard BEFORE INSERT OR UPDATE OR DELETE ON public\.approval_request FOR EACH ROW EXECUTE FUNCTION public\.approval_request_guard\(\)/);
  });

  it("encodes exactly the TypeScript status machine (SQL tuples parsed and compared with APPROVAL_TRANSITIONS)", () => {
    expect(transitionTuples(sql)).toEqual(APPROVAL_TRANSITIONS.map(([a, b]) => `${a}>${b}`).sort());
  });

  it("has the Art. 17 SET NULL carve-out bound to a deleted parent user for all three user columns, and the workspace-cascade DELETE carve-out", () => {
    expect(body).toMatch(/NOT EXISTS \(SELECT 1 FROM public\.users WHERE id = OLD\.requested_by_user_id\)/);
    expect(body).toMatch(/NOT EXISTS \(SELECT 1 FROM public\.users WHERE id = OLD\.decided_by\)/);
    expect(body).toMatch(/NOT EXISTS \(SELECT 1 FROM public\.users WHERE id = OLD\.revoked_by\)/);
    expect(body).toMatch(/to_jsonb\(NEW\) - 'requested_by_user_id' - 'decided_by' - 'revoked_by'/);
    expect(body).toMatch(/NOT EXISTS \(SELECT 1 FROM public\.workspaces WHERE id = OLD\.workspace_id\)/);
  });

  it("admits the erasure DELETE only under app.approval_erase AND with no member left for OLD.workspace_id", () => {
    expect(body).toMatch(/v_erase boolean := COALESCE\(current_setting\('app\.approval_erase', true\), ''\) = 'on'/);
    expect(body).toMatch(/IF v_erase AND NOT EXISTS \(SELECT 1 FROM public\.workspace_members WHERE workspace_id = OLD\.workspace_id\) THEN RETURN OLD; END IF; RAISE EXCEPTION 'approval_request: DELETE rejected'/);
  });

  it("refuses direct writes: INSERT and state changes require the rpc GUC, text scrub requires its own", () => {
    expect(body).toMatch(/app\.approval_rpc/);
    expect(body).toMatch(/app\.approval_scrub/);
  });

  it("makes the identity, decision and revoke columns write-once", () => {
    for (const c of ["workspace_id", "conversation_id", "tool_name", "action_sha256", "expires_at", "created_at"]) {
      expect(body).toContain(`NEW.${c} IS DISTINCT FROM OLD.${c}`);
    }
    expect(body).toMatch(/OLD\.decided_at IS NOT NULL AND/);
    expect(body).toMatch(/consumed_at/);
    expect(body).toMatch(/expired_at/);
    expect(body).toMatch(/unanswered_flagged_at/);
    expect(body).toMatch(/OLD\.revoked_at IS NOT NULL OR OLD\.status <> 'approved' OR NEW\.status <> 'rejected'/);
    expect(body).toMatch(/a revoke records revoked_at and revoked_by/);
  });

  it("orders the cheap column checks before the jsonb equality in the SET NULL carve-out", () => {
    const a = body.indexOf("(a) Art. 17") >= 0 ? 0 : body.indexOf("NEW.requested_by_user_id IS DISTINCT FROM OLD.requested_by_user_id OR");
    expect(a).toBeGreaterThanOrEqual(0);
    expect(body.indexOf("NEW.requested_by_user_id IS DISTINCT FROM OLD.requested_by_user_id OR")).toBeLessThan(body.indexOf("to_jsonb(NEW) - 'requested_by_user_id'"));
  });
});

describe("sweep_approvals and anonymise", () => {
  it("sweep expires due rows, flags unanswered after 15 minutes once, and scrubs text 30 days after the terminal state, bounded", () => {
    const b = norm(fnBody(code, "sweep_approvals"));
    expect(b).toMatch(/expires_at <= now\(\)/);
    expect(b).toMatch(/unanswered_flagged_at IS NULL/);
    expect(b).toMatch(/interval '15 minutes'/);
    expect(b).toMatch(/interval '30 days'/);
    expect(b).toMatch(/canonical_action = NULL/);
    expect(b).toMatch(/COALESCE\(consumed_at, expired_at, revoked_at, decided_at\) < now\(\) - interval '30 days' ORDER BY COALESCE\(consumed_at, expired_at, revoked_at, decided_at\) LIMIT 500 FOR UPDATE SKIP LOCKED/);
  });

  it("anonymise nulls the three user columns and the text, and deletes the rows of a memberless personal workspace", () => {
    const b = norm(fnBody(code, "anonymise_approval_request"));
    expect(b).toMatch(/requested_by_user_id = CASE/);
    expect(b).toMatch(/decided_by = CASE/);
    expect(b).toMatch(/revoked_by = CASE/);
    expect(b).toMatch(/canonical_action = CASE/);
    expect(b).toMatch(/IF NOT EXISTS \(SELECT 1 FROM public\.workspace_members WHERE workspace_id = p_user_id\) THEN/);
    expect(b).toMatch(/set_config\('app\.approval_erase', 'on', true\); DELETE FROM public\.approval_request WHERE workspace_id = p_user_id;/);
    expect(b).toMatch(/set_config\('app\.approval_erase', 'off', true\); DELETE FROM public\.inbox_item WHERE workspace_id = p_user_id AND source = 'approval_required';/);
  });
});

describe("get_approval_status", () => {
  it("selects named scalars, not to_jsonb of the whole row, and exposes no action text or user ids", () => {
    const b = norm(fnBody(code, "get_approval_status"));
    expect(b).not.toMatch(/to_jsonb/);
    expect(b).toContain("jsonb_build_object(");
    for (const bad of ["canonical_action", "requested_by_user_id", "decided_by", "revoked_by"]) expect(b).not.toContain(`'${bad}'`);
    expect(b).toContain("'revoked_at', v_row.revoked_at");
  });
});

describe("inbox_item source CHECK widening", () => {
  it("drops EVERY CHECK that references source (not just one name), adds the widened CHECK NOT VALID, then VALIDATEs it", () => {
    const n = norm(code);
    expect(n).toMatch(/pg_get_constraintdef\(oid\) ~ '\\ysource\\y'/);
    expect(n).toMatch(/EXECUTE format\('ALTER TABLE public\.inbox_item DROP CONSTRAINT %I', c\.conname\)/);
    expect(n).toMatch(/ADD CONSTRAINT inbox_item_source_check CHECK \(source IN \('task_completed', 'system', 'approval_required'\)\) NOT VALID/);
    expect(n).toMatch(/VALIDATE CONSTRAINT inbox_item_source_check/);
    expect(n.indexOf("NOT VALID")).toBeLessThan(n.indexOf("VALIDATE CONSTRAINT inbox_item_source_check"));
    expect(n).not.toMatch(/DROP CONSTRAINT IF EXISTS inbox_item_source_check/);
  });
});

describe("down migration", () => {
  const down = read(DOWN);
  it("drops every function, the table and restores the narrower source CHECK", () => {
    for (const name of [...Object.keys(RPCS), "approval_request_guard", "approval_request_inbox_settle"]) {
      expect(down).toContain(`DROP FUNCTION IF EXISTS public.${name}(`);
    }
    expect(down).toContain("DROP FUNCTION IF EXISTS public.approval_request_inbox_settle(uuid, uuid, text);");
    expect(down).toMatch(/DROP TABLE IF EXISTS public\.approval_request/);
    expect(norm(down)).toMatch(/CHECK \(source IN \('task_completed', 'system'\)\)/);
    expect(down).toMatch(/DELETE FROM public\.inbox_item\s+WHERE source = 'approval_required'/);
  });

  it("states in its header that it is NOT a hot rollback", () => {
    expect(down.split("\n").slice(0, 8).join("\n")).toMatch(/NOT A HOT ROLLBACK/);
  });
});

describe("verify sentinel", () => {
  const v = read(VERIFY);
  it("asserts the grant matrix, definer pins and the live catalog shape (bad=1 on drift)", () => {
    expect(v).toMatch(/\bbad\b/);
    expect(v).toContain("approval_request");
    for (const name of Object.keys(RPCS)) expect(v).toContain(name);
    expect(v).toMatch(/has_function_privilege/);
    expect(v).toMatch(/has_table_privilege/);
  });

  it("asserts no source CHECK lacking approval_required remains, and carries no row-level erasure check", () => {
    expect(v).toContain("inbox_item_source_only_admitting_check");
    // A row-level erased-solo-workspace check also matches a memberless TEAM workspace (accepted residual) and would
    // fail verify-migrations on every later release; the falsifier lives in the tenant-isolation integration test.
    expect(v).not.toContain("no_approval_rows_for_erased_solo_workspace");
    expect(v).toContain("consume_approval_principal_recheck");
    expect(v).not.toContain("approval_request_inbox_settle(uuid, text)");
  });
});

// ---------------------------------------------------------------------------------------------------------------
// MUTATIONS: the eleven mutants that the earlier String.includes version let survive (test-design review S1-S10 and
// S4b). Each is applied to the RAW migration text; the matching checker must report at least one issue.
// ---------------------------------------------------------------------------------------------------------------

function mutate(raw: string, from: string, to: string, within?: { fn: string }): string {
  let idx = -1;
  if (within) {
    const start = raw.indexOf(`CREATE OR REPLACE FUNCTION public.${within.fn}(`);
    expect(start, `function ${within.fn}`).toBeGreaterThanOrEqual(0);
    idx = raw.indexOf(from, start);
  } else {
    idx = raw.indexOf(from);
  }
  expect(idx, `mutation anchor not found: ${from}`).toBeGreaterThanOrEqual(0);
  return raw.slice(0, idx) + to + raw.slice(idx + from.length);
}

const MUTANTS: Array<{ id: string; why: string; checker: (raw: string) => string[]; apply: (raw: string) => string }> = [
  { id: "S1", why: "OR true on the hash conjunct", checker: consumeIssues, apply: (r) => mutate(r, "AND action_sha256 = p_hash", "AND (action_sha256 = p_hash OR true)", { fn: "consume_approval" }) },
  { id: "S2", why: "status OR status = 'pending'", checker: consumeIssues, apply: (r) => mutate(r, "AND status = 'approved'\n     AND expires_at > now()", "AND status = 'approved' OR status = 'pending'\n     AND expires_at > now()", { fn: "consume_approval" }) },
  { id: "S3", why: "expiry slack of 1000 years", checker: consumeIssues, apply: (r) => mutate(r, "AND expires_at > now()", "AND expires_at > now() - interval '1000 years'", { fn: "consume_approval" }) },
  { id: "S4", why: "hash conjunct commented out", checker: consumeIssues, apply: (r) => mutate(r, "AND action_sha256 = p_hash", "AND true -- action_sha256 = p_hash", { fn: "consume_approval" }) },
  { id: "S4b", why: "conversation conjunct commented out", checker: consumeIssues, apply: (r) => mutate(r, "AND conversation_id = p_conversation", "AND true -- conversation_id = p_conversation", { fn: "consume_approval" }) },
  { id: "S10", why: "WHERE (id = p_id OR true)", checker: consumeIssues, apply: (r) => mutate(r, "WHERE id = p_id\n     AND status = 'approved'", "WHERE (id = p_id OR true)\n     AND status = 'approved'", { fn: "consume_approval" }) },
  { id: "S5", why: "decide owner polarity inverted", checker: decideIssues, apply: (r) => mutate(r, "IF NOT v_ok THEN", "IF v_ok THEN", { fn: "decide_approval" }) },
  { id: "S5b", why: "decide owner check negated at the source", checker: decideIssues, apply: (r) => mutate(r, "COALESCE(public.is_workspace_owner(v_ws, auth.uid()), false)", "NOT COALESCE(public.is_workspace_owner(v_ws, auth.uid()), false)", { fn: "decide_approval" }) },
  { id: "S6", why: "decide expiry slack of 100 years", checker: decideIssues, apply: (r) => mutate(r, "AND v_row.expires_at <= now() THEN", "AND v_row.expires_at <= now() - interval '100 years' THEN", { fn: "decide_approval" }) },
  { id: "S7", why: "decide closed-conversation polarity inverted", checker: decideIssues, apply: (r) => mutate(r, "IF NOT FOUND OR v_closed THEN", "IF NOT FOUND OR NOT v_closed THEN", { fn: "decide_approval" }) },
  { id: "S8", why: "TRUNCATE granted to authenticated", checker: grantIssues, apply: (r) => `${r}\nGRANT TRUNCATE ON TABLE public.approval_request TO authenticated;\n` },
  {
    id: "S9",
    why: "extra permissive SELECT USING (true) policy",
    checker: grantIssues,
    apply: (r) => mutate(r, "DROP POLICY IF EXISTS approval_request_owner_select", "CREATE POLICY approval_request_open_select ON public.approval_request FOR SELECT TO authenticated USING (true);\nDROP POLICY IF EXISTS approval_request_owner_select"),
  },
  { id: "T1", why: "a transition tuple dropped (revoke)", checker: (r) => (transitionTuples(r).join() === APPROVAL_TRANSITIONS.map(([a, b]) => `${a}>${b}`).sort().join() ? [] : ["tuple drift"]), apply: (r) => mutate(r, ",\n       ('approved', 'rejected')\n     )", "\n     )") },
  { id: "T2", why: "a transition tuple added (rejected -> approved)", checker: (r) => (transitionTuples(r).join() === APPROVAL_TRANSITIONS.map(([a, b]) => `${a}>${b}`).sort().join() ? [] : ["tuple drift"]), apply: (r) => mutate(r, "('approved', 'rejected')\n     )", "('approved', 'rejected'),\n       ('rejected', 'approved')\n     )") },
  { id: "C1", why: "consume drops the decider-still-Owner re-check", checker: consumeIssues, apply: (r) => mutate(r, "AND public.is_workspace_owner(workspace_id, decided_by)\n", "", { fn: "consume_approval" }) },
  { id: "C2", why: "consume drops the requester-still-member re-check", checker: consumeIssues, apply: (r) => mutate(r, "AND public.is_workspace_member(workspace_id, requested_by_user_id)\n", "", { fn: "consume_approval" }) },
  { id: "D1", why: "decide takes the row lock before the Owner check", checker: decideIssues, apply: (r) => mutate(r, "SELECT workspace_id INTO v_ws FROM public.approval_request WHERE id = p_id;", "SELECT workspace_id INTO v_ws FROM public.approval_request WHERE id = p_id FOR UPDATE;", { fn: "decide_approval" }) },
];

describe("MUTATIONS: the unmutated migration is clean, every mutant is RED", () => {
  it("control: the real migration passes every checker", () => {
    expect(consumeIssues(sql)).toEqual([]);
    expect(decideIssues(sql)).toEqual([]);
    expect(grantIssues(sql)).toEqual([]);
    expect(transitionTuples(sql)).toEqual(APPROVAL_TRANSITIONS.map(([a, b]) => `${a}>${b}`).sort());
  });

  it("covers the eleven survivors of the earlier version (S1-S10 and S4b)", () => {
    for (const id of ["S1", "S2", "S3", "S4", "S4b", "S5", "S6", "S7", "S8", "S9", "S10"]) expect(MUTANTS.map((m) => m.id)).toContain(id);
  });

  for (const m of MUTANTS) {
    it(`${m.id}: ${m.why} is detected (RED)`, () => {
      const mutated = m.apply(sql);
      expect(mutated).not.toBe(sql);
      expect(m.checker(mutated).length, `${m.id} survived`).toBeGreaterThan(0);
    });
  }
});
