/**
 * email_triage_items WORM Mutation Matrix + RLS + purge/anonymise — DB-layer
 * integration test (feat-operator-inbox-delegation Phase 1).
 *
 * Covers the `## WORM Mutation Matrix` contract of
 * knowledge-base/project/plans/2026-06-10-feat-operator-inbox-delegation-plan.md:
 *   (a) stub INSERT happy path — one-time-set columns are SQL NULL (never '')
 *   (b) UNIQUE(claim_key) → 23505 on duplicate claim-insert
 *   (c) hard-frozen column UPDATE (subject, claim_key) → P0001
 *   (d) one-time-set NULL→value succeeds exactly once (finalize); a second
 *       change once set → P0001
 *   (e) direct status UPDATE without the status GUC → P0001 (RPC-only
 *       transitions)
 *   (f) set_email_triage_status: 'new'→'acknowledged' succeeds (sets
 *       acknowledged_at + status_changed_at); reverse transition rejected;
 *       acknowledged→archived rejected (one-way from 'new' only);
 *       wrong-user call rejected (auth.uid() pin)
 *   (g) purge_email_triage_items deletes probe rows >7d + non-statutory rows
 *       >365d + stale probe_tokens under the purge GUC, retains statutory
 *       rows, while a direct DELETE rejects with P0001
 *   (h) anonymise_email_triage_items NULLs user_id + sender under the
 *       anonymise GUC; WORM re-armed afterwards
 *   (i) behavioral RLS deny: second user SELECT → 0 rows with a TYPE-VALID
 *       payload + owner positive control (learning 2026-05-16: a 22P02/23503
 *       masquerades as an RLS deny without the positive control)
 *
 * Opt-in via TENANT_INTEGRATION_TEST=1. Requires `doppler run -p soleur -c dev`.
 *
 *   cd apps/web-platform && \
 *     doppler run -p soleur -c dev -- \
 *     env TENANT_INTEGRATION_TEST=1 \
 *     ./node_modules/.bin/vitest run \
 *     test/server/email-triage-worm.test.ts
 *
 * Synthesized fixtures only (cq-test-fixtures-synthesized-only).
 */

import { afterAll, beforeAll, describe, expect, test } from "vitest";
import {
  createClient,
  type SupabaseClient,
} from "@supabase/supabase-js";
import { randomBytes, randomUUID } from "node:crypto";

import { mintFounderJwt } from "@/lib/supabase/tenant";

const INTEGRATION_ENABLED = process.env.TENANT_INTEGRATION_TEST === "1";

const SYNTHETIC_EMAIL_PATTERN =
  /^tenant-isolation-[a-f0-9]{16}@soleur\.test$/;

function syntheticEmail(): string {
  return `tenant-isolation-${randomBytes(8).toString("hex")}@soleur.test`;
}

function assertSynthetic(email: string): void {
  if (!SYNTHETIC_EMAIL_PATTERN.test(email)) {
    throw new Error(
      `Refusing to touch non-synthetic email "${email}" — this test only ` +
        "manipulates tenant-isolation-*@soleur.test accounts.",
    );
  }
}

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`[email-triage-worm] ${name} is required`);
  return value;
}

function isoDaysAgo(days: number): string {
  return new Date(Date.now() - days * 24 * 60 * 60 * 1000).toISOString();
}

interface StubOverrides {
  user_id?: string | null;
  workspace_id?: string | null;
  claim_key?: string;
  message_id?: string | null;
  sender?: string | null;
  subject?: string;
  received_at?: string;
  mail_class?: string;
  statutory_class?: string;
}

/**
 * Claim-insert a stub row. One-time-set columns (summary, mail_class,
 * statutory_class, rule_id) are SQL NULL unless overridden — never ''.
 */
