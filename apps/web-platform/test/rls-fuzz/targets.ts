// Per-table isolation registry (#6256, ADR-111, AC1/AC2/AC3).
//
// The catalog (catalog.ts) is the ENUMERATOR; this registry supplies the faithful
// per-table seed + attack SQL. The driver asserts registry ⇔ catalog (AC1): a new
// isolated table with no entry here fails the coverage gate, and an entry naming a
// table the catalog no longer classifies as isolated fails too. Seeds are hand-
// written (heterogeneous columns/FKs/CHECKs across 18 tables), never generic —
// but every seed is validated against the live migrated schema, and the driver's
// service_role `count=1` precondition (AC2) proves each seed actually landed a row
// before any tenant-B `count=0` is read as "denied" rather than "empty".

import { randomUUID } from "node:crypto";
import type postgres from "postgres";

type Handle = postgres.Sql<{}> | postgres.TransactionSql<{}>;

/** Synthetic two-tenant fixture (cq-test-fixtures-synthesized-only). */
export interface Ctx {
  userA: string;
  userB: string;
  /** A co-member of wsA — the byok_delegations grantee (its trigger requires a real member). */
  userC: string;
  wsA: string;
  wsB: string;
  orgA: string;
  /** An A-owned conversation (parent for messages / user_concurrency_slots seeds). */
  convA: string;
  /** A second A-owned conversation — the ucs INSERT-forge needs a non-colliding (user,conv) pair. */
  convA2: string;
}

/** A WHERE clause + params that uniquely identify A's seeded canonical row. */
export interface Locate {
  where: string;
  params: unknown[];
}

export interface Target {
  table: string;
  /** A real column to self-assign in the UPDATE attack (`SET col = col`); value irrelevant. */
  updateCol: string;
  /** Ensure A's canonical row exists on the base (service_role) handle; return its locate. */
  seed(base: Handle, ctx: Ctx): Promise<Locate>;
  /**
   * The cross-tenant INSERT-forge attack: insert an A-owned-scope row under the
   * attack handle with FRESH unique values (so a real leak surfaces as a committed
   * row, never masked by a 23505 unique_violation). `undefined` when the table has
   * a BEFORE-INSERT trigger/validation that fires ahead of the RLS WITH CHECK and
   * would raise a non-42501 error — those tables still get UPDATE + DELETE attacks.
   */
  forge?(h: Handle, ctx: Ctx): Promise<unknown>;
  /**
   * When true, the table's PERMISSIVE SELECT policy references `auth.users`
   * (mig 075), which `authenticated` cannot read (no grant) — so an authenticated
   * SELECT raises 42501 "permission denied for table users" for EVERY tenant,
   * A and B alike. That is a grant-layer property, not a tenant decision, so the
   * SELECT positive-control is skipped and a permission-denied on the cross-tenant
   * SELECT counts as a denial. The load-bearing isolation proof for this table is
   * then the service_role count=1 precondition + the write-side attacks (INSERT /
   * UPDATE / DELETE never read auth.users). Whether prod carries the same
   * auth.users grant is checked by the prod-parity diff (AC6).
   */
  selectAuthBlocked?: boolean;
}

/**
 * Workspace-tenancy RLS tables (carry `workspace_id`/`message_id`) that are NOT
 * base-matrix targets, each with a rationale (AC1b coverage gate). These are
 * isolated by a non-`is_workspace_member` predicate or belong to a distinct
 * isolation dimension; excluding them here (rather than letting them silently
 * escape the predicate-based enumerator) keeps the gap TRACKED — a new
 * workspace-scoped table reds the suite until it is a target or listed here.
 * Deepening these into real base-table targets is tracked in the harness-hardening
 * follow-up issue.
 */
export const EXCLUDED_ISOLATION: Record<string, string> = {
  message_attachments:
    "attachment OBJECT isolation is covered by storage.objects (AC9); the metadata-row RLS is an EXISTS-join through messages (itself a fuzzed target) — direct base-table target deferred",
  inbox_item:
    "workspace-owner-gated inbox; cross-tenant write is exercised via the set_inbox_item_state RPC attack (AC8) — direct base-table target deferred",
  email_triage_items:
    "single-founder operator inbox (resend ingest), not multi-tenant workspace data; a faithful seed needs the full ingest fixture — deferred",
  dsar_export_jobs:
    "GDPR DSAR export jobs; user/workspace-scoped, a distinct user-isolation dimension the base matrix (sub=userB non-member) does not model — deferred",
  workspace_member_actions:
    "member-action audit view; workspace-owner-gated read — direct base-table target deferred",
  action_sends:
    "WORM outbound-send audit; user/message-scoped (distinct user-isolation dimension), anonymise-only writes — deferred",
};

const idLocate = (id: string): Locate => ({ where: "id = $1", params: [id] });

