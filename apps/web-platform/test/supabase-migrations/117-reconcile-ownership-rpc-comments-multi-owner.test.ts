import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for
// 117_reconcile_ownership_rpc_comments_multi_owner.sql (#5756 / ADR-073).
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
// The migrations whose prior COMMENT values 117.down.sql must restore VERBATIM.
const mig092 = readFileSync(
  path.join(MIG_DIR, "092_transfer_ownership_caller_override.sql"),
  "utf8",
);
const mig094 = readFileSync(
  path.join(MIG_DIR, "094_member_rpc_caller_override_and_byok_cap_update.sql"),
  "utf8",
);

// Executable SQL with line comments stripped, so prose mentioning a keyword or
// "single-owner strict" does not satisfy executable-code assertions.
const upExecutable = up.replace(/--[^\n]*/g, "");

// Extract the CONCATENATED final value of a `COMMENT ON FUNCTION <sig> IS
// 'a ' 'b ' ...;` adjacent-string-literal block, so a re-introduced space at a
// literal boundary (e.g. 'organizations.' / 'owner_user_id') is caught. Joins
// with "" because PostgreSQL concatenates adjacent literals with no separator.
function extractCommentValue(sql: string, fnSigPattern: string): string | null {
  const re = new RegExp(
    `COMMENT\\s+ON\\s+FUNCTION\\s+${fnSigPattern}\\s+IS\\s+([\\s\\S]*?);`,
    "i",
  );
  const m = sql.match(re);
  if (!m) return null;
  const literals = m[1].match(/'([^']*)'/g) ?? [];
  return literals.map((l) => l.slice(1, -1)).join("");
}

const TRANSFER_SIG =
  "public\\.transfer_workspace_ownership\\(uuid,\\s*uuid,\\s*text,\\s*uuid\\)";
