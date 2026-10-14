import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { render, waitFor } from "@testing-library/react";

const nav = vi.hoisted(() => ({
  search: "mode=crm-lead",
}));

const captured = vi.hoisted(() => ({
  calls: [] as Array<Record<string, unknown>>,
}));

vi.mock("next/navigation", () => ({
  useParams: () => ({ conversationId: "new" }),
  useSearchParams: () => new URLSearchParams(nav.search),
  useRouter: () => ({ replace: vi.fn(), push: vi.fn() }),
  usePathname: () => "/dashboard/chat/new",
}));

vi.mock("@/hooks/use-nav-resume", () => ({
  useNavResume: () => ({ clearChatId: vi.fn() }),
}));

vi.mock("@/components/chat/chat-surface", () => ({
  ChatSurface: (props: Record<string, unknown>) => {
    captured.calls.push(props);
    return <div data-testid="chat-surface" />;
  },
}));

describe("ChatPage — crm-lead mode", () => {
  let fetchSpy: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    captured.calls.length = 0;
    nav.search = "mode=crm-lead";
    fetchSpy = vi.fn(async () =>
      new Response(JSON.stringify({ content: "# Roadmap" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }),
    );
    vi.stubGlobal("fetch", fetchSpy);
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  async function renderChatPage() {
    const mod = await import(
      "@/app/(dashboard)/dashboard/chat/[conversationId]/page"
    );
    return render(<mod.default />);
  }

  it("passes a crm-lead context on first render and does not fetch", async () => {
    await renderChatPage();

    expect(captured.calls.length).toBeGreaterThan(0);
    expect(captured.calls[0]?.initialContext).toEqual({ type: "crm-lead" });
    expect(captured.calls[0]?.contextPending).toBe(false);
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("ignores mode and still fetches KB when context is also present", async () => {
    nav.search = "context=product/roadmap.md&mode=crm-lead";

    await renderChatPage();

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalled();
    });
    const urls = fetchSpy.mock.calls.map((call) => String(call[0]));
    expect(urls.some((url) => url.includes("/api/kb/content/product/roadmap.md"))).toBe(true);
    expect(captured.calls[0]?.initialContext).not.toEqual({ type: "crm-lead" });
  });
});
