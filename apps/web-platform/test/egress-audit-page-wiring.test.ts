import { beforeEach, describe, expect, it, vi } from "vitest";
import type { ReactElement } from "react";

type ViewElement = ReactElement<{ result: unknown; filter: string }>;

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

const render = (decision?: string | string[]) =>
  EgressAuditPage({ searchParams: Promise.resolve(decision === undefined ? {} : { decision }) }) as Promise<ViewElement>;

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
    expect(h.loadEgressAudit).toHaveBeenCalledWith(supabase, USER, "blocked");
    expect(el.type).toBe(h.View);
    expect(el.props).toEqual({ result: RESULT, filter: "blocked" });
  });

  it.each(["all", "allowed", "other"])("?decision=%s is passed through", async (decision) => {
    const el = await render(decision);
    expect(h.loadEgressAudit).toHaveBeenCalledWith(supabase, USER, decision);
    expect(el.props.filter).toBe(decision);
  });

  it("no param, an unknown value or an unsupported spelling (`denied`) falls back to `all`", async () => {
    for (const v of [undefined, "", "bogus", "denied", "BLOCKED"]) {
      h.loadEgressAudit.mockClear();
      const el = await render(v);
      expect(h.loadEgressAudit).toHaveBeenCalledWith(supabase, USER, "all");
      expect(el.props.filter).toBe("all");
    }
  });

  it("a repeated param uses the first value when it is valid and `all` when it is not", async () => {
    await render(["blocked", "allowed"]);
    expect(h.loadEgressAudit).toHaveBeenLastCalledWith(supabase, USER, "blocked");
    await render(["bogus", "blocked"]);
    expect(h.loadEgressAudit).toHaveBeenLastCalledWith(supabase, USER, "all");
  });

  it("a logged-out visitor is redirected to /login and nothing is loaded", async () => {
    h.getUser.mockResolvedValue({ data: { user: null } });
    await expect(render("blocked")).rejects.toThrow("NEXT_REDIRECT:/login");
    expect(h.redirect).toHaveBeenCalledWith("/login");
    expect(h.loadEgressAudit).not.toHaveBeenCalled();
  });

  it("the page is forced dynamic so a member's log is never statically cached", async () => {
    const mod = await import("@/app/(dashboard)/dashboard/settings/scope-grants/egress-audit/page");
    expect(mod.dynamic).toBe("force-dynamic");
  });
});