async function insertStub(
  service: SupabaseClient,
  userId: string,
  overrides: StubOverrides = {},
): Promise<{ id: string; claim_key: string }> {
  const claimKey = overrides.claim_key ?? `resend:${randomUUID()}`;
  // mig 111: workspace grain. Default workspace_id = the row's owner (residual
  // personal-workspace shape: handle_new_user creates workspace id=user_id with
  // an owner membership). Reads/acks are gated on workspace-owner membership.
  const effectiveUserId =
    overrides.user_id === undefined ? userId : overrides.user_id;
  const { data, error } = await service
    .from("email_triage_items")
    .insert({
      user_id: effectiveUserId,
      workspace_id:
        overrides.workspace_id === undefined
          ? effectiveUserId
          : overrides.workspace_id,
      claim_key: claimKey,
      message_id:
        overrides.message_id === undefined
          ? `<${randomUUID()}@synthetic.soleur.test>`
          : overrides.message_id,
      resend_email_id: randomUUID(),
      sender:
        overrides.sender === undefined
          ? "Synthetic Sender <sender@synthetic.soleur.test>"
          : overrides.sender,
      subject: overrides.subject ?? "synthetic triage subject",
      received_at: overrides.received_at ?? new Date().toISOString(),
      received_at_source: "payload",
      ...(overrides.mail_class !== undefined
        ? { mail_class: overrides.mail_class }
        : {}),
      ...(overrides.statutory_class !== undefined
        ? { statutory_class: overrides.statutory_class }
        : {}),
    })
    .select("id, claim_key")
    .single();
  if (error) throw new Error(`insertStub failed: ${error.message}`);
  return { id: data!.id as string, claim_key: data!.claim_key as string };
}

