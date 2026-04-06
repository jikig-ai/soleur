import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, waitFor, act } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

// ---------------------------------------------------------------------------
// Mocks — vi.hoisted ensures these are available when vi.mock factories run
// ---------------------------------------------------------------------------

const { mockPush, mockSearchParams } = vi.hoisted(() => ({
  mockPush: vi.fn(),
  mockSearchParams: { current: new URLSearchParams() },
}));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: mockPush }),
  useSearchParams: () => mockSearchParams.current,
}));

vi.mock("next/font/google", () => ({
  Cormorant_Garamond: () => ({
    className: "mock-serif",
    variable: "--font-serif",
  }),
  Inter: () => ({ className: "mock-sans", variable: "--font-sans" }),
}));

import ConnectRepoPage from "@/app/(auth)/connect-repo/page";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const mockRepo = {
  name: "test-repo",
  fullName: "user/test-repo",
  private: false,
  description: null,
  language: null,
  updatedAt: "2026-04-06T00:00:00Z",
};

let mockFetch: ReturnType<typeof vi.fn>;
let hrefSetter: ReturnType<typeof vi.fn>;

function setupFetchMock(overrides: Record<string, () => Promise<Response>> = {}) {
  const defaults: Record<string, () => Promise<Response>> = {
    "/api/repo/app-info": () =>
      Promise.resolve(new Response(JSON.stringify({ slug: "soleur-ai" }), { status: 200 })),
    "/api/repo/install": () =>
      Promise.resolve(new Response(JSON.stringify({ ok: true }), { status: 200 })),
    "/api/repo/repos": () =>
      Promise.resolve(
        new Response(JSON.stringify({ repos: [mockRepo] }), { status: 200 }),
      ),
    "/api/repo/create": () =>
      Promise.resolve(
        new Response(
          JSON.stringify({ repoUrl: "https://github.com/user/test", fullName: "user/test" }),
          { status: 200 },
        ),
      ),
    "/api/repo/setup": () =>
      Promise.resolve(new Response(JSON.stringify({ status: "cloning" }), { status: 200 })),
    "/api/repo/status": () =>
      Promise.resolve(
        new Response(JSON.stringify({ status: "ready", repoName: "user/test-repo" }), {
          status: 200,
        }),
      ),
  };

  const handlers = { ...defaults, ...overrides };

  mockFetch.mockImplementation((url: string, _options?: RequestInit) => {
    const handler = handlers[url];
    if (handler) return handler();
    return Promise.resolve(new Response(JSON.stringify({}), { status: 404 }));
  });
}

function setCallbackParams(search: string) {
  mockSearchParams.current = new URLSearchParams(search);

  // Also set window.location.search for the useState initializer
  Object.defineProperty(window.location, "search", {
    value: search,
    configurable: true,
    writable: true,
  });
}

// ---------------------------------------------------------------------------
// Setup / Teardown
// ---------------------------------------------------------------------------

beforeEach(() => {
  mockFetch = vi.fn();
  vi.stubGlobal("fetch", mockFetch);
  setupFetchMock();

  // Track window.location.href assignments (redirect detection)
  hrefSetter = vi.fn();
  const originalHref = window.location.href;
  Object.defineProperty(window.location, "href", {
    get: () => originalHref,
    set: hrefSetter,
    configurable: true,
  });

  mockSearchParams.current = new URLSearchParams();
  mockPush.mockClear();
});

afterEach(() => {
  vi.restoreAllMocks();
});

// ===========================================================================
// Phase 1: Callback handler — setup_action broadening
// ===========================================================================

describe("Phase 1: Callback handler", () => {
  test("processes setup_action=update callback (register install + fetch repos)", async () => {
    setCallbackParams("?installation_id=123&setup_action=update");

    render(<ConnectRepoPage />);

    await waitFor(() => {
      expect(screen.getByText("Select a Project")).toBeInTheDocument();
    });

    // Verify POST /api/repo/install was called with the installation ID
    const installCall = mockFetch.mock.calls.find(
      (call) =>
        call[0] === "/api/repo/install" && (call[1] as RequestInit | undefined)?.method === "POST",
    );
    expect(installCall).toBeDefined();
    const installBody = JSON.parse(installCall![1]!.body as string);
    expect(installBody.installationId).toBe(123);
  });

  test("processes setup_action=install callback (regression)", async () => {
    setCallbackParams("?installation_id=456&setup_action=install");

    render(<ConnectRepoPage />);

    await waitFor(() => {
      expect(screen.getByText("Select a Project")).toBeInTheDocument();
    });

    const installCall = mockFetch.mock.calls.find(
      (call) =>
        call[0] === "/api/repo/install" && (call[1] as RequestInit | undefined)?.method === "POST",
    );
    expect(installCall).toBeDefined();
    const installBody = JSON.parse(installCall![1]!.body as string);
    expect(installBody.installationId).toBe(456);
  });

  test("does NOT process callback without setup_action param", async () => {
    setCallbackParams("?installation_id=123");

    render(<ConnectRepoPage />);

    // Should show the choose screen, not process callback
    await waitFor(() => {
      expect(
        screen.getByText("Give Your AI Team the Full Picture"),
      ).toBeInTheDocument();
    });

    const installCall = mockFetch.mock.calls.find(
      (call) => call[0] === "/api/repo/install",
    );
    expect(installCall).toBeUndefined();
  });
});

