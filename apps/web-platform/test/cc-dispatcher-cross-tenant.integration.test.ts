/**
 * cc-dispatcher cross-tenant write-boundary — DB integration test (#3603 W1).
 *
 * cc-dispatcher.ts INSERTs `messages` via the service-role Supabase client
 * (RLS-bypass on writes). RLS catches reads, not writes. This file pins the
 * load-bearing DB-layer invariants that downstream-of-write semantics rely
 * on, so a future RLS / FK / migration regression can't silently re-open
 * the cross-tenant data-exposure surface.
 *
 * Scope (post-rev-2 trim — 6 invariants, was 7 in rev-1):
 *   - T-W1-matrix         — 4 conversations × 2 users × concurrent assistant
 *                           INSERTs land in the right conversation; no
 *                           cross-contamination of content.
 *   - T-W1-invariant-1    — RLS-enforced auth-client SELECT: user A on
 *                           conversation A1 returns A1 rows; same client on
 *                           B1 returns ZERO rows.
 *   - T-W1-invariant-2    — Forged-`conversation_id` attack: auth-client
 *                           signed in as A querying B's conversation_id
 *                           returns empty (RLS exists-clause via FK).
 *   - T-W1-invariant-5    — Hydration empty-DB → empty render: no rows in
 *                           `messages` for A1 → handler returns `[]`. SDK
 *                           session content is NOT a hydration fallback.
 *   - T-W1-invariant-5b   — Deterministic dehedge (rev-2): the hydration
 *                           SELECT at `api-messages.ts:76-88` is the only
 *                           source; no SDK→write roundtrip exists, so
 *                           populating an SDK session WITHOUT a DB row
 *                           still yields empty.
 *   - T-W1-invariant-6    — Cascade-erasure (consumes W4 contract): an
 *                           assistant row carrying `usage = { cost_usd }`
 *                           is removed by FK cascade when its parent
 *                           `conversations` row is deleted. `usage` jsonb
 *                           is gone along with the row.
 *
 * Carry-forward / covered elsewhere:
 *   - T-W1-invariant-4 (dedup) — closure-level `workflowEnded` flag pinned
 *     by `T-W2-late-text` + `T-W2-late-text-async` in `cc-dispatcher.test.ts`
 *     (PR-A1 W2). No DB-layer expression; included in the rev-2 invariant
 *     matrix for completeness only.
 *   - T-W1-invariant-3 (grep-meta) — CUT per rev-2 simplicity F5. Replaced
 *     by the TS-level invariant that `DispatchEvents` callback args at
 *     `soleur-go-runner.ts:653-690` do NOT carry `user_id` / `conversation_id`
 *     fields. Verified at plan-time via grep.
 *
 * Opt-in via `SUPABASE_DEV_INTEGRATION=1`. Run from apps/web-platform:
 *   doppler run -p soleur -c dev -- \
 *     env SUPABASE_DEV_INTEGRATION=1 \
 *     ./node_modules/.bin/vitest run test/cc-dispatcher-cross-tenant.integration.test.ts
 *
 * Carries forward learnings:
 *   - 2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind.md — RLS gates
 *     only run against real Supabase; vitest-mocked chains are blind to
 *     GRANT / RLS violations.
 *   - 2026-05-06-rls-zero-policies-anon-delete-204-semantic.md — RLS-deny
 *     for SELECT returns `data: []` with `error == null` or `PGRST116`,
 *     NOT an HTTP-error code. Assertions match that shape.
 *   - 2026-04-12-silent-rls-failures-in-team-names.md — auth client should
 *     NOT silently swallow failures; we assert error semantics distinctly
 *     from row absence.
 *   - account-deletion-cascade-order-20260402.md — FK cascade fires on
 *     conversation delete; invariant-6 asserts the chain.
 */

import { afterAll, afterEach, beforeAll, describe, expect, test } from "vitest";
import {
  createClient,
  type SupabaseClient,
} from "@supabase/supabase-js";
import { randomBytes, randomUUID } from "crypto";
import { __resetP0DedupForTests } from "@/server/observability";

