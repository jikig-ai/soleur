import { beforeEach, describe, expect, it, vi } from "vitest";

// Unit tests for the service-role-safe installation-id resolver (#5470).
//
// resolveInstallationIdForWorkspace reads workspaces.github_installation_id
// directly via an INJECTED service-role client (no auth.uid() needed) — the
// distinct service-role path for Inngest/cron contexts where the canonical
// membership-checked resolve_workspace_installation_id RPC (mig 079) returns
// NULL. Mirrors workspace-identity-resolver.ts (injected client, .maybeSingle()),
// minus its auth.getUser() gate.

const { reportSilentFallbackSpy } = vi.hoisted(() => ({
  reportSilentFallbackSpy: vi.fn(),
}));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: reportSilentFallbackSpy,
}));

import { resolveInstallationIdForWorkspace } from "@/server/resolve-installation-id-for-workspace";

// Structural service-client mock: from("workspaces").select(...).eq("id", ws)
// .maybeSingle() → { data, error }. Captures the eq args for assertions.
const eqSpy = vi.fn();
let MAYBE_SINGLE_RESULT: { data: unknown; error: unknown } = {
  data: null,
  error: null,
};

function makeService(table = "workspaces") {
  const chain = {
    select: () => chain,
    eq: (col: string, val: unknown) => {
      eqSpy(col, val);
      return chain;
    },
    maybeSingle: () => Promise.resolve(MAYBE_SINGLE_RESULT),
  } as Record<string, unknown>;
  return {
    from: (t: string) => {
      if (t !== table) throw new Error(`unexpected service table ${t}`);
      return chain;
    },
  };
}

beforeEach(() => {
  reportSilentFallbackSpy.mockClear();
  eqSpy.mockClear();
  MAYBE_SINGLE_RESULT = { data: null, error: null };
});

describe("resolveInstallationIdForWorkspace", () => {
  it("resolves the install for a newly-connected workspace (populated workspaces.github_installation_id)", async () => {
    MAYBE_SINGLE_RESULT = { data: { github_installation_id: 12345 }, error: null };
    const result = await resolveInstallationIdForWorkspace("ws-1", makeService());
    expect(result).toBe(12345);
    // Keyed on the workspace id via eq("id", …) — single scoped read, no sibling
    // discovery (CLO forbid: no unscoped membership scan).
    expect(eqSpy).toHaveBeenCalledWith("id", "ws-1");
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("returns null when the workspace row exists but the install is NULL (not connected)", async () => {
    MAYBE_SINGLE_RESULT = { data: { github_installation_id: null }, error: null };
    const result = await resolveInstallationIdForWorkspace("ws-1", makeService());
    expect(result).toBeNull();
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("returns 0 (not null) for a 0 install id — pins `?? null` over a `|| null` truthiness regression", async () => {
    // 0 is a valid integer the column could hold; the resolver uses `?? null`
    // (nullish), so 0 must survive. A future `|| null` refactor would wrongly
    // coalesce 0 → null; the downstream `install === null` gate correctly keeps 0.
    MAYBE_SINGLE_RESULT = { data: { github_installation_id: 0 }, error: null };
    const result = await resolveInstallationIdForWorkspace("ws-1", makeService());
    expect(result).toBe(0);
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("returns null when no workspace row is found", async () => {
    MAYBE_SINGLE_RESULT = { data: null, error: null };
    const result = await resolveInstallationIdForWorkspace("ws-unknown", makeService());
    expect(result).toBeNull();
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("returns null AND mirrors to Sentry on a db error", async () => {
    MAYBE_SINGLE_RESULT = { data: null, error: { message: "boom" } };
    const result = await resolveInstallationIdForWorkspace("ws-1", makeService());
    expect(result).toBeNull();
    expect(reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    const [, options] = reportSilentFallbackSpy.mock.calls[0];
    expect(options.feature).toBe("resolve-installation-id-for-workspace");
    expect(options.op).toBe("workspaces-read");
    expect(options.extra).toMatchObject({ workspaceId: "ws-1" });
  });
});
