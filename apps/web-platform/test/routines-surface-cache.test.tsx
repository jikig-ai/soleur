import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { SwrTestProvider } from "./helpers/swr-wrapper";

// ChatSurface is heavy (WS client, chat stack) and only used by the Draft tab;
// stub it so the Routines-tab SWR migration test stays focused.
vi.mock("@/components/chat/chat-surface", () => ({
  ChatSurface: () => <div data-testid="chat-surface" />,
}));

import { RoutinesSurface } from "@/components/routines/routines-surface";

interface RoutineItem {
  fnId: string;
  description: string;
  domain: string;
  ownerRole: string;
  scheduleLabel: string;
  manualTrigger: "allowed" | "confirm";
  lastRun: null;
}

function routine(over: Partial<RoutineItem> = {}): RoutineItem {
  return {
    fnId: "cron-legal-audit",
    description: "Weekly legal audit",
    domain: "legal",
    ownerRole: "clo",
    scheduleLabel: "0 0 * * 1",
    manualTrigger: "allowed",
    lastRun: null,
    ...over,
  };
}

function Wrapped() {
  return (
    <SwrTestProvider>
      <RoutinesSurface />
    </SwrTestProvider>
  );
}

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

describe("RoutinesSurface — SWR migration", () => {
  it("loads the routines list and renders rows", async () => {
    global.fetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ routines: [routine()] }),
    }) as unknown as typeof fetch;

    render(<Wrapped />);
    await waitFor(() =>
      expect(screen.getByText("Legal audit")).toBeTruthy(),
    );
    expect(screen.getByText("1 routines")).toBeTruthy();
  });

  it("run-now writes an optimistic 'running' state into the cache", async () => {
    const fetchMock = vi.fn((url: string, init?: RequestInit) => {
      if (typeof url === "string" && url.includes("/run")) {
        return Promise.resolve({ ok: true, status: 202, json: async () => ({}) });
      }
      return Promise.resolve({
        ok: true,
        json: async () => ({ routines: [routine()] }),
      });
    });
    global.fetch = fetchMock as unknown as typeof fetch;

    render(<Wrapped />);
    await waitFor(() => expect(screen.getByText("Legal audit")).toBeTruthy());

    fireEvent.click(screen.getByTestId("run-now-cron-legal-audit"));

    // Optimistic running state appears without waiting for any refetch.
    await waitFor(() => expect(screen.getByText("running")).toBeTruthy());
    expect(fetchMock).toHaveBeenCalledWith(
      "/api/dashboard/routines/run",
      expect.objectContaining({ method: "POST" }),
    );
  });
});