// ===========================================================================
// Phase 2: Skip redirect via on-click fetch
// ===========================================================================

describe("Phase 2: Skip redirect via on-click fetch", () => {
  test("Connect Existing with installation skips redirect, shows repos", async () => {
    // No callback params — user is on the choose screen
    setupFetchMock({
      "/api/repo/repos": () =>
        Promise.resolve(
          new Response(JSON.stringify({ repos: [mockRepo] }), { status: 200 }),
        ),
    });

    render(<ConnectRepoPage />);

    // Click "Connect Project" (the Connect Existing button)
    const connectBtn = await screen.findByText("Connect Project");
    await userEvent.click(connectBtn);

    // Should skip GitHub redirect and show repo list directly
    await waitFor(() => {
      expect(screen.getByText("Select a Project")).toBeInTheDocument();
    });

    // Should NOT have redirected to GitHub
    expect(hrefSetter).not.toHaveBeenCalled();
  });

  test("Connect Existing without installation shows GitHub redirect", async () => {
    // Repos endpoint returns 400 (no installation)
    setupFetchMock({
      "/api/repo/repos": () =>
        Promise.resolve(
          new Response(
            JSON.stringify({ error: "GitHub App not installed" }),
            { status: 400 },
          ),
        ),
    });

    render(<ConnectRepoPage />);

    const connectBtn = await screen.findByText("Connect Project");
    await userEvent.click(connectBtn);

    // Should show the GitHub redirect screen
    await waitFor(() => {
      expect(screen.getByText("Connecting to GitHub")).toBeInTheDocument();
    });
  });

  test("Connect Existing with network error falls back to GitHub redirect", async () => {
    setupFetchMock({
      "/api/repo/repos": () => Promise.reject(new Error("Network error")),
    });

    render(<ConnectRepoPage />);

    const connectBtn = await screen.findByText("Connect Project");
    await userEvent.click(connectBtn);

    await waitFor(() => {
      expect(screen.getByText("Connecting to GitHub")).toBeInTheDocument();
    });
  });

  test("Connect Existing with installation but no repos shows no-projects state", async () => {
    setupFetchMock({
      "/api/repo/repos": () =>
        Promise.resolve(
          new Response(JSON.stringify({ repos: [] }), { status: 200 }),
        ),
    });

    render(<ConnectRepoPage />);

    const connectBtn = await screen.findByText("Connect Project");
    await userEvent.click(connectBtn);

    await waitFor(() => {
      expect(screen.getByText("No projects found")).toBeInTheDocument();
    });
  });

  test("Create New with installation creates repo directly (no redirect)", async () => {
    // Mock repos to return 200 (installation exists — detected during create)
    setupFetchMock();

    render(<ConnectRepoPage />);

    // Click "Create Project"
    const createBtn = await screen.findByText("Create Project");
    await userEvent.click(createBtn);

    // Fill in project name
    const nameInput = await screen.findByLabelText("Project Name");
    await userEvent.type(nameInput, "my-test-project");

    // Submit the form
    const submitBtn = screen.getByRole("button", { name: /Create Project/i });
    await userEvent.click(submitBtn);

    // Should call POST /api/repo/create directly (no GitHub redirect)
    await waitFor(() => {
      const createCall = mockFetch.mock.calls.find(
        (call) =>
          call[0] === "/api/repo/create" && (call[1] as RequestInit | undefined)?.method === "POST",
      );
      expect(createCall).toBeDefined();
    });

    // Should NOT have redirected to GitHub
    expect(hrefSetter).not.toHaveBeenCalled();
  });

  test("Create New without installation falls back to redirect", async () => {
    // Create endpoint returns 400 (no installation)
    setupFetchMock({
      "/api/repo/create": () =>
        Promise.resolve(
          new Response(
            JSON.stringify({ error: "GitHub App not installed" }),
            { status: 400 },
          ),
        ),
    });

    render(<ConnectRepoPage />);

    const createBtn = await screen.findByText("Create Project");
    await userEvent.click(createBtn);

    const nameInput = await screen.findByLabelText("Project Name");
    await userEvent.type(nameInput, "my-test-project");

    const submitBtn = screen.getByRole("button", { name: /Create Project/i });
    await userEvent.click(submitBtn);

    // Should fall back to GitHub redirect
    await waitFor(() => {
      expect(screen.getByText("Connecting to GitHub")).toBeInTheDocument();
    });
  });
});

