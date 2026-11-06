import { beforeEach, describe, expect, it, vi } from "vitest";
import type { ReactElement } from "react";
import { existsSync } from "node:fs";
import path from "node:path";
import { EGRESS_AUDIT_PATH } from "@/lib/egress-audit/summary";

type ViewElement = ReactElement<{ result: unknown; filter: string; timeWindow: string }>;

// #9545 PR2 — wiring of the destination page: the `?decision=` search param is the filter, and it reaches the
// loader parsed (an unknown or repeated value is "all", never a 400). A logged-out visitor is redirected before
// anything is loaded. The loader and the view are mocked; their own suites cover their behaviour.

const h = vi.hoisted(() => ({
  getUser: vi.fn(),
  createClient: vi.fn(),
  loadEgressAudit: vi.fn(),
  redirect: vi.fn((to: string) => {
    throw new Error(`NEXT_REDIRECT:${to}`);
  }),
  View: () => null,
}));

vi.mock("next/navigation", () => ({ redirect: h.redirect }));
vi.mock("@/lib/supabase/server", () => ({ createClient: h.createClient }));
vi.mock("@/server/egress-audit-read", () => ({ loadEgressAudit: h.loadEgressAudit }));
vi.mock("@/components/settings/egress-audit-view", () => ({ EgressAuditView: h.View }));

import EgressAuditPage from "@/app/(dashboard)/dashboard/settings/scope-grants/egress-audit/page";

const USER = "33333333-3333-4333-8333-333333333333";
const RESULT = { kind: "unbound" } as const;
const supabase = { auth: { getUser: h.getUser } };

// window-assembly: timeWindow — not a regex-extracted source region: it is the
// ?window= URL parameter (24h / 7d / 30d). The toEqual below pins the props the
// page hands the view, complete against EgressAuditView's prop list.
const render = (decision?: string | string[], timeWindow?: string | string[]) =>
  EgressAuditPage({
    searchParams: Promise.resolve({
      ...(decision === undefined ? {} : { decision }),
      ...(timeWindow === undefined ? {} : { window: timeWindow }),
    }),
  }) as Promise<ViewElement>;

beforeEach(() => {
  vi.clearAllMocks();
  h.createClient.mockResolvedValue(supabase);
  h.getUser.mockResolvedValue({ data: { user: { id: USER } } });
  h.loadEgressAudit.mockResolvedValue(RESULT);
});

describe("egress audit page wiring", () => {
  it("?decision=blocked calls the loader with the cookie client, the user id and `blocked`, and hands the view the same filter and result", async () => {
    const el = await render("blocked");
    expect(h.loadEgressAudit).toHaveBeenCalledTimes(1);
    expect(h.loadEgressAudit).toHaveBeenCalledWith(supabase, USER, "blocked", "30d");
    expect(el.type).toBe(h.View);
    expect(el.props).toEqual({ result: RESULT, filter: "blocked", timeWindow: "30d" });
  });

  it.each(["all", "allowed", "other"])("?decision=%s is passed through", async (decision) => {
    const el = await render(decision);
    expect(h.loadEgressAudit).toHaveBeenCalledWith(supabase, USER, decision, "30d");
    expect(el.props.filter).toBe(decision);
  });

  it("no param, an unknown value or an unsupported spelling (`denied`) falls back to `all`", async () => {
    for (const v of [undefined, "", "bogus", "denied", "BLOCKED"]) {
      h.loadEgressAudit.mockClear();
      const el = await render(v);
      expect(h.loadEgressAudit).toHaveBeenCalledWith(supabase, USER, "all", "30d");
      expect(el.props.filter).toBe("all");
    }
  });

  it("a repeated param uses the first value when it is valid and `all` when it is not", async () => {
    await render(["blocked", "allowed"]);
    expect(h.loadEgressAudit).toHaveBeenLastCalledWith(supabase, USER, "blocked", "30d");
    await render(["bogus", "blocked"]);
    expect(h.loadEgressAudit).toHaveBeenLastCalledWith(supabase, USER, "all", "30d");
  });

  it.each(["24h", "7d", "30d"])("?window=%s reaches the loader as the 4th argument and the view as `timeWindow`", async (w) => {
    const el = await render(undefined, w);
    expect(h.loadEgressAudit).toHaveBeenCalledWith(supabase, USER, "all", w);
    expect(el.props).toEqual({ result: RESULT, filter: "all", timeWindow: w });
  });

  it("an unknown, empty or differently-cased window falls back to 30d (never a 400)", async () => {
    for (const v of ["", "bogus", "7D", "90d", " 24h"]) {
      h.loadEgressAudit.mockClear();
      const el = await render(undefined, v);
      expect([v, h.loadEgressAudit.mock.calls[0][3]]).toEqual([v, "30d"]);
      expect(el.props.timeWindow).toBe("30d");
    }
  });

  it("a repeated window uses the first value when valid and 30d when not", async () => {
    await render(undefined, ["7d", "24h"]);
    expect(h.loadEgressAudit).toHaveBeenLastCalledWith(supabase, USER, "all", "7d");
    await render(undefined, ["bogus", "24h"]);
    expect(h.loadEgressAudit).toHaveBeenLastCalledWith(supabase, USER, "all", "30d");
  });

  it("decision and window are parsed independently", async () => {
    const el = await render("blocked", "24h");
    expect(h.loadEgressAudit).toHaveBeenCalledWith(supabase, USER, "blocked", "24h");
    expect(el.props).toEqual({ result: RESULT, filter: "blocked", timeWindow: "24h" });
    const el2 = await render("bogus", "7d");
    expect(el2.props).toMatchObject({ filter: "all", timeWindow: "7d" });
    const el3 = await render("allowed", "bogus");
    expect(el3.props).toMatchObject({ filter: "allowed", timeWindow: "30d" });
  });

  it("a logged-out visitor is redirected to /login and nothing is loaded", async () => {
    h.getUser.mockResolvedValue({ data: { user: null } });
    await expect(render("blocked")).rejects.toThrow("NEXT_REDIRECT:/login");
    expect(h.redirect).toHaveBeenCalledWith("/login");
    expect(h.loadEgressAudit).not.toHaveBeenCalled();
  });

  it("the page file lives at the route the card link and the filter chips point to (EGRESS_AUDIT_PATH), so a move cannot 404 them", () => {
    // /dashboard/settings/scope-grants/egress-audit -> app/(dashboard)/dashboard/settings/scope-grants/egress-audit/page.tsx
    expect(EGRESS_AUDIT_PATH.startsWith("/dashboard/")).toBe(true);
    const page = path.join(__dirname, "..", "app", "(dashboard)", ...EGRESS_AUDIT_PATH.split("/").filter(Boolean), "page.tsx");
    expect([page, existsSync(page)]).toEqual([page, true]);
  });

  it("the page is forced dynamic so a member's log is never statically cached", async () => {
    const mod = await import("@/app/(dashboard)/dashboard/settings/scope-grants/egress-audit/page");
    expect(mod.dynamic).toBe("force-dynamic");
  });
});
