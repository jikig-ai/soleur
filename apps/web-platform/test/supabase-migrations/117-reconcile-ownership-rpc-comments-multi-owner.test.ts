import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for
// 117_reconcile_ownership_rpc_comments_multi_owner.sql (#5756 / ADR-072).
//
// Migration 117 is a COMMENT-ON-FUNCTION-ONLY metadata reconcile: it makes NO
// RPC behavior change. So the canonical PR-time gates are static SQL-shape
// assertions (mirrors 092/094 tests; per learning
// 2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind.md vitest mocks .rpc
// and CANNOT catch a GRANT/COMMENT mismatch, so this source-regex test is the
// canonical plan-time gate). The behavioral DB invariants (two owners coexist,
// member->owner promotion no-raise, demote-last raises, verify/117 bad=0) are
// locked at apply time by the release-workflow migrate+verify path (verify/117)
// and proved-negative by test/fixtures/verify-117-single-owner-negative.sql.

const MIG_DIR = path.join(__dirname, "../../supabase/migrations");
const VERIFY_DIR = path.join(__dirname, "../../supabase/verify");
const FIXTURE_DIR = path.join(__dirname, "../fixtures");

const up = readFileSync(
  path.join(MIG_DIR, "117_reconcile_ownership_rpc_comments_multi_owner.sql"),
  "utf8",
);
const down = readFileSync(
  path.join(MIG_DIR, "117_reconcile_ownership_rpc_comments_multi_owner.down.sql"),
  "utf8",
);
const verify = readFileSync(
  path.join(VERIFY_DIR, "117_reconcile_ownership_rpc_comments_multi_owner.sql"),
  "utf8",
);
const negativeFixture = readFileSync(
  path.join(FIXTURE_DIR, "verify-117-single-owner-negative.sql"),
  "utf8",
);

// Executable SQL with line comments stripped, so prose mentioning a keyword or
// "single-owner strict" does not satisfy executable-code assertions.
const upExecutable = up.replace(/--[^\n]*/g, "");

