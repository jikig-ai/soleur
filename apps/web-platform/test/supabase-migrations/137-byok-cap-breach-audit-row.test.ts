import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 137_byok_cap_breach_audit_row.sql (#7829).
//
// OFFLINE TRIPWIRE ONLY — explicitly NOT the proof. Reachability (does a row
// actually exist after a refusal?) is proven by the live tenant-integration
// suite under TENANT_INTEGRATION_TEST=1. Everything here is presence, and
// presence is exactly what shipped green against the broken state before, so
// these assertions are anchored on syntax the SUT owns and never on a bare
// token a comment could also carry.
//
// THE DEFECT 136 CLOSES: 084's refusal branches signalled by RAISE. An
// unhandled plpgsql RAISE aborts the transaction, which discards the INSERT
// made in that same transaction — and the function declares no EXCEPTION
// handler. So NO refusal branch has ever persisted its audit row, including
// the three that visibly INSERT before raising. The fix converts refusal from
// an exception into a RETURNED VALUE.

const MIGRATION_PATH = path.join(
  __dirname,
  "../../supabase/migrations/137_byok_cap_breach_audit_row.sql",
);
const DOWN_PATH = path.join(
  __dirname,
  "../../supabase/migrations/137_byok_cap_breach_audit_row.down.sql",
);

const sql = readFileSync(MIGRATION_PATH, "utf8");
const downSql = readFileSync(DOWN_PATH, "utf8");
// Strip line comments so no assertion below can be satisfied by prose.
const executable = sql.replace(/--[^\n]*/g, "");
const downExecutable = downSql.replace(/--[^\n]*/g, "");

// The one function under change, extracted CREATE-anchored so assertions
// cannot drift onto the sibling record_byok_use_and_check_cap redefinition.
function delegationFn(): string {
  const m = executable.match(
    /CREATE\s+FUNCTION\s+public\.check_and_record_byok_delegation_use\b[\s\S]*?\n\$\$;/i,
  );
  if (!m) throw new Error("fixture: check_and_record_byok_delegation_use body not found");
  return m[0];
}

const REFUSAL_REASONS = [
  "revoked_post_grace",
  "consent_withdrawn",
  "expired",
  "hourly_cap_exceeded",
  "daily_cap_exceeded",
] as const;

describe("migration 137_byok_cap_breach_audit_row", () => {
  describe("AC1 — migration pair exists and is transactional", () => {
    it("both files are wrapped BEGIN;/COMMIT;", () => {
      expect(executable).toMatch(/^\s*BEGIN;/m);
      expect(executable).toMatch(/COMMIT;\s*$/m);
      expect(downExecutable).toMatch(/^\s*BEGIN;/m);
      expect(downExecutable).toMatch(/COMMIT;\s*$/m);
    });
    it("cites #7829", () => {
      expect(sql).toMatch(/#7829/);
    });
  });

  describe("AC2/T1 — refusal returns, it does not raise", () => {
    it("the function returns a refusal reason rather than void", () => {
      expect(delegationFn()).toMatch(
        /RETURNS\s+TABLE\s*\(\s*refusal_reason\s+text\s*\)/i,
      );
      expect(delegationFn()).not.toMatch(/RETURNS\s+void/i);
    });

    it.each(REFUSAL_REASONS)(
      "the %s branch INSERTs and never raises that reason",
      (reason) => {
        const body = delegationFn();
        // The reason must be written into a row...
        expect(body).toMatch(
          new RegExp(`'${reason}'[\\s\\S]{0,400}?ON\\s+CONFLICT\\s*\\(invocation_id\\)`, "i"),
        );
        // ...and must never appear as the operand of a RAISE.
        expect(body).not.toMatch(
          new RegExp(`RAISE\\s+EXCEPTION\\s+'byok_delegations:${reason}'`, "i"),
        );
      },
    );

    it("every INSERT in the function is followed by a RETURN, so five refusals persist", () => {
      const inserts = delegationFn().match(/INSERT\s+INTO\s+public\.audit_byok_use/gi) ?? [];
      // five refusal rows + the passing row
      expect(inserts.length).toBe(6);
    });

    it("no RAISE carries a byok_delegations: refusal sentinel any more", () => {
      // Validation errors (22023 / P0002 / anonymised / caller mismatch) still
      // raise by design; only the five accounted refusals must not.
      for (const reason of REFUSAL_REASONS) {
        expect(delegationFn()).not.toMatch(new RegExp(`byok_delegations:${reason}`));
      }
    });
  });

  describe("AC3 — the security envelope is re-issued verbatim", () => {
    it("retains SECURITY DEFINER and the search_path pin including pg_temp", () => {
      expect(delegationFn()).toMatch(/SECURITY\s+DEFINER/i);
      expect(delegationFn()).toMatch(/SET\s+search_path\s*=\s*public,\s*pg_temp/i);
    });
    it("retains the FOR UPDATE row lock (ADR-040 D1)", () => {
      expect(delegationFn()).toMatch(/FOR\s+UPDATE/i);
    });
    it("re-issues REVOKE ALL from PUBLIC, anon, authenticated and GRANTs service_role only", () => {
      expect(executable).toMatch(
        /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.check_and_record_byok_delegation_use\([^)]*\)\s*FROM\s+PUBLIC,\s*anon,\s*authenticated/i,
      );
      expect(executable).toMatch(
        /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.check_and_record_byok_delegation_use\([^)]*\)\s*TO\s+service_role/i,
      );
    });
    it("a return-type change requires DROP + CREATE, not CREATE OR REPLACE", () => {
      expect(executable).toMatch(
        /DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.check_and_record_byok_delegation_use/i,
      );
      expect(executable).not.toMatch(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.check_and_record_byok_delegation_use/i,
      );
    });
  });

  describe("AC4/T2 — the CHECK admits exactly the five reasons plus NULL", () => {
    const constraint = () => {
      const m = executable.match(
        /ADD\s+CONSTRAINT\s+audit_byok_use_attribution_shift_reason_check\s+CHECK\s*\(([\s\S]*?)\)\s*;/i,
      );
      if (!m) throw new Error("fixture: widened CHECK constraint not found");
      return m[1];
    };
    it.each(REFUSAL_REASONS)("admits %s", (reason) => {
      expect(constraint()).toContain(`'${reason}'`);
    });
    it("admits NULL", () => {
      expect(constraint()).toMatch(/IS\s+NULL/i);
    });
    it("uses underscores, not the hyphenated Sentry op slugs", () => {
      expect(constraint()).not.toMatch(/'[a-z]+-cap-exceeded'/);
    });
    it("is NOT declared NOT VALID (it would re-break the Art. 17 cascade)", () => {
      expect(executable).not.toMatch(/NOT\s+VALID/i);
    });
  });

  describe("AC5/T3 — neither cap SUM filters on attribution_shift_reason", () => {
    // Anchored on the INTO target, NOT on a '-- Hourly cap SUM' comment: the
    // comment strip above deletes that anchor, so anchoring there could not run.
    const sumFor = (target: string) => {
      const m = delegationFn().match(
        new RegExp(`SELECT[\\s\\S]{0,200}?INTO\\s+${target}[\\s\\S]*?;`, "i"),
      );
      if (!m) throw new Error(`fixture: SUM INTO ${target} not found`);
      return m[0];
    };
    it.each(["v_hourly_spent", "v_daily_spent"])(
      "%s sums every row in its window, including the refusal rows",
      (target) => {
        expect(sumFor(target)).not.toMatch(/attribution_shift_reason/i);
      },
    );
  });

  describe("Decision 4 — the caller is pinned to the grantee", () => {
    it("raises when p_caller_user_id is not the grantee (founder_id is a billing assertion)", () => {
      expect(delegationFn()).toMatch(
        /p_caller_user_id\s+IS\s+DISTINCT\s+FROM\s+v_row\.grantee_user_id/i,
      );
    });
  });

  describe("Decision 4 — the personal Layer-1 cap excludes delegated spend", () => {
    // Without this, a grantee-attributed cap row enters the GRANTEE's own
    // ADR-041 Layer 1 accumulator and pauses their runtime for exceeding
    // someone else's cap.
    const founderFn = () => {
      const m = executable.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.record_byok_use_and_check_cap\b[\s\S]*?\n\$\$;/i,
      );
      if (!m) throw new Error("fixture: record_byok_use_and_check_cap body not found");
      return m[0];
    };
    it("the founder SUM filters delegation_id IS NULL", () => {
      const m = founderFn().match(/SELECT[\s\S]*?INTO\s+v_total[\s\S]*?;/i);
      expect(m).not.toBeNull();
      expect(m![0]).toMatch(/delegation_id\s+IS\s+NULL/i);
    });
    it("does NOT alter the token_count multiplication (that is #7920, out of scope)", () => {
      expect(founderFn()).toMatch(/SUM\(token_count\s*\*\s*unit_cost_cents\)/i);
    });
  });

  describe("AC6/T4 — the down migration does not narrow the CHECK", () => {
    it("restores the 084 RETURNS void body", () => {
      expect(downExecutable).toMatch(/RETURNS\s+void/i);
    });
    it("contains no NOT VALID", () => {
      expect(downExecutable).not.toMatch(/NOT\s+VALID/i);
    });
    it("leaves the enum widened — it must not re-add a narrowed CHECK", () => {
      for (const reason of ["hourly_cap_exceeded", "daily_cap_exceeded"]) {
        const narrowed = downExecutable.match(
          /ADD\s+CONSTRAINT\s+audit_byok_use_attribution_shift_reason_check[\s\S]*?;/i,
        );
        if (narrowed) expect(narrowed[0]).toContain(reason);
      }
    });
  });
});
