/**
 * DSAR author-only message redaction (Art. 15(4)) — integration test.
 *
 * Plan: knowledge-base/project/plans/2026-05-22-feat-dsar-author-redaction-art-15-4-plan.md
 * Issue: #4319, draft PR: #4351.
 *
 * Fixture: shared workspace W with members Alice + Bob + Charlie. Alice
 * owns conversation C in W. Messages M1-M5 with attachments A1, A2, A2b
 * cover author-mix, legacy NULL, and allowlist-fail-closed cases.
 *
 * Audited Phase 0.3 LEGACY_NULL_IS_SUBJECT = false: post-mig 059 the
 * messages_workspace_member_insert RLS policy gates on
 * is_workspace_member(workspace_id, auth.uid()) — NOT on user_id matching
 * conversation owner — and every server INSERT site
 * (cc-dispatcher.ts:1411/1519, agent-runner.ts:435/2322, etc.) omits
 * user_id (defaults NULL). A non-subject CAN write `user_id IS NULL`
 * rows into a foreign-owned conversation. Fail-closed default applies.
 *
 * Opt-in via SUPABASE_DEV_INTEGRATION=1. Run from apps/web-platform:
 *   doppler run -p soleur -c dev -- \
 *     env SUPABASE_DEV_INTEGRATION=1 \
 *     ./node_modules/.bin/vitest run \
 *     test/dsar-author-redaction.integration.test.ts
 *
 * Synthetic-email gating: workspace-members-fixtures uses the
 * `workspace-fixture-*@soleur.test` pattern; no real-customer data is
 * referenced. (`cq-test-fixtures-synthesized-only`.)
 */

import { afterAll, beforeAll, describe, expect, test, vi } from "vitest";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { randomBytes } from "node:crypto";

import {
  createSharedWorkspaceMembers,
  tearDownSharedWorkspace,
  type SharedWorkspaceFixture,
} from "./helpers/workspace-members-fixtures";

const INTEGRATION_ENABLED = process.env.SUPABASE_DEV_INTEGRATION === "1";

function requireEnv(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`[dsar-author-redaction.integration] ${name} is required`);
  return v;
}

function distinctivePhrase(label: string): string {
  return `DSAR_AUTHOR_REDACT_${label}_${randomBytes(8).toString("hex")}`;
}

const PSEUDONYM_RE = /^member_[0-9a-f]{12}$/;

