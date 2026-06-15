import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 104 (agent-native outbound email, #5325 pilot).
//
// 104_outbound_email.sql adds ONLY the email_suppression table + its three
// SECURITY DEFINER RPCs. The send-audit + body-hash approval binding reuses
// public.action_sends (migration 051) unchanged — so this migration MUST NOT
// create an outbound_sends table or widen any enum.
//
// File-parse test, not a live-DB test — pins the SQL contract. Live behaviour
// (RLS owner-isolation, upsert idempotency, auth.uid() owner-pin) is verified
// against dev-DB at apply time and recorded in
// knowledge-base/project/specs/feat-agent-native-outbound-email/migration-checklist.md.
// The generalised SECURITY DEFINER grant + search_path lint is in
// test/migration-rpc-grants.test.ts; this file pins 104-specific invariants.
// Mirrors 103-github-events-retention-7day.test.ts.
//
// Plan: knowledge-base/project/plans/2026-06-15-feat-agent-native-outbound-email-pilot-plan.md

const MIG_DIR = path.join(__dirname, "../../supabase/migrations");
const stripComments = (sql: string) => sql.replace(/--[^\n]*/g, "");

const raw = readFileSync(path.join(MIG_DIR, "104_outbound_email.sql"), "utf8");
const executable = stripComments(raw);
const down = stripComments(
  readFileSync(path.join(MIG_DIR, "104_outbound_email.down.sql"), "utf8"),
);

describe("migration 104_outbound_email — email_suppression table", () => {
  it("creates public.email_suppression", () => {
    expect(executable).toMatch(
      /create\s+table\s+if\s+not\s+exists\s+public\.email_suppression/i,
    );
  });

  it("owner_id FKs users(id) ON DELETE RESTRICT (no accidental erasure)", () => {
    expect(executable).toMatch(
      /owner_id\s+uuid\s+null\s+references\s+public\.users\(id\)\s+on\s+delete\s+restrict/i,
    );
  });

  it("reason is constrained to the four suppression causes", () => {
    expect(executable).toMatch(
      /reason\s+text\s+not\s+null\s+check\s*\(\s*reason\s+in\s*\(\s*'opt_out',\s*'decline',\s*'bounce',\s*'manual'\s*\)\s*\)/i,
    );
  });

  it("enforces a UNIQUE (owner_id, recipient_hash) upsert target", () => {
    expect(executable).toMatch(
      /create\s+unique\s+index\s+if\s+not\s+exists\s+email_suppression_owner_recipient_unique\s+on\s+public\.email_suppression\s*\(\s*owner_id,\s*recipient_hash\s*\)/i,
    );
  });

  it("enables RLS with an owner-only SELECT policy (no FOR ALL USING)", () => {
    expect(executable).toMatch(
      /alter\s+table\s+public\.email_suppression\s+enable\s+row\s+level\s+security/i,
    );
    expect(executable).toMatch(
      /create\s+policy\s+email_suppression_owner_select\s+on\s+public\.email_suppression\s+for\s+select\s+to\s+authenticated\s+using\s*\(\s*owner_id\s*=\s*auth\.uid\(\)\s*\)/i,
    );
    expect(executable).not.toMatch(/for\s+all\s+using/i);
  });

  it("REVOKEs direct INSERT/UPDATE/DELETE from authenticated (RPC-only writes)", () => {
    expect(executable).toMatch(
      /revoke\s+insert,\s*update,\s*delete\s+on\s+public\.email_suppression\s+from\s+authenticated/i,
    );
    // No INSERT/UPDATE/DELETE policy exists — writes go through the SD RPC only.
    expect(executable).not.toMatch(/for\s+insert\s+to\s+authenticated/i);
  });
});

describe("migration 104_outbound_email — suppress_recipient RPC (monotonic upsert)", () => {
  it("is SECURITY DEFINER with the pinned search_path", () => {
    expect(executable).toMatch(
      /create\s+or\s+replace\s+function\s+public\.suppress_recipient[\s\S]*?security\s+definer[\s\S]*?set\s+search_path\s*=\s*public,\s*pg_temp/i,
    );
  });

  it("pins the caller to auth.uid() and rejects NULL (28000)", () => {
    expect(executable).toMatch(
      /v_owner_id\s+uuid\s*:=\s*auth\.uid\(\)/i,
    );
    expect(executable).toMatch(/errcode\s*=\s*'28000'/i);
  });

  it("upserts ON CONFLICT DO NOTHING (idempotent, monotonic add)", () => {
    expect(executable).toMatch(
      /insert\s+into\s+public\.email_suppression[\s\S]*?on\s+conflict\s*\(\s*owner_id,\s*recipient_hash\s*\)\s+do\s+nothing/i,
    );
  });
});

describe("migration 104_outbound_email — is_recipient_suppressed RPC (send-time check)", () => {
  it("is SECURITY DEFINER, auth.uid()-pinned, owner-scoped EXISTS", () => {
    expect(executable).toMatch(
      /create\s+or\s+replace\s+function\s+public\.is_recipient_suppressed[\s\S]*?security\s+definer[\s\S]*?set\s+search_path\s*=\s*public,\s*pg_temp/i,
    );
    expect(executable).toMatch(
      /return\s+exists\s*\([\s\S]*?from\s+public\.email_suppression\s+where\s+owner_id\s*=\s*v_owner_id\s+and\s+recipient_hash\s*=\s*p_recipient_hash/i,
    );
  });
});

describe("migration 104_outbound_email — Art-17 erasure", () => {
  it("provides anonymise_email_suppression granted to service_role", () => {
    expect(executable).toMatch(
      /create\s+or\s+replace\s+function\s+public\.anonymise_email_suppression\(p_user_id\s+uuid\)/i,
    );
    expect(executable).toMatch(
      /grant\s+execute\s+on\s+function\s+public\.anonymise_email_suppression\(uuid\)\s+to\s+service_role/i,
    );
  });

  it("tombstones rather than deletes (owner_id NULL + recipient_hash scrub)", () => {
    expect(executable).toMatch(
      /update\s+public\.email_suppression\s+set\s+owner_id\s*=\s*null,\s*recipient_hash\s*=\s*'__anonymised__:'/i,
    );
  });
});

describe("migration 104_outbound_email — outbound_sends WORM audit (ADR-060)", () => {
  it("creates public.outbound_sends NOT FK'd to messages", () => {
    expect(executable).toMatch(
      /create\s+table\s+if\s+not\s+exists\s+public\.outbound_sends/i,
    );
    // The whole point of ADR-060: no messages FK (agent path has no message id).
    const tableBlock = executable.slice(
      executable.search(/create\s+table\s+if\s+not\s+exists\s+public\.outbound_sends/i),
      executable.search(/create\s+table\s+if\s+not\s+exists\s+public\.outbound_sends/i) + 1200,
    );
    expect(tableBlock).not.toMatch(/references\s+public\.messages/i);
  });

  it("binds body hash both ways (approved + per-send) and recipient hash", () => {
    expect(executable).toMatch(/approved_body_sha256\s+text\s+not\s+null/i);
    expect(executable).toMatch(/per_send_body_sha256\s+text\s+not\s+null/i);
    expect(executable).toMatch(/recipient_hash\s+text\s+not\s+null/i);
  });

  it("action_class carries the enum-absence CHECK (no locked domain)", () => {
    expect(executable).toMatch(
      /action_class\s+text\s+not\s+null\s+default\s+'marketing\.outreach'[\s\S]*?check\s*\(\s*action_class\s*!~\s*'\^\(payment\|legal\|auth\)\\\.'\s*\)/i,
    );
  });

  it("is WORM — both pure-reject triggers attached + owner-select RLS, writes revoked", () => {
    expect(executable).toMatch(
      /create\s+or\s+replace\s+function\s+public\.outbound_sends_no_mutate\(\)\s+returns\s+trigger/i,
    );
    expect(executable).toMatch(/create\s+trigger\s+outbound_sends_no_update[\s\S]*?before\s+update\s+on\s+public\.outbound_sends/i);
    expect(executable).toMatch(/create\s+trigger\s+outbound_sends_no_delete[\s\S]*?before\s+delete\s+on\s+public\.outbound_sends/i);
    expect(executable).toMatch(/alter\s+table\s+public\.outbound_sends\s+enable\s+row\s+level\s+security/i);
    expect(executable).toMatch(/revoke\s+insert,\s*update,\s*delete\s+on\s+public\.outbound_sends\s+from\s+authenticated/i);
  });

  it("record_outbound_send is the SECURITY DEFINER write path, auth.uid()-pinned, rejects hash mismatch", () => {
    expect(executable).toMatch(
      /create\s+or\s+replace\s+function\s+public\.record_outbound_send[\s\S]*?security\s+definer[\s\S]*?set\s+search_path\s*=\s*public,\s*pg_temp/i,
    );
    expect(executable).toMatch(/p_approved_body_sha256\s+is\s+distinct\s+from\s+p_per_send_body_sha256/i);
  });

  it("provides anonymise_outbound_sends (Art-17) granted to service_role", () => {
    expect(executable).toMatch(
      /grant\s+execute\s+on\s+function\s+public\.anonymise_outbound_sends\(uuid\)\s+to\s+service_role/i,
    );
  });

  it("uses the privilege-free app.worm_bypass GUC, NOT superuser-only session_replication_role (mig 087 / #4696)", () => {
    // session_replication_role is PGC_SUSET — postgres is not superuser on
    // managed Supabase, so it 42501-aborts the account-delete saga (the #4696
    // outage). Migration 087 eradicated it; 104 must follow.
    expect(executable).not.toMatch(/session_replication_role/i);
    expect(executable).toMatch(/set\s+local\s+app\.worm_bypass\s*=\s*'on'/i);
    expect(executable).toMatch(/current_setting\('app\.worm_bypass',\s*true\)\s*=\s*'on'/i);
  });

  it("has a duplicate-send guard (UNIQUE dedup index + outbound_send_exists RPC)", () => {
    expect(executable).toMatch(
      /create\s+unique\s+index\s+if\s+not\s+exists\s+outbound_sends_dedup_unique\s+on\s+public\.outbound_sends\s*\(\s*owner_id,\s*recipient_hash,\s*approved_body_sha256\s*\)/i,
    );
    expect(executable).toMatch(
      /create\s+or\s+replace\s+function\s+public\.outbound_send_exists[\s\S]*?security\s+definer[\s\S]*?set\s+search_path\s*=\s*public,\s*pg_temp/i,
    );
  });
});

describe("migration 104_outbound_email — negative-space invariants", () => {
  it("does NOT widen any enum or alter action_sends/scope_grants", () => {
    expect(executable).not.toMatch(/alter\s+table\s+public\.action_sends/i);
    expect(executable).not.toMatch(/alter\s+table\s+public\.scope_grants/i);
    expect(executable).not.toMatch(/alter\s+type/i);
  });

  it("anonymise RPCs are service-role-only — NOT granted to authenticated (no self-service erasure; sec review #5325)", () => {
    // The erasure RPCs must never be self-callable: outbound_sends is a
    // third-party WORM audit, and wiping email_suppression could re-enable
    // opted-out sends. Account deletion (service_role) is the only Art-17 trigger.
    expect(executable).not.toMatch(
      /grant\s+execute\s+on\s+function\s+public\.anonymise_outbound_sends\(uuid\)\s+to\s+authenticated/i,
    );
    expect(executable).not.toMatch(
      /grant\s+execute\s+on\s+function\s+public\.anonymise_email_suppression\(uuid\)\s+to\s+authenticated/i,
    );
    // The body guards service-role-only (no auth.uid()=p_user_id self-branch).
    expect(executable).toMatch(/anonymise_outbound_sends:\s*service-role only/i);
    expect(executable).toMatch(/anonymise_email_suppression:\s*service-role only/i);
    expect(executable).not.toMatch(/self-call only for authenticated callers/i);
  });

  it("has NO un-suppress path (suppression is permanent/monotonic)", () => {
    // No RPC that removes a row from email_suppression. The ONLY DELETE on the
    // table is the down-migration's DROP TABLE, never a per-row un-suppress.
    expect(executable).not.toMatch(
      /delete\s+from\s+public\.email_suppression/i,
    );
    expect(executable).not.toMatch(/function\s+public\.(un)?un_?suppress/i);
  });

  it("pins the HMAC algorithm + pepper source in the header (deterministic key)", () => {
    // recipient_hash determinism is the load-bearing anti-incident property:
    // a per-row/random salt would break cross-campaign suppression lookup.
    expect(raw).toMatch(/HMAC-SHA-256\(EMAIL_HASH_PEPPER/i);
    expect(raw).toMatch(/NOT a per-row\/random salt/i);
  });
});

describe("migration 104_outbound_email — down", () => {
  it("drops the three RPCs before the table they reference", () => {
    expect(down).toMatch(
      /drop\s+function\s+if\s+exists\s+public\.anonymise_email_suppression\(uuid\)/i,
    );
    expect(down).toMatch(
      /drop\s+function\s+if\s+exists\s+public\.is_recipient_suppressed\(text\)/i,
    );
    expect(down).toMatch(
      /drop\s+function\s+if\s+exists\s+public\.suppress_recipient\(text,\s*text\)/i,
    );
    expect(down).toMatch(/drop\s+table\s+if\s+exists\s+public\.email_suppression/i);
  });

  it("makes NO action_sends/scope_grants reversions (none were applied)", () => {
    expect(down).not.toMatch(/action_sends/i);
    expect(down).not.toMatch(/scope_grants/i);
  });
});
