import { describe, it, expect, vi, afterEach } from "vitest";
import { render, screen, cleanup } from "@testing-library/react";
import {
  KbChatContext,
  type KbChatContextValue,
} from "@/components/kb/kb-chat-context";
import { KbChatTrigger } from "@/components/kb/kb-chat-trigger";
import { KbContentHeader } from "@/components/kb/kb-content-header";
import { KbChatQuoteBridgeProvider } from "@/components/kb/kb-chat-quote-bridge";

// #7326 — three fixes that only misbehave on a phone, so every assertion here
// pins the mobile branch explicitly rather than trusting happy-dom's 1024px
// default (which is the width at which the old code was already correct).

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), replace: vi.fn(), prefetch: vi.fn() }),
  usePathname: () => "/dashboard/kb/diagrams/c4-model.md",
  useSearchParams: () => new URLSearchParams(),
}));

// Captures what ChatSurface was handed, so the composer placeholder can be
// asserted without mounting the whole chat stack.
const sidebarPropsSpy = vi.fn();
vi.mock("@/components/chat/chat-surface", () => ({
  ChatSurface: (props: { sidebarProps?: Record<string, unknown> }) => {
    sidebarPropsSpy(props.sidebarProps);
    return <div data-testid="chat-surface" />;
  },
}));

vi.mock("@/lib/analytics-client", () => ({ track: vi.fn() }));

function ctx(over: Partial<KbChatContextValue> = {}): KbChatContextValue {
  return {
    enabled: true,
    open: false,
    openSidebar: vi.fn(),
    closeSidebar: vi.fn(),
    messageCount: 0,
    setMessageCount: vi.fn(),
    suppressSidebar: false,
    embeddedConciergeOpen: false,
    revealEmbeddedConcierge: vi.fn(),
    ...over,
  } as KbChatContextValue;
}

afterEach(() => {
  cleanup();
  sidebarPropsSpy.mockClear();
});

describe("KbChatTrigger — fits the phone without losing its accessible name", () => {
  it("renders a SHORT visible label for mobile and the full one for md+", () => {
    render(
      <KbChatContext.Provider value={ctx()}>
        <KbChatTrigger fallbackHref="/dashboard/chat/new" />
      </KbChatContext.Provider>,
    );
    const short = screen.getByText("Ask");
    const full = screen.getByText("Ask about this document");
    // A CSS swap, not a JS branch: both are in the DOM so the header needs no
    // viewport read and there is no hydration-time flip.
    expect(short.className).toContain("md:hidden");
    expect(full.className).toContain("hidden");
    expect(full.className).toContain("md:inline");
  });

  it("keeps the FULL wording as the accessible name at every width", () => {
    render(
      <KbChatContext.Provider value={ctx()}>
        <KbChatTrigger fallbackHref="/dashboard/chat/new" />
      </KbChatContext.Provider>,
    );
    // aria-label overrides text content entirely, so a screen reader (and any
    // agent driving by accessible name) never sees the abbreviated "Ask".
    expect(
      screen.getByRole("button", { name: "Ask about this document" }),
    ).toBeTruthy();
  });

  it("shortens 'Continue thread' to 'Continue' once a thread exists", () => {
    render(
      <KbChatContext.Provider value={ctx({ messageCount: 3 })}>
        <KbChatTrigger fallbackHref="/dashboard/chat/new" />
      </KbChatContext.Provider>,
    );
    expect(screen.getByText("Continue").className).toContain("md:hidden");
    expect(screen.getByRole("button", { name: "Continue thread" })).toBeTruthy();
  });

  it("refuses to shrink or wrap — it is the fixed side of the header", () => {
    render(
      <KbChatContext.Provider value={ctx()}>
        <KbChatTrigger fallbackHref="/dashboard/chat/new" />
      </KbChatContext.Provider>,
    );
    const btn = screen.getByRole("button", { name: "Ask about this document" });
    expect(btn.className).toContain("shrink-0");
    expect(btn.className).toContain("whitespace-nowrap");
    expect(btn.className).toContain("min-h-[44px]");
  });
});

