import { describe, expect, it } from "vitest";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { APPROVAL_TRANSITIONS } from "@/server/approval/service";
import { APPROVAL_REQUIRED_TOOLS } from "@/server/approval/tools";

// Static shape tests for migration 180 (#4672). The BEHAVIOURAL proof of the consume predicate, the status
// machine and decide_approval runs against a real database (supabase/verify/180_approval_request.sql plus
// test/rls-fuzz/approval-request.integration.test.ts); this file pins the TEXT so a one-line edit that drops a
// conjunct, a grant or a carve-out is red in the ordinary vitest run. The mutation rows below DELETE one conjunct
// from the extracted statement and assert the checker notices (a checker that cannot go red is vacuous).

const DIR = path.join(__dirname, "../../supabase");
const UP = path.join(DIR, "migrations/180_approval_request.sql");
const DOWN = path.join(DIR, "migrations/180_approval_request.down.sql");
const VERIFY = path.join(DIR, "verify/180_approval_request.sql");

const read = (p: string): string => (existsSync(p) ? readFileSync(p, "utf8") : "");
const sql = read(UP);
const stripComments = (s: string) =>
  s
    .split("\n")
    .filter((l) => !l.trim().startsWith("--"))
    .join("\n");
const code = stripComments(sql);
const norm = (s: string) => s.replace(/\s+/g, " ").trim();

/** The body of one function, from its CREATE to its terminating `$tag$;`. */
function fnBody(src: string, name: string): string {
  const re = new RegExp(`CREATE OR REPLACE FUNCTION public\\.${name}\\([\\s\\S]*?\\n\\$(\\w*)\\$;`, "i");
  const m = re.exec(src);
  return m ? m[0] : "";
}

/** The UPDATE statement of consume_approval (the single place an approval turns into an allow). */
const consumeUpdate = (src: string): string => {
  const body = fnBody(src, "consume_approval");
  const m = /UPDATE public\.approval_request[\s\S]*?RETURNING[^;]*;/i.exec(body);
  return m ? norm(m[0]) : "";
};

const CONSUME_CONJUNCTS = [
  "id = p_id",
  "status = 'approved'",
  "expires_at > now()",
  "action_sha256 = p_hash",
  "conversation_id = p_conversation",
] as const;
const CONSUME_SETS = ["status = 'consumed'", "consumed_at = now()"] as const;

function consumeIssues(update: string): string[] {
  const issues: string[] = [];
  for (const c of [...CONSUME_CONJUNCTS, ...CONSUME_SETS]) if (!update.includes(c)) issues.push(c);
  return issues;
}

