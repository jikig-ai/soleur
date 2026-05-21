// #4224 — `KbSyncStatus` single merged badge+button component.
//
// Inline 12-line discriminator distinguishes legacy `{date,count}` rows
// (`recordKbSyncHistory`) from the new richer shape — the empty-state
// renders the synced variant with "Workspace ready" copy per Kieran #10
// + Simplicity #1 (no third dedicated state).

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { fireEvent, render, screen, waitFor, act } from "@testing-library/react";

const mockFetch = vi.fn();
const originalFetch = globalThis.fetch;

beforeEach(() => {
  mockFetch.mockReset();
  globalThis.fetch = mockFetch as unknown as typeof fetch;
});

afterEach(() => {
  globalThis.fetch = originalFetch;
});

import { KbSyncStatus } from "@/components/kb/kb-sync-status";

describe("KbSyncStatus — empty state", () => {
  it("renders 'Workspace ready' when lastSync is null", () => {
    render(<KbSyncStatus lastSync={null} />);
    expect(screen.getByText(/workspace ready/i)).toBeTruthy();
  });
});

describe("KbSyncStatus — synced state (new richer shape)", () => {
  it("renders 'Synced …' label with ok:true row", () => {
    render(
      <KbSyncStatus
        lastSync={{
          at: new Date(Date.now() - 60_000).toISOString(),
          trigger: "webhook_push",
          ok: true,
          sync_completed_at: Date.now() - 60_000,
        }}
      />,
    );
    expect(screen.getByText(/synced/i)).toBeTruthy();
  });
});

describe("KbSyncStatus — desync state (ok:false)", () => {
  it("renders 'out of sync' label with ok:false row", () => {
    render(
      <KbSyncStatus
        lastSync={{
          at: new Date().toISOString(),
          trigger: "webhook_push",
          ok: false,
          error_class: "non_fast_forward",
          sync_completed_at: Date.now(),
        }}
      />,
    );
    expect(screen.getByText(/out of sync/i)).toBeTruthy();
  });
});

describe("KbSyncStatus — legacy {date,count} row", () => {
  it("treats a legacy entry as synced (renders 'Synced')", () => {
    render(
      <KbSyncStatus
        lastSync={
          {
            date: "2026-05-20",
            count: 42,
          } as unknown as React.ComponentProps<typeof KbSyncStatus>["lastSync"]
        }
      />,
    );
    expect(screen.getByText(/synced/i)).toBeTruthy();
  });
});

describe("KbSyncStatus — Sync now click", () => {
  it("POSTs /api/kb/sync, calls onSynced on success", async () => {
    const onSynced = vi.fn();
    mockFetch.mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({ ok: true, at: new Date().toISOString() }),
    });

    render(
      <KbSyncStatus
        lastSync={{
          at: new Date(Date.now() - 60_000).toISOString(),
          trigger: "manual",
          ok: true,
          sync_completed_at: Date.now() - 60_000,
        }}
        onSynced={onSynced}
      />,
    );

    const button = screen.getByRole("button", { name: /sync now/i });
    await act(async () => {
      fireEvent.click(button);
    });

    expect(mockFetch).toHaveBeenCalledTimes(1);
    const [url, init] = mockFetch.mock.calls[0];
    expect(url).toBe("/api/kb/sync");
    expect((init as RequestInit).method).toBe("POST");

    await waitFor(() => expect(onSynced).toHaveBeenCalledTimes(1));
  });

  it("shows in-flight state while the request is pending (button disabled)", async () => {
    let resolveFetch!: (value: { ok: boolean; status: number; json: () => Promise<unknown> }) => void;
    mockFetch.mockReturnValue(
      new Promise((r) => {
        resolveFetch = r;
      }),
    );

    render(<KbSyncStatus lastSync={null} />);
    const button = screen.getByRole("button", { name: /sync now/i });
    await act(async () => {
      fireEvent.click(button);
    });

    expect((button as HTMLButtonElement).disabled).toBe(true);

    await act(async () => {
      resolveFetch({
        ok: true,
        status: 200,
        json: async () => ({ ok: true, at: new Date().toISOString() }),
      });
    });

    await waitFor(() => {
      expect((screen.getByRole("button", { name: /sync now/i }) as HTMLButtonElement).disabled).toBe(false);
    });
  });

  it("calls onError when /api/kb/sync returns 409 (workspace_not_ready)", async () => {
    const onError = vi.fn();
    mockFetch.mockResolvedValue({
      ok: false,
      status: 409,
      json: async () => ({
        error: "Workspace not ready",
        code: "WORKSPACE_NOT_READY",
      }),
    });

    render(<KbSyncStatus lastSync={null} onError={onError} />);
    const button = screen.getByRole("button", { name: /sync now/i });
    await act(async () => {
      fireEvent.click(button);
    });

    await waitFor(() => {
      expect(onError).toHaveBeenCalledTimes(1);
      const arg = onError.mock.calls[0][0];
      expect(arg).toEqual(
        expect.objectContaining({ code: "WORKSPACE_NOT_READY" }),
      );
    });
  });
});
