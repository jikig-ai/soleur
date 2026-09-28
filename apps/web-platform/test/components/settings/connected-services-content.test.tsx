import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

// #9053 — ProviderCard converts its two hand-rolled pending flags to
// usePendingAction. The remove path previously swallowed a thrown parent
// onRemove, leaving `removing=true` forever (stranded disabled control) and
// no visible signal; the hook releases + the new error surface reports it.

import { ConnectedServicesContent } from "@/components/settings/connected-services-content";

let fetchMock: ReturnType<typeof vi.fn>;

beforeEach(() => {
  fetchMock = vi.fn();
  vi.stubGlobal("fetch", fetchMock);
});
afterEach(() => {
  vi.unstubAllGlobals();
  vi.clearAllMocks();
});

describe("ConnectedServicesContent — remove failure surface (#9053)", () => {
  it("a rejected remove releases the button and renders a role=alert error", async () => {
    // DELETE /api/services rejects (network failure).
    fetchMock = vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url === "/api/services") throw new Error("network down");
      return new Response("{}", { status: 404 });
    });
    vi.stubGlobal("fetch", fetchMock);

    render(
      <ConnectedServicesContent
        initialServices={[
          { provider: "anthropic", is_valid: true, validated_at: "2026-01-01T00:00:00Z", updated_at: null },
        ]}
      />,
    );

    const removeBtn = screen.getByRole("button", { name: /^remove$/i });
    await userEvent.click(removeBtn);

    await vi.waitFor(() => {
      expect(screen.getByRole("alert")).toHaveTextContent(/couldn't remove/i);
    });
    await vi.waitFor(() => {
      expect(screen.getByRole("button", { name: /^remove$/i })).toBeEnabled();
    });
  });

  it("a successful remove clears the card's connected state", async () => {
    fetchMock = vi.fn(async () => new Response("{}", { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);

    render(
      <ConnectedServicesContent
        initialServices={[
          { provider: "anthropic", is_valid: true, validated_at: "2026-01-01T00:00:00Z", updated_at: null },
        ]}
      />,
    );

    await userEvent.click(screen.getByRole("button", { name: /^remove$/i }));

    await vi.waitFor(() => {
      // Every provider card renders a Connect affordance; the removed card is
      // the only one that LOSES its Remove button — assert Remove is gone.
      expect(screen.queryByRole("button", { name: /^remove$/i })).toBeNull();
      expect(screen.getAllByRole("button", { name: /^connect$/i }).length).toBeGreaterThan(0);
    });
  });
});