export const ISOLATION_TARGETS: Target[] = [
  // ---- onboarding-created tenant-root rows (no seed insert; forge is default-deny) ----
  {
    table: "workspaces",
    updateCol: "name",
    seed: async (_b, c) => ({ where: "id = $1", params: [c.wsA] }),
    // forge omitted: workspaces has bootstrap triggers that fire before RLS.
  },
  {
    table: "workspace_members",
    updateCol: "role",
    seed: async (_b, c) => ({ where: "workspace_id = $1 and user_id = $2", params: [c.wsA, c.userA] }),
    forge: (h, c) =>
      h`insert into workspace_members (workspace_id, user_id, role) values (${c.wsA}, ${c.userB}, 'member')`,
  },
  {
    table: "organizations",
    updateCol: "name",
    seed: async (_b, c) => ({ where: "id = $1", params: [c.orgA] }),
    // forge omitted: organizations rows are created by the onboarding path only.
  },

  // ---- workspace-keyed rows (is_workspace_member(workspace_id, uid)) ----
  {
    table: "workspace_activity",
    updateCol: "workspace_id",
    seed: async (b, c) => {
      const [{ id }] = await b`insert into workspace_activity (workspace_id, event_type) values (${c.wsA}, 'rls-fuzz-seed') returning id`;
      return idLocate(id);
    },
    forge: (h, c) => h`insert into workspace_activity (workspace_id, event_type) values (${c.wsA}, 'rls-fuzz-forge')`,
  },
  {
    table: "messages",
    updateCol: "workspace_id",
    seed: async (b, c) => {
      const [{ id }] = await b`insert into messages (workspace_id, template_id, conversation_id, role, content)
        values (${c.wsA}, 'work', ${c.convA}, 'user', 'rls-fuzz-seed') returning id`;
      return idLocate(id);
    },
    forge: (h, c) =>
      h`insert into messages (workspace_id, template_id, conversation_id, role, content)
        values (${c.wsA}, 'work', ${c.convA}, 'user', 'rls-fuzz-forge')`,
  },
  {
    table: "push_subscriptions",
    updateCol: "endpoint",
    seed: async (b, c) => {
      const [{ id }] = await b`insert into push_subscriptions (user_id, workspace_id, endpoint, p256dh, auth)
        values (${c.userA}, ${c.wsA}, ${`https://push.test/${randomUUID()}`}, 'p', 'au') returning id`;
      return idLocate(id);
    },
    forge: (h, c) =>
      h`insert into push_subscriptions (user_id, workspace_id, endpoint, p256dh, auth)
        values (${c.userA}, ${c.wsA}, ${`https://push.test/${randomUUID()}`}, 'p', 'au')`,
  },
  {
    table: "scope_grants",
    updateCol: "tier",
    seed: async (b, c) => {
      const [{ id }] = await b`insert into scope_grants (founder_id, workspace_id, action_class, tier)
        values (${c.userA}, ${c.wsA}, ${`general.${randomUUID().slice(0, 8)}`}, 'auto') returning id`;
      return idLocate(id);
    },
    forge: (h, c) =>
      h`insert into scope_grants (founder_id, workspace_id, action_class, tier)
        values (${c.userA}, ${c.wsA}, ${`general.${randomUUID().slice(0, 8)}`}, 'auto')`,
  },
  {
    table: "user_concurrency_slots",
    updateCol: "workspace_id",
    seed: async (b, c) => {
      const [{ id }] = await b`insert into user_concurrency_slots (user_id, workspace_id, conversation_id)
        values (${c.userA}, ${c.wsA}, ${c.convA}) returning id`;
      return idLocate(id);
    },
    // forge uses convA2 so the (user_id, conversation_id) unique tuple doesn't collide with the seed.
    forge: (h, c) =>
      h`insert into user_concurrency_slots (user_id, workspace_id, conversation_id)
        values (${c.userA}, ${c.wsA}, ${c.convA2})`,
  },
  {
    table: "worktree_write_lease",
    updateCol: "host_id",
    seed: async (b, c) => {
      const wt = `wt-${randomUUID()}`;
      await b`insert into worktree_write_lease (workspace_id, worktree_id, host_id) values (${c.wsA}, ${wt}, 'h')`;
      return { where: "workspace_id = $1 and worktree_id = $2", params: [c.wsA, wt] };
    },
    forge: (h, c) =>
      h`insert into worktree_write_lease (workspace_id, worktree_id, host_id) values (${c.wsA}, ${`wt-${randomUUID()}`}, 'h')`,
  },
  {
    table: "workspace_member_attestations",
    updateCol: "workspace_id",
    seed: async (b, c) => {
      const [{ id }] = await b`insert into workspace_member_attestations (workspace_id, inviter_user_id, invitee_user_id)
        values (${c.wsA}, ${c.userA}, ${c.userA}) returning id`;
      return idLocate(id);
    },
    forge: (h, c) =>
      h`insert into workspace_member_attestations (workspace_id, inviter_user_id, invitee_user_id)
        values (${c.wsA}, ${c.userA}, ${c.userA})`,
  },
  {
    table: "workspace_member_removals",
    updateCol: "workspace_id",
    seed: async (b, c) => {
      const [{ id }] = await b`insert into workspace_member_removals (workspace_id, removed_user_id, removed_by_user_id)
        values (${c.wsA}, ${c.userA}, ${c.userA}) returning id`;
      return idLocate(id);
    },
    forge: (h, c) =>
      h`insert into workspace_member_removals (workspace_id, removed_user_id, removed_by_user_id)
        values (${c.wsA}, ${c.userA}, ${c.userA})`,
  },
  {
    table: "workspace_invitations",
    updateCol: "role",
    selectAuthBlocked: true, // SELECT policy subqueries auth.users (mig 075) → 42501 for all authenticated
    seed: async (b, c) => {
      const [{ id }] = await b`insert into workspace_invitations (workspace_id, token_hash, role, expires_at, inviter_user_id)
        values (${c.wsA}, ${`h-${randomUUID()}`}, 'member', now() + interval '1 day', ${c.userA}) returning id`;
      return idLocate(id);
    },
    forge: (h, c) =>
      h`insert into workspace_invitations (workspace_id, token_hash, role, expires_at, inviter_user_id)
        values (${c.wsA}, ${`h-${randomUUID()}`}, 'member', now() + interval '1 day', ${c.userA})`,
  },
  {
    table: "audit_byok_use",
    updateCol: "workspace_id",
    seed: async (b, c) => {
      const [{ id }] = await b`insert into audit_byok_use (invocation_id, agent_role, token_count, unit_cost_cents, workspace_id, founder_id)
        values (${randomUUID()}, 'r', 1, 1, ${c.wsA}, ${c.userA}) returning id`;
      return idLocate(id);
    },
    forge: (h, c) =>
      h`insert into audit_byok_use (invocation_id, agent_role, token_count, unit_cost_cents, workspace_id, founder_id)
        values (${randomUUID()}, 'r', 1, 1, ${c.wsA}, ${c.userA})`,
  },
  {
    table: "audit_github_token_use",
    updateCol: "workspace_id",
    seed: async (b, c) => {
      const [{ id }] = await b`insert into audit_github_token_use (installation_id, endpoint, workspace_id, founder_id)
        values (1, ${`/x/${randomUUID().slice(0, 8)}`}, ${c.wsA}, ${c.userA}) returning id`;
      return idLocate(id);
    },
    forge: (h, c) =>
      h`insert into audit_github_token_use (installation_id, endpoint, workspace_id, founder_id)
        values (1, ${`/x/${randomUUID().slice(0, 8)}`}, ${c.wsA}, ${c.userA})`,
  },
  {
    table: "byok_delegations",
    updateCol: "workspace_id",
    // grantee must be a member of wsA (byok_delegations_check_same_workspace trigger); userC is seeded as co-member.
    seed: async (b, c) => {
      const [{ id }] = await b`insert into byok_delegations (grantor_user_id, grantee_user_id, workspace_id, created_by_user_id, daily_usd_cap_cents, hourly_usd_cap_cents)
        values (${c.userA}, ${c.userC}, ${c.wsA}, ${c.userA}, 1000, 100) returning id`;
      return idLocate(id);
    },
    // forge omitted: the same-workspace/cap CHECK + membership trigger fire before RLS WITH CHECK.
  },

  // ---- user-keyed rows (user_id = auth.uid(); workspace visibility overlaid) ----
  {
    table: "conversations",
    updateCol: "workspace_id",
    seed: async (b, c) => {
      const [{ id }] = await b`insert into conversations (id, user_id, workspace_id, status, visibility)
        values (${randomUUID()}, ${c.userA}, ${c.wsA}, 'active', 'workspace') returning id`;
      return idLocate(id);
    },
    // forge forges A's ownership (user_id = userA) — violates the with_check user_id = auth.uid() for tenant-B.
    forge: (h, c) =>
      h`insert into conversations (id, user_id, workspace_id, status, visibility)
        values (${randomUUID()}, ${c.userA}, ${c.wsA}, 'active', 'workspace')`,
  },
  {
    table: "kb_files",
    updateCol: "file_path",
    seed: async (b, c) => {
      const [{ id }] = await b`insert into kb_files (workspace_id, user_id, file_path, filename, visibility)
        values (${c.wsA}, ${c.userA}, ${`/a/${randomUUID()}`}, 'a', 'workspace') returning id`;
      return idLocate(id);
    },
    forge: (h, c) =>
      h`insert into kb_files (workspace_id, user_id, file_path, filename, visibility)
        values (${c.wsA}, ${c.userA}, ${`/a/${randomUUID()}`}, 'a', 'workspace')`,
  },
  {
    table: "kb_share_links",
    updateCol: "document_path",
    seed: async (b, c) => {
      const [{ id }] = await b`insert into kb_share_links (user_id, workspace_id, token, document_path, content_sha256)
        values (${c.userA}, ${c.wsA}, ${`tok-${randomUUID()}`}, ${`/a/${randomUUID()}`}, ${"a".repeat(64)}) returning id`;
      return idLocate(id);
    },
    forge: (h, c) =>
      h`insert into kb_share_links (user_id, workspace_id, token, document_path, content_sha256)
        values (${c.userA}, ${c.wsA}, ${`tok-${randomUUID()}`}, ${`/a/${randomUUID()}`}, ${"a".repeat(64)})`,
  },
];
