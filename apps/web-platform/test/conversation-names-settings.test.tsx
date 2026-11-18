import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { ConversationNamesSettingsContent } from "@/components/settings/conversation-names-settings";
import { TeamNamesProvider } from "@/hooks/use-team-names";
import { SwrTestProvider } from "./helpers/swr-wrapper";

const mockFetch = vi.fn();
vi.stubGlobal("fetch", mockFetch);

function renderTeamSettings() {
  // #9178 — the provider's GET is SWR-keyed and post-FCP-deferred by default.
  // This page is where names are primary content (the real page passes
  // defer={false}); the fresh per-render cache keeps one test's payload out
  // of the next.
  return render(
    <SwrTestProvider>
      <TeamNamesProvider defer={false}>
        <ConversationNamesSettingsContent />
      </TeamNamesProvider>
    </SwrTestProvider>,
  );
}

describe("ConversationNamesSettingsContent", () => {
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

  it("shows domain-specific icon avatars for each leader", async () => {
    renderTeamSettings();

    await waitFor(() => {
      // Each leader row has an avatar with upload trigger
      const avatars = screen.getAllByLabelText(/avatar.*upload/i);
      expect(avatars.length).toBe(8);
    });
  });

  it("renders clickable avatar for each leader with upload trigger", async () => {
    renderTeamSettings();

    await waitFor(() => {
      // Each leader row should have a clickable avatar with an associated file input
      const avatars = screen.getAllByLabelText(/avatar.*upload/i);
      expect(avatars.length).toBe(8);
    });
  });

  it("has hidden file inputs accepting PNG/SVG/WebP", async () => {
    renderTeamSettings();

    await waitFor(() => {
      expect(screen.getAllByPlaceholderText("Enter a name...")).toHaveLength(8);
    });

    const fileInputs = document.querySelectorAll('input[type="file"]');
    expect(fileInputs.length).toBe(8);
    for (const input of fileInputs) {
      expect(input.getAttribute("accept")).toBe("image/png,image/webp");
    }
  });

  it("shows reset button when leader has a custom icon", async () => {
    mockFetch.mockReset();
    mockFetch.mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({
        names: { cto: "Alex" },
        iconPaths: { cto: "settings/team-icons/cto.png" },
        nudgesDismissed: [],
        namingPromptedAt: null,
      }),
    });

    renderTeamSettings();

    await waitFor(() => {
      const resetButtons = screen.getAllByLabelText(/reset.*icon/i);
      expect(resetButtons.length).toBe(1);
    });
  });
});

// Demoted from e2e/team-membership.e2e.ts (#9855) — the e2e asserted
// GET /dashboard/settings/conversation-names is not 404 (route reachability
// after the Phase 5.1 rename). At this layer the equivalent is the route's
// page module existing and rendering its real tree.
import ConversationNamesSettingsPage from "@/app/(dashboard)/dashboard/settings/conversation-names/page";

describe("ConversationNamesSettingsPage (route reachability, demoted from e2e)", () => {
  it("the /dashboard/settings/conversation-names page module renders", async () => {
    render(
      <SwrTestProvider>
        <ConversationNamesSettingsPage />
      </SwrTestProvider>,
    );

    await waitFor(() => {
      expect(screen.getAllByRole("textbox").length).toBeGreaterThan(0);
    });
  });
});

// ---------------------------------------------------------------------------
// #12714 task 11.7 (V6(6), D31(1)/(3)): the leader-icon upload's two non-error outcomes render as a full-width NEUTRAL
// status row under the leader row; "Upload failed. Please try again." stays (red, under the input) for every other
// failure. Strings verbatim from V6(6).
// ---------------------------------------------------------------------------

const PENDING =
  "Saved to GitHub. Your workspace has local changes that aren't on your repository's main branch yet, so it was not updated. The new icon appears here once it is; until then, you see the default icon. You don't need to try again.";
const CONFLICT =
  "An icon with this file name is already on GitHub, so nothing was uploaded. If you just uploaded it, it appears here once your workspace is updated from GitHub.";
const CONFLICT_NOT_SAVED =
  "An icon with this file name is already on GitHub, so nothing was uploaded and the icon shown here stays as it is. Replacing an icon that was uploaded before is not available yet.";
const FAILED = "Upload failed. Please try again.";

