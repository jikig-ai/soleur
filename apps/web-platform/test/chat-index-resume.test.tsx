// @vitest-environment happy-dom
/**
 * Bare /dashboard/chat client resume (#4826 AC7/AC8/AC10).
 */
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { render, waitFor, act } from "@testing-library/react";
import { resumeKey } from "@/lib/nav-resume";

const WS = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
const CONV = "11111111-2222-3333-4444-555555555555";

const replace = vi.fn();

vi.mock("next/navigation", () => ({
  usePathname: () => "/dashboard/chat",
  useRouter: () => ({ replace, push: vi.fn() }),
}));

let mockWorkspaceId: string | null = WS;

vi.mock("@/hooks/use-active-repo", () => ({
  useActiveRepo: () => ({
    data: mockWorkspaceId
      ? {
          workspaceId: mockWorkspaceId,
          repoUrl: null,
          repoName: null,
          repoStatus: "ready",
          fellBackToSolo: false,
        }
      : null,
  }),
}));

import ChatIndexPage from "@/app/(dashboard)/dashboard/chat/page";

describe("chat index resume", () => {
  beforeEach(() => {
    sessionStorage.clear();
    replace.mockClear();
    mockWorkspaceId = WS;
  });

  afterEach(() => {
    sessionStorage.clear();
  });

  it("AC7: replaces to last uuid when present", async () => {
    sessionStorage.setItem(resumeKey(WS, "chat", "id"), CONV);
    await act(async () => {
      render(<ChatIndexPage />);
    });
    await waitFor(() => {
      expect(replace).toHaveBeenCalledWith(`/dashboard/chat/${CONV}`);
    });
  });

  it("AC8/AC10: no stored id lands on /new", async () => {
    await act(async () => {
      render(<ChatIndexPage />);
    });
    await waitFor(() => {
      expect(replace).toHaveBeenCalledWith("/dashboard/chat/new");
    });
  });

  it("AC14: non-UUID stored id does not become href target", async () => {
    sessionStorage.setItem(resumeKey(WS, "chat", "id"), "new");
    await act(async () => {
      render(<ChatIndexPage />);
    });
    await waitFor(() => {
      expect(replace).toHaveBeenCalledWith("/dashboard/chat/new");
    });
    expect(replace).not.toHaveBeenCalledWith(
      expect.stringContaining("/dashboard/chat/new/"),
    );
  });
});
