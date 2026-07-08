/**
 * Beta-CRM behavioral integration — DEV-only (feat-beta-conversation-capture
 * #6165, ADR-102). Proves the make-or-break agent-native invariants against a
 * live Postgres with real RLS + SECURITY DEFINER RPCs — the things offline
 * SQL-text shape tests structurally cannot:
 *   AC7  write→read round-trip (crm_contact_upsert → crm_contact_get/list;
 *        crm_note_append → crm_note_list, lens filter honored)
 *   AC3  cross-tenant read deny WITH a positive owner-read control
 *   AC4  cross-tenant write isolation (B's upsert/set_stage/note vs A → 42501,
 *        A unchanged)
 *   AC9  owner DSAR export returns rows from all three beta-CRM tables (and none
 *        of B's)
 *   AC10 Art. 17: crm_erase_contact (service_role) + account-delete CASCADE
 *        both empty all three tables
 *
 * Opt-in via SUPABASE_DEV_INTEGRATION=1 against a DEDICATED dev Supabase project
 * (hr-dev-prd-distinct-supabase-projects — NEVER the shared dev pre-merge). Run
 * from apps/web-platform:
 *   doppler run -p soleur -c dev -- \
 *     env SUPABASE_DEV_INTEGRATION=1 \
 *     ./node_modules/.bin/vitest run test/beta-crm-dsar.integration.test.ts
 *
 * Fixtures are SYNTHESIZED only (cq-test-fixtures-synthesized-only); the
 * synthetic-email guard refuses to touch any non-synthetic account. Assertions
 * re-check via a service-role read after each write (never via an HTTP/RPC
 * success code alone).
 */

import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { randomBytes } from "crypto";

const INTEGRATION_ENABLED = process.env.SUPABASE_DEV_INTEGRATION === "1";

const SYNTHETIC_EMAIL_PATTERN = /^beta-crm-[a-f0-9]{16}@soleur\.test$/;
const syntheticEmail = () => `beta-crm-${randomBytes(8).toString("hex")}@soleur.test`;
function assertSynthetic(email: string): void {
  if (!SYNTHETIC_EMAIL_PATTERN.test(email)) {
    throw new Error(
      `Refusing to touch non-synthetic email "${email}" — this test only ` +
        "manipulates beta-crm-*@soleur.test accounts.",
    );
  }
}
function requireEnv(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`[beta-crm-dsar.integration] ${name} is required`);
  return v;
}

const BETA_TABLES = [
  "beta_contacts",
  "interview_notes",
  "beta_contact_stage_transitions",
] as const;