describe("ConversationNamesSettingsContent — leader icon upload outcomes (#12714)", () => {
  let teamNamesBody: { names: object; nudgesDismissed: never[]; namingPromptedAt: null; iconPaths?: Record<string, string> };
  let uploadResponse: { ok: boolean; status: number; body: unknown };
  const calls: Array<{ url: string; method: string }> = [];

  beforeEach(() => {
    teamNamesBody = { names: {}, nudgesDismissed: [], namingPromptedAt: null };
    calls.length = 0;
    mockFetch.mockReset();
    mockFetch.mockImplementation(async (url: string, init?: RequestInit) => {
      calls.push({ url, method: init?.method ?? "GET" });
      if (url === "/api/kb/upload") {
        return {
          ok: uploadResponse.ok,
          status: uploadResponse.status,
          json: () => Promise.resolve(uploadResponse.body),
        };
      }
      return { ok: true, status: 200, json: () => Promise.resolve(teamNamesBody) };
    });
    // jsdom has no image decoding: the dimension check resolves through a stub that "loads" a 64x64 image.
    vi.stubGlobal(
      "Image",
      class {
        width = 64;
        height = 64;
        onload: (() => void) | null = null;
        onerror: (() => void) | null = null;
        set src(_v: string) {
          setTimeout(() => this.onload?.(), 0);
        }
        get src() {
          return "blob:stub";
        }
      },
    );
    URL.createObjectURL = vi.fn(() => "blob:stub");
    URL.revokeObjectURL = vi.fn();
  });

  async function uploadCmoIcon() {
    renderTeamSettings();
    await waitFor(() => expect(screen.getByText("Chief Marketing Officer")).toBeInTheDocument());
    const input = document.querySelectorAll('input[type="file"]')[0] as HTMLInputElement;
    const file = new File([new Uint8Array([137, 80, 78, 71])], "icon.png", { type: "image/png" });
    fireEvent.change(input, { target: { files: [file] } });
  }

  it("workspace_sync: 'pending' shows the V6 pending notice as a neutral status row, and still saves the icon path", async () => {
    uploadResponse = { ok: true, status: 201, body: { path: "settings/team-icons/cmo.png", workspace_sync: "pending" } };
    await uploadCmoIcon();
    const status = await screen.findByRole("status");
    expect(status.textContent).toBe(PENDING);
    expect(status.className).not.toMatch(/red/);
    expect(screen.queryByText(FAILED)).not.toBeInTheDocument();
    // The path is saved so the icon appears once the workspace updates (until then the avatar falls back to default).
    await waitFor(() => expect(calls.some((c) => c.url === "/api/team-names" && c.method !== "GET")).toBe(true));
  });

  it("a plain success shows no notice", async () => {
    uploadResponse = { ok: true, status: 201, body: { path: "settings/team-icons/cmo.png" } };
    await uploadCmoIcon();
    await waitFor(() => expect(calls.some((c) => c.url === "/api/team-names" && c.method !== "GET")).toBe(true));
    expect(screen.queryByRole("status")).not.toBeInTheDocument();
    expect(screen.queryByText(FAILED)).not.toBeInTheDocument();
  });

  it("a 409 for the path the leader already has saved shows the V6 409 notice (neutral, not red) and saves nothing", async () => {
    teamNamesBody.iconPaths = { cmo: "settings/team-icons/cmo.png" };
    uploadResponse = { ok: false, status: 409, body: { error: "File already exists" } };
    await uploadCmoIcon();
    const status = await screen.findByRole("status");
    expect(status.textContent).toBe(CONFLICT);
    expect(status.className).not.toMatch(/red/);
    expect(screen.queryByText(FAILED)).not.toBeInTheDocument();
    expect(calls.some((c) => c.url === "/api/team-names" && c.method !== "GET")).toBe(false);
  });

  it.each([
    ["no saved icon (after Reset)", undefined],
    ["a different file type saved", { cmo: "settings/team-icons/cmo.webp" }],
  ])("V12: a 409 with %s shows the 'stays as it is' notice, never the 'appears here' promise", async (_n, iconPaths) => {
    if (iconPaths) teamNamesBody.iconPaths = iconPaths;
    uploadResponse = { ok: false, status: 409, body: { error: "File already exists" } };
    await uploadCmoIcon();
    const status = await screen.findByRole("status");
    expect(status.textContent).toBe(CONFLICT_NOT_SAVED);
    expect(status.className).not.toMatch(/red/);
    expect(screen.queryByText(FAILED)).not.toBeInTheDocument();
    expect(calls.some((c) => c.url === "/api/team-names" && c.method !== "GET")).toBe(false);
  });

  it("the pending notice composes the KB notice's shared clause (one source, simplicity F15)", async () => {
    const { KB_WORKSPACE_SYNC_HELD_CLAUSE, kbWorkspaceSyncPendingNotice } = await import("@/lib/kb-workspace-sync-notice");
    expect(PENDING).toContain(KB_WORKSPACE_SYNC_HELD_CLAUSE);
    expect(kbWorkspaceSyncPendingNotice("upload")).toContain(KB_WORKSPACE_SYNC_HELD_CLAUSE);
    const { readFileSync } = await import("node:fs");
    const { join } = await import("node:path");
    const src = readFileSync(join(__dirname, "..", "components", "settings", "conversation-names-settings.tsx"), "utf8");
    expect(src).toContain("${KB_WORKSPACE_SYNC_HELD_CLAUSE}");
    expect(src).not.toMatch(/class \w+ extends Error/);
  });

  it.each([400, 403, 500, 503])("any other failure (%i) keeps 'Upload failed. Please try again.' and no status row", async (status) => {
    uploadResponse = { ok: false, status, body: { error: "nope" } };
    await uploadCmoIcon();
    expect(await screen.findByText(FAILED)).toBeInTheDocument();
    expect(screen.queryByRole("status")).not.toBeInTheDocument();
  });

  it("a network error keeps 'Upload failed. Please try again.'", async () => {
    mockFetch.mockImplementation(async (url: string) => {
      if (url === "/api/kb/upload") throw new TypeError("network");
      return { ok: true, status: 200, json: () => Promise.resolve(teamNamesBody) };
    });
    await uploadCmoIcon();
    expect(await screen.findByText(FAILED)).toBeInTheDocument();
    expect(screen.queryByRole("status")).not.toBeInTheDocument();
  });
});