describe("files exist (up, down, verify)", () => {
  it("ships the migration, its down and the verify sentinel", () => {
    expect(existsSync(UP)).toBe(true);
    expect(existsSync(DOWN)).toBe(true);
    expect(existsSync(VERIFY)).toBe(true);
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
    expect(norm(code)).toMatch(/workspace_id uuid NOT NULL REFERENCES public\.workspaces\(id\) ON DELETE CASCADE/);
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

  it("annotates every personal-data column with a lawful basis and states the retention", () => {
    expect((sql.match(/-- LAWFUL_BASIS:/g) ?? []).length).toBeGreaterThanOrEqual(3);
    for (const col of ["requested_by_user_id", "decided_by", "canonical_action"]) {
      const m = new RegExp(`\\n  ${col}\\s`).exec(sql);
      expect(m, `column definition of ${col}`).not.toBeNull();
      const before = sql.slice(Math.max(0, (m?.index ?? 0) - 700), m?.index ?? 0);
      expect(before, col).toMatch(/LAWFUL_BASIS/);
    }
    expect(sql).toMatch(/30 days/i);
    expect(sql).toMatch(/RETENTION:/i);
  });
});

describe("RLS and Data API grants (ADR-303)", () => {
  it("revokes every privilege from every api role, then grants SELECT to authenticated only", () => {
    expect(norm(code)).toMatch(/REVOKE ALL ON TABLE public\.approval_request FROM PUBLIC, anon, authenticated, service_role/);
    expect(norm(code)).toMatch(/GRANT SELECT ON TABLE public\.approval_request TO authenticated/);
    expect(code).not.toMatch(/GRANT[^;]*\b(INSERT|UPDATE|DELETE|ALL)\b[^;]*ON TABLE public\.approval_request/i);
    expect(code).not.toMatch(/GRANT[^;]*ON TABLE public\.approval_request TO (anon|service_role)/i);
  });

  it("has an owner SELECT policy, a restrictive jti policy and NO write policy", () => {
    expect(norm(code)).toMatch(/CREATE POLICY approval_request_owner_select ON public\.approval_request FOR SELECT TO authenticated USING \( public\.is_workspace_owner\(workspace_id, auth\.uid\(\)\) \)/);
    expect(norm(code)).toMatch(/approval_request_jti_not_denied/);
    const policies = code.match(/CREATE POLICY \w+ ON public\.approval_request([^;]*);/g) ?? [];
    for (const p of policies) {
      if (/RESTRICTIVE/i.test(p)) continue;
      expect(p).toMatch(/FOR SELECT/i);
    }
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
    for (const name of ["create_approval_request", "consume_approval", "get_approval_status", "list_live_approvals", "sweep_approvals"]) {
      expect(fnBody(code, name), name).toMatch(/auth\.uid\(\) IS NOT NULL/);
    }
  });

  it("the write-once trigger function is pinned and revoked too", () => {
    const body = fnBody(code, "approval_request_guard");
    expect(body).toMatch(/SECURITY DEFINER/);
    expect(body).toMatch(/SET search_path = public, pg_temp/);
    expect(norm(code)).toMatch(/REVOKE ALL ON FUNCTION public\.approval_request_guard\(\) FROM PUBLIC, anon, authenticated, service_role/);
  });
});

describe("Guard 1: consume predicate (static pin; behavioural proof is in verify/180 and the integration test)", () => {
  it("the single atomic UPDATE carries every conjunct and both SET columns", () => {
    expect(consumeIssues(consumeUpdate(code))).toEqual([]);
  });

  for (const conjunct of [...CONSUME_CONJUNCTS, ...CONSUME_SETS]) {
    it(`mutation: deleting '${conjunct}' from the consume statement is detected (RED)`, () => {
      const mutated = consumeUpdate(code).replace(conjunct, "true");
      expect(mutated).not.toBe(consumeUpdate(code));
      expect(consumeIssues(mutated)).toContain(conjunct);
    });
  }

  it("consume never reads the hash or conversation from anywhere but its parameters", () => {
    expect(consumeUpdate(code)).not.toMatch(/\bNEW\./);
    expect(fnBody(code, "consume_approval")).toMatch(/GET DIAGNOSTICS|RETURNING/);
  });
});

describe("decide_approval", () => {
  const body = norm(fnBody(code, "decide_approval"));

  it("derives the actor from auth.uid() and has no actor parameter", () => {
    expect(body).toMatch(/auth\.uid\(\)/);
    expect(body).not.toMatch(/p_actor|p_user_id|p_decided_by/);
  });

  it("re-checks the Owner role at decision time, with one error for missing and non-owner (no existence oracle)", () => {
    expect(body).toMatch(/public\.is_workspace_owner\(v_row\.workspace_id, auth\.uid\(\)\)/);
    expect((body.match(/approval: not authorized/g) ?? []).length).toBe(1);
  });

  it("checks the jti denylist, locks the row, enforces expiry inline and refuses a closed conversation", () => {
    expect(body).toMatch(/public\.is_jti_denied_from_jwt\(\)/);
    expect(body).toMatch(/FOR UPDATE/);
    expect(body).toMatch(/expires_at <= now\(\)/);
    expect(body).toMatch(/'expired'/);
    expect(body).toMatch(/archived_at IS NOT NULL/);
    expect(body).toMatch(/'closed'/);
  });

  it("returns a distinct outcome per case and validates the decision", () => {
    for (const o of ["decided", "unchanged", "conflict", "expired", "closed"]) expect(body).toContain(`'${o}'`);
    expect(body).toMatch(/p_decision NOT IN \('approve', 'deny'\)/);
  });

  it("moves the linked inbox item out of the action_required count in the same transaction", () => {
    expect(body).toMatch(/approval_request_inbox_settle/);
    const helper = norm(fnBody(code, "approval_request_inbox_settle"));
    expect(helper).toMatch(/acted_at/);
    expect(helper).toMatch(/severity = 'info'/);
  });

  it("mutation: removing the is_workspace_owner check is detected", () => {
    const mutated = body.replace(/public\.is_workspace_owner\(v_row\.workspace_id, auth\.uid\(\)\)/, "true");
    expect(mutated).not.toMatch(/is_workspace_owner/);
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
    expect(body).toMatch(/count\(\*\)/);
    expect(body).not.toMatch(/count\(\*\)[^;]*status IN/);
  });
});

describe("write-once trigger and carve-outs", () => {
  const body = norm(fnBody(code, "approval_request_guard"));

  it("is a BEFORE INSERT OR UPDATE OR DELETE row trigger", () => {
    expect(norm(code)).toMatch(/CREATE TRIGGER approval_request_guard BEFORE INSERT OR UPDATE OR DELETE ON public\.approval_request FOR EACH ROW EXECUTE FUNCTION public\.approval_request_guard\(\)/);
  });

  it("encodes exactly the TypeScript status machine", () => {
    const m = /\(OLD\.status, NEW\.status\) NOT IN \(([^)]*(?:\)[^)]*)*?)\)\s*THEN/i.exec(body);
    const pairs = [...(m ? m[1] : "").matchAll(/\('(\w+)',\s*'(\w+)'\)/g)].map((x) => `${x[1]}>${x[2]}`).sort();
    expect(pairs).toEqual(APPROVAL_TRANSITIONS.map(([a, b]) => `${a}>${b}`).sort());
  });

  it("has the Art. 17 SET NULL carve-out bound to a deleted parent user and the workspace-cascade DELETE carve-out", () => {
    expect(body).toMatch(/NOT EXISTS \(SELECT 1 FROM public\.users WHERE id = OLD\.requested_by_user_id\)/);
    expect(body).toMatch(/NOT EXISTS \(SELECT 1 FROM public\.users WHERE id = OLD\.decided_by\)/);
    expect(body).toMatch(/to_jsonb\(NEW\) - 'requested_by_user_id' - 'decided_by'/);
    expect(body).toMatch(/NOT EXISTS \(SELECT 1 FROM public\.workspaces WHERE id = OLD\.workspace_id\)/);
  });

  it("refuses direct writes: INSERT and state changes require the rpc GUC, text scrub requires its own", () => {
    expect(body).toMatch(/app\.approval_rpc/);
    expect(body).toMatch(/app\.approval_scrub/);
  });

  it("makes the identity and decision columns write-once", () => {
    for (const c of ["workspace_id", "conversation_id", "tool_name", "action_sha256", "expires_at", "created_at"]) {
      expect(body).toContain(`NEW.${c} IS DISTINCT FROM OLD.${c}`);
    }
    expect(body).toMatch(/OLD\.decided_at IS NOT NULL AND/);
    expect(body).toMatch(/consumed_at/);
    expect(body).toMatch(/expired_at/);
    expect(body).toMatch(/unanswered_flagged_at/);
  });
});

