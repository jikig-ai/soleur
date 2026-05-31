import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 087_worm_bypass_privilege_independence.sql (#4696).
// Offline lint — runs in default CI without a live DB.
//
// Context: GDPR Art. 17 account deletion was BROKEN in production (Sentry
// WEB-PLATFORM-13). Every anonymise RPC in the account-delete saga bypassed
// its append-only (WORM) trigger via `SET LOCAL session_replication_role =
// 'replica'`. That GUC is superuser-only (PGC_SUSET); the SECURITY DEFINER
// RPCs are owned by `postgres`, which on managed Supabase is NOT a superuser,
// so the SET raises 42501 before the UPDATE and the saga aborts on its first
// such step (anonymise_action_sends).
//
// Fix (this migration): replace the privileged GUC with a privilege-free,
// custom `app.worm_bypass` SET LOCAL GUC. The trigger functions honor it via
// `current_setting('app.worm_bypass', true) = 'on'`. This is the learning's
// proven-safe no-role-check variant (NOT `current_user = 'service_role'`,
// which is silently always-false under PostgREST routing inside a SECURITY
// DEFINER function — see
// knowledge-base/project/learnings/2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md).
//
// Pins the load-bearing invariants:
//   1. NO anonymise RPC references session_replication_role anywhere.
//   2. Each anonymise RPC sets `app.worm_bypass = 'on'` (SET LOCAL).
//   3. Each rewritten trigger function honors the app.worm_bypass GUC.
//   4. The proven-dead `current_user = 'service_role'` bypass is gone.
//   5. byok_delegation_acceptances.user_id DROP NOT NULL (else the
//      `SET user_id = NULL` anonymise hits 23502 — column is NOT NULL with
//      81 live rows; FK→users ON DELETE RESTRICT requires nulling before
//      auth-delete).
//   6. search_path stays pinned on every SECURITY DEFINER function.
//   7. down migration restores session_replication_role + re-adds NOT NULL.

const MIGRATION_PATH = path.join(
  __dirname,
  "../../supabase/migrations/087_worm_bypass_privilege_independence.sql",
);
const DOWN_PATH = path.join(
  __dirname,
  "../../supabase/migrations/087_worm_bypass_privilege_independence.down.sql",
);

const sql = readFileSync(MIGRATION_PATH, "utf8");
const downSql = readFileSync(DOWN_PATH, "utf8");
// Strip line comments so assertions match executable SQL, not prose.
const executable = sql.replace(/--[^\n]*/g, "");
const downExecutable = downSql.replace(/--[^\n]*/g, "");

// The 7 anonymise RPCs the account-delete saga depends on (6 fatal + the
// non-fatal anonymise_audit_github_token_use), all previously broken by the
// superuser-only session_replication_role GUC.
const ANONYMISE_RPCS = [
  "anonymise_action_sends",
  "anonymise_template_authorizations",
  "anonymise_workspace_member_actions",
  "anonymise_workspace_members",
  "anonymise_byok_delegation_acceptances",
  "anonymise_byok_delegation_withdrawals",
  "anonymise_audit_github_token_use",
];

// The 8 trigger functions that must now honor app.worm_bypass: 6 BEFORE
// reject/shape WORM triggers + 2 AFTER side-effect triggers (the audit
// writer + the byok-revoke cascade) that anonymise_workspace_members must
// suppress so the erasure DELETE creates no new PII/audit rows.
const WORM_REJECT_FNS = [
  "action_sends_no_mutate",
  "template_authorizations_no_mutate",
  "byok_delegation_acceptances_no_mutate",
  "byok_delegation_withdrawals_no_mutate",
  "workspace_member_actions_no_mutate",
  "audit_github_token_use_no_mutate",
];
const AFTER_SUPPRESS_FNS = [
  "workspace_members_audit",
  "byok_delegations_on_member_delete",
];
const TRIGGER_FNS = [...WORM_REJECT_FNS, ...AFTER_SUPPRESS_FNS];

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

describe("migration 087_worm_bypass_privilege_independence", () => {
  describe("no privileged GUC anywhere", () => {
    it("forward migration never references session_replication_role", () => {
      expect(executable).not.toMatch(/session_replication_role/i);
    });

    it("forward migration never uses the proven-dead current_user = 'service_role' bypass", () => {
      expect(executable).not.toMatch(
        /current_user\s*=\s*'service_role'/i,
      );
    });
  });

  describe("anonymise RPCs use the privilege-free app.worm_bypass GUC", () => {
    for (const rpc of ANONYMISE_RPCS) {
      it(`${rpc} sets app.worm_bypass = 'on' (SET LOCAL) and not session_replication_role`, () => {
        const block = fnBlock(executable, rpc);
        expect(block).toMatch(
          /SET\s+LOCAL\s+app\.worm_bypass\s*=\s*'on'/i,
        );
        expect(block).not.toMatch(/session_replication_role/i);
      });

      it(`${rpc} keeps search_path pinned`, () => {
        const block = fnBlock(executable, rpc);
        expect(block).toMatch(
          /SET\s+search_path\s*(?:=|TO)\s*'?public'?\s*,\s*'?pg_temp'?/i,
        );
      });
    }
  });

  describe("trigger functions honor app.worm_bypass", () => {
    for (const fn of TRIGGER_FNS) {
      it(`${fn} bypasses when current_setting('app.worm_bypass', true) = 'on'`, () => {
        const block = fnBlock(executable, fn);
        expect(block).toMatch(
          /current_setting\(\s*'app\.worm_bypass'\s*,\s*true\s*\)\s*=\s*'on'/i,
        );
      });
    }

    it("the BEFORE-reject WORM triggers still RAISE P0001 outside the bypass", () => {
      for (const fn of WORM_REJECT_FNS) {
        const block = fnBlock(executable, fn);
        expect(
          block,
          `${fn} must still reject non-bypass writes`,
        ).toMatch(/RAISE\s+EXCEPTION[\s\S]*?'P0001'/i);
      }
    });
  });

  describe("byok_delegation_acceptances.user_id nullability", () => {
    it("DROPs NOT NULL so the Art-17 anonymise UPDATE can null the FK", () => {
      expect(executable).toMatch(
        /ALTER\s+TABLE\s+public\.byok_delegation_acceptances\s+ALTER\s+COLUMN\s+user_id\s+DROP\s+NOT\s+NULL/i,
      );
    });
  });

  describe("down migration", () => {
    it("restores session_replication_role in the anonymise RPCs", () => {
      expect(downExecutable).toMatch(/session_replication_role/i);
    });

    it("re-adds NOT NULL to byok_delegation_acceptances.user_id", () => {
      expect(downExecutable).toMatch(
        /ALTER\s+TABLE\s+public\.byok_delegation_acceptances\s+ALTER\s+COLUMN\s+user_id\s+SET\s+NOT\s+NULL/i,
      );
    });
  });
});
