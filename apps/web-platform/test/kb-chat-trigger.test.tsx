import { describe, it, expect, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import type { KbChatContextValue } from "@/components/kb/kb-chat-context";

async function renderTrigger(
  ctx: KbChatContextValue | null,
  fallbackHref = "/dashboard/chat/new",
) {
  const { KbChatContext } = await import("@/components/kb/kb-chat-context");
  const { KbChatTrigger } = await import("@/components/kb/kb-chat-trigger");
  return render(
    <KbChatContext value={ctx}>
      <KbChatTrigger fallbackHref={fallbackHref} />
    </KbChatContext>,
  );
}

function makeCtx(overrides: Partial<KbChatContextValue> = {}): KbChatContextValue {
  return {
    open: false,
    openSidebar: vi.fn(),
    closeSidebar: vi.fn(),
    contextPath: "knowledge-base/product/roadmap.md",
    enabled: true,
    messageCount: 0,
    setMessageCount: vi.fn(),
    ...overrides,
  };
}

describe("KbChatTrigger — label + dot reflect messageCount (AC2)", () => {
  it("renders fallback Link when ctx is missing (no provider)", async () => {
    await renderTrigger(null, "/dashboard/chat/new");
    const link = screen.getByText("Chat about this");
    expect(link.tagName.toLowerCase()).toBe("a");
    expect(link.getAttribute("href")).toBe("/dashboard/chat/new");
  });

  it("renders fallback Link when feature flag is disabled", async () => {
    await renderTrigger(makeCtx({ enabled: false }), "/dashboard/chat/new");
    const link = screen.getByText("Chat about this");
    expect(link.tagName.toLowerCase()).toBe("a");
  });

  it("renders 'Ask about this document' with NO thread-indicator dot when messageCount === 0", async () => {
    const { container } = await renderTrigger(makeCtx({ messageCount: 0 }));
    const button = screen.getByRole("button");
    expect(button.textContent).toContain("Ask about this document");
    expect(button.textContent).not.toContain("Continue thread");
    // Thread-indicator dot is identified by data-testid; absent here.
    const dot = container.querySelector("[data-testid='kb-trigger-thread-indicator']");
    expect(dot).toBeNull();
  });

  it("renders 'Continue thread' WITH thread-indicator dot when messageCount > 0 (AC2 GREEN case)", async () => {
    const { container } = await renderTrigger(makeCtx({ messageCount: 3 }));
    const button = screen.getByRole("button");
    expect(button.textContent).toContain("Continue thread");
    expect(button.textContent).not.toContain("Ask about this document");
    const dot = container.querySelector("[data-testid='kb-trigger-thread-indicator']");
    expect(dot).not.toBeNull();
  });

  it("flips label as messageCount transitions 0 → N → 0 (re-render)", async () => {
    const { rerender } = await renderTrigger(makeCtx({ messageCount: 0 }));
    expect(screen.getByRole("button").textContent).toContain("Ask about this document");

    const { KbChatContext } = await import("@/components/kb/kb-chat-context");
    const { KbChatTrigger } = await import("@/components/kb/kb-chat-trigger");
    rerender(
      <KbChatContext value={makeCtx({ messageCount: 5 })}>
        <KbChatTrigger fallbackHref="/dashboard/chat/new" />
      </KbChatContext>,
    );
    expect(screen.getByRole("button").textContent).toContain("Continue thread");

    rerender(
      <KbChatContext value={makeCtx({ messageCount: 0 })}>
        <KbChatTrigger fallbackHref="/dashboard/chat/new" />
      </KbChatContext>,
    );
    expect(screen.getByRole("button").textContent).toContain("Ask about this document");
  });
});
