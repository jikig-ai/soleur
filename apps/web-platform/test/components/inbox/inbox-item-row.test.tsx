import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import type { InboxItemRowData } from "@/lib/inbox-severity";

const mockPush = vi.fn();
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: mockPush }),
}));

import { InboxItemRow } from "@/components/inbox/inbox-item-row";

function row(over: Partial<InboxItemRowData> = {}): InboxItemRowData {
  return {
    id: "11111111-1111-4111-8111-111111111111",
    severity: "info",
    source: "task_completed",
    title: "Chief Legal Officer finished",
    source_ref: { conversationId: "conv-1" },
    status: "unread",
    created_at: "2026-07-01T00:00:00.000Z",
    read_at: null,
    acted_at: null,
    archived_at: null,
    ...over,
  };
}

beforeEach(() => {
  mockPush.mockClear();
  global.fetch = vi
    .fn()
    .mockResolvedValue({ ok: true, json: async () => ({ ok: true }) }) as unknown as typeof fetch;
});
afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

describe("InboxItemRow", () => {
  it("renders as plain text (no anchors) and navigates to the built deep link on click", () => {
    render(<InboxItemRow item={row()} />);
    expect(screen.getByText("Chief Legal Officer finished")).toBeTruthy();
    // No <a> built from content (nav is a router push only).
    expect(document.querySelector("a")).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: /chief legal officer finished/i }));
    expect(mockPush).toHaveBeenCalledWith("/dashboard/chat/conv-1");
  });

  it("is non-navigating when the deep-link target is missing", () => {
    render(<InboxItemRow item={row({ source_ref: null })} />);
    // No navigable button role for the row when there's no link.
    expect(
      screen.queryByRole("button", { name: /chief legal officer finished/i }),
    ).toBeNull();
    expect(screen.getByText(/nothing to open yet/i)).toBeTruthy();
  });

  it("action_required: Archive is guarded (disabled) until the item is marked done", () => {
    render(<InboxItemRow item={row({ severity: "action_required", title: "billing failed" })} />);
    const archive = screen.getByRole("button", { name: "Archive item" });
    expect(archive).toBeDisabled();
    // The primary affordance is Mark done.
    expect(screen.getByRole("button", { name: "Mark done" })).toBeTruthy();
  });

  it("Mark done posts the acted transition and reports the change", async () => {
    const onChanged = vi.fn();
    render(
      <InboxItemRow
        item={row({ severity: "action_required", title: "billing failed" })}
        onChanged={onChanged}
      />,
    );
    fireEvent.click(screen.getByRole("button", { name: "Mark done" }));
    await waitFor(() => expect(onChanged).toHaveBeenCalled());
    expect(global.fetch).toHaveBeenCalledWith(
      "/api/inbox/11111111-1111-4111-8111-111111111111/state",
      expect.objectContaining({
        method: "POST",
        body: JSON.stringify({ action: "acted" }),
      }),
    );
  });

  it("archiving an acted action_required item requires a confirm step", async () => {
    const onChanged = vi.fn();
    render(
      <InboxItemRow
        item={row({
          severity: "action_required",
          title: "billing failed",
          acted_at: "2026-07-02T00:00:00.000Z",
        })}
        onChanged={onChanged}
      />,
    );
    // Acted → archive enabled; first click reveals a confirm, does NOT archive yet.
    fireEvent.click(screen.getByRole("button", { name: "Archive item" }));
    expect(global.fetch).not.toHaveBeenCalled();
    expect(screen.getByText(/archive this\?/i)).toBeTruthy();

    fireEvent.click(screen.getByRole("button", { name: "Confirm archive" }));
    await waitFor(() => expect(onChanged).toHaveBeenCalled());
    expect(global.fetch).toHaveBeenCalledWith(
      expect.stringContaining("/state"),
      expect.objectContaining({ body: JSON.stringify({ action: "archived" }) }),
    );
  });

  it("info items archive directly (no confirm)", async () => {
    const onChanged = vi.fn();
    render(<InboxItemRow item={row({ severity: "info" })} onChanged={onChanged} />);
    fireEvent.click(screen.getByRole("button", { name: "Archive item" }));
    await waitFor(() => expect(onChanged).toHaveBeenCalled());
    expect(global.fetch).toHaveBeenCalledWith(
      expect.stringContaining("/state"),
      expect.objectContaining({ body: JSON.stringify({ action: "archived" }) }),
    );
  });
});
