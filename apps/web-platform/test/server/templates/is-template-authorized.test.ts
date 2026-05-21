/**
 * PR-I (#4078) — isTemplateAuthorized predicate unit tests (TR4 + exception path).
 *
 * Covers:
 *   (a) first_send: no existing row → predicate returns { status: 'first_send', grantId }.
 *   (b) authorized: active row with bounds in range → { status: 'authorized', rowId, sendsUsed }.
 *   (c) denied/revoked: row exists with revoked_at NOT NULL → { status: 'denied', reason: 'template_revoked' }.
 *   (d) denied/expired: row exists with expires_at <= now → { status: 'denied', reason: 'template_expired' };
 *       auto-revoke side effect fires.
 *   (e) denied/quota_exhausted: row exists with sends_used >= max_sends → { status: 'denied',
 *       reason: 'template_quota_exhausted' }; auto-revoke side effect fires.
 *   (f) fail-closed exception: DB error → throws PredicateException (route layer catches and
 *       returns 500 + Sentry).
 *
 * Auto-revoke is best-effort: revoke RPC failure must NOT mask the denial.
 */

import { describe, test, expect, vi, beforeEach } from "vitest";

import {
  isTemplateAuthorized,
  PredicateException,
} from "@/server/templates/is-template-authorized";

const FOUNDER_A = "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa";
const TEMPLATE_HASH = "deadbeef".repeat(8);
const GRANT_ID = "22222222-2222-4222-aaaa-222222222222";
const ROW_ID = "33333333-3333-4333-aaaa-333333333333";

interface MockOpts {
  taRow?: {
    id: string;
    expires_at: string;
    max_sends: number;
    revoked_at: string | null;
  } | null;
  sendsCount?: number;
  taError?: Error | null;
  countError?: Error | null;
  rpcError?: Error | null;
}

function makeMockClient(opts: MockOpts = {}) {
  const {
    taRow = null,
    sendsCount = 0,
    taError = null,
    countError = null,
    rpcError = null,
  } = opts;

  const rpcSpy = vi.fn(async () => ({ data: 1, error: rpcError }));

  const taMaybeSingle = vi.fn(async () => ({
    data: taRow,
    error: taError,
  }));
  const taLimit = vi.fn(() => ({ maybeSingle: taMaybeSingle }));
  const taOrder = vi.fn(() => ({ limit: taLimit }));
  const taEq2 = vi.fn(() => ({ order: taOrder }));
  const taEq1 = vi.fn(() => ({ eq: taEq2 }));
  const taSelect = vi.fn(() => ({ eq: taEq1 }));

  // action_sends count probe: select('id', { count: 'exact', head: true })
  //   .eq(user_id, ...).eq(template_hash, ...)
  // returns thenable resolving to { count, error }
  const sendsThenable = {
    then: (
      resolve: (value: { count: number; error: Error | null }) => unknown,
    ) => Promise.resolve(resolve({ count: sendsCount, error: countError })),
  };
  const sendsEq2 = vi.fn(() => sendsThenable);
  const sendsEq1 = vi.fn(() => ({ eq: sendsEq2 }));
  const sendsSelect = vi.fn(() => ({ eq: sendsEq1 }));

  const from = vi.fn((table: string) => {
    if (table === "template_authorizations") {
      return { select: taSelect };
    }
    if (table === "action_sends") {
      return { select: sendsSelect };
    }
    throw new Error(`unexpected table: ${table}`);
  });

  const client = { from, rpc: rpcSpy };
  return { client, rpcSpy, taSelect, sendsSelect };
}

