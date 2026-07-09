import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, waitFor, cleanup } from "@testing-library/react";
import { SWRConfig } from "swr";
import { useSignOut } from "@/components/auth/use-sign-out";

// GAP D (ADR-067 staleTimes amendment): a sign-out in tab A fires a SIGNED_OUT
// auth event in sibling tab B. The `onAuthStateChange("SIGNED_OUT")` listener in
// useSignOut must clear the SWR cache AND hard-navigate tab B to /login — a
// soft/no nav would leave tab B's warm App Router Router Cache reachable by a new
// principal. A same-tab guard (`pathname !== "/login"`) avoids a redundant nav.

const { onAuthStateChangeMock, authCallbackRef } = vi.hoisted(() => {
  const authCallbackRef: { current: ((event: string) => void) | null } = {
    current: null,
  };
  return {
    authCallbackRef,
    onAuthStateChangeMock: vi.fn((cb: (event: string) => void) => {
      authCallbackRef.current = cb;
      return { data: { subscription: { unsubscribe: vi.fn() } } };
    }),
  };
});

vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({
    auth: {
      signOut: vi.fn(() => Promise.resolve({ error: null })),
      onAuthStateChange: onAuthStateChangeMock,
    },
    removeAllChannels: vi.fn(() => Promise.resolve([])),
  }),
}));

vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: vi.fn(),
}));

const assignMock = vi.fn();
let originalLocation: Location;

function Harness() {
  useSignOut();
  return null;
}

beforeEach(() => {
  assignMock.mockReset();
  authCallbackRef.current = null;
  originalLocation = window.location;
  Object.defineProperty(window, "location", {
    configurable: true,
    writable: true,
    value: { assign: assignMock, pathname: "/dashboard" } as unknown as Location,
  });
});

afterEach(() => {
  Object.defineProperty(window, "location", {
    configurable: true,
    writable: true,
    value: originalLocation,
  });
  cleanup();
});

describe("useSignOut — sibling-tab SIGNED_OUT listener (GAP D)", () => {
  it("hard-navigates to /login when a SIGNED_OUT event fires in a sibling tab", async () => {
    render(
      <SWRConfig value={{ provider: () => new Map() }}>
        <Harness />
      </SWRConfig>,
    );
    // The listener registered on mount.
    await waitFor(() => expect(authCallbackRef.current).toBeTypeOf("function"));

    // Simulate a sign-out that happened in another tab.
    authCallbackRef.current!("SIGNED_OUT");

    await waitFor(() => expect(assignMock).toHaveBeenCalledWith("/login"));
  });

  it("does NOT hard-nav when already on /login (same-tab redundancy guard)", async () => {
    Object.defineProperty(window, "location", {
      configurable: true,
      writable: true,
      value: { assign: assignMock, pathname: "/login" } as unknown as Location,
    });
    render(
      <SWRConfig value={{ provider: () => new Map() }}>
        <Harness />
      </SWRConfig>,
    );
    await waitFor(() => expect(authCallbackRef.current).toBeTypeOf("function"));

    authCallbackRef.current!("SIGNED_OUT");

    // Let the clear + finally microtasks settle, then assert no nav.
    await new Promise((r) => setTimeout(r, 0));
    expect(assignMock).not.toHaveBeenCalled();
  });

  it("ignores non-SIGNED_OUT events", async () => {
    render(
      <SWRConfig value={{ provider: () => new Map() }}>
        <Harness />
      </SWRConfig>,
    );
    await waitFor(() => expect(authCallbackRef.current).toBeTypeOf("function"));

    authCallbackRef.current!("TOKEN_REFRESHED");
    await new Promise((r) => setTimeout(r, 0));
    expect(assignMock).not.toHaveBeenCalled();
  });
});
