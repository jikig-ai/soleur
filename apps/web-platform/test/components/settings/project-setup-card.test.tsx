import { describe, test, expect, vi, beforeEach } from "vitest";
import { render, screen, act, waitFor } from "@testing-library/react";

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

const { mockRefresh } = vi.hoisted(() => ({ mockRefresh: vi.fn() }));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ refresh: mockRefresh, push: vi.fn() }),
}));

const { mockReport, mockWarn } = vi.hoisted(() => ({
  mockReport: vi.fn(),
  mockWarn: vi.fn(),
}));

vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: mockReport,
  warnSilentFallback: mockWarn,
}));

import { ProjectSetupCard } from "@/components/settings/project-setup-card";

const REPO_URL = "https://github.com/owner/repo";

let assignSpy: ReturnType<typeof vi.fn>;
function installLocation(pathname = "/dashboard/settings") {
  assignSpy = vi.fn();
  Object.defineProperty(window.location, "pathname", {
    configurable: true,
    value: pathname,
  });
  Object.defineProperty(window.location, "assign", {
    configurable: true,
    value: assignSpy,
  });
}

function routerFetch(opts: {
  statusSequence?: Array<{ status: string }>;
  setupStatus?: number;
}) {
  const statusSeq = [...(opts.statusSequence ?? [{ status: "ready" }])];
  return vi.fn((input: string, init?: RequestInit) => {
    void init;
    if (input === "/api/repo/detect-installation") {
      return Promise.resolve(
        new Response(
          JSON.stringify({ installed: true, repos: [{ fullName: "owner/repo" }] }),
          { status: 200 },
        ),
      );
    }
    if (input === "/api/repo/setup") {
      return Promise.resolve(
        new Response(JSON.stringify({ status: "cloning" }), {
          status: opts.setupStatus ?? 200,
        }),
      );
    }
    if (input === "/api/repo/status") {
      const next = statusSeq.length > 1 ? statusSeq.shift()! : statusSeq[0];
      return Promise.resolve(new Response(JSON.stringify(next), { status: 200 }));
    }
    return Promise.reject(new Error(`unexpected fetch ${input}`));
  });
}

describe("ProjectSetupCard — error-branch re-setup recovery (FIX 1b)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    installLocation();
    sessionStorage.clear();
  });

  test("error branch renders a reconnect affordance (button), not only a connect-repo link", () => {
    const fetchMock = routerFetch({});
    vi.stubGlobal("fetch", fetchMock);

    render(
      <ProjectSetupCard
        repoUrl={REPO_URL}
        repoStatus="error"
        repoLastSyncedAt={null}
      />,
    );

    // The recovery affordance is an actionable button (reconnect), not just an
    // anchor to /connect-repo.
    expect(
      screen.getByRole("button", { name: /reconnect|retry/i }),
    ).toBeInTheDocument();
  });

  test("clicking reconnect in error state issues POST /api/repo/setup then polls status to ready → router.refresh", async () => {
    const fetchMock = routerFetch({
      statusSequence: [{ status: "cloning" }, { status: "ready" }],
    });
    vi.stubGlobal("fetch", fetchMock);

    render(
      <ProjectSetupCard
        repoUrl={REPO_URL}
        repoStatus="error"
        repoLastSyncedAt={null}
      />,
    );

    const btn = screen.getByRole("button", { name: /reconnect|retry/i });
    await act(async () => {
      btn.click();
    });

    await waitFor(() => {
      const calls = fetchMock.mock.calls.map((c) => c[0]);
      expect(calls).toContain("/api/repo/setup");
      expect(calls).toContain("/api/repo/status");
    });

    const setupCall = fetchMock.mock.calls.find((c) => c[0] === "/api/repo/setup");
    expect(JSON.parse((setupCall![1] as RequestInit).body as string)).toEqual({
      repoUrl: REPO_URL,
    });
    await waitFor(() => expect(mockRefresh).toHaveBeenCalled());
  });

  test("background clone fails → status error → terminal actionable state shown (no spinner-forever)", async () => {
    const fetchMock = routerFetch({
      statusSequence: [{ status: "cloning" }, { status: "error" }],
    });
    vi.stubGlobal("fetch", fetchMock);

    render(
      <ProjectSetupCard
        repoUrl={REPO_URL}
        repoStatus="error"
        repoLastSyncedAt={null}
      />,
    );

    const btn = screen.getByRole("button", { name: /reconnect|retry/i });
    await act(async () => {
      btn.click();
    });

    // Terminal error surfaced; refresh NOT called as if ready.
    await waitFor(() =>
      expect(screen.getByText(/couldn.t|could not|failed|try again/i)).toBeInTheDocument(),
    );
    expect(mockRefresh).not.toHaveBeenCalled();
  });
});