describe("sweep_approvals and anonymise", () => {
  it("sweep expires due rows, flags unanswered after 15 minutes once, and scrubs text 30 days after the terminal state", () => {
    const b = norm(fnBody(code, "sweep_approvals"));
    expect(b).toMatch(/expires_at <= now\(\)/);
    expect(b).toMatch(/unanswered_flagged_at IS NULL/);
    expect(b).toMatch(/interval '15 minutes'/);
    expect(b).toMatch(/interval '30 days'/);
    expect(b).toMatch(/canonical_action = NULL/);
  });

  it("anonymise nulls both user columns and the text, and is service-role only", () => {
    const b = norm(fnBody(code, "anonymise_approval_request"));
    expect(b).toMatch(/requested_by_user_id = CASE/);
    expect(b).toMatch(/decided_by = CASE/);
    expect(b).toMatch(/canonical_action = CASE/);
  });
});

describe("inbox_item source CHECK widening", () => {
  it("replaces the CHECK NOT VALID and then VALIDATEs it, keeping the two existing sources", () => {
    const n = norm(code);
    expect(n).toMatch(/DROP CONSTRAINT IF EXISTS inbox_item_source_check/);
    expect(n).toMatch(/ADD CONSTRAINT inbox_item_source_check CHECK \(source IN \('task_completed', 'system', 'approval_required'\)\) NOT VALID/);
    expect(n).toMatch(/VALIDATE CONSTRAINT inbox_item_source_check/);
    expect(n.indexOf("NOT VALID")).toBeLessThan(n.indexOf("VALIDATE CONSTRAINT inbox_item_source_check"));
  });
});

describe("down migration", () => {
  const down = read(DOWN);
  it("drops every function, the table and restores the narrower source CHECK", () => {
    for (const name of [...Object.keys(RPCS), "approval_request_guard", "approval_request_inbox_settle"]) {
      expect(down).toContain(`DROP FUNCTION IF EXISTS public.${name}(`);
    }
    expect(down).toMatch(/DROP TABLE IF EXISTS public\.approval_request/);
    expect(norm(down)).toMatch(/CHECK \(source IN \('task_completed', 'system'\)\)/);
    expect(down).toMatch(/DELETE FROM public\.inbox_item\s+WHERE source = 'approval_required'/);
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
});
