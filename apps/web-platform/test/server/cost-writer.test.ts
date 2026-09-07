import { describe, it, expect, beforeEach, vi } from "vitest";

// Phase 3 (feat-team-workspace-multi-user) — pins that `persistTurnCost`
// threads `p_workspace_id` into the `write_byok_audit` RPC. Migration
// 055 made `audit_byok_use.workspace_id` NOT NULL; the 5-arg RPC
// shape would fail with a NOT NULL constraint violation. Migration
// 057 widens both RPCs to 6-arg signatures; this test pins the JS
// caller wire-up.

const { rpcSpy, sendToClientSpy, maybeSingleSpy } = vi.hoisted(() => ({
  rpcSpy: vi.fn(
    // Return type widened to the error union AND to `data` so per-test
    // mockImplementation can return an RPC error (e.g. the cross-tenant P0001
    // path, #4364) or a mig-136 refusal payload (#7829) without tripping
    // TS2345 — the default value stays a clean admit.
    async (
      _name: string,
      _args: Record<string, unknown>,
    ): Promise<{ data?: unknown; error: null | { message: string } }> => ({
      error: null,
    }),
  ),
  sendToClientSpy: vi.fn(
    (_userId: string, _msg: Record<string, unknown>) => true,
  ),
  // `audit_byok_use` read-back behind the `ledger_row_written` Sentry tag
  // (#7829 observability). Default: the refusal row IS present.
  maybeSingleSpy: vi.fn(
    async (): Promise<{
      data: { invocation_id: string } | null;
      error: null | { message: string };
    }> => ({ data: { invocation_id: "seeded" }, error: null }),
  ),
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    rpc: rpcSpy,
    from: () => ({
      select: () => ({ eq: () => ({ maybeSingle: maybeSingleSpy }) }),
    }),
  }),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
  mirrorP0Deduped: vi.fn(),
}));

vi.mock("@/server/ws-handler", () => ({
  sendToClient: sendToClientSpy,
}));

vi.mock("@/server/logger", () => ({
  createChildLogger: () => ({
    error: vi.fn(),
    warn: vi.fn(),
    info: vi.fn(),
  }),
}));

const { emitMarkerSpy } = vi.hoisted(() => ({ emitMarkerSpy: vi.fn() }));
vi.mock("@/server/claude-cost-marker", () => ({
  emitClaudeCostMarker: emitMarkerSpy,
}));

import { persistTurnCost, readRefusalReason } from "@/server/cost-writer";
import { reportSilentFallback, mirrorP0Deduped } from "@/server/observability";
import {
  ByokDelegationCrossTenantError,
  ByokDelegationConsentWithdrawnError,
  ByokDelegationHourlyCapError,
  ByokDelegationDailyCapError,
} from "@/server/byok-resolver";

const USER = "550e8400-e29b-41d4-a716-446655440000";
const WORKSPACE = "660e8400-e29b-41d4-a716-446655440111";
const CONV = "770e8400-e29b-41d4-a716-446655440222";

beforeEach(() => {
  rpcSpy.mockClear();
  sendToClientSpy.mockClear();
});

describe("persistTurnCost — cost marker threading (Phase 1, AC2)", () => {
  it("emits a SOLEUR_CLAUDE_COST marker with the threaded source + model", () => {
    emitMarkerSpy.mockClear();
    persistTurnCost(
      USER,
      CONV,
      "cpo",
      WORKSPACE,
      {
        totalCostUsd: 0.012,
        usage: {
          input_tokens: 100,
          output_tokens: 50,
          cache_read_input_tokens: 4,
          cache_creation_input_tokens: 2,
        },
      },
      { source: "agent-runner", model: "claude-opus-4-8" },
    );
    expect(emitMarkerSpy).toHaveBeenCalledTimes(1);
    expect(emitMarkerSpy.mock.calls[0][0]).toMatchObject({
      source: "agent-runner",
      model: "claude-opus-4-8",
      input_tokens: 100,
      output_tokens: 50,
      cache_read_input_tokens: 4,
      cache_creation_input_tokens: 2,
      cost_usd: 0.012,
      id: CONV,
      capture_status: "ok",
    });
  });
});

