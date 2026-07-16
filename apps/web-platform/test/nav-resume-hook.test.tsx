// @vitest-environment happy-dom
/**
 * useNavResume — workspace-gated persist/restore for #4826.
 * Clears sessionStorage between tests (shared happy-dom leak class).
 */
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { render, screen, act, waitFor } from "@testing-library/react";
import { resumeKey } from "@/lib/nav-resume";

const WS = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
const WS_B = "bbbbbbbb-cccc-dddd-eeee-ffffffffffff";
const CONV = "11111111-2222-3333-4444-555555555555";

let mockPathname = "/dashboard";
let mockWorkspaceId: string | null = WS;

vi.mock("next/navigation", () => ({
  usePathname: () => mockPathname,
  useRouter: () => ({ replace: vi.fn(), push: vi.fn() }),
}));

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

// Import AFTER mocks so the hook sees them.
import { useNavResume } from "@/hooks/use-nav-resume";

function Probe({
  onReady,
}: {
  onReady?: (api: ReturnType<typeof useNavResume>) => void;
}) {
  const api = useNavResume();
  onReady?.(api);
  return (
    <div>
      <span data-testid="kb-href">{api.getKbEntryHref()}</span>
      <span data-testid="chat-href">{api.getChatEntryHref()}</span>
      <span data-testid="ws">{api.workspaceId ?? "null"}</span>
    </div>
  );
}

describe("useNavResume", () => {
  beforeEach(() => {
    sessionStorage.clear();
    mockPathname = "/dashboard";
    mockWorkspaceId = WS;
  });

  afterEach(() => {
    sessionStorage.clear();
  });

  it("AC1: opening a KB doc writes soleur:nav.resume.<ws>.kb.path", async () => {
    mockPathname = "/dashboard/kb/foo/bar.md";
    await act(async () => {
      render(<Probe />);
    });
    await waitFor(() => {
      expect(sessionStorage.getItem(resumeKey(WS, "kb", "path"))).toBe(
        "foo/bar.md",
      );
    });
  });

  it("AC2: sticky KB href becomes /dashboard/kb/foo/bar.md after visiting doc", async () => {
    mockPathname = "/dashboard/kb/foo/bar.md";
    const { rerender } = await act(async () => render(<Probe />));
    await waitFor(() => {
      expect(screen.getByTestId("kb-href").textContent).toBe(
        "/dashboard/kb/foo/bar.md",
      );
    });
    // Leave KB — sticky href remains
    mockPathname = "/dashboard";
    await act(async () => {
      rerender(<Probe />);
    });
    await waitFor(() => {
      expect(screen.getByTestId("kb-href").textContent).toBe(
        "/dashboard/kb/foo/bar.md",
      );
    });
  });

  it("AC15: sticky href stays section root until workspaceId resolves", async () => {
    mockWorkspaceId = null;
    mockPathname = "/dashboard/kb/foo.md";
    // Pre-seed a path under a real workspace — must NOT be read without ws
    sessionStorage.setItem(resumeKey(WS, "kb", "path"), "foo.md");
    await act(async () => {
      render(<Probe />);
    });
    expect(screen.getByTestId("kb-href").textContent).toBe("/dashboard/kb");
    // Must not write under null workspace
    expect(sessionStorage.getItem(resumeKey("null", "kb", "path"))).toBeNull();
  });

  it("AC6: visiting chat UUID stores it; never stores new", async () => {
    mockPathname = `/dashboard/chat/${CONV}`;
    await act(async () => {
      render(<Probe />);
    });
    await waitFor(() => {
      expect(sessionStorage.getItem(resumeKey(WS, "chat", "id"))).toBe(CONV);
    });

    mockPathname = "/dashboard/chat/new";
    const { unmount } = await act(async () => render(<Probe />));
    // key must still be the previous UUID, not "new"
    expect(sessionStorage.getItem(resumeKey(WS, "chat", "id"))).toBe(CONV);
    unmount();
  });

  it("AC9: workspace A keys are not read when active repo is workspace B", async () => {
    sessionStorage.setItem(resumeKey(WS, "kb", "path"), "from-a.md");
    sessionStorage.setItem(resumeKey(WS, "chat", "id"), CONV);
    mockWorkspaceId = WS_B;
    mockPathname = "/dashboard";
    await act(async () => {
      render(<Probe />);
    });
    await waitFor(() => {
      expect(screen.getByTestId("kb-href").textContent).toBe("/dashboard/kb");
    });
    expect(screen.getByTestId("chat-href").textContent).toBe("/dashboard/chat");
  });

  it("AC14: stored path with .. does not become a dangerous href", async () => {
    sessionStorage.setItem(resumeKey(WS, "kb", "path"), "foo/../etc/passwd");
    mockPathname = "/dashboard";
    await act(async () => {
      render(<Probe />);
    });
    await waitFor(() => {
      expect(screen.getByTestId("kb-href").textContent).toBe("/dashboard/kb");
    });
  });

  it("read/write expanded + scrollTop are workspace-gated", async () => {
    let api: ReturnType<typeof useNavResume> | null = null;
    await act(async () => {
      render(
        <Probe
          onReady={(a) => {
            api = a;
          }}
        />,
      );
    });
    expect(api).not.toBeNull();
    await act(async () => {
      api!.writeExpanded(["a", "b/c"]);
      api!.writeScrollTop(400);
    });
    expect(api!.readExpanded()).toEqual(["a", "b/c"]);
    expect(api!.readScrollTop()).toBe(400);
    expect(sessionStorage.getItem(resumeKey(WS, "kb", "expanded"))).toContain(
      "a",
    );
    expect(sessionStorage.getItem(resumeKey(WS, "kb", "scrollTop"))).toBe(
      "400",
    );

    await act(async () => {
      api!.clearKbPath();
      api!.clearChatId();
    });
    // clear after we stored path via pathname? path may be empty already
    expect(sessionStorage.getItem(resumeKey(WS, "kb", "path"))).toBeNull();
    expect(sessionStorage.getItem(resumeKey(WS, "chat", "id"))).toBeNull();
  });

  it("AC11: no throw when sessionStorage throws (degrades on read to root)", async () => {
    const getSpy = vi
      .spyOn(Storage.prototype, "getItem")
      .mockImplementation(() => {
        throw new Error("SecurityError");
      });
    const setSpy = vi
      .spyOn(Storage.prototype, "setItem")
      .mockImplementation(() => {
        throw new Error("QuotaExceeded");
      });
    // On a non-doc path, sticky href must come from storage — which throws → root.
    mockPathname = "/dashboard";
    await act(async () => {
      expect(() => render(<Probe />)).not.toThrow();
    });
    expect(screen.getByTestId("kb-href").textContent).toBe("/dashboard/kb");
    expect(screen.getByTestId("chat-href").textContent).toBe("/dashboard/chat");
    getSpy.mockRestore();
    setSpy.mockRestore();
  });
});
