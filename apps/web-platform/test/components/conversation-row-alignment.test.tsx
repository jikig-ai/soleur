import { describe, it, expect, vi } from "vitest";
import { render } from "@testing-library/react";
import { createUseTeamNamesMock } from "../mocks/use-team-names";
import { ConversationRow } from "@/components/inbox/conversation-row";
import type { ConversationWithPreview } from "@/hooks/use-conversations";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn() }),
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
    lastMessageLeader: null,
    title: "Test conversation",
    preview: "preview text",
    ...overrides,
  } as ConversationWithPreview;
}

describe("ConversationRow — desktop time column stability (issue #2229)", () => {
  it("renders the desktop time span with stable-width utilities", () => {
    const { container } = render(<ConversationRow conversation={makeConv()} />);
    const desktopRoot = container.querySelector("div.hidden.md\\:flex");
    expect(desktopRoot).not.toBeNull();

    const spans = desktopRoot!.querySelectorAll("span");
    const timeSpan = Array.from(spans).find((el) =>
      /ago|just now/i.test(el.textContent ?? ""),
    );
    expect(timeSpan, "desktop time span").toBeTruthy();

    const classList = timeSpan!.className;
    expect(classList).toContain("w-16");
    expect(classList).toContain("tabular-nums");
    expect(classList).toContain("text-right");
    expect(classList).toContain("shrink-0");
  });
});