describe.skipIf(!INTEGRATION_ENABLED)(
  "email_triage_items WORM Mutation Matrix + RLS (integration)",
  () => {
    let service: SupabaseClient;
    let tenantA: SupabaseClient;
    let tenantB: SupabaseClient;
    const userA = { id: "", email: syntheticEmail() };
    const userB = { id: "", email: syntheticEmail() };

    beforeAll(async () => {
      const url = requireEnv("SUPABASE_URL");
      const anonKey = requireEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY");
      const serviceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
      requireEnv("SUPABASE_JWT_SECRET");

      service = createClient(url, serviceRoleKey, {
        auth: { persistSession: false, autoRefreshToken: false },
      });

      for (const u of [userA, userB]) {
        assertSynthetic(u.email);
        const { data, error } = await service.auth.admin.createUser({
          email: u.email,
          password: randomBytes(16).toString("hex"),
          email_confirm: true,
        });
        expect(error, `createUser(${u.email})`).toBeNull();
        if (data.user?.id) u.id = data.user.id;
        expect(u.id).toBeTruthy();
      }

      const { jwt: jwtA } = await mintFounderJwt(userA.id, { ttlSec: 600 });
      const { jwt: jwtB } = await mintFounderJwt(userB.id, { ttlSec: 600 });
      tenantA = createClient(url, anonKey, {
        global: { headers: { Authorization: `Bearer ${jwtA}` } },
        auth: { persistSession: false, autoRefreshToken: false },
      });
      tenantB = createClient(url, anonKey, {
        global: { headers: { Authorization: `Bearer ${jwtB}` } },
        auth: { persistSession: false, autoRefreshToken: false },
      });
    });

    afterAll(async () => {
      // user_id has ON DELETE RESTRICT — anonymise (NULLs the FK) before
      // deleting the auth users. WORM rows themselves stay (append-only by
      // design; only the purge RPC can remove old rows).
      for (const u of [userA, userB]) {
        if (!u.id) continue;
        assertSynthetic(u.email);
        try {
          await service.rpc("anonymise_email_triage_items", {
            p_user_id: u.id,
          });
        } catch {
          /* tolerate teardown failures */
        }
        try {
          await service.auth.admin.deleteUser(u.id);
        } catch {
          /* tolerate teardown failures */
        }
      }
    });

    test("(a) stub INSERT happy path — one-time-set columns are SQL NULL", async () => {
      const stub = await insertStub(service, userA.id);
      const { data, error } = await service
        .from("email_triage_items")
        .select("summary, mail_class, statutory_class, rule_id, status, acknowledged_at")
        .eq("id", stub.id)
        .single();
      expect(error).toBeNull();
      expect(data!.summary).toBeNull();
      expect(data!.mail_class).toBeNull();
      expect(data!.statutory_class).toBeNull();
      expect(data!.rule_id).toBeNull();
      expect(data!.acknowledged_at).toBeNull();
      expect(data!.status).toBe("new");
    });

    test("(b) duplicate claim_key → 23505 (UNIQUE dedup gate)", async () => {
      const stub = await insertStub(service, userA.id);
      const { error } = await service.from("email_triage_items").insert({
        user_id: userA.id,
        claim_key: stub.claim_key,
        resend_email_id: randomUUID(),
        sender: "dup@synthetic.soleur.test",
        subject: "duplicate claim",
        received_at: new Date().toISOString(),
        received_at_source: "envelope",
      });
      expect(error).not.toBeNull();
      expect(error!.code).toBe("23505");
    });

    test("(c) hard-frozen column UPDATE → P0001", async () => {
      const stub = await insertStub(service, userA.id);

      const { error: subjErr } = await service
        .from("email_triage_items")
        .update({ subject: "attacker rewrite" })
        .eq("id", stub.id);
      expect(subjErr).not.toBeNull();
      expect(subjErr!.code).toBe("P0001");

      const { error: claimErr } = await service
        .from("email_triage_items")
        .update({ claim_key: `resend:${randomUUID()}` })
        .eq("id", stub.id);
      expect(claimErr).not.toBeNull();
      expect(claimErr!.code).toBe("P0001");
    });

    test("(d) one-time-set: finalize NULL→value once; second change → P0001", async () => {
      const stub = await insertStub(service, userA.id);

      // Finalize (the pipeline's own UPDATE) must succeed without any GUC.
      const { error: finalizeErr } = await service
        .from("email_triage_items")
        .update({
          summary: "synthetic summary",
          mail_class: "vendor",
          rule_id: null, // staying NULL is fine — only NULL→value is one-shot
        })
        .eq("id", stub.id);
      expect(finalizeErr, "finalize NULL→value must pass WORM").toBeNull();

      // Second finalize changing an already-set value → P0001.
      const { error: secondErr } = await service
        .from("email_triage_items")
        .update({ summary: "rewritten summary" })
        .eq("id", stub.id);
      expect(secondErr).not.toBeNull();
      expect(secondErr!.code).toBe("P0001");

      // Set-then-NULL is also a change once set → P0001.
      const { error: nullErr } = await service
        .from("email_triage_items")
        .update({ mail_class: null })
        .eq("id", stub.id);
      expect(nullErr).not.toBeNull();
      expect(nullErr!.code).toBe("P0001");

      // A still-NULL one-time-set column can be set later (late statutory
      // classification) without disturbing the already-set ones.
      const { error: lateErr } = await service
        .from("email_triage_items")
        .update({ statutory_class: "dsar", rule_id: "rule-dsar-1" })
        .eq("id", stub.id);
      expect(lateErr, "late one-time-set on still-NULL columns").toBeNull();
    });

    test("(e) direct status UPDATE without GUC → P0001 (RPC-only transitions)", async () => {
      const stub = await insertStub(service, userA.id);
      const { error } = await service
        .from("email_triage_items")
        .update({ status: "acknowledged" })
        .eq("id", stub.id);
      expect(error).not.toBeNull();
      expect(error!.code).toBe("P0001");

      const { error: ackErr } = await service
        .from("email_triage_items")
        .update({ acknowledged_at: new Date().toISOString() })
        .eq("id", stub.id);
      expect(ackErr).not.toBeNull();
      expect(ackErr!.code).toBe("P0001");
    });

    test("(f) set_email_triage_status: one-way transitions + workspace-owner pin (mig 111)", async () => {
      const stub = await insertStub(service, userA.id);

      // Non-owner-of-the-row's-workspace first (row still 'new' so only the
      // authz gate can fire). userB is not an Owner of workspace userA.
      const { error: wrongUserErr } = await tenantB.rpc(
        "set_email_triage_status",
        { p_id: stub.id, p_status: "acknowledged" },
      );
      expect(wrongUserErr, "non-owner call must be rejected").not.toBeNull();

      // Owner: 'new' → 'acknowledged' succeeds.
      const { error: ackErr } = await tenantA.rpc("set_email_triage_status", {
        p_id: stub.id,
        p_status: "acknowledged",
      });
      expect(ackErr, "owner new→acknowledged").toBeNull();

      const { data: row } = await service
        .from("email_triage_items")
        .select("status, status_changed_at, acknowledged_at")
        .eq("id", stub.id)
        .single();
      expect(row!.status).toBe("acknowledged");
      expect(row!.status_changed_at).not.toBeNull();
      expect(row!.acknowledged_at).not.toBeNull();

      // Reverse transition acknowledged → 'new' rejected (invalid target).
      const { error: reverseErr } = await tenantA.rpc(
        "set_email_triage_status",
        { p_id: stub.id, p_status: "new" },
      );
      expect(reverseErr, "reverse transition must be rejected").not.toBeNull();

      // acknowledged → archived rejected (transitions start from 'new' only).
      const { error: archErr } = await tenantA.rpc("set_email_triage_status", {
        p_id: stub.id,
        p_status: "archived",
      });
      expect(archErr, "acknowledged→archived must be rejected").not.toBeNull();

      // 'new' → 'archived' is the other legal edge.
      const stub2 = await insertStub(service, userA.id);
      const { error: archiveOkErr } = await tenantA.rpc(
        "set_email_triage_status",
        { p_id: stub2.id, p_status: "archived" },
      );
      expect(archiveOkErr, "owner new→archived").toBeNull();
      const { data: row2 } = await service
        .from("email_triage_items")
        .select("status, acknowledged_at")
        .eq("id", stub2.id)
        .single();
      expect(row2!.status).toBe("archived");
      // Archiving without viewing is not an acknowledgement.
      expect(row2!.acknowledged_at).toBeNull();
    });

    test("(g) purge RPC deletes under GUC bypass; direct DELETE → P0001", async () => {
      // Probe row older than 7 days (mail_class set at claim time —
      // INSERT is not trigger-constrained, only UPDATE/DELETE are).
      const probe = await insertStub(service, userA.id, {
        mail_class: "probe",
        received_at: isoDaysAgo(8),
        subject: "synthetic probe",
      });
      // Non-statutory row older than 365 days.
      const stale = await insertStub(service, userA.id, {
        mail_class: "vendor",
        received_at: isoDaysAgo(366),
        subject: "synthetic stale vendor",
      });
      // Statutory row older than 365 days — must be RETAINED.
      const statutory = await insertStub(service, userA.id, {
        mail_class: "legal-review",
        statutory_class: "regulator",
        received_at: isoDaysAgo(366),
        subject: "synthetic statutory",
      });
      // Probe row >7d WITH a statutory_class — the probe sweep's statutory
      // carve-out (mirrors the 365d sweep) must RETAIN it.
      const statutoryProbe = await insertStub(service, userA.id, {
        mail_class: "probe",
        statutory_class: "dsar",
        received_at: isoDaysAgo(8),
        subject: "synthetic statutory probe",
      });
      // Fresh row — must be retained and rejects direct DELETE.
      const fresh = await insertStub(service, userA.id);

      // Stale probe token.
      const staleToken = `probe-${randomUUID()}`;
      const { error: tokenErr } = await service.from("probe_tokens").insert({
        token: staleToken,
        created_at: isoDaysAgo(8),
      });
      expect(tokenErr).toBeNull();

      // Direct DELETE (no GUC) → P0001.
      const { error: delErr } = await service
        .from("email_triage_items")
        .delete()
        .eq("id", fresh.id);
      expect(delErr).not.toBeNull();
      expect(delErr!.code).toBe("P0001");

      // Purge RPC under the GUC bypass.
      const { data: purged, error: purgeErr } = await service.rpc(
        "purge_email_triage_items",
      );
      expect(purgeErr, "purge_email_triage_items RPC").toBeNull();
      expect(purged).toBeTruthy();

      const ids = [probe.id, stale.id, statutory.id, statutoryProbe.id, fresh.id];
      const { data: remaining } = await service
        .from("email_triage_items")
        .select("id")
        .in("id", ids);
      const remainingIds = new Set((remaining ?? []).map((r) => r.id));
      expect(remainingIds.has(probe.id), "probe >7d purged").toBe(false);
      expect(remainingIds.has(stale.id), "non-statutory >365d purged").toBe(
        false,
      );
      expect(remainingIds.has(statutory.id), "statutory retained").toBe(true);
      expect(
        remainingIds.has(statutoryProbe.id),
        "statutory probe >7d retained (probe-sweep carve-out)",
      ).toBe(true);
      expect(remainingIds.has(fresh.id), "fresh row retained").toBe(true);

      const { data: tokenRows } = await service
        .from("probe_tokens")
        .select("token")
        .eq("token", staleToken);
      expect(tokenRows?.length ?? 0, "stale probe token purged").toBe(0);
    });

    test("(g2) purge exact-boundary fixtures — the > vs >= one-character bug", async () => {
      // INTENDED SEMANTICS (read from migration 102's purge predicates):
      // `received_at < now() - interval '365 days'` / `< now() - interval
      // '7 days'` — STRICTLY OLDER than the window is deleted; a row exactly
      // AT the boundary survives. isoDaysAgo(364) is comfortably inside the
      // window (retained); isoDaysAgo(366) is strictly older (deleted).
      // Exactly-365d is deliberately NOT fixtured: by purge time the fixture
      // is microseconds past the boundary, which makes the assertion a
      // wall-clock race rather than a semantics probe. The one-character
      // `>` vs `>=` regression class is fully covered by the 364/366 and
      // 6/8 pairs on either side.
      const nonStatutory364 = await insertStub(service, userA.id, {
        mail_class: "vendor",
        received_at: isoDaysAgo(364),
        subject: "synthetic boundary vendor 364d",
      });
      const nonStatutory366 = await insertStub(service, userA.id, {
        mail_class: "vendor",
        received_at: isoDaysAgo(366),
        subject: "synthetic boundary vendor 366d",
      });
      const probe6 = await insertStub(service, userA.id, {
        mail_class: "probe",
        received_at: isoDaysAgo(6),
        subject: "synthetic boundary probe 6d",
      });
      const probe8 = await insertStub(service, userA.id, {
        mail_class: "probe",
        received_at: isoDaysAgo(8),
        subject: "synthetic boundary probe 8d",
      });
      // Statutory deep past the general window — the statutory_class IS
      // NULL carve-out IS the accountability-period retention guarantee.
      const statutory400 = await insertStub(service, userA.id, {
        mail_class: "legal-review",
        statutory_class: "dsar",
        received_at: isoDaysAgo(400),
        subject: "synthetic boundary statutory 400d",
      });

      const { error: purgeErr } = await service.rpc(
        "purge_email_triage_items",
      );
      expect(purgeErr, "purge_email_triage_items RPC").toBeNull();

      const ids = [
        nonStatutory364.id,
        nonStatutory366.id,
        probe6.id,
        probe8.id,
        statutory400.id,
      ];
      const { data: remaining } = await service
        .from("email_triage_items")
        .select("id")
        .in("id", ids);
      const remainingIds = new Set((remaining ?? []).map((r) => r.id));

      expect(
        remainingIds.has(nonStatutory364.id),
        "non-statutory 364d RETAINED (not strictly older than 365d)",
      ).toBe(true);
      expect(
        remainingIds.has(nonStatutory366.id),
        "non-statutory 366d DELETED (strictly older than 365d)",
      ).toBe(false);
      expect(
        remainingIds.has(probe6.id),
        "probe 6d RETAINED (not strictly older than 7d)",
      ).toBe(true);
      expect(
        remainingIds.has(probe8.id),
        "probe 8d DELETED (strictly older than 7d)",
      ).toBe(false);
      expect(
        remainingIds.has(statutory400.id),
        "statutory 400d RETAINED (accountability-period carve-out)",
      ).toBe(true);
    });

    test("(h) anonymise RPC NULLs user_id + sender; WORM re-armed", async () => {
      // Throwaway user so we don't strip the shared userA mid-suite.
      const u = { id: "", email: syntheticEmail() };
      assertSynthetic(u.email);
      const { data: created, error: createErr } =
        await service.auth.admin.createUser({
          email: u.email,
          password: randomBytes(16).toString("hex"),
          email_confirm: true,
        });
      expect(createErr).toBeNull();
      u.id = created.user!.id;

      const stub = await insertStub(service, u.id);

      const { data: affected, error: anonErr } = await service.rpc(
        "anonymise_email_triage_items",
        { p_user_id: u.id },
      );
      expect(anonErr, "anonymise_email_triage_items RPC").toBeNull();
      expect(affected as unknown as number).toBeGreaterThan(0);

      const { data: after } = await service
        .from("email_triage_items")
        .select("user_id, sender")
        .eq("id", stub.id)
        .single();
      expect(after!.user_id, "user_id zeroed").toBeNull();
      expect(after!.sender, "sender zeroed").toBeNull();

      // Idempotent re-run → 0 rows.
      const { data: secondRun, error: secondErr } = await service.rpc(
        "anonymise_email_triage_items",
        { p_user_id: u.id },
      );
      expect(secondErr).toBeNull();
      expect(secondRun as unknown as number).toBe(0);

      // WORM re-armed: the anonymise GUC must not leak past the RPC.
      const { error: rearmErr } = await service
        .from("email_triage_items")
        .update({ subject: "post-anonymise rewrite" })
        .eq("id", stub.id);
      expect(rearmErr, "WORM re-armed after anonymise").not.toBeNull();
      expect(rearmErr!.code).toBe("P0001");

      // Re-identification (NULL → value) is rejected even though sender is
      // anonymise-shaped: only NOT NULL → NULL is admitted.
      const { error: reidentErr } = await service
        .from("email_triage_items")
        .update({ sender: "reidentified@synthetic.soleur.test" })
        .eq("id", stub.id);
      expect(reidentErr).not.toBeNull();
      expect(reidentErr!.code).toBe("P0001");

      try {
        await service.auth.admin.deleteUser(u.id);
      } catch {
        /* tolerate teardown failure */
      }
    });

    test("(i) behavioral RLS deny: type-valid cross-tenant SELECT → 0 rows + owner positive control", async () => {
      const stub = await insertStub(service, userA.id);

      // Owner positive control FIRST — proves the query shape is type-valid
      // and returns rows for the owner (learning 2026-05-16: without this a
      // 22P02/23503 masquerades as an RLS deny).
      const { data: ownRows, error: ownErr } = await tenantA
        .from("email_triage_items")
        .select("id, subject")
        .eq("id", stub.id);
      expect(ownErr).toBeNull();
      expect(ownRows?.length).toBe(1);

      // Second user, IDENTICAL type-valid payload → 0 rows, no error.
      const { data: crossRows, error: crossErr } = await tenantB
        .from("email_triage_items")
        .select("id, subject")
        .eq("id", stub.id);
      expect(crossErr).toBeNull();
      expect(crossRows?.length ?? 0).toBe(0);

      // Broad cross-tenant sweep by owner column → 0 rows.
      const { data: sweepRows, error: sweepErr } = await tenantB
        .from("email_triage_items")
        .select("id")
        .eq("user_id", userA.id);
      expect(sweepErr).toBeNull();
      expect(sweepRows?.length ?? 0).toBe(0);
    });

    test("(j) shared workspace inbox (mig 111): a co-Owner of the row's workspace can read + acknowledge", async () => {
      const stub = await insertStub(service, userA.id); // workspace_id = userA.id

      // Before the grant: userB is NOT an Owner of workspace userA → no read.
      const { data: before } = await tenantB
        .from("email_triage_items")
        .select("id")
        .eq("id", stub.id);
      expect(before?.length ?? 0).toBe(0);

      // Promote userB to Owner of workspace userA (the shared-inbox grant —
      // handle_new_user owner-row shape: attestation_id NULL).
      const { error: memberErr } = await service
        .from("workspace_members")
        .insert({
          workspace_id: userA.id,
          user_id: userB.id,
          role: "owner",
          attestation_id: null,
        });
      expect(memberErr, "grant userB co-owner of workspace userA").toBeNull();

      try {
        // Now a co-Owner CAN read userA's row via the owner-membership RLS.
        const { data: shared, error: sharedErr } = await tenantB
          .from("email_triage_items")
          .select("id, subject")
          .eq("id", stub.id);
        expect(sharedErr).toBeNull();
        expect(shared?.length, "co-owner reads the shared row").toBe(1);

        // ...and CAN act on it (the status RPC authorizes any workspace Owner).
        const { error: ackErr } = await tenantB.rpc("set_email_triage_status", {
          p_id: stub.id,
          p_status: "acknowledged",
        });
        expect(ackErr, "co-owner new→acknowledged").toBeNull();
        const { data: row } = await service
          .from("email_triage_items")
          .select("status")
          .eq("id", stub.id)
          .single();
        expect(row!.status).toBe("acknowledged");
      } finally {
        // Best-effort teardown (this is the last case; afterAll's user-delete
        // also cascades the membership). Ignore WORM/remove-RPC restrictions.
        await service
          .from("workspace_members")
          .delete()
          .eq("workspace_id", userA.id)
          .eq("user_id", userB.id);
      }
    });
  },
);
