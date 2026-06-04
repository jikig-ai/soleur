import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";

// react-resizable-panels (this fork) needs real layout/ResizeObserver; mock it
// to plain divs so the collapse/reveal *logic* (conditional render driven by
// local state) is what's under test, not the library's flex math.
vi.mock("react-resizable-panels", () => ({
  Group: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  Panel: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  Separator: ({ children }: { children?: React.ReactNode }) => (
    <div data-testid="resize-handle">{children}</div>
  ),
}));

// KbChatContent → ChatSurface pulls next/navigation + server hooks; mock it to a
// stub that exposes the contextPath it was mounted with and an onClose button
// mirroring the real "Close panel" affordance (kb-chat-content.tsx:158-168).
vi.mock("@/components/chat/kb-chat-content", () => ({
  KbChatContent: ({
    contextPath,
    onClose,
  }: {
    contextPath: string;
    onClose: () => void;
    visible: boolean;
  }) => (
    <div data-testid="kb-chat-content" data-context-path={contextPath}>
      <button type="button" aria-label="Close panel" onClick={onClose}>
        close
      </button>
    </div>
  ),
}));

vi.mock("@/components/ui/markdown-renderer", () => ({
  MarkdownRenderer: () => <div data-testid="markdown" />,
}));

vi.mock("@/components/kb/c4-shared", () => ({
  Spinner: () => <div>loading</div>,
  useC4Project: () => ({
    data: { dump: { foo: 1 }, diagnostics: [] },
    error: null,
    loading: false,
    reload: vi.fn(),
  }),
  C4Canvas: () => <div data-testid="c4-canvas" />,
  C4Diagnostics: () => <div data-testid="c4-diagnostics" />,
  C4CodePanel: () => <div data-testid="c4-code-panel" />,
}));

async function renderWorkspace() {
  const { default: C4Workspace } = await import("@/components/kb/c4-workspace");
  return render(
    <C4Workspace
      viewId="index"
      dirPath="knowledge-base/diagrams"
      contextPath="knowledge-base/diagrams/c4-model.md"
    />,
  );
}

beforeEach(() => {
  vi.clearAllMocks();
});

describe("C4Workspace — Concierge collapse/reveal (AC5, AC6)", () => {
  it("renders the Concierge panel by default (no reveal control)", async () => {
    await renderWorkspace();
    expect(screen.getByTestId("kb-chat-content")).toBeTruthy();
    expect(screen.getByLabelText("Collapse Concierge")).toBeTruthy();
    expect(screen.queryByLabelText("Open Concierge")).toBeNull();
    expect(screen.getByTestId("resize-handle")).toBeTruthy();
  });

  it("collapses the right panel when the collapse control is clicked (diagram full width)", async () => {
    await renderWorkspace();
    fireEvent.click(screen.getByLabelText("Collapse Concierge"));
    // Right panel (Concierge + resize handle) is gone; reveal control appears.
    expect(screen.queryByTestId("kb-chat-content")).toBeNull();
    expect(screen.queryByTestId("resize-handle")).toBeNull();
    expect(screen.getByLabelText("Open Concierge")).toBeTruthy();
  });

  it("collapses when the existing KbChatContent X (Close panel) is clicked", async () => {
    await renderWorkspace();
    fireEvent.click(screen.getByLabelText("Close panel"));
    expect(screen.queryByTestId("kb-chat-content")).toBeNull();
    expect(screen.getByLabelText("Open Concierge")).toBeTruthy();
  });

  it("reveals the Concierge again (re-scoped to the same contextPath) when the reveal control is clicked", async () => {
    await renderWorkspace();
    fireEvent.click(screen.getByLabelText("Collapse Concierge"));
    fireEvent.click(screen.getByLabelText("Open Concierge"));
    const chat = screen.getByTestId("kb-chat-content");
    expect(chat).toBeTruthy();
    // Re-mounts scoped to the same document so ChatSurface re-resumes the thread
    // server-side (resumeByContextPath) — explicit unmount-on-collapse choice.
    expect(chat.getAttribute("data-context-path")).toBe(
      "knowledge-base/diagrams/c4-model.md",
    );
    expect(screen.queryByLabelText("Open Concierge")).toBeNull();
  });
});