describe("migration 117_reconcile_ownership_rpc_comments_multi_owner", () => {
  describe("up: COMMENT ON FUNCTION ONLY (no behavior change)", () => {
    it("contains NO CREATE/ALTER/GRANT/REVOKE/DROP/UPDATE statement (the AC grep)", () => {
      const ddl = upExecutable
        .split("\n")
        .filter((l) => /^\s*(CREATE|ALTER|GRANT|REVOKE|DROP|UPDATE)\b/.test(l));
      expect(ddl).toEqual([]);
    });

    it("comments BOTH 4-arg ownership RPCs and nothing else", () => {
      const comments = upExecutable.match(/COMMENT\s+ON\s+FUNCTION\s+public\.\w+/gi) ?? [];
      expect(comments).toHaveLength(2);
      expect(upExecutable).toMatch(
        /COMMENT\s+ON\s+FUNCTION\s+public\.transfer_workspace_ownership\(uuid,\s*uuid,\s*text,\s*uuid\)\s+IS/i,
      );
      expect(upExecutable).toMatch(
        /COMMENT\s+ON\s+FUNCTION\s+public\.update_workspace_member_role\(uuid,\s*uuid,\s*text,\s*uuid\)\s+IS/i,
      );
    });

    it("transfer comment is reconciled to hand-off-and-step-down + primary-pointer, NOT single-owner-strict", () => {
      expect(upExecutable).toMatch(/hand-off-and-step-down/i);
      expect(upExecutable).toMatch(/primary\/billing\/DSAR pointer/i);
      expect(upExecutable).toMatch(/promote-before-demote/i);
      // The stale assertion must be gone from the new comment text.
      expect(upExecutable).not.toMatch(/Single-owner strict/i);
      expect(upExecutable).toMatch(/ADR-072/i);
    });

    it("update_workspace_member_role comment states member->owner promotion is permitted + at-least-one-owner", () => {
      expect(upExecutable).toMatch(/member->owner promotion is PERMITTED/i);
      expect(upExecutable).toMatch(/at-least-one-owner invariant/i);
      expect(upExecutable).toMatch(/ADR-072/i);
    });
  });

  describe("down: restores the prior COMMENT text VERBATIM (reversibility)", () => {
    it("restores the exact 092 transfer comment (concatenated value, no inserted space)", () => {
      // The concatenated final value of the 092:193-198 adjacent string literals.
      expect(down).toContain("Atomic workspace ownership transfer. Single-owner strict: promotes ");
      expect(down).toContain("target to owner, demotes caller to member, updates organizations.");
      expect(down).toContain("owner_user_id, writes attestation + revocation rows.");
    });

    it("restores the exact 094 update_workspace_member_role comment", () => {
      expect(down).toContain("Workspace-member role-change RPC (mig 094 caller-override fix). Caller ");
      expect(down).toContain("self-mutate + last-owner-demote guards, audit GUC, revocation row, F6 ");
    });

    it("targets both 4-arg signatures", () => {
      expect(down).toMatch(
        /COMMENT\s+ON\s+FUNCTION\s+public\.transfer_workspace_ownership\(uuid,\s*uuid,\s*text,\s*uuid\)/i,
      );
      expect(down).toMatch(
        /COMMENT\s+ON\s+FUNCTION\s+public\.update_workspace_member_role\(uuid,\s*uuid,\s*text,\s*uuid\)/i,
      );
    });
  });

  describe("verify/117 sentinel locks the durable multi-owner invariant", () => {
    it("returns check_name + bad and casts every branch ::int (no boolean/integer UNION, #5474)", () => {
      expect(verify).toMatch(/AS check_name/i);
      // Each of the 8 emitted rows ends in an ::int-cast bad column.
      expect((verify.match(/::int AS bad/gi) ?? []).length).toBe(8);
    });

    it("check 1: no single-owner partial-UNIQUE index AND no UNIQUE/EXCLUDE constraint", () => {
      expect(verify).toMatch(/no_single_owner_unique_index/);
      expect(verify).toMatch(/no_single_owner_constraint/);
      expect(verify).toMatch(/i\.indisunique/i);
      expect(verify).toMatch(/pg_get_expr\(i\.indpred[\s\S]*?ILIKE\s+'%owner%'/i);
      expect(verify).toMatch(/con\.contype\s+IN\s*\(\s*'u',\s*'x'\s*\)/i);
    });

    it("check 2: at-least-one-owner guard pinned to the 4-arg identity signature", () => {
      expect(verify).toMatch(/last_owner_guard_present_4arg/);
      expect(verify).toMatch(
        /pg_get_function_identity_arguments\(p\.oid\)\s*\n?\s*=\s*'p_workspace_id uuid, p_user_id uuid, p_new_role text, p_caller_user_id uuid'/i,
      );
      expect(verify).toMatch(/ILIKE\s+'%cannot demote the last owner%'/i);
    });

    it("check 3: service_role-only grant lock on all THREE new-coverage RPCs", () => {
      for (const sig of [
        "public.update_workspace_member_role(uuid, uuid, text, uuid)",
        "public.create_workspace_invitation(uuid, text, text, text, text, uuid)",
        "public.accept_workspace_invitation(uuid, uuid)",
      ]) {
        expect(verify).toContain(sig);
      }
      expect(verify).toMatch(/has_function_privilege\(\s*\n?\s*'authenticated'/i);
    });

    it("check 4: the old 3-arg update_workspace_member_role overload stays dropped", () => {
      expect(verify).toMatch(/update_role_3arg_overload_dropped/);
      expect(verify).toMatch(
        /=\s*'p_workspace_id uuid, p_user_id uuid, p_new_role text'/i,
      );
    });

    it("check 5: secondary transfer-comment check + header notes the two known limits", () => {
      expect(verify).toMatch(/transfer_comment_not_single_owner_strict/);
      // Header must disclose the trigger-vector + message-proxy limits.
      expect(verify).toMatch(/TRIGGER/);
      expect(verify).toMatch(/PROXY/i);
    });
  });

  describe("negative-proof fixture (the sentinel is not a no-op)", () => {
    it("re-introduces a single-owner partial-unique index inside BEGIN;...ROLLBACK; and asserts check 1 bad>0", () => {
      expect(negativeFixture).toMatch(/^\s*BEGIN;/m);
      expect(negativeFixture).toMatch(/CREATE\s+UNIQUE\s+INDEX[\s\S]*?WHERE\s+role\s*=\s*'owner'/i);
      expect(negativeFixture).toMatch(/RAISE\s+EXCEPTION[\s\S]*?FAILED to fire/i);
      expect(negativeFixture).toMatch(/^\s*ROLLBACK;/m);
    });
  });

  // owner_user_id behavior (ADR-072, documented contract — not DB-exercised here):
  // when the pointed-to owner is demoted while co-owners remain, the pointer is
  // UNCHANGED (transfer is the only product-reachable re-pointer; demote is
  // service_role-only with no live route). The demote->remove no-repoint dead-end
  // (transfer rejects an already-owner target, 092:104-107) means no RPC can
  // re-point a stranded pointer to a surviving co-owner — the Phase-6 follow-up.
  describe("owner_user_id pointer contract (ADR-072)", () => {
    it("is documented as the single primary/billing/DSAR pointer, maintained only by transfer", () => {
      // Sanity-anchor the ADR exists and pins the pointer semantics so this
      // contract has a decision-of-record.
      const adr = readFileSync(
        path.join(
          __dirname,
          "../../../../knowledge-base/engineering/architecture/decisions/ADR-072-workspaces-support-n-co-owners.md",
        ),
        "utf8",
      );
      expect(adr).toMatch(/primary\/billing\/DSAR owner pointer/i);
      expect(adr).toMatch(/no-repoint dead-end/i);
    });
  });
});