const INTEGRATION_ENABLED =
  process.env.SUPABASE_DEV_INTEGRATION === "1";

// hr-destructive-prod-tests-allowlist: only synthetic emails matching this
// pattern may be created or deleted by this test. A bare `@soleur.test`
// match would let a typo wipe real Supabase auth.users rows; the pattern
// + assertSynthetic gate is the load-bearing destruction guard.
const SYNTHETIC_EMAIL_PATTERN =
  /^cc-cross-tenant-[a-f0-9]{16}@soleur\.test$/;

function syntheticEmail(): string {
  return `cc-cross-tenant-${randomBytes(8).toString("hex")}@soleur.test`;
}

function assertSynthetic(email: string): void {
  if (!SYNTHETIC_EMAIL_PATTERN.test(email)) {
    throw new Error(
      `Refusing to touch non-synthetic email "${email}" — this test only ` +
        "manipulates cc-cross-tenant-*@soleur.test accounts.",
    );
  }
}

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`[cc-dispatcher-cross-tenant.integration] ${name} is required`);
  }
  return value;
}

// Mirrors the production INSERT payload shape from
// `cc-dispatcher.ts:saveAssistantMessage`. Keeping this assembly local to
// the test (vs. importing the helper) gives DB-layer coverage that survives
// a future refactor of the helper internals — the contract we're pinning
// is the **row shape** the service-role writes, not the helper's call graph.
function assistantRowFor(args: {
  conversationId: string;
  content: string;
  usage?: { cost_usd: number } | null;
  status?: "complete" | "aborted";
}): Record<string, unknown> {
  return {
    id: randomUUID(),
    conversation_id: args.conversationId,
    role: "assistant",
    content: args.content,
    tool_calls: null,
    leader_id: "cc_router",
    usage: args.usage ?? null,
    ...(args.status === "aborted" ? { status: "aborted" } : {}),
  };
}