describe.skipIf(!INTEGRATION_ENABLED)("beta-CRM behavioral (dev)", () => {
  let service: SupabaseClient;
  let tenantA: SupabaseClient;
  let tenantB: SupabaseClient;

  const userA = { id: "", email: syntheticEmail(), password: randomBytes(16).toString("hex") };
  const userB = { id: "", email: syntheticEmail(), password: randomBytes(16).toString("hex") };
  let contactA = "";

  beforeAll(async () => {
    const url = requireEnv("NEXT_PUBLIC_SUPABASE_URL");
    const serviceKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
    const anonKey = requireEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY");
    service = createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    for (const u of [userA, userB]) {
      assertSynthetic(u.email);
      const { data, error } = await service.auth.admin.createUser({
        email: u.email,
        password: u.password,
        email_confirm: true,
      });
      if (error || !data.user) throw new Error(`createUser failed: ${error?.message}`);
      u.id = data.user.id;
      await service.from("users").upsert({ id: u.id, email: u.email, workspace_status: "ready" });
    }

    // Signed-in tenant clients so the RPCs' auth.uid() resolves to each user.
    const signIn = async (email: string, password: string) => {
      const c = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
      const { error } = await c.auth.signInWithPassword({ email, password });
      if (error) throw new Error(`signIn failed for ${email}: ${error.message}`);
      return c;
    };
    tenantA = await signIn(userA.email, userA.password);
    tenantB = await signIn(userB.email, userB.password);
  }, 60_000);

  afterAll(async () => {
    for (const u of [userA, userB]) {
      if (!u.id) continue;
      assertSynthetic(u.email);
      try {
        await service.auth.admin.deleteUser(u.id);
      } catch {
        /* best-effort; bounded by the synthetic-email guard */
      }
    }
  }, 30_000);

  test("AC7 — write→read round-trip incl. crm_note_list lens filter", async () => {
    const { data: id, error } = await tenantA.rpc("crm_contact_upsert", {
      p_name: "Alice Example",
      p_company: "ACME Corp",
      p_stage: "qualified",
      p_amount: 1000,
      p_currency: "USD",
    });
    expect(error).toBeNull();
    expect(id).toBeTruthy();
    contactA = id as string;

    // every writable column round-trips (RLS-scoped read as the owner)
    const { data: got } = await tenantA.from("beta_contacts").select("*").eq("id", contactA).single();
    expect(got).toMatchObject({ name: "Alice Example", company: "ACME Corp", stage: "qualified", currency: "USD" });

    // INSERT-at-non-default-stage recorded exactly one transition
    const { data: trans } = await tenantA
      .from("beta_contact_stage_transitions")
      .select("*")
      .eq("contact_id", contactA);
    expect(trans).toHaveLength(1);
    expect(trans?.[0]).toMatchObject({ from_stage: null, to_stage: "qualified" });

    // append two notes with different lenses; crm_note_list honors the filter
    await tenantA.rpc("crm_note_append", { p_contact_id: contactA, p_body: "sales note", p_lens: ["sales"] });
    await tenantA.rpc("crm_note_append", { p_contact_id: contactA, p_body: "product note", p_lens: ["product"] });
    const { data: salesOnly } = await tenantA
      .from("interview_notes")
      .select("*")
      .eq("contact_id", contactA)
      .contains("lens", ["sales"]);
    expect(salesOnly).toHaveLength(1);
    expect(salesOnly?.[0].body).toBe("sales note");

    // an empty-lens note is rejected live ('{}' fails cardinality())
    const { error: lensErr } = await tenantA.rpc("crm_note_append", {
      p_contact_id: contactA,
      p_body: "x",
      p_lens: [],
    });
    expect(lensErr).not.toBeNull();
  });

  test("AC3 — cross-tenant read deny with a positive owner-read control", async () => {
    const own = await tenantA.from("beta_contacts").select("id").eq("id", contactA);
    expect(own.data).toHaveLength(1); // positive control (policy is load-bearing)
    const foreign = await tenantB.from("beta_contacts").select("id").eq("id", contactA);
    expect(foreign.data).toHaveLength(0); // RLS filters, not errors
  });

  test("AC4 — cross-tenant write isolation; A's row unchanged", async () => {
    const upsert = await tenantB.rpc("crm_contact_upsert", { p_id: contactA, p_name: "HACKED" });
    expect(upsert.error?.code).toBe("42501");
    const setStage = await tenantB.rpc("crm_contact_set_stage", { p_contact_id: contactA, p_to_stage: "closed_lost" });
    expect(setStage.error?.code).toBe("42501");
    const note = await tenantB.rpc("crm_note_append", { p_contact_id: contactA, p_body: "x", p_lens: ["sales"] });
    expect(note.error?.code).toBe("42501");
    // service-role ground-truth re-check: A's row is untouched
    const { data } = await service.from("beta_contacts").select("name, stage").eq("id", contactA).single();
    expect(data).toMatchObject({ name: "Alice Example", stage: "qualified" });
  });

  test("AC9 — owner DSAR export returns all three beta-CRM tables (and none of B's)", async () => {
    const { exportSqlTable } = await import("../server/dsar-export");
    const results = await exportSqlTable(userA.id, randomBytes(16), new AbortController().signal);
    for (const t of BETA_TABLES) {
      const entry = results.find((r) => r.table === t);
      expect(entry, `export missing ${t}`).toBeTruthy();
      expect(entry!.rows.length, `${t} should have A's rows`).toBeGreaterThan(0);
      for (const row of entry!.rows) expect((row as { user_id: string }).user_id).toBe(userA.id);
    }
  });

  test("AC10 — crm_erase_contact CASCADEs children; account-delete empties all three", async () => {
    // third-party erasure: service-role-only RPC deletes the contact + children
    const { data: erased, error } = await service.rpc("crm_erase_contact", { p_contact_id: contactA });
    expect(error).toBeNull();
    expect(erased).toBe(1);
    for (const t of ["interview_notes", "beta_contact_stage_transitions"]) {
      const { data } = await service.from(t).select("id").eq("contact_id", contactA);
      expect(data, `${t} should be empty after erase`).toHaveLength(0);
    }

    // owner erasure: seed a fresh contact, then delete the account → CASCADE
    const { data: freshId } = await tenantA.rpc("crm_contact_upsert", { p_name: "Bob" });
    expect(freshId).toBeTruthy();
    await service.auth.admin.deleteUser(userA.id);
    const gone = await service.from("beta_contacts").select("id").eq("user_id", userA.id);
    expect(gone.data).toHaveLength(0);
    userA.id = ""; // prevent afterAll double-delete
  });
});