describe("isTemplateAuthorized", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-05-21T12:00:00Z"));
  });

  test("(a) first_send: no existing row → returns first_send with grantId", async () => {
    const { client, rpcSpy } = makeMockClient({ taRow: null });

    const result = await isTemplateAuthorized(
      client as never,
      FOUNDER_A,
      TEMPLATE_HASH,
      GRANT_ID,
    );

    expect(result).toEqual({ status: "first_send", grantId: GRANT_ID });
    expect(rpcSpy).not.toHaveBeenCalled();
  });

  test("(b) authorized: active row with bounds in range → authorized with sendsUsed", async () => {
    const { client, rpcSpy } = makeMockClient({
      taRow: {
        id: ROW_ID,
        expires_at: "2026-08-19T12:00:00Z",
        max_sends: 100,
        revoked_at: null,
      },
      sendsCount: 12,
    });

    const result = await isTemplateAuthorized(
      client as never,
      FOUNDER_A,
      TEMPLATE_HASH,
      GRANT_ID,
    );

    expect(result).toEqual({
      status: "authorized",
      rowId: ROW_ID,
      sendsUsed: 12,
    });
    expect(rpcSpy).not.toHaveBeenCalled();
  });

  test("(c) denied/template_revoked: revoked_at NOT NULL → denied, no auto-revoke", async () => {
    const { client, rpcSpy } = makeMockClient({
      taRow: {
        id: ROW_ID,
        expires_at: "2026-08-19T12:00:00Z",
        max_sends: 100,
        revoked_at: "2026-05-20T12:00:00Z",
      },
      sendsCount: 5,
    });

    const result = await isTemplateAuthorized(
      client as never,
      FOUNDER_A,
      TEMPLATE_HASH,
      GRANT_ID,
    );

    expect(result).toEqual({ status: "denied", reason: "template_revoked" });
    // Row already revoked — no auto-revoke side effect.
    expect(rpcSpy).not.toHaveBeenCalled();
  });

  test("(d) denied/template_expired: expires_at <= now → denied + auto-revoke fires", async () => {
    const { client, rpcSpy } = makeMockClient({
      taRow: {
        id: ROW_ID,
        expires_at: "2026-05-20T12:00:00Z", // 24h ago
        max_sends: 100,
        revoked_at: null,
      },
      sendsCount: 5,
    });

    const result = await isTemplateAuthorized(
      client as never,
      FOUNDER_A,
      TEMPLATE_HASH,
      GRANT_ID,
    );

    expect(result).toEqual({ status: "denied", reason: "template_expired" });

    // Auto-revoke side effect: fire-and-forget revoke RPC with reason='expired'.
    await vi.waitFor(() => {
      expect(rpcSpy).toHaveBeenCalledWith("revoke_template_authorization", {
        p_template_hash: TEMPLATE_HASH,
        p_reason: "expired",
      });
    });
  });

  test("(e) denied/template_quota_exhausted: sends_used >= max_sends → denied + auto-revoke", async () => {
    const { client, rpcSpy } = makeMockClient({
      taRow: {
        id: ROW_ID,
        expires_at: "2026-08-19T12:00:00Z",
        max_sends: 100,
        revoked_at: null,
      },
      sendsCount: 100,
    });

    const result = await isTemplateAuthorized(
      client as never,
      FOUNDER_A,
      TEMPLATE_HASH,
      GRANT_ID,
    );

    expect(result).toEqual({
      status: "denied",
      reason: "template_quota_exhausted",
    });

    await vi.waitFor(() => {
      expect(rpcSpy).toHaveBeenCalledWith("revoke_template_authorization", {
        p_template_hash: TEMPLATE_HASH,
        p_reason: "quota_exhausted",
      });
    });
  });

  test("(f) fail-closed exception: DB SELECT error → throws PredicateException", async () => {
    const { client } = makeMockClient({
      taError: new Error("connection refused"),
    });

    await expect(
      isTemplateAuthorized(client as never, FOUNDER_A, TEMPLATE_HASH, GRANT_ID),
    ).rejects.toBeInstanceOf(PredicateException);
  });

  test("(g) fail-closed exception: action_sends count error → throws PredicateException", async () => {
    const { client } = makeMockClient({
      taRow: {
        id: ROW_ID,
        expires_at: "2026-08-19T12:00:00Z",
        max_sends: 100,
        revoked_at: null,
      },
      countError: new Error("timeout"),
    });

    await expect(
      isTemplateAuthorized(client as never, FOUNDER_A, TEMPLATE_HASH, GRANT_ID),
    ).rejects.toBeInstanceOf(PredicateException);
  });

  test("(h) auto-revoke best-effort: revoke RPC error does NOT mask the denial", async () => {
    const { client, rpcSpy } = makeMockClient({
      taRow: {
        id: ROW_ID,
        expires_at: "2026-05-20T12:00:00Z",
        max_sends: 100,
        revoked_at: null,
      },
      sendsCount: 5,
      rpcError: new Error("rpc failed"),
    });

    // Should still return the denial — the auto-revoke is fire-and-forget.
    const result = await isTemplateAuthorized(
      client as never,
      FOUNDER_A,
      TEMPLATE_HASH,
      GRANT_ID,
    );

    expect(result).toEqual({ status: "denied", reason: "template_expired" });

    await vi.waitFor(() => {
      expect(rpcSpy).toHaveBeenCalled();
    });
  });
});
