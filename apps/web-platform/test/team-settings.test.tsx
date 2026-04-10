import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { TeamSettingsContent } from "@/components/settings/team-settings";
import { TeamNamesProvider } from "@/hooks/use-team-names";

const mockFetch = vi.fn();
vi.stubGlobal("fetch", mockFetch);

function renderTeamSettings() {
  return render(
    <TeamNamesProvider>
      <TeamSettingsContent />
    </TeamNamesProvider>,
  );
}

describe("TeamSettingsContent", () => {
  beforeEach(() => {
    mockFetch.mockReset();
    mockFetch.mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({
        names: { cmo: "Sarah", cto: "Alex" },
        nudgesDismissed: [],
        namingPromptedAt: null,
      }),
    });
  });

  it("renders all 8 domain leaders", async () => {
    renderTeamSettings();

    await waitFor(() => {
      expect(screen.getByText("Chief Marketing Officer")).toBeInTheDocument();
      expect(screen.getByText("Chief Technology Officer")).toBeInTheDocument();
      expect(screen.getByText("Chief Financial Officer")).toBeInTheDocument();
      expect(screen.getByText("Chief Product Officer")).toBeInTheDocument();
      expect(screen.getByText("Chief Revenue Officer")).toBeInTheDocument();
      expect(screen.getByText("Chief Operations Officer")).toBeInTheDocument();
      expect(screen.getByText("Chief Legal Officer")).toBeInTheDocument();
      expect(screen.getByText("Chief Communications Officer")).toBeInTheDocument();
    });
  });

  it("shows existing custom names in input fields", async () => {
    renderTeamSettings();

    await waitFor(() => {
      const inputs = screen.getAllByPlaceholderText("Enter a name...");
      // Find inputs with values
      const sarahInput = inputs.find((i) => (i as HTMLInputElement).value === "Sarah");
      const alexInput = inputs.find((i) => (i as HTMLInputElement).value === "Alex");
      expect(sarahInput).toBeDefined();
      expect(alexInput).toBeDefined();
    });
  });

  it("shows the page heading 'Domain Leaders'", async () => {
    renderTeamSettings();

    await waitFor(() => {
      expect(screen.getByText("Domain Leaders")).toBeInTheDocument();
    });
  });

  it("shows 'Changes save automatically' text", async () => {
    renderTeamSettings();

    await waitFor(() => {
      expect(screen.getByText("Changes save automatically")).toBeInTheDocument();
    });
  });

  it("has 8 input fields for leader names", async () => {
    renderTeamSettings();

    await waitFor(() => {
      const inputs = screen.getAllByPlaceholderText("Enter a name...");
      expect(inputs).toHaveLength(8);
    });
  });

  it("calls API when input value changes", async () => {
    renderTeamSettings();

    await waitFor(() => {
      expect(screen.getAllByPlaceholderText("Enter a name...")).toHaveLength(8);
    });

    // Clear prior mock calls from the initial fetch
    mockFetch.mockClear();
    mockFetch.mockResolvedValue({ ok: true, json: () => Promise.resolve({ saved: true }) });

    const inputs = screen.getAllByPlaceholderText("Enter a name...");
    // Change the first empty input (CFO, index depends on order)
    fireEvent.change(inputs[2], { target: { value: "Jordan" } });

    // The debounced save fires (we need to wait)
    await waitFor(() => {
      expect(mockFetch).toHaveBeenCalledWith(
        "/api/team-names",
        expect.objectContaining({ method: "PUT" }),
      );
    });
  });

  it("shows colored badges for each leader", async () => {
    renderTeamSettings();

    await waitFor(() => {
      // Badges show 3-letter role acronyms by default, or custom name prefix
      expect(screen.getByText("CMO")).toBeInTheDocument();
      expect(screen.getByText("CTO")).toBeInTheDocument();
    });
  });
});