describe.skipIf(!INTEGRATION_ENABLED)(
  "DSAR Art. 15(4) author-only redaction (AC1 + AC3 + AC5)",
  () => {
    let service: SupabaseClient;
    let fixture: SharedWorkspaceFixture;
    let alice: { id: string; email: string };
    let bob: { id: string; email: string };
    let charlie: { id: string; email: string };
    let conversationId: string;

    const messageIds: Record<"M1" | "M2" | "M3" | "M4" | "M5", string> = {
      M1: "",
      M2: "",
      M3: "",
      M4: "",
      M5: "",
    };

    const phrases = {
      M1: distinctivePhrase("ALICE_M1"),
      M2: distinctivePhrase("BOB_M2"),
      M3: distinctivePhrase("LEGACY_M3"),
      M4: distinctivePhrase("BOB_M4"),
      M5: distinctivePhrase("CHARLIE_M5"),
    };

    const attachmentPaths = {
      A1: `chat-attachments/__ALICE__/A1-${randomBytes(4).toString("hex")}.png`,
      A2: `chat-attachments/__BOB__/A2-${randomBytes(4).toString("hex")}.png`,
      A2b: `chat-attachments/__BOB__/A2b-${randomBytes(4).toString("hex")}.png`,
    };

    beforeAll(async () => {
      const url = requireEnv("NEXT_PUBLIC_SUPABASE_URL");
      const key = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
      service = createClient(url, key, {
        auth: { persistSession: false, autoRefreshToken: false },
      });

      fixture = await createSharedWorkspaceMembers(service, 3);
      alice = { id: fixture.members[0].userId, email: fixture.members[0].email };
      bob = { id: fixture.members[1].userId, email: fixture.members[1].email };
      charlie = { id: fixture.members[2].userId, email: fixture.members[2].email };

      // Seed conversation owned by Alice in the shared workspace.
      const { data: convRow, error: convErr } = await service
        .from("conversations")
        .insert({
          user_id: alice.id,
          workspace_id: fixture.workspaceId,
          domain_leader: "cto",
          status: "active",
        })
        .select("id")
        .single();
      if (convErr || !convRow) {
        throw new Error(
          `seed conversation insert failed: ${convErr?.message ?? "no row"}`,
        );
      }
      conversationId = (convRow as { id: string }).id;

      // Seed messages M1-M5.
      // M1: Alice authored — should be preserved.
      // M2: Bob authored — content + namespace columns redacted; user_id pseudonymised.
      // M3: legacy user_id IS NULL — fail-closed redaction (LEGACY_NULL_IS_SUBJECT=false).
      // M4: Bob authored again — same pseudonym as M2 within bundle.
      // M5: Charlie authored — distinct pseudonym from Bob.
      const messageSeeds: Array<{
        key: keyof typeof messageIds;
        user_id: string | null;
        content: string;
      }> = [
        { key: "M1", user_id: alice.id, content: phrases.M1 },
        { key: "M2", user_id: bob.id, content: phrases.M2 },
        { key: "M3", user_id: null, content: phrases.M3 },
        { key: "M4", user_id: bob.id, content: phrases.M4 },
        { key: "M5", user_id: charlie.id, content: phrases.M5 },
      ];

      for (const s of messageSeeds) {
        const { data: mRow, error: mErr } = await service
          .from("messages")
          .insert({
            conversation_id: conversationId,
            workspace_id: fixture.workspaceId,
            user_id: s.user_id,
            role: "user",
            content: s.content,
            tool_calls: { sample: `tc-${s.key}` },
            usage: { input_tokens: 1, output_tokens: 1 },
            draft_preview: `draft-${s.key}`,
            action_class: `infra.test_${s.key.toLowerCase()}`,
            template_id: "default_legacy",
            // Expanded MESSAGE_REDACT_FIELDS coverage (#4351 P1 review
            // cross-reconcile): seed every column that must be nulled on
            // a foreign-author row so the AC1 assertions can verify each
            // leak vector closed. `tier` is kept off the `external_*`
            // band to avoid the mig 046 `messages_external_tier_status_
            // check` (external_* tiers require status IN
            // ('draft','archived'); default status is 'complete' here).
            tier: "internal_routing",
            source: `src-${s.key}`,
            owning_domain: "cto",
            urgency: `urgent-${s.key}-phrase`,
            trust_tier: `trust-${s.key}`,
            source_ref: `pr-acme:repo:${s.key}`,
            leader_id: `leader-${s.key}`,
          })
          .select("id")
          .single();
        if (mErr || !mRow) {
          throw new Error(
            `seed message ${s.key} insert failed: ${mErr?.message ?? "no row"}`,
          );
        }
        messageIds[s.key] = (mRow as { id: string }).id;
      }

      // Attachments:
      //   A1 on M1 (Alice)   → preserved
      //   A2 on M2 (Bob)     → redacted
      //   A2b on M4 (Bob)    → redacted (allowlist semantic — foreign-author parent)
      // (Plan called A2b "orphan-shape"; FK ON DELETE CASCADE on
      // message_attachments.message_id makes a literal parent-deleted
      // orphan unconstructible. A2b on M4 hits the SAME code path
      // — `subjectAuthoredMessageIds.has(message_id) === false` — so
      // the allowlist fail-closed contract is exercised.)
      const attachmentSeeds: Array<{ message_id: string; storage_path: string; filename: string }> = [
        { message_id: messageIds.M1, storage_path: attachmentPaths.A1, filename: "alice.png" },
        { message_id: messageIds.M2, storage_path: attachmentPaths.A2, filename: "bob.png" },
        { message_id: messageIds.M4, storage_path: attachmentPaths.A2b, filename: "bob-second.png" },
      ];
      for (const a of attachmentSeeds) {
        const { error: aErr } = await service.from("message_attachments").insert({
          message_id: a.message_id,
          storage_path: a.storage_path,
          filename: a.filename,
          content_type: "image/png",
          size_bytes: 42,
        });
        if (aErr) {
          throw new Error(
            `seed attachment for message ${a.message_id} failed: ${aErr.message}`,
          );
        }
      }
    }, 90_000);

    afterAll(async () => {
      // Reverse order: attachments → messages → conversations → fixture.
      try {
        if (conversationId) {
          // CASCADE will sweep attachments via messages → conversations.
          await service.from("conversations").delete().eq("id", conversationId);
        }
      } catch {
        // best-effort
      }
      try {
        if (fixture) {
          await tearDownSharedWorkspace(service, fixture);
        }
      } catch {
        // best-effort — leaked synthetic emails are bounded by the regex guard.
      }
    }, 60_000);

    test(
      "exportSqlTable: messages predicate redacts foreign-authored rows and pseudonymises user_id consistently",
      async () => {
        const { exportSqlTable } = await import("../server/dsar-export");
        const controller = new AbortController();
        const { randomBytes } = await import("node:crypto");
        const tables = await exportSqlTable.call(null, alice.id, randomBytes(32), controller.signal);

        const messagesTable = tables.find((t) => t.table === "messages");
        expect(messagesTable, "messages block must be present").toBeDefined();
        const rows = (messagesTable!.rows as Array<Record<string, unknown>>).filter(
          (r) => r.conversation_id === conversationId,
        );
        const byId = new Map(rows.map((r) => [r.id as string, r]));

        // M1 — Alice authored, preserved.
        const m1 = byId.get(messageIds.M1)!;
        expect(m1, "M1 present").toBeDefined();
        expect(m1.content).toBe(phrases.M1);
        expect(m1.tool_calls).not.toBeNull();
        expect(m1.usage).not.toBeNull();
        expect(m1.draft_preview).not.toBeNull();
        expect(m1.action_class).not.toBeNull();
        expect(m1.user_id).toBe(alice.id);

        // M2 — Bob authored, redacted; user_id pseudonymised.
        // Coverage spans the expanded MESSAGE_REDACT_FIELDS set (#4351
        // P1 cross-reconcile): tier / source / owning_domain / urgency
        // / trust_tier / source_ref / leader_id / template_id were
        // re-classified from "structural" (plan Reconciliation #2) to
        // "redact" by orthogonal data-integrity + security review.
        const m2 = byId.get(messageIds.M2)!;
        expect(m2.content).toBeNull();
        expect(m2.tool_calls).toBeNull();
        expect(m2.usage).toBeNull();
        expect(m2.draft_preview).toBeNull();
        expect(m2.action_class).toBeNull();
        expect(m2.tier).toBeNull();
        expect(m2.source).toBeNull();
        expect(m2.owning_domain).toBeNull();
        expect(m2.urgency).toBeNull();
        expect(m2.trust_tier).toBeNull();
        expect(m2.source_ref).toBeNull();
        expect(m2.leader_id).toBeNull();
        expect(m2.template_id).toBeNull();
        expect(String(m2.user_id)).toMatch(PSEUDONYM_RE);

        // M3 — legacy NULL, fail-closed: content nulled, user_id stays null.
        const m3 = byId.get(messageIds.M3)!;
        expect(m3.content).toBeNull();
        expect(m3.tool_calls).toBeNull();
        expect(m3.usage).toBeNull();
        expect(m3.draft_preview).toBeNull();
        expect(m3.action_class).toBeNull();
        expect(m3.user_id).toBeNull();

        // M4 — Bob's second message, same pseudonym as M2.
        const m4 = byId.get(messageIds.M4)!;
        expect(m4.content).toBeNull();
        expect(String(m4.user_id)).toBe(String(m2.user_id));

        // M5 — Charlie authored, distinct pseudonym from Bob.
        const m5 = byId.get(messageIds.M5)!;
        expect(m5.content).toBeNull();
        expect(String(m5.user_id)).toMatch(PSEUDONYM_RE);
        expect(String(m5.user_id)).not.toBe(String(m2.user_id));

        // Structural fields preserved on redacted rows.
        for (const m of [m2, m3, m4, m5]) {
          expect(m.id).toBeTruthy();
          expect(m.conversation_id).toBe(conversationId);
          expect(m.role).toBe("user");
          expect(m.created_at).toBeTruthy();
        }

        // Content-level scan: no foreign-author phrase leaks into the bundle's messages block.
        const messagesDump = JSON.stringify(rows);
        expect(messagesDump).toContain(phrases.M1);
        expect(messagesDump).not.toContain(phrases.M2);
        expect(messagesDump).not.toContain(phrases.M3);
        expect(messagesDump).not.toContain(phrases.M4);
        expect(messagesDump).not.toContain(phrases.M5);
      },
      120_000,
    );

    test(
      "exportSqlTable: message_attachments allowlist redacts foreign-author parents",
      async () => {
        const { exportSqlTable } = await import("../server/dsar-export");
        const controller = new AbortController();
        const { randomBytes } = await import("node:crypto");
        const tables = await exportSqlTable.call(null, alice.id, randomBytes(32), controller.signal);

        const attTable = tables.find((t) => t.table === "message_attachments");
        expect(attTable, "message_attachments block present").toBeDefined();
        const rows = (attTable!.rows as Array<Record<string, unknown>>).filter((r) =>
          [messageIds.M1, messageIds.M2, messageIds.M4].includes(String(r.message_id)),
        );
        const byMsg = new Map(rows.map((r) => [String(r.message_id), r]));

        // A1 (Alice/M1) preserved.
        const a1 = byMsg.get(messageIds.M1)!;
        expect(a1.storage_path).toBe(attachmentPaths.A1);
        expect(a1.filename).toBe("alice.png");

        // A2 (Bob/M2) redacted.
        const a2 = byMsg.get(messageIds.M2)!;
        expect(a2.storage_path).toBeNull();
        expect(a2.filename).toBeNull();
        // Structural preserved.
        expect(a2.id).toBeTruthy();
        expect(a2.message_id).toBe(messageIds.M2);
        expect(a2.content_type).toBe("image/png");
        expect(a2.size_bytes).toBe(42);

        // A2b (Bob/M4) redacted via allowlist fail-closed.
        const a2b = byMsg.get(messageIds.M4)!;
        expect(a2b.storage_path).toBeNull();
        expect(a2b.filename).toBeNull();

        // Content-level scan: no foreign-author attachment path leaks.
        const attDump = JSON.stringify(rows);
        expect(attDump).toContain(attachmentPaths.A1);
        expect(attDump).not.toContain(attachmentPaths.A2);
        expect(attDump).not.toContain(attachmentPaths.A2b);
      },
      120_000,
    );

    test(
      "manifest: schema_version === '1.1.0' and redactions[] reflects counts",
      async () => {
        const { exportSqlTable, buildArchiveToDisk } = await import(
          "../server/dsar-export"
        );
        const controller = new AbortController();
        const { randomBytes } = await import("node:crypto");
        const salt = randomBytes(32);
        const tables = await exportSqlTable.call(null, alice.id, salt, controller.signal);
        const jobId = `test-${randomBytes(8).toString("hex")}`;
        const { manifest, localPath } = await buildArchiveToDisk(
          jobId,
          alice.id,
          tables,
          null,
          salt,
          controller.signal,
        );

        try {
          expect(manifest.schema_version).toBe("1.2.0");
          expect(Array.isArray(manifest.redactions)).toBe(true);

          const byPath = new Map(
            (manifest.redactions ?? []).map((r) => [r.path, r]),
          );
          const messagesEntry = byPath.get("tables/messages.json");
          expect(messagesEntry, "messages redaction entry present").toBeDefined();
          expect(messagesEntry!.reason).toBe("art-15-4-rights-of-others");
          // 4 redacted messages: M2, M3, M4, M5 (legacy NULL counts under fail-closed).
          expect(messagesEntry!.count).toBeGreaterThanOrEqual(4);

          const attachmentsEntry = byPath.get("tables/message_attachments.json");
          expect(attachmentsEntry, "attachments redaction entry present").toBeDefined();
          expect(attachmentsEntry!.reason).toBe("art-15-4-rights-of-others");
          // 2 redacted attachments: A2 (Bob/M2), A2b (Bob/M4).
          expect(attachmentsEntry!.count).toBeGreaterThanOrEqual(2);
        } finally {
          await import("node:fs/promises").then((fs) =>
            fs.rm(localPath, { force: true }).catch(() => {}),
          );
        }
      },
      120_000,
    );

    test(
      "observability: emits redaction-counts log line with hashed userId and no PII",
      async () => {
        // Intercept dsar-export's module-load `createChildLogger("dsar-
        // export")` call so the captured `log` reference is our stub.
        // `vi.doMock` (not hoisted) + `vi.resetModules()` + fresh dynamic
        // import is the canonical shape for spying on a module-init call
        // performed at SUT top-level. See learning 2026-05-07-vitest-
        // domock-factory-throw-wrapped-message for related interop notes.
        const infoSpy = vi.fn();
        const childStub: Record<string, unknown> = {
          info: infoSpy,
          warn: vi.fn(),
          error: vi.fn(),
          debug: vi.fn(),
          trace: vi.fn(),
          fatal: vi.fn(),
        };
        childStub.child = vi.fn(() => childStub);

        vi.doMock("../server/logger", async () => {
          const actual = await vi.importActual<
            typeof import("../server/logger")
          >("../server/logger");
          return {
            ...actual,
            default: childStub,
            createChildLogger: () => childStub,
          };
        });

        try {
          vi.resetModules();
          const { exportSqlTable, buildArchiveToDisk } = await import(
            "../server/dsar-export"
          );
          const controller = new AbortController();
          const { randomBytes } = await import("node:crypto");
          const salt = randomBytes(32);
          const tables = await exportSqlTable.call(null, alice.id, salt, controller.signal);
          const jobId = `test-${randomBytes(8).toString("hex")}`;
          const { localPath } = await buildArchiveToDisk(
            jobId,
            alice.id,
            tables,
            null,
            salt,
            controller.signal,
          );

          try {
            // Find the redact-foreign-author info call.
            const redactCall = infoSpy.mock.calls.find((c) => {
              const payload = c[0] as Record<string, unknown> | undefined;
              return payload?.op === "redact-foreign-author";
            });
            expect(redactCall, "redact-foreign-author log emitted").toBeDefined();
            const payload = redactCall![0] as Record<string, unknown>;
            expect(payload.feature).toBe("dsar-export");
            expect(payload.userIdHash).toMatch(/^[0-9a-f]{32,}$/);
            const r = payload.redactions as { messages: number; message_attachments: number };
            expect(r.messages).toBeGreaterThanOrEqual(4);
            expect(r.message_attachments).toBeGreaterThanOrEqual(2);

            // No PII leakage in the payload.
            const dumped = JSON.stringify(payload);
            expect(dumped, "no raw userId").not.toContain(alice.id);
            expect(dumped, "no raw bob id").not.toContain(bob.id);
            expect(dumped, "no raw charlie id").not.toContain(charlie.id);
            expect(dumped, "no content").not.toContain(phrases.M1);
            expect(dumped, "no content").not.toContain(phrases.M2);
            expect(dumped, "no salt").not.toMatch(/pseudonymSalt|salt/i);
          } finally {
            await import("node:fs/promises").then((fs) =>
              fs.rm(localPath, { force: true }).catch(() => {}),
            );
          }
        } finally {
          vi.doUnmock("../server/logger");
          vi.resetModules();
        }
      },
      120_000,
    );

    test(
      "scope-sanity: subject viewing own messages is not pseudonymised, and CrossTenantViolation class is exported",
      async () => {
        // Renamed (#4351 review — code-quality #7, test-design #1) to
        // match what this test actually exercises: a subject-scope
        // sanity check + an exported-class probe. The TR3 ordering
        // invariant (assertReadScope BEFORE redaction) is properly
        // exercised by dsar-export-cross-tenant.integration.test.ts;
        // duplicating its service-role-glitch fixture here would not
        // add coverage.
        const { exportSqlTable, CrossTenantViolation } = await import(
          "../server/dsar-export"
        );
        const controller = new AbortController();
        const { randomBytes } = await import("node:crypto");
        const tablesForBob = await exportSqlTable.call(null, bob.id, randomBytes(32), controller.signal);
        // Bob's own messages block should NOT pseudonymise Bob's user_id
        // (he's the subject) — sanity check that the predicate is
        // scoped-correct, not over-applied.
        const bobMsgs = tablesForBob.find((t) => t.table === "messages");
        if (bobMsgs) {
          for (const row of bobMsgs.rows as Array<Record<string, unknown>>) {
            if (row.user_id === bob.id) {
              // Bob viewing his own row — content preserved.
              expect(row.content).not.toBeNull();
            }
          }
        }

        // CrossTenantViolation surface exists.
        expect(CrossTenantViolation.name).toBe("CrossTenantViolation");
      },
      120_000,
    );
  },
);
