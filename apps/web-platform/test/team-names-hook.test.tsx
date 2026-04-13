import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, act } from "@testing-library/react";
import { TeamNamesProvider, useTeamNames } from "@/hooks/use-team-names";

// Mock fetch globally
const mockFetch = vi.fn();
vi.stubGlobal("fetch", mockFetch);

function TestConsumer() {
  const { names, getDisplayName, getIconPath, loading, error, refetch } = useTeamNames();
  return (
    <div>
      <span data-testid="loading">{String(loading)}</span>
      <span data-testid="error">{error ?? "none"}</span>
      <span data-testid="cto-display">{getDisplayName("cto")}</span>
      <span data-testid="cmo-display">{getDisplayName("cmo")}</span>
      <span data-testid="cto-name">{names.cto ?? "none"}</span>
      <span data-testid="cto-icon">{getIconPath("cto") ?? "none"}</span>
      <span data-testid="cmo-icon">{getIconPath("cmo") ?? "none"}</span>
      <button data-testid="refetch" onClick={refetch}>Refetch</button>
    </div>
  );
}

function renderWithProvider() {
  return render(
    <TeamNamesProvider>
      <TestConsumer />
    </TeamNamesProvider>,
  );
}

describe("useTeamNames", () => {
  beforeEach(() => {
    mockFetch.mockReset();
  });

  it("returns role acronym when no custom name is set", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve({ names: {}, nudgesDismissed: [], namingPromptedAt: null }),
    });

    await act(async () => {
      renderWithProvider();
    });

    expect(screen.getByTestId("cto-display").textContent).toBe("CTO");
  });

  it("returns 'Name (Role)' format when custom name is set", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve({
        names: { cto: "Alex", cmo: "Sarah" },
        nudgesDismissed: [],
        namingPromptedAt: null,
      }),
    });

    await act(async () => {
      renderWithProvider();
    });

    expect(screen.getByTestId("cto-display").textContent).toBe("Alex (CTO)");
    expect(screen.getByTestId("cmo-display").textContent).toBe("Sarah (CMO)");
  });

  it("exposes raw name map", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve({
        names: { cto: "Alex" },
        nudgesDismissed: [],
        namingPromptedAt: null,
      }),
    });

    await act(async () => {
      renderWithProvider();
    });

    expect(screen.getByTestId("cto-name").textContent).toBe("Alex");
  });

  it("shows loading state initially", async () => {
    let resolvePromise: (v: unknown) => void;
    mockFetch.mockReturnValueOnce(
      new Promise((resolve) => {
        resolvePromise = resolve;
      }),
    );

    renderWithProvider();

    expect(screen.getByTestId("loading").textContent).toBe("true");

    await act(async () => {
      resolvePromise!({
        ok: true,
        json: () => Promise.resolve({ names: {}, nudgesDismissed: [], namingPromptedAt: null }),
      });
    });

    expect(screen.getByTestId("loading").textContent).toBe("false");
  });

  it("handles fetch errors gracefully and exposes error state", async () => {
    mockFetch.mockRejectedValueOnce(new Error("Network error"));

    await act(async () => {
      renderWithProvider();
    });

    // Falls back to empty names — no custom names displayed
    expect(screen.getByTestId("cto-display").textContent).toBe("CTO");
    expect(screen.getByTestId("loading").textContent).toBe("false");
    expect(screen.getByTestId("error").textContent).toBe("Network error");
  });

  it("refetch retries and clears error on success", async () => {
    mockFetch.mockRejectedValueOnce(new Error("Network error"));

    await act(async () => {
      renderWithProvider();
    });

    expect(screen.getByTestId("error").textContent).toBe("Network error");

    // Set up a successful response for the retry
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve({
        names: { cto: "Alex" },
        nudgesDismissed: [],
        namingPromptedAt: null,
      }),
    });

    await act(async () => {
      screen.getByTestId("refetch").click();
    });

    expect(screen.getByTestId("error").textContent).toBe("none");
    expect(screen.getByTestId("cto-display").textContent).toBe("Alex (CTO)");
  });

  it("returns icon path from API response", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve({
        names: { cto: "Alex" },
        iconPaths: { cto: "settings/team-icons/cto.png" },
        nudgesDismissed: [],
        namingPromptedAt: null,
      }),
    });

    await act(async () => {
      renderWithProvider();
    });

    expect(screen.getByTestId("cto-icon").textContent).toBe("settings/team-icons/cto.png");
    expect(screen.getByTestId("cmo-icon").textContent).toBe("none");
  });

  it("returns null icon path when no icons are set", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve({
        names: {},
        nudgesDismissed: [],
        namingPromptedAt: null,
      }),
    });

    await act(async () => {
      renderWithProvider();
    });

    expect(screen.getByTestId("cto-icon").textContent).toBe("none");
  });
});
