import { describe, it, expect, vi } from "vitest";
import { render } from "@testing-library/react";
import { createUseTeamNamesMock } from "./mocks/use-team-names";
import { ConversationRow } from "@/components/inbox/conversation-row";
import type { ConversationWithPreview } from "@/hooks/use-conversations";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn() }),
  usePathname: () => "/dashboard",
}));

vi.mock("@/hooks/use-team-names", () => ({
  useTeamNames: () => createUseTeamNamesMock(),
}));

function makeConv(overrides: Partial<ConversationWithPreview> = {}): ConversationWithPreview {
  return {
    id: "conv-test",
    user_id: "user-1",
    domain_leader: "cto",
    session_id: null,
    status: "active",
    total_cost_usd: 0,
    input_tokens: 0,
    output_tokens: 0,
    last_active: new Date(Date.now() - 5 * 60_000).toISOString(),
    created_at: new Date(Date.now() - 3_600_000).toISOString(),
    archived_at: null,
    title: "Test conversation",
    preview: "preview text",
    ...overrides,
  } as ConversationWithPreview;
}

describe("ConversationRow — desktop time column stability (issue #2229)", () => {
  it("renders the desktop time span with stable-width utilities", () => {
    const { container } = render(<ConversationRow conversation={makeConv()} />);
    // Desktop block is `div.hidden.w-full.items-center.md:flex`
    const desktopRoot = container.querySelector("div.hidden.md\\:flex");
    expect(desktopRoot).not.toBeNull();

    // The time span is the last <span> before an optional ArchiveButton inside desktop row
    const spans = desktopRoot!.querySelectorAll("span");
    const timeSpan = Array.from(spans).find(
      (el) => /ago|just now/i.test(el.textContent ?? ""),
    );
    expect(timeSpan, "desktop time span").toBeTruthy();

    const classList = timeSpan!.className;
    expect(classList).toContain("w-16");
    expect(classList).toContain("tabular-nums");
    expect(classList).toContain("text-right");
    expect(classList).toContain("shrink-0");
  });

  it("keeps the same time-span classes regardless of single- vs two-digit relative time", () => {
    const singleDigit = makeConv({
      id: "conv-single",
      last_active: new Date(Date.now() - 5 * 60_000).toISOString(),
    });
    const twoDigit = makeConv({
      id: "conv-two",
      last_active: new Date(Date.now() - 12 * 60_000).toISOString(),
    });

    const first = render(<ConversationRow conversation={singleDigit} />);
    const second = render(<ConversationRow conversation={twoDigit} />);

    function getTimeSpanClass(container: HTMLElement): string {
      const desktop = container.querySelector("div.hidden.md\\:flex")!;
      const spans = desktop.querySelectorAll("span");
      const span = Array.from(spans).find((el) =>
        /ago|just now/i.test(el.textContent ?? ""),
      )!;
      return span.className;
    }

    expect(getTimeSpanClass(first.container as HTMLElement)).toBe(
      getTimeSpanClass(second.container as HTMLElement),
    );
  });
});