describe("KbContentHeader — the breadcrumb yields, the actions do not", () => {
  it("lets the breadcrumb group shrink and pins the action group", () => {
    const { container } = render(
      <KbChatContext.Provider value={ctx()}>
        <KbContentHeader
          joinedPath="engineering/architecture/diagrams/c4-model.md"
          chatUrl="/dashboard/chat/new"
        />
      </KbChatContext.Provider>,
    );
    const header = container.querySelector("header") as HTMLElement;
    const [left, right] = Array.from(header.children) as HTMLElement[];

    // Without min-w-0 the left group takes max-content width, justify-between
    // has nothing to distribute, and the actions leave the screen entirely.
    expect(left.className).toContain("min-w-0");
    expect(left.className).toContain("flex-1");
    expect(right.className).toContain("shrink-0");
  });
});

describe("KbChatContent — the takeover owns the chrome", () => {
  it("suppresses its own filename+close header inside the takeover", async () => {
    const { KbChatContent } = await import("@/components/chat/kb-chat-content");
    render(
      <KbChatContext.Provider value={ctx()}>
        <KbChatQuoteBridgeProvider onOpenSidebar={vi.fn()}>
          <KbChatContent contextPath="a/b/c4-model.md" onClose={vi.fn()} visible mobileTakeover />
        </KbChatQuoteBridgeProvider>
      </KbChatContext.Provider>,
    );
    // The takeover header already carries both the filename AND the exit —
    // rendering this one there duplicated the name and gave two competing
    // dismiss controls.
    expect(screen.queryByLabelText("Close panel")).toBeNull();
  });

  it("KEEPS that header on desktop, where it is the only close affordance", async () => {
    const { KbChatContent } = await import("@/components/chat/kb-chat-content");
    render(
      <KbChatContext.Provider value={ctx()}>
        <KbChatQuoteBridgeProvider onOpenSidebar={vi.fn()}>
          <KbChatContent contextPath="a/b/c4-model.md" onClose={vi.fn()} visible />
        </KbChatQuoteBridgeProvider>
      </KbChatContext.Provider>,
    );
    expect(screen.getByLabelText("Close panel")).toBeTruthy();
  });

  it("drops the keyboard chord from the placeholder inside the takeover", async () => {
    const { KbChatContent } = await import("@/components/chat/kb-chat-content");
    render(
      <KbChatContext.Provider value={ctx()}>
        <KbChatQuoteBridgeProvider onOpenSidebar={vi.fn()}>
          <KbChatContent contextPath="a/b/c4-model.md" onClose={vi.fn()} visible mobileTakeover />
        </KbChatQuoteBridgeProvider>
      </KbChatContext.Provider>,
    );
    const props = sidebarPropsSpy.mock.calls.at(-1)?.[0] as { placeholder: string };
    // At rows={1} the extra clause wrapped past the textarea and was clipped
    // mid-glyph — and it named a chord a touch device cannot press.
    expect(props.placeholder).toBe("Ask about this document");
    expect(props.placeholder).not.toMatch(/Shift/);
  });

  it("KEEPS the quote chord on desktop, where it is reachable", async () => {
    const { KbChatContent } = await import("@/components/chat/kb-chat-content");
    render(
      <KbChatContext.Provider value={ctx()}>
        <KbChatQuoteBridgeProvider onOpenSidebar={vi.fn()}>
          <KbChatContent contextPath="a/b/c4-model.md" onClose={vi.fn()} visible />
        </KbChatQuoteBridgeProvider>
      </KbChatContext.Provider>,
    );
    const props = sidebarPropsSpy.mock.calls.at(-1)?.[0] as { placeholder: string };
    expect(props.placeholder).toMatch(/to quote selection$/);
  });
});
