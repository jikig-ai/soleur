import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { SharePopover, SHARE_ERROR_MESSAGE } from "@/components/kb/share-popover";

// Minimal Response-like object for the fetch mock.
function jsonResponse(status: number, body: unknown) {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  } as Response;
}

const fetchMock = vi.fn();

beforeEach(() => {
  fetchMock.mockReset();
  vi.stubGlobal("fetch", fetchMock);
});

afterEach(() => {
  vi.unstubAllGlobals();
});

function openAndGenerate() {
  render(<SharePopover documentPath="knowledge-base/x.md" />);
  fireEvent.click(screen.getByText("Share"));
  return screen.findByText("Generate link").then((btn) => {
    fireEvent.click(btn);
  });
}

describe("SharePopover — client error surfacing (AC1, AC2)", () => {
  it("shows a visible error message + retry control on a POST 500, not a silent reset to idle", async () => {
    fetchMock.mockImplementation((_url: string, init?: RequestInit) => {
      if (init?.method === "POST") {
        return Promise.resolve(
          jsonResponse(500, { error: "Failed to create share link", code: "db-error" }),
        );
      }
      return Promise.resolve(jsonResponse(200, { shares: [] }));
    });

    await openAndGenerate();

    // Error message visible + retry affordance.
    expect(await screen.findByText(SHARE_ERROR_MESSAGE)).toBeTruthy();
    expect(screen.getByText("Try again")).toBeTruthy();
  });

  it("renders a GENERIC error string, never the raw server error payload (AC2)", async () => {
    fetchMock.mockImplementation((_url: string, init?: RequestInit) => {
      if (init?.method === "POST") {
        return Promise.resolve(
          jsonResponse(500, {
            error: "duplicate key value violates unique constraint kb_share_links_pkey",
            code: "db-error",
          }),
        );
      }
      return Promise.resolve(jsonResponse(200, { shares: [] }));
    });

    await openAndGenerate();

    expect(await screen.findByText(SHARE_ERROR_MESSAGE)).toBeTruthy();
    // The raw server string must NOT leak into the UI.
    expect(screen.queryByText(/duplicate key value/)).toBeNull();
    expect(screen.queryByText(/kb_share_links_pkey/)).toBeNull();
  });

  it("surfaces an error on a thrown/network failure (catch path)", async () => {
    fetchMock.mockImplementation((_url: string, init?: RequestInit) => {
      if (init?.method === "POST") return Promise.reject(new Error("network down"));
      return Promise.resolve(jsonResponse(200, { shares: [] }));
    });

    await openAndGenerate();

    expect(await screen.findByText(SHARE_ERROR_MESSAGE)).toBeTruthy();
  });
});

describe("SharePopover — happy path still works", () => {
  it("renders the active share link after a POST 201", async () => {
    fetchMock.mockImplementation((_url: string, init?: RequestInit) => {
      if (init?.method === "POST") {
        return Promise.resolve(jsonResponse(201, { token: "tok123", url: "/shared/tok123" }));
      }
      return Promise.resolve(jsonResponse(200, { shares: [] }));
    });

    await openAndGenerate();

    const input = (await screen.findByDisplayValue(/\/shared\/tok123$/)) as HTMLInputElement;
    expect(input).toBeTruthy();
    expect(screen.queryByText(SHARE_ERROR_MESSAGE)).toBeNull();
  });
});

describe("SharePopover — 409 concurrent-retry recovery (AC4)", () => {
  it("lands on the active state (re-reads existing row) instead of erroring on POST 409", async () => {
    let getCall = 0;
    fetchMock.mockImplementation((_url: string, init?: RequestInit) => {
      if (init?.method === "POST") {
        return Promise.resolve(
          jsonResponse(409, { error: "Concurrent share creation — retry", code: "concurrent-retry" }),
        );
      }
      // GET: first call (on open) sees no share; after the 409 the winner row exists.
      getCall += 1;
      if (getCall === 1) return Promise.resolve(jsonResponse(200, { shares: [] }));
      return Promise.resolve(
        jsonResponse(200, { shares: [{ token: "winner", revoked: false }] }),
      );
    });

    await openAndGenerate();

    const input = (await screen.findByDisplayValue(/\/shared\/winner$/)) as HTMLInputElement;
    expect(input).toBeTruthy();
    expect(screen.queryByText(SHARE_ERROR_MESSAGE)).toBeNull();
  });
});
