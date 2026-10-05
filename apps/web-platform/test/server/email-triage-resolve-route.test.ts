import { beforeEach, describe, expect, it, vi } from "vitest";

import {
  resolveInboundRoute,
  resetOwnerValidationMemo,
} from "@/server/email-triage/resolve-inbound-route";

// ADR-269 resolver. The Supabase client is injected, so this suite drives it
// with a scripted fake rather than mocking a module.

const ENV_OWNER = "11111111-1111-4111-8111-111111111111";
const WS = "33333333-3333-4333-8333-333333333333";
const OWNER = "44444444-4444-4444-8444-444444444444";
const ADDR = "cro@inbound.soleur.ai";

interface Call {
  table: string;
  filters: { kind: string; col: string; val: unknown }[];
}

function makeClient(script: (call: Call) => { data?: unknown; error?: unknown }) {
  const calls: Call[] = [];
  const client = {
    from(table: string) {
      const call: Call = { table, filters: [] };
      const b: Record<string, unknown> = {};
      const chain =
        (kind: string) =>
        (col: string, val: unknown) => {
          call.filters.push({ kind, col, val });
          return b;
        };
      Object.assign(b, {
        select: () => b,
        eq: chain("eq"),
        in: chain("in"),
        maybeSingle: () => {
          calls.push(call);
          return Promise.resolve({ data: null, error: null, ...script(call) });
        },
        then: (
          ok: (v: unknown) => unknown,
          bad?: (e: unknown) => unknown,
        ) => {
          calls.push(call);
          return Promise.resolve({
            data: null,
            error: null,
            ...script(call),
          }).then(ok, bad);
        },
      });
      return b;
    },
  };
  return { client: client as never, calls };
}

/** users + workspace_members both validate; routes table scripted per test. */
function script(routes: unknown[] | { error: unknown }) {
  return (call: Call) => {
    if (call.table === "users") return { data: { id: "x" } };
    if (call.table === "workspace_members") return { data: { user_id: "x" } };
    if (call.table === "email_inbox_routes") {
      return Array.isArray(routes) ? { data: routes } : routes;
    }
    return {};
  };
}

beforeEach(() => {
  resetOwnerValidationMemo();
  vi.clearAllMocks();
});

