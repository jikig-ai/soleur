// PR-H+1 (#4098) — discoverability gate for /dashboard/audit/github.
//
// AC19: the parent /dashboard/audit page MUST link to /dashboard/audit/github
// so the new sub-route is reachable from the existing UI. Without this
// anchor, the GitHub audit ledger is reachable by URL only — a
// single-user-incident regression vector for Art. 30 PA-16 (the disclosure
// asserts founders can inspect the ledger).
//
// Why a dedicated test file: the existing audit-github-page.test.tsx
// covers the sub-route; this one regresses on the parent's anchor.

import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";
import "@testing-library/jest-dom/vitest";

const { mockGetUser, mockLimit, mockOrder, mockEq, mockSelect, mockFrom } =
  vi.hoisted(() => ({
    mockGetUser: vi.fn(),
    mockLimit: vi.fn(),
    mockOrder: vi.fn(),
    mockEq: vi.fn(),
    mockSelect: vi.fn(),
    mockFrom: vi.fn(),
  }));

vi.mock("next/navigation", () => ({
  redirect: vi.fn((p: string) => {
    throw new Error(`redirect:${p}`);
  }),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({
    auth: { getUser: mockGetUser },
    from: mockFrom,
  }),
}));

// AuditSections is a "use client" component; the parent server page
// passes it byok rows. Render it as a no-op stub so this test focuses
// on the discoverability anchor.
vi.mock("@/components/audit/audit-sections", () => ({
  AuditSections: () => null,
}));

import AuditPage from "@/app/(dashboard)/dashboard/audit/page";

beforeEach(() => {
  mockGetUser.mockReset();
  mockFrom.mockReset();
  mockSelect.mockReset();
  mockEq.mockReset();
  mockOrder.mockReset();
  mockLimit.mockReset();

  mockGetUser.mockResolvedValue({
    data: { user: { id: "founder-A" } },
  });
  mockLimit.mockResolvedValue({ data: [], error: null });
  mockOrder.mockReturnValue({ limit: mockLimit });
  mockEq.mockReturnValue({ order: mockOrder });
  mockSelect.mockReturnValue({ eq: mockEq });
  mockFrom.mockReturnValue({ select: mockSelect });
});

describe("/dashboard/audit — GitHub audit discoverability link (AC19)", () => {
  it("renders an anchor pointing at /dashboard/audit/github", async () => {
    const Page = await AuditPage();
    render(Page);
    const link = screen.getByTestId("audit-github-link");
    expect(link).toBeInTheDocument();
    expect(link).toHaveAttribute("href", "/dashboard/audit/github");
  });

  it("anchor copy matches the brand voice for the audit ledger", async () => {
    const Page = await AuditPage();
    render(Page);
    expect(
      screen.getByText(/GitHub token-use audit/i),
    ).toBeInTheDocument();
  });
});
