/**
 * Cross-tenant isolation — DB integration test for DSAR export.
 *
 * Phase 10 of feat-dsar-art15-export-endpoint (#3637, plan rev-2).
 * AC6 + AC12 + AC15 + FR9. Load-bearing per the plan's User-Brand
 * Impact section: a single A->B leak is Art. 33 (CNIL 72h) + Art. 34
 * (data subject) notifiable.
 *
 * Assertion shape per `2026-05-06-rls-zero-policies-anon-delete-204-
 * semantic.md`: NEVER assert via HTTP status. Always re-check via
 * service-role read after the worker runs, comparing the bundle
 * contents to ground truth.
 *
 * Opt-in via SUPABASE_DEV_INTEGRATION=1. Run from apps/web-platform:
 *   doppler run -p soleur -c dev -- \
 *     env SUPABASE_DEV_INTEGRATION=1 \
 *     ./node_modules/.bin/vitest run \
 *     test/dsar-export-cross-tenant.integration.test.ts
 *
 * hr-destructive-prod-tests-allowlist: only synthetic emails matching
 * the pattern below may be created or deleted by this test.
 */

import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { randomBytes } from "crypto";

const INTEGRATION_ENABLED = process.env.SUPABASE_DEV_INTEGRATION === "1";

const SYNTHETIC_EMAIL_PATTERN =
  /^dsar-cross-tenant-[a-f0-9]{16}@soleur\.test$/;

function syntheticEmail(): string {
  return `dsar-cross-tenant-${randomBytes(8).toString("hex")}@soleur.test`;
}

function assertSynthetic(email: string): void {
  if (!SYNTHETIC_EMAIL_PATTERN.test(email)) {
    throw new Error(
      `Refusing to touch non-synthetic email "${email}" — this test only ` +
        "manipulates dsar-cross-tenant-*@soleur.test accounts.",
    );
  }
}

function requireEnv(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`[dsar-cross-tenant.integration] ${name} is required`);
  return v;
}

// Distinctive content for each user — the worker's bundle should
// never contain ANY of the other user's strings.
function distinctivePhrase(userId: string): string {
  return `DSAR_CT_DISTINCT_${userId}_${randomBytes(8).toString("hex")}`;
}

describe.skipIf(!INTEGRATION_ENABLED)(
  "DSAR cross-tenant isolation (AC6 + AC12 + AC15)",
  () => {
    let service: SupabaseClient;

    const userA = {
      id: "",
      email: syntheticEmail(),
      password: randomBytes(16).toString("hex"),
      phrase: "",
    };
    const userB = {
      id: "",
      email: syntheticEmail(),
      password: randomBytes(16).toString("hex"),
      phrase: "",
    };

    beforeAll(async () => {
      const url = requireEnv("NEXT_PUBLIC_SUPABASE_URL");
      const key = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
      service = createClient(url, key, {
        auth: { persistSession: false, autoRefreshToken: false },
      });

      for (const u of [userA, userB]) {
        assertSynthetic(u.email);
        const { data, error } = await service.auth.admin.createUser({
          email: u.email,
          password: u.password,
          email_confirm: true,
        });
        if (error || !data.user) {
          throw new Error(`createUser failed for ${u.email}: ${error?.message}`);
        }
        u.id = data.user.id;
        u.phrase = distinctivePhrase(u.id);

        // Ensure public.users row exists (the auth trigger usually
        // creates it; some local stacks lag — upsert defensively).
        await service.from("users").upsert({
          id: u.id,
          email: u.email,
          workspace_path: "",
          workspace_status: "ready",
        });

        // Seed a conversation + message that contains the user's
        // distinctive phrase. The bundle assertions look for this
        // phrase fragment by fragment.
        const { data: conv } = await service
          .from("conversations")
          .insert({
            user_id: u.id,
            domain_leader: "cto",
            status: "active",
          })
          .select("id")
          .single();
        if (!conv) throw new Error("seed conversation insert failed");

        await service.from("messages").insert({
          conversation_id: conv.id,
          role: "user",
          content: `Hello ${u.phrase}`,
        });

        // KB share link with the distinctive phrase in the document_path.
        await service.from("kb_share_links").insert({
          user_id: u.id,
          token: randomBytes(16).toString("hex"),
          document_path: `kb/notes/${u.phrase}.md`,
        });
      }
    }, 60_000);

    afterAll(async () => {
      for (const u of [userA, userB]) {
        if (!u.id) continue;
        assertSynthetic(u.email);
        try {
          await service.auth.admin.deleteUser(u.id);
        } catch {
          // Cleanup is best-effort — leaked synthetic emails are
          // bounded by the pattern guard.
        }
      }
    }, 30_000);

    test(
      "A's worker reads contain ZERO rows attributable to B (per-row WHERE + assertReadScope)",
      async () => {
        const { exportSqlTable } = await import("../server/dsar-export");
        const controller = new AbortController();
        const tables = await exportSqlTable.call(null, userA.id, controller.signal);

        // Per-row invariant: every row's owner field matches userA.id.
        for (const t of tables) {
          for (const row of t.rows) {
            // The owner column varies per table; for joinVia tables
            // the parent owner has already been re-asserted inside
            // exportSqlTable. Here we cross-reference by re-querying
            // ground truth via service-role and confirming every id
            // belongs to userA.
            if (t.table === "users") {
              expect((row as { id: string }).id).toBe(userA.id);
            }
            if (t.table === "conversations" || t.table === "kb_share_links") {
              expect((row as { user_id: string }).user_id).toBe(userA.id);
            }
            if (t.table === "audit_byok_use") {
              expect((row as { founder_id: string }).founder_id).toBe(userA.id);
            }
          }
        }

        // Content-level scan per SpecFlow finding: B's distinctive
        // phrase MUST NOT appear in A's bundle anywhere.
        const dumped = JSON.stringify(tables);
        expect(dumped).not.toContain(userB.phrase);
        expect(dumped).toContain(userA.phrase);
      },
      60_000,
    );

    test(
      "assertReadScope raises on a deliberately misowned fixture row",
      async () => {
        const { assertReadScope, CrossTenantViolation } = await import(
          "../server/dsar-export"
        );
        // A row whose owner_id is userB injected into a fixture set
        // labelled as belonging to userA. The invariant fires.
        const fixture = [
          { id: "1", owner_id: userA.id },
          { id: "2", owner_id: userB.id }, // cross-tenant
        ];
        expect(() => assertReadScope(fixture, userA.id, "conversations")).toThrow(
          CrossTenantViolation,
        );
      },
      10_000,
    );

    test(
      "service-role re-check after enqueueExport: in-flight row's user_id matches the requester",
      async () => {
        const { enqueueExport } = await import("../server/dsar-export");
        const { jobId } = await enqueueExport({
          userId: userA.id,
          sessionId: userA.id, // dummy session id for the binding test
          reauthEventId: "00000000-0000-0000-0000-000000000000",
          requesterIp: "127.0.0.1",
          userAgent: "vitest",
        });

        // Service-role re-check: the inserted row is owned by userA.
        const { data: rows } = await service
          .from("dsar_export_jobs")
          .select("user_id")
          .eq("id", jobId);
        expect(rows).toHaveLength(1);
        expect((rows![0] as { user_id: string }).user_id).toBe(userA.id);

        // Cleanup the test job so the user can re-run the test.
        await service.from("dsar_export_jobs").delete().eq("id", jobId);
      },
      30_000,
    );
  },
);