describe("resolveInboundRoute", () => {
  const operatorRow = {
    address: ADDR,
    workspace_id: ENV_OWNER,
    owner_user_id: ENV_OWNER,
  };
  const foreignRow = { address: ADDR, workspace_id: WS, owner_user_id: OWNER };

  it("empty recipients → env owner, and NO routes query is issued", async () => {
    const { client, calls } = makeClient(script([]));
    const r = await resolveInboundRoute(client, [], ENV_OWNER);
    expect(r).toEqual({
      workspaceId: ENV_OWNER,
      ownerId: ENV_OWNER,
      source: "env-fallback",
    });
    expect(calls.some((c) => c.table === "email_inbox_routes")).toBe(false);
  });

  it("no matching route → env owner (fallback), not degraded", async () => {
    const { client, calls } = makeClient(script([]));
    const r = await resolveInboundRoute(client, [ADDR], ENV_OWNER);
    expect(r.source).toBe("env-fallback");
    expect(r.ownerId).toBe(ENV_OWNER);
    expect(r.degraded).toBeUndefined();
    const q = calls.find((c) => c.table === "email_inbox_routes");
    expect(q?.filters).toEqual([{ kind: "in", col: "address", val: [ADDR] }]);
  });

  it("a route to the operator pair → source table, validated as the operator", async () => {
    const { client, calls } = makeClient(script([operatorRow]));
    const r = await resolveInboundRoute(client, [ADDR], ENV_OWNER);
    expect(r).toEqual({
      workspaceId: ENV_OWNER,
      ownerId: ENV_OWNER,
      source: "table",
    });
    const member = calls.find((c) => c.table === "workspace_members");
    expect(member?.filters).toEqual(
      expect.arrayContaining([
        { kind: "eq", col: "workspace_id", val: ENV_OWNER },
        { kind: "eq", col: "user_id", val: ENV_OWNER },
        { kind: "eq", col: "role", val: "owner" },
      ]),
    );
  });

  it("two aliases of the operator are NOT ambiguous", async () => {
    const { client } = makeClient(
      script([
        operatorRow,
        { ...operatorRow, address: "ops@inbound.soleur.ai" },
      ]),
    );
    const r = await resolveInboundRoute(
      client,
      [ADDR, "ops@inbound.soleur.ai"],
      ENV_OWNER,
    );
    expect(r.source).toBe("table");
    expect(r.degraded).toBeUndefined();
  });

  it("a route to ANOTHER workspace is refused → env owner, degraded non-operator-route", async () => {
    const { client } = makeClient(script([foreignRow]));
    const r = await resolveInboundRoute(client, [ADDR], ENV_OWNER);
    expect(r).toEqual({
      workspaceId: ENV_OWNER,
      ownerId: ENV_OWNER,
      source: "env-fallback",
      degraded: "non-operator-route",
    });
  });

  it("an operator route plus a foreign route is refused (every matched row must be the operator)", async () => {
    const { client } = makeClient(
      script([operatorRow, { ...foreignRow, address: "b@inbound.soleur.ai" }]),
    );
    const r = await resolveInboundRoute(client, [ADDR, "b@inbound.soleur.ai"], ENV_OWNER);
    expect(r.degraded).toBe("non-operator-route");
    expect(r.ownerId).toBe(ENV_OWNER);
  });

  it("a routes query ERROR degrades to the env owner with the pg code only — it does not throw", async () => {
    const { client } = makeClient(script({ error: { code: "PGRST205" } }));
    const r = await resolveInboundRoute(client, [ADDR], ENV_OWNER);
    expect(r).toEqual({
      workspaceId: ENV_OWNER,
      ownerId: ENV_OWNER,
      source: "env-fallback",
      degraded: "route-lookup-failed",
      detail: "PGRST205",
    });
  });

  it("the env owner is still validated when degrading (a bad owner row throws, retriable)", async () => {
    const { client } = makeClient((call) => {
      if (call.table === "workspace_members") return { data: null };
      return script({ error: { code: "57P03" } })(call);
    });
    await expect(
      resolveInboundRoute(client, [ADDR], ENV_OWNER),
    ).rejects.toThrow(/not the workspace owner/);
  });

  it("env owner unset throws the unset error, even with recipients and a matching route", async () => {
    const { client, calls } = makeClient(script([operatorRow]));
    await expect(resolveInboundRoute(client, [ADDR], undefined)).rejects.toThrow(
      /EMAIL_TRIAGE_OWNER_USER_ID is unset/,
    );
    expect(calls).toHaveLength(0);
  });

  it("owner validation is memoized per owner for the TTL, and expires after it", async () => {
    vi.useFakeTimers();
    try {
      const { client, calls } = makeClient(script([operatorRow]));
      await resolveInboundRoute(client, [ADDR], ENV_OWNER);
      await resolveInboundRoute(client, [ADDR], ENV_OWNER);
      expect(calls.filter((c) => c.table === "users")).toHaveLength(1);
      expect(calls.filter((c) => c.table === "workspace_members")).toHaveLength(1);
      // Just inside the 1h TTL: still memoized.
      vi.advanceTimersByTime(59 * 60 * 1000);
      await resolveInboundRoute(client, [ADDR], ENV_OWNER);
      expect(calls.filter((c) => c.table === "users")).toHaveLength(1);
      // Past the TTL: re-validated.
      vi.advanceTimersByTime(2 * 60 * 1000);
      await resolveInboundRoute(client, [ADDR], ENV_OWNER);
      expect(calls.filter((c) => c.table === "users")).toHaveLength(2);
      // A rotated env owner is validated on its own.
      await resolveInboundRoute(client, [], "99999999-9999-4999-8999-999999999999");
      expect(calls.filter((c) => c.table === "users")).toHaveLength(3);
    } finally {
      vi.useRealTimers();
    }
  });
});
