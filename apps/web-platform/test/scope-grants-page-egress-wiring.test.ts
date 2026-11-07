import { beforeEach, describe, expect, it, vi } from "vitest";
import type { ReactElement, ReactNode } from "react";

// #9545 PR2 — the Scope Grants page hands the web-access toggle the card state the loader read. The loader reads
// its own workspace pointer while the page resolves the active workspace separately (for the owner flag), so the
// page drops the hint and the collection state when the two disagree: they must never describe a different
// workspace than the owner state beside them.

const h = vi.hoisted(() => ({
  loadEgressCardState: vi.fn(),
  resolveCurrentWorkspaceId: vi.fn(),
  WebEgressToggle: () => null,
  Noop: () => null,
}));

vi.mock("next/navigation", () => ({
  redirect: (to: string) => {
    throw new Error(`NEXT_REDIRECT:${to}`);
  },
}));
vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({
    auth: { getUser: async () => ({ data: { user: { id: "u1" } } }) },
    from: (table: string) => {
      // A generic thenable query chain: every builder method returns the chain, single()/maybeSingle() resolve a row.
      const row = table === "workspace_members" ? { role: "owner" } : table === "users" ? { role: "prd" } : null;
      const chain: Record<string, unknown> = {};
      for (const m of ["select", "eq", "is", "order"]) chain[m] = () => chain;
      chain.maybeSingle = async () => ({ data: row, error: null });
      chain.single = async () => ({ data: row, error: null });
      chain.then = (res: (v: unknown) => unknown) => Promise.resolve({ data: [], error: null, count: 0 }).then(res);
      return chain;
    },
  }),
}));
vi.mock("@/server/egress-audit-read", () => ({ loadEgressCardState: h.loadEgressCardState }));
vi.mock("@/server/workspace-resolver", () => ({ resolveCurrentWorkspaceId: h.resolveCurrentWorkspaceId }));
vi.mock("@/server/resolve-bash-autonomous", () => ({ resolveBashAutonomous: async () => false }));
vi.mock("@/server/resolve-debug-mode", () => ({ resolveDebugMode: async () => false }));
vi.mock("@/server/resolve-web-egress", () => ({ resolveWebEgress: async () => true }));
vi.mock("@/lib/feature-flags/server", () => ({ isDebugModeAvailable: async () => false }));
vi.mock("@/components/settings/web-egress-toggle", () => ({ WebEgressToggle: h.WebEgressToggle }));
vi.mock("@/components/settings/bash-autonomous-toggle", () => ({ BashAutonomousToggle: h.Noop }));
vi.mock("@/components/settings/debug-mode-toggle", () => ({ DebugModeToggle: h.Noop }));
vi.mock("@/components/scope-grants/scope-grant-row", () => ({ ScopeGrantRow: h.Noop }));
vi.mock("@/components/scope-grants/template-authorization-row", () => ({ TemplateAuthorizationRow: h.Noop }));

import ScopeGrantsPage from "@/app/(dashboard)/dashboard/settings/scope-grants/page";

const WS = "11111111-1111-4111-8111-111111111111";
const OTHER_WS = "44444444-4444-4444-8444-444444444444";

// Walk the returned element tree for the toggle element.
function findByType(node: ReactNode, type: unknown): ReactElement | null {
  if (Array.isArray(node)) {
    for (const n of node) {
      const f = findByType(n, type);
      if (f) return f;
    }
    return null;
  }
  if (typeof node !== "object" || node === null) return null;
  const el = node as ReactElement<{ children?: ReactNode }>;
  if (el.type === type) return el;
  return findByType(el.props?.children, type);
}

const toggleProps = async () => {
  const tree = (await ScopeGrantsPage()) as ReactElement;
  const toggle = findByType(tree, h.WebEgressToggle);
  expect(toggle).not.toBeNull();
  return toggle!.props as Record<string, unknown>;
};

beforeEach(() => {
  vi.clearAllMocks();
  h.resolveCurrentWorkspaceId.mockResolvedValue(WS);
});

describe("Scope Grants page: egress card wiring", () => {
  it("passes the loader's lastRequestAt and collection to the toggle when the loader read the page's active workspace", async () => {
    h.loadEgressCardState.mockResolvedValue({ lastRequestAt: "2026-10-26T11:00:00Z", collection: true, workspaceId: WS });
    const p = await toggleProps();
    expect(p.lastRequestAt).toBe("2026-10-26T11:00:00Z");
    expect(p.collection).toBe(true);
    expect(p.isOwner).toBe(true);
    expect(p.initialWebEgress).toBe(true);
    expect(h.loadEgressCardState).toHaveBeenCalledTimes(1);
    expect(h.loadEgressCardState.mock.calls[0][1]).toBe("u1");
  });

  it.each([[true], [false], ["unknown"]])("carries the collection state %s through unchanged", async (collection) => {
    h.loadEgressCardState.mockResolvedValue({ lastRequestAt: null, collection, workspaceId: WS });
    expect((await toggleProps()).collection).toBe(collection);
  });

  it("on a workspace mismatch the toggle gets lastRequestAt = null and collection = unknown (neither workspace's state is shown)", async () => {
    h.loadEgressCardState.mockResolvedValue({ lastRequestAt: "2026-10-26T11:00:00Z", collection: true, workspaceId: OTHER_WS });
    const p = await toggleProps();
    expect(p.lastRequestAt).toBeNull();
    expect(p.collection).toBe("unknown");
  });

  it("a card state that read no workspace (hidden hint) is also forced to unknown", async () => {
    h.loadEgressCardState.mockResolvedValue({ lastRequestAt: "2026-10-26T11:00:00Z", collection: false, workspaceId: null });
    const p = await toggleProps();
    expect(p.lastRequestAt).toBeNull();
    expect(p.collection).toBe("unknown");
  });

  it("the toggle never receives the workspace id", async () => {
    h.loadEgressCardState.mockResolvedValue({ lastRequestAt: null, collection: true, workspaceId: WS });
    const p = await toggleProps();
    expect(Object.keys(p)).not.toContain("workspaceId");
    expect(JSON.stringify(p)).not.toContain(WS);
  });
});
