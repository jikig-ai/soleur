// PR-H (#3244) — Smoke test for /dashboard/audit/github server component.
// Asserts the unauthenticated redirect path and the empty-state copy
// (the load-bearing render until PR-H+1 wires the per-Octokit writer).

import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";

const { mockGetUser, mockEq, mockOrder, mockLimit, mockSelect, mockFrom, mockRedirect } = vi.hoisted(() => {
  const mockLimit = vi.fn();
  const mockOrder = vi.fn(() => ({ limit: mockLimit }));
  const mockEq = vi.fn(() => ({ order: mockOrder }));
  const mockSelect = vi.fn(() => ({ eq: mockEq }));
  const mockFrom = vi.fn(() => ({ select: mockSelect }));
  return {
    mockGetUser: vi.fn(),
    mockEq,
    mockOrder,
    mockLimit,
    mockSelect,
    mockFrom,
    mockRedirect: vi.fn(),
  };
});

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
    from: mockFrom,
  })),
}));

// Next.js's real `redirect()` throws an internal `NEXT_REDIRECT` error to
// halt the server-component render. Mirror that so the page short-circuits
// in tests just like in prod.
vi.mock("next/navigation", () => ({
  redirect: (...args: unknown[]) => {
    mockRedirect(...args);
    throw new Error("NEXT_REDIRECT");
  },
}));

import GitHubAuditPage from "@/app/(dashboard)/dashboard/audit/github/page";

beforeEach(() => {
  vi.clearAllMocks();
  mockLimit.mockResolvedValue({ data: [], error: null });
  mockGetUser.mockResolvedValue({
    data: { user: { id: "founder-A" } },
    error: null,
  });
});

describe("/dashboard/audit/github page", () => {
  it("redirects to /login when no authenticated user", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null }, error: null });
    await expect(GitHubAuditPage()).rejects.toThrow("NEXT_REDIRECT");
    expect(mockRedirect).toHaveBeenCalledWith("/login");
    // The page must NOT issue any DB queries after redirect throws.
    expect(mockFrom).not.toHaveBeenCalled();
  });

  it("queries audit_github_token_use with founder_id belt-and-suspenders filter", async () => {
    await GitHubAuditPage();
    expect(mockFrom).toHaveBeenCalledWith("audit_github_token_use");
    expect(mockEq).toHaveBeenCalledWith("founder_id", "founder-A");
    expect(mockOrder).toHaveBeenCalledWith("ts", { ascending: false });
    expect(mockLimit).toHaveBeenCalledWith(50);
  });

  it("renders the empty-state copy when no rows returned", async () => {
    const Page = await GitHubAuditPage();
    render(Page);
    expect(screen.getByTestId("gh-audit-empty")).toBeInTheDocument();
    expect(screen.getByText(/No GitHub token uses yet/i)).toBeInTheDocument();
    // PR-H+1 (#4098): empty-state copy no longer carries a forward-
    // reference to the tracking issue — the writer is live.
    expect(
      screen.getByText(/populates as Soleur uses your GitHub App/i),
    ).toBeInTheDocument();
  });

  it("renders the row table when at least one row is returned", async () => {
    mockLimit.mockResolvedValue({
      data: [
        {
          ts: "2026-05-19T18:00:00Z",
          installation_id: 99887766,
          repo_full_name: "jikig-ai/soleur",
          endpoint: "/repos/{owner}/{repo}/pulls/{pull_number}",
          response_status: 200,
        },
      ],
      error: null,
    });
    const Page = await GitHubAuditPage();
    render(Page);
    expect(screen.queryByTestId("gh-audit-empty")).not.toBeInTheDocument();
    // The page dual-renders below/at md (desktop table + mobile cards, CSS-gated),
    // so each value appears in BOTH trees in jsdom (which ignores media queries).
    // getAllByText tolerates the duplication while still asserting presence.
    expect(screen.getAllByText("jikig-ai/soleur").length).toBeGreaterThan(0);
    expect(
      screen.getAllByText("/repos/{owner}/{repo}/pulls/{pull_number}").length,
    ).toBeGreaterThan(0);
    expect(screen.getAllByText("200").length).toBeGreaterThan(0);
  });

  it("renders em-dash placeholders when repo_full_name or response_status are NULL (post-anonymise)", async () => {
    mockLimit.mockResolvedValue({
      data: [
        {
          ts: "2026-05-19T18:00:00Z",
          installation_id: 99887766,
          repo_full_name: null,
          endpoint: "/installation/token",
          response_status: null,
        },
      ],
      error: null,
    });
    const Page = await GitHubAuditPage();
    const { container } = render(Page);
    // Two em-dash placeholders (one for repo, one for status).
    const dashes = container.querySelectorAll(".text-soleur-text-muted");
    expect(dashes.length).toBeGreaterThanOrEqual(2);
  });
});
