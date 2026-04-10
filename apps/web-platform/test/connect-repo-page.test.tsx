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

vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({
    auth: {
      linkIdentity: vi.fn().mockResolvedValue({ data: {}, error: null }),
    },
  }),
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
    // Repos endpoint returns 400 (no installation) AND detection returns not installed
    setupFetchMock({
      "/api/repo/repos": () =>
        Promise.resolve(
          new Response(
            JSON.stringify({ error: "GitHub App not installed" }),
            { status: 400 },
          ),
        ),
      "/api/repo/detect-installation": () =>
        Promise.resolve(
          new Response(
            JSON.stringify({ installed: false, reason: "not_installed" }),
            { status: 200 },
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
    // Create endpoint returns 400 (no installation) AND detection returns not installed
    setupFetchMock({
      "/api/repo/create": () =>
        Promise.resolve(
          new Response(
            JSON.stringify({ error: "GitHub App not installed" }),
            { status: 400 },
          ),
        ),
      "/api/repo/detect-installation": () =>
        Promise.resolve(
          new Response(
            JSON.stringify({ installed: false, reason: "not_installed" }),
            { status: 200 },
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
      expect(screen.getByText("Cloning repository")).toBeInTheDocument();
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

// ===========================================================================
// Phase 4: Auto-detect existing installation (breaks redirect loop)
// ===========================================================================

describe("Phase 4: Auto-detect existing installation", () => {
  test("on mount: auto-detects installation and skips to repo selection", async () => {
    // No callback params, repos returns 400 (no installation_id stored),
    // but detect-installation finds the app is installed
    setupFetchMock({
      "/api/repo/repos": () =>
        Promise.resolve(
          new Response(
            JSON.stringify({ error: "GitHub App not installed" }),
            { status: 400 },
          ),
        ),
      "/api/repo/detect-installation": () =>
        Promise.resolve(
          new Response(
            JSON.stringify({ installed: true, repos: [mockRepo] }),
            { status: 200 },
          ),
        ),
    });

    render(<ConnectRepoPage />);

    // Should auto-detect and skip to repo selection
    await waitFor(() => {
      expect(screen.getByText("Select a Project")).toBeInTheDocument();
    });

    // Verify detect-installation was called
    const detectCall = mockFetch.mock.calls.find(
      (call) => call[0] === "/api/repo/detect-installation",
    );
    expect(detectCall).toBeDefined();
  });

  test("on mount: detection returns not installed, stays on choose screen", async () => {
    setupFetchMock({
      "/api/repo/detect-installation": () =>
        Promise.resolve(
          new Response(
            JSON.stringify({ installed: false, reason: "not_installed" }),
            { status: 200 },
          ),
        ),
    });

    render(<ConnectRepoPage />);

    // Should remain on the choose screen
    await waitFor(() => {
      expect(
        screen.getByText("Give Your AI Team the Full Picture"),
      ).toBeInTheDocument();
    });
  });

  test("on mount: detection fails silently, stays on choose screen", async () => {
    setupFetchMock({
      "/api/repo/detect-installation": () =>
        Promise.resolve(new Response("Server Error", { status: 500 })),
    });

    render(<ConnectRepoPage />);

    await waitFor(() => {
      expect(
        screen.getByText("Give Your AI Team the Full Picture"),
      ).toBeInTheDocument();
    });
  });

  test("Connect Existing: falls back to detect-installation when repos returns 400", async () => {
    setupFetchMock({
      "/api/repo/repos": () =>
        Promise.resolve(
          new Response(
            JSON.stringify({ error: "GitHub App not installed" }),
            { status: 400 },
          ),
        ),
      "/api/repo/detect-installation": () =>
        Promise.resolve(
          new Response(
            JSON.stringify({ installed: true, repos: [mockRepo] }),
            { status: 200 },
          ),
        ),
    });

    render(<ConnectRepoPage />);

    // Wait for mount detection to complete (it will also detect)
    await waitFor(() => {
      expect(screen.getByText("Select a Project")).toBeInTheDocument();
    });
  });

  test("Create New: falls back to detect-installation when create returns 400, then retries", async () => {
    let createCallCount = 0;
    let detectCallCount = 0;
    setupFetchMock({
      "/api/repo/create": () => {
        createCallCount++;
        if (createCallCount === 1) {
          // First call: no installation
          return Promise.resolve(
            new Response(
              JSON.stringify({ error: "GitHub App not installed" }),
              { status: 400 },
            ),
          );
        }
        // Retry after detection: succeeds
        return Promise.resolve(
          new Response(
            JSON.stringify({
              repoUrl: "https://github.com/user/my-project",
              fullName: "user/my-project",
            }),
            { status: 200 },
          ),
        );
      },
      "/api/repo/detect-installation": () => {
        detectCallCount++;
        if (detectCallCount === 1) {
          // Mount-time detection: not installed (let user reach choose screen)
          return Promise.resolve(
            new Response(
              JSON.stringify({ installed: false, reason: "not_installed" }),
              { status: 200 },
            ),
          );
        }
        // Create-flow detection: installed
        return Promise.resolve(
          new Response(
            JSON.stringify({ installed: true, repos: [] }),
            { status: 200 },
          ),
        );
      },
    });

    render(<ConnectRepoPage />);

    // Navigate to create screen
    const createBtn = await screen.findByText("Create Project");
    await userEvent.click(createBtn);

    const nameInput = await screen.findByLabelText("Project Name");
    await userEvent.type(nameInput, "my-project");

    const submitBtn = screen.getByRole("button", { name: /Create Project/i });
    await userEvent.click(submitBtn);

    // Should have retried create after detection, and entered setting_up
    await waitFor(() => {
      expect(createCallCount).toBe(2);
    });

    // Should NOT have redirected to GitHub
    expect(hrefSetter).not.toHaveBeenCalled();
  });
});

// ===========================================================================
// Phase 5: Email-only users go through GitHub App redirect
// ===========================================================================

describe("Phase 5: Email-only users", () => {
  test("on mount: stays on choose when no GitHub identity (no auto-redirect)", async () => {
    setupFetchMock({
      "/api/repo/detect-installation": () =>
        Promise.resolve(
          new Response(
            JSON.stringify({ installed: false, reason: "no_github_identity" }),
            { status: 200 },
          ),
        ),
    });

    render(<ConnectRepoPage />);

    // Should stay on choose screen — user clicks Connect/Create to proceed
    await waitFor(() => {
      expect(
        screen.getByText("Give Your AI Team the Full Picture"),
      ).toBeInTheDocument();
    });
  });

  test("Connect Existing: shows github_resolve state when no GitHub identity", async () => {
    let detectCount = 0;
    setupFetchMock({
      "/api/repo/repos": () =>
        Promise.resolve(
          new Response(
            JSON.stringify({ error: "GitHub App not installed" }),
            { status: 400 },
          ),
        ),
      "/api/repo/detect-installation": () => {
        detectCount++;
        if (detectCount === 1) {
          // Mount: no identity
          return Promise.resolve(
            new Response(
              JSON.stringify({ installed: false, reason: "no_github_identity" }),
              { status: 200 },
            ),
          );
        }
        // Click: still no identity
        return Promise.resolve(
          new Response(
            JSON.stringify({ installed: false, reason: "no_github_identity" }),
            { status: 200 },
          ),
        );
      },
    });

    render(<ConnectRepoPage />);

    const connectBtn = await screen.findByText("Connect Project");
    await userEvent.click(connectBtn);

    // Should go to github_resolve, not github_redirect
    await waitFor(() => {
      expect(screen.getByText("Connect to GitHub")).toBeInTheDocument();
    });
  });

  test("shows error banner when returning with ?resolve_error=1", async () => {
    mockSearchParams.current = new URLSearchParams("resolve_error=1");

    setupFetchMock({
      "/api/repo/detect-installation": () =>
        Promise.resolve(
          new Response(
            JSON.stringify({ installed: false, reason: "no_github_identity" }),
            { status: 200 },
          ),
        ),
    });

    render(<ConnectRepoPage />);

    await waitFor(() => {
      expect(
        screen.getByText(/GitHub connection failed/i),
      ).toBeInTheDocument();
    });

    // Reset search params for other tests
    mockSearchParams.current = new URLSearchParams();
  });
});