// ===========================================================================
// Phase 3: Refresh UI + auto-refresh
// ===========================================================================

describe("Phase 3: Refresh button", () => {
  test("SelectProjectState Refresh button triggers onRefresh", async () => {
    const { SelectProjectState } = await import(
      "@/components/connect-repo/select-project-state"
    );
    const onRefresh = vi.fn();
    render(
      <SelectProjectState
        repos={[mockRepo]}
        loading={false}
        onSelect={vi.fn()}
        onBack={vi.fn()}
        onRefresh={onRefresh}
      />,
    );

    const refreshBtn = screen.getByRole("button", { name: /refresh/i });
    await userEvent.click(refreshBtn);
    expect(onRefresh).toHaveBeenCalledOnce();
  });

  test("NoProjectsState Refresh button triggers onRefresh", async () => {
    const { NoProjectsState } = await import(
      "@/components/connect-repo/no-projects-state"
    );
    const onRefresh = vi.fn();
    render(
      <NoProjectsState
        onUpdateAccess={vi.fn()}
        onBack={vi.fn()}
        onRefresh={onRefresh}
      />,
    );

    const refreshBtn = screen.getByRole("button", { name: /refresh/i });
    await userEvent.click(refreshBtn);
    expect(onRefresh).toHaveBeenCalledOnce();
  });
});

describe("Phase 3: Auto-refresh on visibility change", () => {
  test("visibilitychange to visible triggers repo re-fetch in select_project state", async () => {
    setupFetchMock();
    render(<ConnectRepoPage />);

    // Navigate to select_project via Connect Existing
    const connectBtn = await screen.findByText("Connect Project");
    await userEvent.click(connectBtn);
    await waitFor(() => {
      expect(screen.getByText("Select a Project")).toBeInTheDocument();
    });

    // Clear fetch calls to track only the refresh
    mockFetch.mockClear();
    setupFetchMock();

    // Simulate tab becoming visible
    Object.defineProperty(document, "visibilityState", {
      value: "visible",
      configurable: true,
      writable: true,
    });
    document.dispatchEvent(new Event("visibilitychange"));

    // Should re-fetch repos
    await waitFor(() => {
      const reposCalls = mockFetch.mock.calls.filter(
        (call) => call[0] === "/api/repo/repos",
      );
      expect(reposCalls.length).toBeGreaterThanOrEqual(1);
    });
  });

  test("visibilitychange does NOT trigger fetch in setting_up state", async () => {
    setupFetchMock();
    render(<ConnectRepoPage />);

    // Navigate to select_project, then select a repo to enter setting_up
    const connectBtn = await screen.findByText("Connect Project");
    await userEvent.click(connectBtn);
    await waitFor(() => {
      expect(screen.getByText("Select a Project")).toBeInTheDocument();
    });

    // Select the repo to start setup
    const repoBtn = screen.getByText("test-repo");
    await userEvent.click(repoBtn);
    const connectRepoBtn = screen.getByText("Connect This Repository");
    await userEvent.click(connectRepoBtn);

    // Wait for setting_up state
    await waitFor(() => {
      expect(screen.getByText("Copying your project files")).toBeInTheDocument();
    });

    // Clear fetch and simulate visibility change
    mockFetch.mockClear();
    setupFetchMock();

    Object.defineProperty(document, "visibilityState", {
      value: "visible",
      configurable: true,
      writable: true,
    });
    document.dispatchEvent(new Event("visibilitychange"));

    // Wait a tick to ensure no fetch fires
    await act(async () => {
      await new Promise((r) => setTimeout(r, 100));
    });

    const reposCalls = mockFetch.mock.calls.filter(
      (call) => call[0] === "/api/repo/repos",
    );
    expect(reposCalls.length).toBe(0);
  });

  test("refresh error keeps current state (no transition to interrupted)", async () => {
    setupFetchMock();
    render(<ConnectRepoPage />);

    // Navigate to select_project
    const connectBtn = await screen.findByText("Connect Project");
    await userEvent.click(connectBtn);
    await waitFor(() => {
      expect(screen.getByText("Select a Project")).toBeInTheDocument();
    });

    // Make repos endpoint fail for the refresh
    mockFetch.mockClear();
    setupFetchMock({
      "/api/repo/repos": () => Promise.reject(new Error("Network error")),
    });

    // Trigger refresh via visibilitychange
    Object.defineProperty(document, "visibilityState", {
      value: "visible",
      configurable: true,
      writable: true,
    });
    document.dispatchEvent(new Event("visibilitychange"));

    // Wait and verify state remains select_project
    await act(async () => {
      await new Promise((r) => setTimeout(r, 200));
    });

    // Should still show the repo list, not the interrupted screen
    expect(screen.getByText("Select a Project")).toBeInTheDocument();
    expect(screen.queryByText("Resume")).not.toBeInTheDocument();
  });
});
