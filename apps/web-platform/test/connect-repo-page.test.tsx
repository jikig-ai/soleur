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
      ([url, opts]: [string, RequestInit?]) =>
        url === "/api/repo/install" && opts?.method === "POST",
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
      ([url, opts]: [string, RequestInit?]) =>
        url === "/api/repo/install" && opts?.method === "POST",
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
      ([url]: [string]) => url === "/api/repo/install",
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
        ([url, opts]: [string, RequestInit?]) =>
          url === "/api/repo/create" && opts?.method === "POST",
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
