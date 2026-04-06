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