const UPDATE_ROLE_SIG =
  "public\\.update_workspace_member_role\\(uuid,\\s*uuid,\\s*text,\\s*uuid\\)";

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
      // The exact pre-117 stale phrasing must be GONE from the new comment.
      // Anchored on the literal stale sentence ("...ownership transfer.
      // Single-owner strict: promotes target to owner...") rather than the
      // brittle space-vs-hyphen "Single-owner strict" token — which the new
      // comment's "NOT a single-owner enforcer" / "single-owner-strict mig-075"
      // prose would dodge on a technicality.
      expect(upExecutable).not.toContain("Single-owner strict: promotes");
      expect(upExecutable).not.toContain("ownership transfer. Single-owner strict");
      expect(upExecutable).toMatch(/ADR-073/i);
    });

    it("update_workspace_member_role comment states member->owner promotion is permitted + at-least-one-owner", () => {
      expect(upExecutable).toMatch(/member->owner promotion is PERMITTED/i);
      expect(upExecutable).toMatch(/at-least-one-owner invariant/i);
      expect(upExecutable).toMatch(/ADR-073/i);
    });
  });

  describe("down: restores the prior COMMENT text VERBATIM (reversibility)", () => {
    it("restores the EXACT 092 transfer comment value (concatenated, no inserted space)", () => {
      // Extract the concatenated final value from migration 092 itself and assert
      // down.sql restores byte-identical text — so a re-introduced space at the
      // 'organizations.' / 'owner_user_id' literal boundary (different line breaks,
      // same value) fails this assertion.
      const mig092Value = extractCommentValue(mig092, TRANSFER_SIG);
      const downValue = extractCommentValue(down, TRANSFER_SIG);
      expect(mig092Value).toBeTruthy();
      expect(downValue).toBe(mig092Value);
      // Belt-and-suspenders on the CONCATENATED value (raw source splits the
      // string across literal lines at the boundary): NO inserted space.
      expect(downValue).toContain("organizations.owner_user_id");
      expect(downValue).not.toContain("organizations. owner_user_id");
    });

    it("restores the EXACT 094 update_workspace_member_role comment value", () => {
      const mig094Value = extractCommentValue(mig094, UPDATE_ROLE_SIG);
      const downValue = extractCommentValue(down, UPDATE_ROLE_SIG);
      expect(mig094Value).toBeTruthy();
      expect(downValue).toBe(mig094Value);
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
    it("returns check_name + bad, casts every branch ::int, and ships NINE check rows (no boolean/integer UNION, #5474)", () => {
      expect(verify).toMatch(/AS check_name/i);
      // `AS check_name` aliases ONLY the first UNION branch, so it is NOT a
      // per-row counter. Count check ROWS by their per-branch check_name literal
      // (`SELECT '<name>'`) — a counter that survives `AS bad`/`AS check_name`
      // alias normalization. After adding check 3d (anonymise grant-lock) the
      // file ships NINE check rows; every branch still casts ::int (the #5474
      // boolean/integer UNION guard).
      expect((verify.match(/SELECT\s+'[a-z0-9_]+'/gi) ?? []).length).toBe(9);
      expect((verify.match(/::int AS bad/gi) ?? []).length).toBe(9);
    });

    it("check 1: no single-owner partial-UNIQUE index AND no UNIQUE/EXCLUDE constraint", () => {
      expect(verify).toMatch(/no_single_owner_unique_index/);
      expect(verify).toMatch(/no_single_owner_constraint/);
      expect(verify).toMatch(/i\.indisunique/i);
      expect(verify).toMatch(/pg_get_expr\(i\.indpred[\s\S]*?ILIKE\s+'%owner%'/i);
      expect(verify).toMatch(/con\.contype\s+IN\s*\(\s*'u',\s*'x'\s*\)/i);
    });

    it("check 2: at-least-one-owner guard pinned to the 4-arg signature AND the count(owner) <= 1 predicate text", () => {
      expect(verify).toMatch(/last_owner_guard_present_4arg/);
      expect(verify).toMatch(
        /pg_get_function_identity_arguments\(p\.oid\)\s*\n?\s*=\s*'p_workspace_id uuid, p_user_id uuid, p_new_role text, p_caller_user_id uuid'/i,
      );
      expect(verify).toMatch(/ILIKE\s+'%cannot demote the last owner%'/i);
      // Predicate hardening: the guard's count(owner) <= 1 predicate text is
      // ALSO pinned, so a future migration that keeps the RAISE message while
      // neutering the predicate flips bad>0 (mig 094:227-230).
      expect(verify).toMatch(/ILIKE\s+'%count\(%'/i);
      expect(verify).toMatch(/ILIKE\s+'%<= 1%'/i);
    });

    it("check 3: service_role-only grant lock on all FOUR new-coverage RPCs (incl. anonymise 3d)", () => {
      for (const sig of [
        "public.update_workspace_member_role(uuid, uuid, text, uuid)",
        "public.create_workspace_invitation(uuid, text, text, text, text, uuid)",
        "public.accept_workspace_invitation(uuid, uuid)",
        "public.anonymise_organization_membership(uuid)",
      ]) {
        expect(verify).toContain(sig);
      }
      expect(verify).toMatch(/has_function_privilege\(\s*\n?\s*'authenticated'/i);
      // check 3d: the anonymise Art-17 path (5th owner-minting vector, mig 081)
      // is grant-locked here; transfer is grant-locked separately in verify/092.
      expect(verify).toMatch(/anonymise_org_membership_not_granted_to_authenticated/);
    });

    it("check 4: the old 3-arg update_workspace_member_role overload stays dropped", () => {
      expect(verify).toMatch(/update_role_3arg_overload_dropped/);
      expect(verify).toMatch(
        /=\s*'p_workspace_id uuid, p_user_id uuid, p_new_role text'/i,
      );
    });

    it("check 5: transfer-comment check uses catalog-pinned obj_description + header notes the known limits", () => {
      expect(verify).toMatch(/transfer_comment_not_single_owner_strict/);
      // Resolves the comment via the catalog-pinned 2-arg obj_description(p.oid,
      // 'pg_proc') — NOT the deprecated single-arg regprocedure form.
      expect(verify).toMatch(/obj_description\(p\.oid,\s*'pg_proc'\)/i);
      expect(verify).not.toMatch(/obj_description\(\s*\n?\s*'public\.transfer/i);
      // Header must disclose the trigger-vector limit + check 2's predicate pinning.
      expect(verify).toMatch(/TRIGGER/);
      expect(verify).toMatch(/predicate/i);
    });
  });

  describe("negative-proof fixture (the sentinel is not a no-op)", () => {
    it("re-introduces a single-owner partial-unique index inside BEGIN;...ROLLBACK; and asserts check 1 bad>0", () => {
      expect(negativeFixture).toMatch(/^\s*BEGIN;/m);
      expect(negativeFixture).toMatch(/CREATE\s+UNIQUE\s+INDEX[\s\S]*?WHERE\s+role\s*=\s*'owner'/i);
      expect(negativeFixture).toMatch(/RAISE\s+EXCEPTION[\s\S]*?FAILED to fire/i);
      expect(negativeFixture).toMatch(/^\s*ROLLBACK;/m);
    });

    it("fixture check-1 query stays in LOCKSTEP with shipped verify/117 check 1 (no silent drift)", () => {
      // String-level parity: the load-bearing check-1 predicate fragments must be
      // present in BOTH the shipped verify file and the fixture's embedded copy.
      // If verify/117 check 1 changes a matcher, the fixture must change too or
      // this fails — they cannot silently diverge.
      const check1Predicates = [
        "i.indisunique",
        "pg_get_expr(i.indpred, i.indrelid) ILIKE '%owner%'",
        "pg_get_indexdef(i.indexrelid) ILIKE '%workspace_id%'",
      ];
      for (const frag of check1Predicates) {
        expect(verify).toContain(frag);
        expect(negativeFixture).toContain(frag);
      }
      // The planted index must be exactly the shape check 1 detects: a UNIQUE
      // index scoped by workspace_id whose predicate mentions owner.
      expect(negativeFixture).toMatch(
        /CREATE\s+UNIQUE\s+INDEX[\s\S]*?workspace_id[\s\S]*?WHERE\s+role\s*=\s*'owner'/i,
      );
    });

    it("fixture check-1b query proves the UNIQUE/EXCLUDE CONSTRAINT branch fires (not just the index branch)", () => {
      // The second BEGIN;...ROLLBACK; block plants a UNIQUE/EXCLUDE constraint
      // mentioning owner and asserts check 1b (no_single_owner_constraint) bad>0.
      expect((negativeFixture.match(/^\s*BEGIN;/gm) ?? []).length).toBeGreaterThanOrEqual(2);
      expect((negativeFixture.match(/^\s*ROLLBACK;/gm) ?? []).length).toBeGreaterThanOrEqual(2);
      expect(negativeFixture).toMatch(/con\.contype\s+IN\s*\(\s*'u',\s*'x'\s*\)/i);
      expect(negativeFixture).toMatch(/pg_get_constraintdef\(con\.oid\)\s+ILIKE\s+'%owner%'/i);
      expect(negativeFixture).toMatch(/check 1b FAILED to fire/i);
    });
  });

  // owner_user_id behavior (ADR-073, documented contract — not DB-exercised here):
  // when the pointed-to owner is demoted while co-owners remain, the pointer is
  // UNCHANGED (transfer is the only product-reachable re-pointer; demote is
  // service_role-only with no live route). The demote->remove no-repoint dead-end
  // (transfer rejects an already-owner target, 092:104-107) means no RPC can
  // re-point a stranded pointer to a surviving co-owner — the Phase-6 follow-up.
  describe("owner_user_id pointer contract (ADR-073)", () => {
    it("is documented as the single primary/billing/DSAR pointer, maintained only by transfer", () => {
      // Sanity-anchor the ADR exists and pins the pointer semantics so this
      // contract has a decision-of-record.
      const adr = readFileSync(
        path.join(
          __dirname,
          "../../../../knowledge-base/engineering/architecture/decisions/ADR-073-workspaces-support-n-co-owners.md",
        ),
        "utf8",
      );
      expect(adr).toMatch(/primary\/billing\/DSAR owner pointer/i);
      expect(adr).toMatch(/no-repoint dead-end/i);
    });
  });
});