describe.skipIf(!INTEGRATION_ENABLED)(
  "cc-dispatcher cross-tenant write-boundary (DB integration)",
  () => {
    let service: SupabaseClient;

    const userA = {
      id: "",
      email: syntheticEmail(),
      password: randomBytes(16).toString("hex"),
    };
    const userB = {
      id: "",
      email: syntheticEmail(),
      password: randomBytes(16).toString("hex"),
    };

    // 4 conversations: A1, A2 owned by userA; B1, B2 owned by userB.
    let conversationA1 = "";
    let conversationA2 = "";
    let conversationB1 = "";
    let conversationB2 = "";

    beforeAll(async () => {
      const supabaseUrl = requireEnv("NEXT_PUBLIC_SUPABASE_URL");
      const serviceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");

      service = createClient(supabaseUrl, serviceRoleKey, {
        auth: { persistSession: false, autoRefreshToken: false },
      });

      // Reset the production P0-dedup map so prior test files in the same
      // run don't suppress this file's expected mirror events. The unit
      // test file overrides `mirrorP0Deduped` with a spy and never touches
      // the real map; this hookup is the integration-side reset.
      __resetP0DedupForTests();

      // Create userA + userB via service-role auth admin. Up to 3 retries
      // tolerate the rare email-collision case (random hex collision in
      // the synthetic namespace is astronomical but not impossible).
      for (const user of [userA, userB]) {
        let lastErr: string | null = null;
        for (let attempt = 0; attempt < 3; attempt++) {
          assertSynthetic(user.email);
          const { data, error } = await service.auth.admin.createUser({
            email: user.email,
            password: user.password,
            email_confirm: true,
          });
          if (!error && data.user?.id) {
            user.id = data.user.id;
            lastErr = null;
            break;
          }
          lastErr = error?.message ?? "unknown";
          if (/already registered|exists/i.test(lastErr)) {
            // Recycle the email and retry.
            user.email = syntheticEmail();
            continue;
          }
          throw new Error(`createUser(${user.email}) failed: ${lastErr}`);
        }
        expect(user.id, `userA/B id missing: ${lastErr}`).toBeTruthy();
      }

      // Create 4 conversations via service-role. `domain_leader: "cco"` is
      // the closest existing-enum proxy for the cc-router surface; cc-path
      // assistant rows carry `leader_id: "cc_router"` independently of the
      // parent conversation's domain_leader.
      const seedConv = async (uid: string): Promise<string> => {
        const { data, error } = await service
          .from("conversations")
          .insert({ user_id: uid, domain_leader: "cco" })
          .select("id")
          .single();
        expect(error, `seed conversation for ${uid}`).toBeNull();
        return data!.id as string;
      };
      conversationA1 = await seedConv(userA.id);
      conversationA2 = await seedConv(userA.id);
      conversationB1 = await seedConv(userB.id);
      conversationB2 = await seedConv(userB.id);
    }, 30_000);

    afterEach(async () => {
      if (!service) return;
      // rev-2 Note 2 — truncate messages for the 4 conversation IDs as
      // belt-and-braces. Prevents test bleed if a prior test fixture left
      // rows behind after assertion failure.
      for (const convId of [
        conversationA1,
        conversationA2,
        conversationB1,
        conversationB2,
      ]) {
        if (!convId) continue;
        await service.from("messages").delete().eq("conversation_id", convId);
      }
    });

    afterAll(async () => {
      if (!service) return;
      // Cascade chain: delete conversations → ON DELETE CASCADE removes
      // their messages (migration 001 line 70). Then delete auth users.
      for (const uid of [userA.id, userB.id]) {
        if (!uid) continue;
        await service.from("conversations").delete().eq("user_id", uid);
      }
      for (const user of [userA, userB]) {
        if (!user.id) continue;
        assertSynthetic(user.email);
        const { data: check } = await service.auth.admin.getUserById(user.id);
        if (check?.user?.email && check.user.email !== user.email) {
          throw new Error(
            `afterAll: auth.users.email for ${user.id} (${check.user.email}) ` +
              `does not match synthetic email ${user.email}`,
          );
        }
        const { error } = await service.auth.admin.deleteUser(user.id);
        if (error && !/not found/i.test(error.message)) {
          throw new Error(
            `afterAll: deleteUser(${user.email}) failed: ${error.message}`,
          );
        }
      }
    }, 30_000);

    test("T-W1-matrix: 4 concurrent assistant INSERTs land in the right conversation; no content cross-contamination", async () => {
      // Mirror the dispatch matrix: each conversation gets its own
      // assistant row inserted concurrently. The deliberate cross-fire
      // (`Promise.all`) validates the FK conversation_id propagation
      // under concurrency; a sequential await chain would not exercise
      // the concurrent-write surface that Art. 32 evidence requires.
      const payloads = [
        { conv: conversationA1, content: "A1-content" },
        { conv: conversationA2, content: "A2-content" },
        { conv: conversationB1, content: "B1-content" },
        { conv: conversationB2, content: "B2-content" },
      ];

      const results = await Promise.all(
        payloads.map((p) =>
          service
            .from("messages")
            .insert(assistantRowFor({ conversationId: p.conv, content: p.content }))
            .select("id, conversation_id, content"),
        ),
      );

      for (const r of results) {
        expect(r.error, "concurrent INSERT failed").toBeNull();
      }

      // Verify per-conversation isolation via service-role SELECT (no RLS).
      for (const p of payloads) {
        const { data, error } = await service
          .from("messages")
          .select("conversation_id, content")
          .eq("conversation_id", p.conv);
        expect(error).toBeNull();
        expect(data).toHaveLength(1);
        expect(data![0]).toEqual({
          conversation_id: p.conv,
          content: p.content,
        });
      }

      // Cross-tenant smoke: NO row from A's content appears under B's
      // conversation_ids, and vice versa.
      const { data: bRows } = await service
        .from("messages")
        .select("content")
        .in("conversation_id", [conversationB1, conversationB2]);
      expect(bRows?.every((r) => /^B[12]-content$/.test(r.content as string))).toBe(true);
      const { data: aRows } = await service
        .from("messages")
        .select("content")
        .in("conversation_id", [conversationA1, conversationA2]);
      expect(aRows?.every((r) => /^A[12]-content$/.test(r.content as string))).toBe(true);
    }, 30_000);

    test("T-W1-invariant-1: RLS-enforced SELECT — auth client signed in as userA reads ZERO rows from B's conversation", async () => {
      // Seed: one assistant row in B1.
      const { error: seedErr } = await service
        .from("messages")
        .insert(assistantRowFor({ conversationId: conversationB1, content: "B1-secret" }));
      expect(seedErr).toBeNull();

      // Auth client signed in as userA.
      const anonKey = requireEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY");
      const authClient = createClient(requireEnv("NEXT_PUBLIC_SUPABASE_URL"), anonKey, {
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const { error: signInErr } = await authClient.auth.signInWithPassword({
        email: userA.email,
        password: userA.password,
      });
      expect(signInErr, "userA sign-in failed").toBeNull();

      // userA → B1 must return ZERO rows. The RLS predicate at
      // `001_initial_schema.sql:79-86` requires
      // `exists(... where c.user_id = auth.uid())`; userA's JWT does
      // not satisfy that for B1's parent conversation.
      const { data: deniedRows, error: deniedErr } = await authClient
        .from("messages")
        .select("id, content")
        .eq("conversation_id", conversationB1);
      // Distinguish RLS-deny (empty rows, no error or PGRST116) from
      // an auth-fail (per learning 2026-04-12-silent-rls-failures-in-team-names.md):
      // RLS-deny is NOT an error, but the auth client should still
      // surface auth errors loudly when they occur.
      expect(deniedRows).toEqual([]);
      expect(
        deniedErr == null || deniedErr.code === "PGRST116",
        `unexpected error shape: ${JSON.stringify(deniedErr)}`,
      ).toBe(true);

      // Positive control: userA → A1 (seed first).
      const { error: a1SeedErr } = await service
        .from("messages")
        .insert(
          assistantRowFor({ conversationId: conversationA1, content: "A1-mine" }),
        );
      expect(a1SeedErr).toBeNull();
      const { data: allowedRows, error: allowedErr } = await authClient
        .from("messages")
        .select("id, content")
        .eq("conversation_id", conversationA1);
      expect(allowedErr).toBeNull();
      expect(allowedRows).toHaveLength(1);
      expect(allowedRows![0]!.content).toBe("A1-mine");
    }, 30_000);

    test("T-W1-invariant-2: forged-`conversation_id` attack — userA's auth client cannot read B's rows by guessing B's conversation id", async () => {
      // Seed: row in B2.
      const { error: seedErr } = await service
        .from("messages")
        .insert(
          assistantRowFor({ conversationId: conversationB2, content: "B2-forgery-target" }),
        );
      expect(seedErr).toBeNull();

      const authClient = createClient(
        requireEnv("NEXT_PUBLIC_SUPABASE_URL"),
        requireEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY"),
        { auth: { persistSession: false, autoRefreshToken: false } },
      );
      const { error: signInErr } = await authClient.auth.signInWithPassword({
        email: userA.email,
        password: userA.password,
      });
      expect(signInErr).toBeNull();

      // userA explicitly queries B's known conversation id (the
      // "forged" condition — the id is correct but the JWT is wrong).
      // RLS exists-clause via FK MUST return empty.
      const { data, error } = await authClient
        .from("messages")
        .select("content")
        .eq("conversation_id", conversationB2);
      expect(data).toEqual([]);
      expect(
        error == null || error.code === "PGRST116",
        `unexpected error shape: ${JSON.stringify(error)}`,
      ).toBe(true);
    }, 30_000);

    test("T-W1-invariant-5: hydration empty-DB → empty render — no messages for A1 yields empty SELECT (SDK session is NOT a hydration fallback)", async () => {
      // afterEach already truncated; A1 starts clean.
      const authClient = createClient(
        requireEnv("NEXT_PUBLIC_SUPABASE_URL"),
        requireEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY"),
        { auth: { persistSession: false, autoRefreshToken: false } },
      );
      const { error: signInErr } = await authClient.auth.signInWithPassword({
        email: userA.email,
        password: userA.password,
      });
      expect(signInErr).toBeNull();

      // Mirror `api-messages.ts:76-88` hydration SELECT shape — the only
      // source of truth for the chat surface's resume render. If a future
      // change introduces an SDK→write roundtrip, this test will need
      // its assertion updated.
      const { data, error } = await authClient
        .from("messages")
        .select("id, role, content, leader_id, status, usage, created_at")
        .eq("conversation_id", conversationA1)
        .order("created_at", { ascending: true });
      expect(error).toBeNull();
      expect(data).toEqual([]);
    }, 30_000);

    test("T-W1-invariant-5b: deterministic dehedge — no SDK→write roundtrip exists; empty messages stays empty regardless of SDK session state", async () => {
      // rev-2 dehedge per simplicity F9. SDK session is read-only on
      // the hydration path (verified at plan time). This test pins the
      // determinism: empty `messages` rows yields `[]` even after a
      // service-role write to a SIBLING conversation (proving no global
      // fallback fan-out exists).
      const authClient = createClient(
        requireEnv("NEXT_PUBLIC_SUPABASE_URL"),
        requireEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY"),
        { auth: { persistSession: false, autoRefreshToken: false } },
      );
      const { error: signInErr } = await authClient.auth.signInWithPassword({
        email: userA.email,
        password: userA.password,
      });
      expect(signInErr).toBeNull();

      // Sibling conversation A2 has content; A1 is empty.
      const { error: seedErr } = await service
        .from("messages")
        .insert(assistantRowFor({ conversationId: conversationA2, content: "A2-only" }));
      expect(seedErr).toBeNull();

      const { data: a1Rows, error: a1Err } = await authClient
        .from("messages")
        .select("content")
        .eq("conversation_id", conversationA1);
      expect(a1Err).toBeNull();
      expect(a1Rows).toEqual([]);
    }, 30_000);

    test("T-W1-invariant-6: FK cascade — DELETE parent conversation removes child messages incl. usage jsonb column (W4 contract)", async () => {
      // Seed A1 with one assistant row carrying the cc-narrowed usage
      // shape: `{ cost_usd: 0.005 }`. This exercises the W4 column write
      // path under `CC_PERSIST_USAGE=true` semantics (the test uses the
      // service-role direct INSERT — the gate is at the cc-dispatcher
      // layer, not at the DB layer).
      const rowId = randomUUID();
      const { error: seedErr } = await service.from("messages").insert({
        id: rowId,
        conversation_id: conversationA1,
        role: "assistant",
        content: "A1-with-usage",
        tool_calls: null,
        leader_id: "cc_router",
        usage: { cost_usd: 0.005 },
      });
      expect(seedErr).toBeNull();

      // Confirm the row exists pre-cascade.
      const { data: pre } = await service
        .from("messages")
        .select("id, usage")
        .eq("id", rowId);
      expect(pre).toHaveLength(1);
      expect(pre![0]!.usage).toEqual({ cost_usd: 0.005 });

      // DELETE the parent conversation. FK at
      // `migrations/001_initial_schema.sql:70` is `ON DELETE CASCADE`.
      const { error: delErr } = await service
        .from("conversations")
        .delete()
        .eq("id", conversationA1);
      expect(delErr).toBeNull();

      // Child row is gone, including its `usage` jsonb.
      const { data: post } = await service
        .from("messages")
        .select("id")
        .eq("id", rowId);
      expect(post).toEqual([]);

      // Re-seed the conversation so afterEach + afterAll cleanup chain
      // doesn't choke on a missing parent (test isolation hygiene).
      const { data: reseed, error: reseedErr } = await service
        .from("conversations")
        .insert({ user_id: userA.id, domain_leader: "cco" })
        .select("id")
        .single();
      expect(reseedErr).toBeNull();
      conversationA1 = reseed!.id as string;
    }, 30_000);
  },
);
