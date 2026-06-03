import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 088_worm_bypass_non_erasure_rpcs.sql (#4702).
// Offline lint — runs in default CI without a live DB.
//
// Context: migration 087 (#4696) converted the GDPR Art. 17 account-delete
// saga off the superuser-only `SET LOCAL session_replication_role = 'replica'`
// WORM bypass (which raises 42501 on managed Supabase, where the postgres role
// owning the SECURITY DEFINER RPCs is NOT a superuser) onto the privilege-free
// custom `app.worm_bypass` GUC. 087 deliberately deferred the two NON-erasure
// RPCs that use the identical broken bypass to this follow-up (087.sql L57-59):
//
//   * purge_workspace_member_actions()        — pg_cron 7-year retention DELETE
//                                                (defined mig 063). Silently
//                                                no-ops on prod (42501) → audit
//                                                PII over-retains, Art. 5(1)(e).
//   * revoke_template_authorization(text,text) — founder/auto revoke UPDATE
//                                                (defined mig 053). 42501 on
//                                                every call that reaches the
//                                                bypass → founders cannot
//                                                withdraw (Art. 7(3)).
//
// The trigger functions (workspace_member_actions_no_mutate,
// template_authorizations_no_mutate) ALREADY honor app.worm_bypass after 087,
// so 088 swaps the bypass GUC in only the two RPC bodies — no trigger edits.
//
// Pins the load-bearing invariants:
//   1. The forward migration references session_replication_role NOWHERE.
//   2. Each RPC sets `app.worm_bypass = 'on'` (SET LOCAL) and re-arms 'off'.
//   3. search_path stays pinned on each SECURITY DEFINER RPC.
//   4. The two RPCs preserve their content gates (revoke's reason-enum +
//      founder-attribution gates; purge's 7-year DELETE + RAISE LOG) — so a
//      careless re-CREATE that drops authz/retention logic fails here.
//   5. list ↔ migration reconciliation: no function escapes coverage (a future
//      edit reintroducing session_replication_role on a 3rd function can't stay
//      green).
//   6. down migration restores session_replication_role (forward-only reality).

const MIGRATION_PATH = path.join(
  __dirname,
  "../../supabase/migrations/088_worm_bypass_non_erasure_rpcs.sql",
);
const DOWN_PATH = path.join(
  __dirname,
  "../../supabase/migrations/088_worm_bypass_non_erasure_rpcs.down.sql",
);

const sql = readFileSync(MIGRATION_PATH, "utf8");
const downSql = readFileSync(DOWN_PATH, "utf8");
// Strip line comments so assertions match executable SQL, not prose.
const executable = sql.replace(/--[^\n]*/g, "");
const downExecutable = downSql.replace(/--[^\n]*/g, "");

// The two non-erasure RPCs deferred from 087 to #4702. Both use the `$$`
// dollar-quote tag (verified in mig 063/053); revoke is two-arg, purge is
// zero-arg — fnBlock's `public\.${name}\s*\(` prefix is signature-agnostic.
const NON_ERASURE_RPCS = [
  "purge_workspace_member_actions",
  "revoke_template_authorization",
];

function fnBlock(src: string, name: string): string {
  // CREATE OR REPLACE FUNCTION public.<name>(...) ... $function$ ... $function$;
  // or $$ ... $$; — match either dollar-quote tag, non-greedy to the first
  // closing tag that terminates the body.
  const re = new RegExp(
    `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+public\\.${name}\\s*\\([\\s\\S]*?\\$([A-Za-z_]*)\\$[\\s\\S]*?\\$\\1\\$\\s*;`,
    "i",
  );
  const m = src.match(re);
  expect(m, `expected function block for public.${name}`).not.toBeNull();
  return m![0];
}

describe("migration 088_worm_bypass_non_erasure_rpcs", () => {
  describe("no privileged GUC anywhere", () => {
    it("forward migration never references session_replication_role", () => {
      expect(executable).not.toMatch(/session_replication_role/i);
    });
  });

  describe("non-erasure RPCs use the privilege-free app.worm_bypass GUC", () => {
    for (const rpc of NON_ERASURE_RPCS) {
      it(`${rpc} sets app.worm_bypass = 'on' (SET LOCAL) and not session_replication_role`, () => {
        const block = fnBlock(executable, rpc);
        expect(block).toMatch(/SET\s+LOCAL\s+app\.worm_bypass\s*=\s*'on'/i);
        expect(block).not.toMatch(/session_replication_role/i);
      });

      it(`${rpc} re-arms WORM with SET LOCAL app.worm_bypass = 'off' after the write`, () => {
        // The re-arm is the single most security-load-bearing line: if it were
        // dropped, the GUC would leak to the rest of the transaction and any
        // subsequent statement would silently bypass WORM. SET LOCAL is already
        // txn-scoped, but each RPC re-arms immediately after its one write
        // (mirrors the prior RESET session_replication_role, and 087's pattern).
        const block = fnBlock(executable, rpc);
        expect(block).toMatch(/SET\s+LOCAL\s+app\.worm_bypass\s*=\s*'off'/i);
      });

      it(`${rpc} keeps search_path pinned`, () => {
        const block = fnBlock(executable, rpc);
        expect(block).toMatch(
          /SET\s+search_path\s*(?:=|TO)\s*'?public'?\s*,\s*'?pg_temp'?/i,
        );
      });

      it(`${rpc} arms 'on' BEFORE the single write and re-arms 'off' AFTER it`, () => {
        // The security property is the ORDERING, not mere presence: arm the
        // bypass, do exactly one write, re-arm. A body that re-armed 'off'
        // before the write would leave the write WORM-rejected; one that armed
        // 'on' after the write would never bypass. Pin arm < write < re-arm.
        const block = fnBlock(executable, rpc);
        const onIdx = block.search(/SET\s+LOCAL\s+app\.worm_bypass\s*=\s*'on'/i);
        const dmlIdx = block.search(/\b(DELETE\s+FROM|UPDATE)\b/i);
        const offIdx = block.search(
          /SET\s+LOCAL\s+app\.worm_bypass\s*=\s*'off'/i,
        );
        expect(onIdx, "arm 'on' must be present").toBeGreaterThanOrEqual(0);
        expect(dmlIdx, "single write must follow arm 'on'").toBeGreaterThan(
          onIdx,
        );
        expect(offIdx, "re-arm 'off' must follow the write").toBeGreaterThan(
          dmlIdx,
        );
      });
    }
  });

  describe("content gates preserved through the re-CREATE", () => {
    it("purge_workspace_member_actions keeps the 7-year DELETE and the audit_retention_purge RAISE LOG", () => {
      const block = fnBlock(executable, "purge_workspace_member_actions");
      expect(block).toMatch(/interval\s+'7 years'/i);
      expect(block).toMatch(/RAISE\s+LOG\s+'audit_retention_purge/i);
    });

    it("revoke_template_authorization keeps the 8-value reason-enum gate and the founder-attribution gate", () => {
      const block = fnBlock(executable, "revoke_template_authorization");
      // 8-value reason enum (sentinel: the last, least-likely-to-be-typed value)
      expect(block).toMatch(/'quarantine_retroactive'/i);
      expect(block).toMatch(/p_reason\s+NOT\s+IN\s*\(/i);
      // founder-attribution gate
      expect(block).toMatch(
        /auth\.uid\(\)\s+IS\s+NOT\s+NULL\s+AND\s+p_reason\s*<>\s*'founder_revoked'/i,
      );
      // authenticated-session guard
      expect(block).toMatch(/v_founder_id\s+uuid\s*:=\s*auth\.uid\(\)/i);
    });
  });

  describe("list ↔ migration reconciliation (no function escapes coverage)", () => {
    it("every CREATE OR REPLACE FUNCTION in the migration is in NON_ERASURE_RPCS", () => {
      // Regression guard mirroring 087's: if a future edit adds a function
      // (e.g. reintroducing session_replication_role on a 3rd RPC), the
      // hardcoded list would silently not cover it and the suite would stay
      // green. Reconcile the declared set against the migration body.
      const declared = new Set(NON_ERASURE_RPCS);
      const created = new Set(
        [
          ...executable.matchAll(
            /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.([a-z0-9_]+)\s*\(/gi,
          ),
        ].map((m) => m[1].toLowerCase()),
      );
      const uncovered = [...created].filter((n) => !declared.has(n));
      expect(
        uncovered,
        `migration creates functions not in the test's coverage list: ${uncovered.join(", ")}`,
      ).toEqual([]);
      const missing = [...declared].filter((n) => !created.has(n));
      expect(
        missing,
        `listed functions absent from the migration: ${missing.join(", ")}`,
      ).toEqual([]);
    });
  });

  describe("down migration", () => {
    it("restores session_replication_role in both RPCs (forward-only reality)", () => {
      expect(downExecutable).toMatch(/session_replication_role/i);
    });

    it("removes app.worm_bypass from the restored bodies (rollback symmetry)", () => {
      // Symmetric with the forward migration's `not.toMatch(session_replication_role)`:
      // a botched down that restored session_replication_role but left a stray
      // app.worm_bypass line (double-bypass / wrong-GUC re-arm) would otherwise
      // stay green.
      expect(downExecutable).not.toMatch(/app\.worm_bypass/i);
    });

    it("re-CREATEs both RPCs", () => {
      for (const rpc of NON_ERASURE_RPCS) {
        expect(
          downExecutable,
          `down migration must re-CREATE public.${rpc}`,
        ).toMatch(
          new RegExp(
            `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+public\\.${rpc}\\s*\\(`,
            "i",
          ),
        );
      }
    });
  });
});