describe("persistTurnCost — workspace_id wiring (Phase 3)", () => {
  it("passes p_workspace_id to the write_byok_audit RPC", async () => {
    persistTurnCost(
      USER,
      CONV,
      "cpo",
      WORKSPACE,
      {
        totalCostUsd: 0.012,
        usage: {
          input_tokens: 100,
          output_tokens: 50,
          cache_read_input_tokens: 0,
          cache_creation_input_tokens: 0,
        },
      },
      { source: "cc-soleur-go", model: null },
    );

    // Microtask drain so .then() handlers attached inside persistTurnCost
    // fire before assertion.
    await new Promise((r) => setImmediate(r));

    const auditCall = rpcSpy.mock.calls.find(
      (c) => (c[0] as string) === "write_byok_audit",
    );
    expect(auditCall).toBeDefined();
    expect(auditCall![1]).toMatchObject({
      p_founder_id: USER,
      p_workspace_id: WORKSPACE,
      p_agent_role: "cpo",
    });
  });

  it("passes p_workspace_id to the increment_conversation_cost RPC (workspace-grain attribution)", async () => {
    persistTurnCost(
      USER,
      CONV,
      "cpo",
      WORKSPACE,
      {
        totalCostUsd: 0.012,
        usage: {
          input_tokens: 100,
          output_tokens: 50,
          cache_read_input_tokens: 0,
          cache_creation_input_tokens: 0,
        },
      },
      { source: "cc-soleur-go", model: null },
    );

    await new Promise((r) => setImmediate(r));

    const incrementCall = rpcSpy.mock.calls.find(
      (c) => (c[0] as string) === "increment_conversation_cost",
    );
    expect(incrementCall).toBeDefined();
    // The conversation row carries workspace_id (migration 059 sweep); the
    // RPC signature is unchanged because the conversation_id already pins
    // the workspace. But the audit row needs explicit threading.
    expect(incrementCall![1]).toMatchObject({
      conv_id: CONV,
    });
  });

  it("usage_update WS event includes the workspaceId for client UI attribution", async () => {
    persistTurnCost(
      USER,
      CONV,
      "cpo",
      WORKSPACE,
      {
        totalCostUsd: 0.012,
        usage: {
          input_tokens: 100,
          output_tokens: 50,
          cache_read_input_tokens: 0,
          cache_creation_input_tokens: 0,
        },
      },
      { source: "cc-soleur-go", model: null },
    );

    expect(sendToClientSpy).toHaveBeenCalledTimes(1);
    const evt = sendToClientSpy.mock.calls[0][1] as Record<string, unknown>;
    expect(evt).toMatchObject({
      type: "usage_update",
      conversationId: CONV,
      workspaceId: WORKSPACE,
    });
  });
});

describe("persistTurnCost — cross-tenant Art.33 emission (#4364, hardened #4656)", () => {
  it("routes byok_delegations:cross-tenant through mirrorP0Deduped (fatal, recurrence-resilient, clock-anchored)", async () => {
    const p0Mock = vi.mocked(mirrorP0Deduped);
    const reportMock = vi.mocked(reportSilentFallback);
    p0Mock.mockClear();
    reportMock.mockClear();
    // The migration-064 trigger raises the HYPHEN form on the cross-tenant
    // path. cost-writer must route it through `mirrorP0Deduped` (#4656 items
    // 2+3): fatal severity, no 5-min debounce, and `first_seen_at` clock
    // anchor — NEVER the `reportSilentFallback` path (capture-swallowed, no
    // clock anchor) and never the merged-rpc-failure catch-all. The
    // `feature` + `art33Breach` options carry the two tags the
    // `byok_art_33_breach` rule filters on (filter_match="all").
    rpcSpy.mockImplementation(
      async (
        name: string,
        _args: Record<string, unknown>,
      ): Promise<{ error: null | { message: string } }> => {
        if (name === "check_and_record_byok_delegation_use") {
          return {
            error: {
              message:
                "byok_delegations:cross-tenant: grantee g-1 is not a member of workspace ws-1",
            },
          };
        }
        return { error: null };
      },
    );
    persistTurnCost(
      USER,
      CONV,
      "cpo",
      WORKSPACE,
      {
        totalCostUsd: 0.02,
        usage: {
          input_tokens: 10,
          output_tokens: 5,
          cache_read_input_tokens: 0,
          cache_creation_input_tokens: 0,
        },
      },
      { source: "cc-soleur-go", model: null },
      { delegationId: "deadbeef", callerUserId: "g-1" },
    );
    await new Promise((r) => setImmediate(r));

    expect(p0Mock).toHaveBeenCalledTimes(1);
    const [errArg, ctx] = p0Mock.mock.calls[0];
    expect(errArg).toBeInstanceOf(ByokDelegationCrossTenantError);
    expect(ctx).toMatchObject({
      op: "cross-tenant-violation",
      userId: USER,
      conversationId: CONV,
      delegationId: "deadbeef",
      feature: "byok-delegations",
      art33Breach: true,
    });

    // Must NOT route through reportSilentFallback for the cross-tenant op
    // (capture-swallow + no clock anchor was the #4656 item-2/3 gap), and must
    // NOT fall through to the merged-rpc-failure catch-all.
    const crossTenantViaFallback = reportMock.mock.calls.find(
      (c) => (c[1] as { op?: string })?.op === "cross-tenant-violation",
    );
    expect(crossTenantViaFallback).toBeFalsy();
    const fallback = reportMock.mock.calls.find(
      (c) => (c[1] as { op?: string })?.op === "merged-rpc-failure",
    );
    expect(fallback).toBeFalsy();
  });
});

