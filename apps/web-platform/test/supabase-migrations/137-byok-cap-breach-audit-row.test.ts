import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 137_byok_cap_breach_audit_row.sql (#7829).
//
// OFFLINE TRIPWIRE ONLY — explicitly NOT the proof. Reachability (does a row
// actually exist after a refusal?) is proven by the live tenant-integration
// suite. Everything here is presence, and presence is exactly what shipped
// green against the broken state before.
//
// THE DEFECT 137 CLOSES: 084's refusal branches signalled by RAISE. An
// unhandled plpgsql RAISE aborts the transaction, which discards the INSERT
// made in that same transaction — and the function declares no EXCEPTION
// handler. So NO refusal branch has ever persisted its audit row, including
// the three that visibly INSERT before raising. The fix makes refusal a
// RETURNED value.
//
// WHAT A REVIEW PANEL FOUND WRONG WITH THE FIRST VERSION OF THIS FILE, and
// what each fix below is for. The first version's header claimed assertions
// were "anchored on syntax the SUT owns and never on a bare token a comment
// could also carry". That was FALSE, and the panel proved it by mutation:
//   * it stripped `--` only, so a /* */ block comment satisfied every bare
//     token. Deleting the FOR UPDATE row lock and leaving a block comment
//     mentioning it passed. So did deleting the caller pin.       → strip() below
//   * a test NAMED "every INSERT is followed by a RETURN" asserted only
//     `inserts.length === 6`. Deleting every RETURN passed, and execution then
//     falls through to the pass branch, ADMITTING a revoked / withdrawn /
//     expired delegation.                                          → §T1 below
//   * a sixth refusal branch that RAISEs and writes no row passed — the exact
//     defect class the PR closes, reintroduced with no signal.      → §T1-universal
//   * the SUM assertion was anchored on the token `attribution_shift_reason`,
//     so excluding refusal rows via `founder_id = grantor` instead — same
//     semantic defect, different column — passed.                   → §AC5 below
//   * the down migration was pinned only by `RETURNS void`. Replacing its whole
//     body with `BEGIN RETURN; END` passed, installing a no-op gate on
//     rollback.                                                     → §AC6 below
//   * `it.each([])` on an emptied array silently drops ten assertions with no
//     warning.                                                      → §harness below

const MIGRATION_PATH = path.join(
  __dirname,
  "../../supabase/migrations/137_byok_cap_breach_audit_row.sql",
);
const DOWN_PATH = path.join(
  __dirname,
  "../../supabase/migrations/137_byok_cap_breach_audit_row.down.sql",
);

/**
 * Strip BOTH comment forms. `--` alone is not enough: a /* *\/ block comment is
 * still executable-adjacent text that satisfies any grep, which is how the
 * first version of this file certified a deleted row lock.
 */
export function strip(sql: string): string {
  return sql.replace(/\/\*[\s\S]*?\*\//g, "").replace(/--[^\n]*/g, "");
}

const sql = readFileSync(MIGRATION_PATH, "utf8");
const downSql = readFileSync(DOWN_PATH, "utf8");
const executable = strip(sql);
const downExecutable = strip(downSql);

function extractFn(src: string, name: string): string {
  const m = src.match(
    new RegExp(`CREATE\\s+(?:OR\\s+REPLACE\\s+)?FUNCTION\\s+public\\.${name}\\b[\\s\\S]*?\\n\\$\\$;`, "i"),
  );
  if (!m) throw new Error(`fixture: ${name} body not found`);
  return m[0];
}
const delegationFn = () => extractFn(executable, "check_and_record_byok_delegation_use");
const founderFn = () => extractFn(executable, "record_byok_use_and_check_cap");

const REFUSAL_REASONS = [
  "revoked_post_grace",
  "consent_withdrawn",
  "expired",
  "hourly_cap_exceeded",
  "daily_cap_exceeded",
] as const;

// Sentinels the function is still ALLOWED to raise. Anything else raising is a
// refusal signalled by exception — the defect.
const PERMITTED_RAISE_SENTINELS = [
  "p_delegation_id and p_caller_user_id are required",
  "delegation % not found",
  "byok_delegations:anonymised",
  "byok_delegations:caller_not_grantee",
];

describe("migration 137_byok_cap_breach_audit_row", () => {
  describe("harness controls (this suite must be able to fail)", () => {
    it("the refusal-reason population is non-empty and is exactly five", () => {
      // Guards the it.each([]) vacuity: an emptied array silently drops every
      // per-reason assertion with no warning and no failure.
      expect(REFUSAL_REASONS.length).toBe(5);
    });

    it("strip() removes block comments, not just line comments", () => {
      expect(strip("a /* FOR UPDATE */ b")).not.toMatch(/FOR UPDATE/);
      expect(strip("a -- FOR UPDATE\nb")).not.toMatch(/FOR UPDATE/);
    });

    it("the branch predicate REJECTS a body that only mentions the reason in a comment", () => {
      // Positive control for §T1: prove the predicate can fail.
      const fake = strip(`
        CREATE FUNCTION public.fake() RETURNS void AS $$
        BEGIN
          /* revoked_post_grace: handled below */
          RAISE EXCEPTION 'byok_delegations:revoked_post_grace';
        END; $$;`);
      expect(fake).not.toMatch(/refusal_reason\s*:=\s*'revoked_post_grace'/);
    });
  });

  describe("AC1 — migration pair exists and is transactional", () => {
    it("both files are wrapped BEGIN;/COMMIT; and cite #7829", () => {
      expect(executable).toMatch(/^\s*BEGIN;/m);
      expect(executable).toMatch(/COMMIT;\s*$/m);
      expect(downExecutable).toMatch(/^\s*BEGIN;/m);
      expect(downExecutable).toMatch(/COMMIT;\s*$/m);
      expect(sql).toMatch(/#7829/);
    });
  });

  describe("AC2/T1 — refusal RETURNS; it does not raise, and it does not fall through", () => {
    it("the function returns a refusal reason rather than void", () => {
      expect(delegationFn()).toMatch(/RETURNS\s+TABLE\s*\(\s*refusal_reason\s+text\s*\)/i);
      expect(delegationFn()).not.toMatch(/RETURNS\s+void/i);
    });

    it.each(REFUSAL_REASONS)(
      "%s INSERTs, assigns the reason, and RETURNS — it cannot fall through",
      (reason) => {
        const body = delegationFn();
        // The ordered triple is the property. Asserting the INSERT alone let a
        // mutation delete every RETURN and silently ADMIT the refused turn.
        const ordered = new RegExp(
          `'${reason}'[\\s\\S]{0,300}?ON\\s+CONFLICT\\s*\\(invocation_id\\)\\s*DO\\s+NOTHING;` +
            `\\s*refusal_reason\\s*:=\\s*'${reason}';` +
            `\\s*RETURN\\s+NEXT;` +
            `\\s*RETURN;`,
          "i",
        );
        expect(body).toMatch(ordered);
      },
    );

    it("NO refusal is signalled by RAISE — including a reason added later", () => {
      // Universal, not a five-item allowlist: a sixth branch that RAISEs
      // reintroduces the transaction-abort defect with no other signal.
      const raises = delegationFn().match(/RAISE\s+EXCEPTION\s+'[^']+'/gi) ?? [];
      for (const r of raises) {
        const permitted = PERMITTED_RAISE_SENTINELS.some((s) => r.includes(s));
        expect(permitted, `unexpected RAISE (a refusal must RETURN, not raise): ${r}`).toBe(true);
      }
      expect(raises.length).toBeGreaterThan(0); // non-vacuity: validation raises still exist
    });

    it("has six INSERTs — five refusals plus the admitted row", () => {
      const inserts = delegationFn().match(/INSERT\s+INTO\s+public\.audit_byok_use/gi) ?? [];
      expect(inserts.length).toBe(6);
    });
  });

  describe("AC3 — the security envelope is re-issued", () => {
    it("retains SECURITY DEFINER, the search_path pin, and the FOR UPDATE row lock", () => {
      expect(delegationFn()).toMatch(/SECURITY\s+DEFINER/i);
      expect(delegationFn()).toMatch(/SET\s+search_path\s*=\s*public,\s*pg_temp/i);
      // Anchored on the real clause, on comment-stripped source.
      expect(delegationFn()).toMatch(/FROM\s+public\.byok_delegations[\s\S]{0,120}?FOR\s+UPDATE/i);
    });
    it("re-issues REVOKE and GRANTs service_role only", () => {
      expect(executable).toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.check_and_record_byok_delegation_use\([^)]*\)\s*FROM\s+PUBLIC,\s*anon,\s*authenticated/i,
      );
      expect(executable).toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.check_and_record_byok_delegation_use\([^)]*\)\s*TO\s+service_role/i,
      );
    });
    it("a return-type change requires DROP + CREATE", () => {
      expect(executable).toMatch(/DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.check_and_record_byok_delegation_use/i);
      expect(executable).not.toMatch(/CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.check_and_record_byok_delegation_use/i);
    });
    it("pins the caller to the grantee", () => {
      expect(delegationFn()).toMatch(/p_caller_user_id\s+IS\s+DISTINCT\s+FROM\s+v_row\.grantee_user_id/i);
    });
  });

  describe("AC4 — the CHECK admits exactly five reasons plus NULL, and nothing else", () => {
    const constraint = () => {
      const m = executable.match(
        /ADD\s+CONSTRAINT\s+audit_byok_use_attribution_shift_reason_check\s+CHECK\s*\(([\s\S]*?)\)\s*;/i,
      );
      if (!m) throw new Error("fixture: widened CHECK not found");
      return m[1];
    };
    it.each(REFUSAL_REASONS)("admits %s", (r) => expect(constraint()).toContain(`'${r}'`));
    it("admits NULL", () => expect(constraint()).toMatch(/IS\s+NULL/i));
    it("admits NOTHING ELSE — the IN list is exactly five literals", () => {
      const literals = constraint().match(/'[a-z_]+'/g) ?? [];
      expect([...literals].sort()).toEqual([...REFUSAL_REASONS].map((r) => `'${r}'`).sort());
    });
    it("is not declared NOT VALID", () => expect(executable).not.toMatch(/NOT\s+VALID/i));
  });

  describe("AC5/T3 — the delegation windows sum every row in scope", () => {
    const sumFor = (target: string) => {
      const m = delegationFn().match(new RegExp(`SELECT[\\s\\S]{0,200}?INTO\\s+${target}[\\s\\S]*?;`, "i"));
      if (!m) throw new Error(`fixture: SUM INTO ${target} not found`);
      return m[0];
    };
    it.each(["v_hourly_spent", "v_daily_spent"])(
      "%s filters on delegation_id and ts ONLY — no row-excluding predicate",
      (target) => {
        // Anchored on the PROPERTY, not the token. The token form let a mutation
        // exclude refusal rows via `founder_id = grantor` and stay green.
        const where = sumFor(target).split(/\bWHERE\b/i)[1] ?? "";
        const predicates = where.split(/\bAND\b/i).map((p) => p.trim()).filter(Boolean);
        expect(predicates.length).toBe(2);
        expect(predicates[0]).toMatch(/au\.delegation_id\s*=\s*p_delegation_id/i);
        expect(predicates[1]).toMatch(/au\.ts\s*>/i);
      },
    );
  });

  describe("Decision 3 (ADR-208) — the delegation windows carry CORRECTED unit semantics", () => {
    // unit_cost_cents holds the WHOLE TURN's cost, so `token_count * unit_cost_cents`
    // is cents-times-tokens and trips any real cap on the first turn. Shipping that
    // would mis-attribute founder_id on 100% of delegated rows in a WORM table.
    it.each(["v_hourly_spent", "v_daily_spent"])("%s sums unit_cost_cents, not the product", (t) => {
      const m = delegationFn().match(new RegExp(`SELECT[\\s\\S]{0,200}?INTO\\s+${t}[\\s\\S]*?;`, "i"))![0];
      expect(m).toMatch(/SUM\(\s*au\.unit_cost_cents\s*\)/i);
      expect(m).not.toMatch(/token_count\s*\*/i);
    });
    it("v_this_cost is the whole-turn cost, not the product", () => {
      expect(delegationFn()).toMatch(/v_this_cost\s+int\s*:=\s*p_unit_cost_cents\s*;/i);
      expect(delegationFn()).not.toMatch(/v_this_cost[^;]*p_token_count\s*\*/i);
    });
  });

  describe("Decision 4 — the personal Layer 1 cap excludes only the refusal rows 137 creates", () => {
    it("the founder SUM filters attribution_shift_reason IS NULL", () => {
      const m = founderFn().match(/SELECT[\s\S]*?INTO\s+v_total[\s\S]*?;/i);
      expect(m).not.toBeNull();
      expect(m![0]).toMatch(/attribution_shift_reason\s+IS\s+NULL/i);
      // delegation_id IS NULL was REJECTED: it would also drop grantor-attributed
      // ADMITTED rows, which 121 has always counted and should keep counting.
      expect(m![0]).not.toMatch(/delegation_id\s+IS\s+NULL/i);
    });
    it("PINS the founder SUM's product PENDING the founder-wide fix — this is the DEFECT, held deliberately, not the correct form", () => {
      expect(founderFn()).toMatch(/SUM\(token_count\s*\*\s*unit_cost_cents\)/i);
    });
  });

  describe("AC6 — the down migration is a real restore, not a stub", () => {
    it("restores the 084 RETURNS void body", () => {
      expect(downExecutable).toMatch(/RETURNS\s+void/i);
    });
    it.each(REFUSAL_REASONS)("restores the %s branch, RAISE and all", (reason) => {
      // Pinned so replacing the whole body with `BEGIN RETURN; END` cannot pass —
      // that mutation installed a no-op gate (no lock, no caps, no audit row).
      expect(downExecutable).toMatch(new RegExp(`byok_delegations:${reason}`, "i"));
    });
    it("restores the row lock and re-issues the grants and the comment", () => {
      expect(downExecutable).toMatch(/FOR\s+UPDATE/i);
      expect(downExecutable).toMatch(/GRANT\s+EXECUTE[\s\S]*?TO\s+service_role/i);
      expect(downExecutable).toMatch(/COMMENT\s+ON\s+FUNCTION/i);
    });
    it("contains no NOT VALID and NARROWS no constraint, under any name", () => {
      expect(downExecutable).not.toMatch(/NOT\s+VALID/i);
      // Name-anchoring let a mutation re-narrow under a renamed constraint.
      expect(downExecutable).not.toMatch(/ADD\s+CONSTRAINT[\s\S]*?attribution_shift_reason\s+IN\s*\(/i);
    });
  });
});
