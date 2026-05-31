import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 089_template_auto_revoke_carveout.sql (#4709).
// Offline lint — runs in default CI without a live DB. Sibling of the 088
// shape test; the behavioral RED→GREEN lives in the (opt-in) integration
// suite test/server/template-authorizations-worm.test.ts.
//
// Context: the send-gate's auto-revoke side effect
// (server/templates/is-template-authorized.ts) calls
// revoke_template_authorization with the AUTHENTICATED request client and
// reason 'expired'/'quota_exhausted'. The 053 founder-attribution gate
// (preserved verbatim through 087/088) raised 42501 for ANY authenticated
// non-'founder_revoked' reason, so auto-revoke could never persist — dead
// authorizations kept rendering as "active" in the scope-grants UI.
//
// 089 is migration 088's body reproduced VERBATIM except the single founder-
// attribution gate block, which becomes a narrow carve-out: an authed founder
// may revoke their OWN row with 'expired'/'quota_exhausted' ONLY when the RPC
// RE-DERIVES the dead state server-side (anti-spoof). All OTHER non-
// 'founder_revoked' reasons still raise 42501. Down reverts to 088 verbatim.
//
// Pins the load-bearing invariants:
//   1. The forward migration uses app.worm_bypass (NOT session_replication_role).
//   2. The RPC arms `app.worm_bypass='on'` BEFORE the single UPDATE and re-arms
//      'off' AFTER — ordering, not mere presence.
//   3. search_path stays pinned on the SECURITY DEFINER RPC; RETURNS integer.
//   4. The 088 content gates survive the re-CREATE (authenticated-session guard,
//      8-value reason-enum gate).
//   5. The carve-out admits ONLY 'expired'/'quota_exhausted', re-derives both
//      from server state (expires_at / max_sends), and raises 42501 on a
//      reason-vs-state mismatch (anti-spoof).
//   6. Down migration restores the 088 founder-attribution gate verbatim and
//      drops the carve-out (rollback symmetry).

const MIGRATION_PATH = path.join(
  __dirname,
  "../../supabase/migrations/089_template_auto_revoke_carveout.sql",
);
const DOWN_PATH = path.join(
  __dirname,
  "../../supabase/migrations/089_template_auto_revoke_carveout.down.sql",
);

const sql = readFileSync(MIGRATION_PATH, "utf8");
const downSql = readFileSync(DOWN_PATH, "utf8");
// Strip line comments so assertions match executable SQL, not prose.
const executable = sql.replace(/--[^\n]*/g, "");
const downExecutable = downSql.replace(/--[^\n]*/g, "");

const RPC = "revoke_template_authorization";

function fnBlock(src: string, name: string): string {
  const re = new RegExp(
    `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+public\\.${name}\\s*\\([\\s\\S]*?\\$([A-Za-z_]*)\\$[\\s\\S]*?\\$\\1\\$\\s*;`,
    "i",
  );
  const m = src.match(re);
  expect(m, `expected function block for public.${name}`).not.toBeNull();
  return m![0];
}

describe("migration 089_template_auto_revoke_carveout", () => {
  describe("WORM bypass GUC parity with 088", () => {
    it("forward migration never references session_replication_role", () => {
      expect(executable).not.toMatch(/session_replication_role/i);
    });

    it(`${RPC} arms 'on' BEFORE the single write and re-arms 'off' AFTER it`, () => {
      const block = fnBlock(executable, RPC);
      const onIdx = block.search(/SET\s+LOCAL\s+app\.worm_bypass\s*=\s*'on'/i);
      const dmlIdx = block.search(/\bUPDATE\b/i);
      const offIdx = block.search(/SET\s+LOCAL\s+app\.worm_bypass\s*=\s*'off'/i);
      expect(onIdx, "arm 'on' must be present").toBeGreaterThanOrEqual(0);
      expect(dmlIdx, "single write must follow arm 'on'").toBeGreaterThan(onIdx);
      expect(offIdx, "re-arm 'off' must follow the write").toBeGreaterThan(
        dmlIdx,
      );
    });

    it(`${RPC} keeps search_path pinned and RETURNS integer`, () => {
      const block = fnBlock(executable, RPC);
      expect(block).toMatch(
        /SET\s+search_path\s*(?:=|TO)\s*'?public'?\s*,\s*'?pg_temp'?/i,
      );
      expect(block).toMatch(/RETURNS\s+integer/i);
    });
  });

  describe("088 content gates preserved through the re-CREATE", () => {
    it(`${RPC} keeps the authenticated-session guard and the 8-value reason-enum gate`, () => {
      const block = fnBlock(executable, RPC);
      // authenticated-session guard (auth.uid() must be non-NULL)
      expect(block).toMatch(/v_founder_id\s+uuid\s*:=\s*auth\.uid\(\)/i);
      expect(block).toMatch(/authenticated session required/i);
      // 8-value reason enum (sentinel: the last, least-likely-to-be-typed value)
      expect(block).toMatch(/p_reason\s+NOT\s+IN\s*\(/i);
      expect(block).toMatch(/'quarantine_retroactive'/i);
    });
  });

  describe("auto-revoke carve-out (#4709)", () => {
    it("admits ONLY 'expired'/'quota_exhausted' for authed non-founder_revoked callers", () => {
      const block = fnBlock(executable, RPC);
      expect(block).toMatch(
        /p_reason\s+IN\s*\(\s*'expired'\s*,\s*'quota_exhausted'\s*\)/i,
      );
      // The non-carve-out branch still raises the founder-attribution 42501.
      expect(block).toMatch(
        /authenticated callers must use reason=founder_revoked/i,
      );
    });

    it("re-derives the dead state server-side (expires_at and max_sends), never trusting p_reason", () => {
      const block = fnBlock(executable, RPC);
      // expired re-derivation against the row's own expires_at
      expect(block).toMatch(/expires_at\s*<=\s*now\(\)/i);
      // quota re-derivation: count(action_sends) >= max_sends (>=, boundary
      // parity with is-template-authorized.ts)
      expect(block).toMatch(/from\s+public\.action_sends/i);
      expect(block).toMatch(/>=\s*v_row\.max_sends/i);
    });

    it("raises 42501 on a reason-vs-state mismatch (anti-spoof)", () => {
      const block = fnBlock(executable, RPC);
      expect(block).toMatch(/anti-spoof/i);
      // Every RAISE in the authed gate must carry ERRCODE 42501.
      expect(block).toMatch(/ERRCODE\s*=\s*'42501'/i);
    });
  });

  describe("down migration (revert to 088 verbatim)", () => {
    it(`re-CREATEs public.${RPC}`, () => {
      expect(downExecutable).toMatch(
        new RegExp(
          `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+public\\.${RPC}\\s*\\(`,
          "i",
        ),
      );
    });

    it("restores the plain 088 founder-attribution gate", () => {
      const block = fnBlock(downExecutable, RPC);
      expect(block).toMatch(
        /auth\.uid\(\)\s+IS\s+NOT\s+NULL\s+AND\s+p_reason\s*<>\s*'founder_revoked'/i,
      );
    });

    it("drops the carve-out (no anti-spoof re-derivation in the restored body)", () => {
      expect(downExecutable).not.toMatch(/anti-spoof/i);
      expect(downExecutable).not.toMatch(/expires_at\s*<=\s*now\(\)/i);
    });

    it("keeps app.worm_bypass (088 reverts to the privilege-free GUC, not session_replication_role)", () => {
      expect(downExecutable).toMatch(/app\.worm_bypass/i);
      expect(downExecutable).not.toMatch(/session_replication_role/i);
    });
  });
});