describe("persistTurnCost — delegated refusal is a RETURNED value, not an exception (#7829, mig 137)", () => {
  const DELEGATION = { delegationId: "d-7829", callerUserId: "grantee-1" };

  // The handler awaits the `audit_byok_use` read-back, so a single microtask
  // drain is no longer enough to settle it.
  async function flush(): Promise<void> {
    for (let i = 0; i < 4; i++) await new Promise((r) => setImmediate(r));
  }

  function runDelegatedTurn(): void {
    persistTurnCost(
      USER,
      CONV,
      "cpo",
      WORKSPACE,
      {
        totalCostUsd: 0.02,
        usage: {
          input_tokens: 10,
          output_tokens: 5,
          cache_read_input_tokens: 0,
          cache_creation_input_tokens: 0,
        },
      },
      { source: "cc-soleur-go", model: null },
      DELEGATION,
    );
  }

  /** Mock the delegation RPC's resolved payload; other RPCs stay clean. */
  function mockRpcResult(result: { data?: unknown; error?: { message: string } }) {
    rpcSpy.mockImplementation(async (name: string) => {
      if (name === "check_and_record_byok_delegation_use") {
        return { data: result.data, error: result.error ?? null };
      }
      return { error: null };
    });
  }

  beforeEach(() => {
    vi.mocked(reportSilentFallback).mockClear();
    vi.mocked(mirrorP0Deduped).mockClear();
    maybeSingleSpy.mockClear();
    maybeSingleSpy.mockResolvedValue({
      data: { invocation_id: "seeded" },
      error: null,
    });
  });

  function fallbackCall(op: string) {
    return vi
      .mocked(reportSilentFallback)
      .mock.calls.find((c) => (c[1] as { op?: string })?.op === op);
  }

  describe("readRefusalReason classifies every PostgREST shape, and fails CLOSED", () => {
    // `RETURNS TABLE(refusal_reason text)` is a SINGLE output column, so
    // PostgreSQL collapses it to SETOF text. Which of these three shapes
    // reaches supabase-js is a PostgREST/client-version detail; none of them
    // may be read as "admitted".
    it.each([
      ["array of rows", [{ refusal_reason: "hourly_cap_exceeded" }]],
      ["array of scalars", ["hourly_cap_exceeded"]],
      ["bare scalar", "hourly_cap_exceeded"],
      ["single row object", { refusal_reason: "hourly_cap_exceeded" }],
    ])("reads a refusal from %s", (_label, payload) => {
      expect(readRefusalReason(payload)).toEqual({
        kind: "refused",
        reason: "hourly_cap_exceeded",
      });
    });

    // Admission is established POSITIVELY: the RPC returned its one row and
    // the column in it was SQL NULL. Nothing weaker counts.
    it.each([
      ["array of one null row", [{ refusal_reason: null }]],
      ["array of one null scalar", [null]],
      ["bare null row object", { refusal_reason: null }],
    ])("admits on %s", (_label, payload) => {
      expect(readRefusalReason(payload)).toEqual({ kind: "admitted" });
    });

    // THE FAIL-CLOSED PROPERTY. Each of these previously read as "admitted",
    // which would silence EVERY refusal on this path if the client/PostgREST
    // pair ever produced one of them — reinstating, through the reporting
    // layer, the exact silent-ledger failure #7829 exists to remove.
    // A shape we cannot parse is never an admission.
    it.each([
      ["no reply at all (undefined)", undefined],
      ["a null reply (the RPC always returns one row)", null],
      ["an empty set", []],
      ["more than one row", [{ refusal_reason: null }, { refusal_reason: "expired" }]],
      ["a non-string reason", [{ refusal_reason: 42 }]],
      ["a row of the wrong type", [7]],
      ["an object without the column", [{ something_else: "x" }]],
    ])("is UNREADABLE, not admitted, on %s", (_label, payload) => {
      const read = readRefusalReason(payload);
      expect(read.kind, `must not read as admitted: ${JSON.stringify(payload)}`).toBe(
        "unreadable",
      );
    });
  });

  it("an unreadable reply pages instead of passing silently", async () => {
    mockRpcResult({ data: [{ something_else: "x" }] });
    runDelegatedTurn();
    await flush();

    const call = fallbackCall("unreadable-refusal-shape");
    expect(call, "unreadable-refusal-shape reported").toBeDefined();
  });

  it("hourly cap: reports the D10 error from `data`, not from an error message", async () => {
    mockRpcResult({ data: [{ refusal_reason: "hourly_cap_exceeded" }] });
    runDelegatedTurn();
    await flush();

    const call = fallbackCall("hourly-cap-exceeded");
    expect(call, "hourly-cap-exceeded reported").toBeDefined();
    expect(call![0]).toBeInstanceOf(ByokDelegationHourlyCapError);
    expect(call![1]).toMatchObject({ feature: "byok-delegations" });
    // The RPC resolved without an `error`, so the pre-136 substring matcher
    // would have reported nothing at all here.
    expect(fallbackCall("merged-rpc-failure")).toBeFalsy();
  });

  it("daily cap: the bare-scalar payload shape is not mistaken for an admit", async () => {
    mockRpcResult({ data: ["daily_cap_exceeded"] });
    runDelegatedTurn();
    await flush();

    const call = fallbackCall("daily-cap-exceeded");
    expect(call).toBeDefined();
    expect(call![0]).toBeInstanceOf(ByokDelegationDailyCapError);
  });

  it("consent_withdrawn now has its own branch (AC9) — no longer merged-rpc-failure", async () => {
    mockRpcResult({ data: [{ refusal_reason: "consent_withdrawn" }] });
    runDelegatedTurn();
    await flush();

    const call = fallbackCall("consent-withdrawn");
    expect(call, "consent-withdrawn reported").toBeDefined();
    expect(call![0]).toBeInstanceOf(ByokDelegationConsentWithdrawnError);
    // Restoring this slug's distinctness is what makes `merged-rpc-failure`
    // usable as the 23514 / 22003 / 42703 detection channel.
    expect(fallbackCall("merged-rpc-failure")).toBeFalsy();
  });

  it("tags ledger_row_written=true when the refusal row persisted", async () => {
    mockRpcResult({ data: [{ refusal_reason: "hourly_cap_exceeded" }] });
    runDelegatedTurn();
    await flush();

    expect(fallbackCall("hourly-cap-exceeded")![1]).toMatchObject({
      tags: { ledger_row_written: "true" },
    });
  });

  it("tags ledger_row_written=false when the refusal wrote no row (the inert-fix mode)", async () => {
    // The highest-probability post-merge failure state: 136 applies, the
    // refusal fires, and the INSERT is still discarded. Without this tag the
    // Sentry event is byte-identical to the healthy one.
    maybeSingleSpy.mockResolvedValue({ data: null, error: null });
    mockRpcResult({ data: [{ refusal_reason: "daily_cap_exceeded" }] });
    runDelegatedTurn();
    await flush();

    expect(fallbackCall("daily-cap-exceeded")![1]).toMatchObject({
      tags: { ledger_row_written: "false" },
    });
  });

  it("tags ledger_row_written=unknown when the read-back itself fails", async () => {
    maybeSingleSpy.mockResolvedValue({ data: null, error: { message: "boom" } });
    mockRpcResult({ data: [{ refusal_reason: "expired" }] });
    runDelegatedTurn();
    await flush();

    expect(fallbackCall("expired")![1]).toMatchObject({
      tags: { ledger_row_written: "unknown" },
    });
  });

  it("admitted turn (refusal_reason NULL) reports nothing", async () => {
    mockRpcResult({ data: [{ refusal_reason: null }] });
    runDelegatedTurn();
    await flush();

    expect(vi.mocked(reportSilentFallback)).not.toHaveBeenCalled();
    expect(maybeSingleSpy, "no read-back on the admit path").not.toHaveBeenCalled();
  });

  it("an unrecognised refusal_reason fails loud instead of folding into the catch-all", async () => {
    mockRpcResult({ data: [{ refusal_reason: "quota_frozen" }] });
    runDelegatedTurn();
    await flush();

    expect(fallbackCall("unknown-refusal-reason"), "distinct slug").toBeDefined();
    expect(fallbackCall("merged-rpc-failure")).toBeFalsy();
  });

  it("42501 caller_not_grantee gets its own slug (mig 137 caller identity pin)", async () => {
    mockRpcResult({ error: { message: "byok_delegations:caller_not_grantee" } });
    runDelegatedTurn();
    await flush();

    const call = fallbackCall("caller-not-grantee");
    expect(call, "caller-not-grantee reported").toBeDefined();
    expect(fallbackCall("merged-rpc-failure")).toBeFalsy();
  });

  it("a genuine RPC failure still lands in merged-rpc-failure", async () => {
    mockRpcResult({
      error: { message: 'new row violates check constraint "…_check"' },
    });
    runDelegatedTurn();
    await flush();

    expect(fallbackCall("merged-rpc-failure")).toBeDefined();
  });
});
